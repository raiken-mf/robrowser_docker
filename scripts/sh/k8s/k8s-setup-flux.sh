#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GITHUB_USER="${GITHUB_USER:-raiken-mf}"
GITHUB_REPO="${GITHUB_REPO:-robrowser_docker}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
CLUSTER_PATH="${CLUSTER_PATH:-deploy/clusters/default}"
FLUX_EXTRA_COMPONENTS="${FLUX_EXTRA_COMPONENTS:-image-reflector-controller,image-automation-controller}"
mode="${1:-}"
[[ $# -le 1 && ( -z "$mode" || "$mode" == --check ) ]] || { echo 'Usage: k8s-setup-flux.sh [--check]' >&2; exit 2; }
[[ "$GITHUB_USER" =~ ^[a-zA-Z0-9-]+$ && "$GITHUB_REPO" =~ ^[a-zA-Z0-9_.-]+$ && "$GITHUB_BRANCH" =~ ^[a-zA-Z0-9_./-]+$ && "$CLUSTER_PATH" =~ ^[a-zA-Z0-9_./-]+$ && "$CLUSTER_PATH" != *..* && "$CLUSTER_PATH" != /* ]] || { echo 'ERROR: Invalid Git configuration.' >&2; exit 1; }
[[ -d "$ROOT_DIR/$CLUSTER_PATH" ]] || { echo 'ERROR: Cluster path does not exist in this checkout.' >&2; exit 1; }
for command in kubectl flux; do
  command -v "$command" >/dev/null 2>&1 || { echo "ERROR: Missing prerequisite: $command" >&2; exit 1; }
done
kubectl get nodes >/dev/null || { echo 'ERROR: Kubernetes API unavailable.' >&2; exit 1; }
namespace=$(kubectl get namespace flux-system --ignore-not-found -o name) || { echo 'ERROR: Cannot inspect Flux namespace.' >&2; exit 1; }
if [[ -n "$namespace" ]]; then
  source_url=$(kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.spec.url}') || { echo 'ERROR: Flux GitRepository missing or inaccessible.' >&2; exit 1; }
  branch=$(kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.spec.ref.branch}') || exit 1
  parent=$(kubectl -n flux-system get kustomization flux-system -o jsonpath='{.spec.path}{"|"}{.spec.sourceRef.kind}{"|"}{.spec.sourceRef.name}{"|"}{.spec.sourceRef.namespace}') || { echo 'ERROR: Flux parent Kustomization missing or inaccessible.' >&2; exit 1; }
  child=$(kubectl -n flux-system get kustomization ragnarok-stack -o jsonpath='{.spec.path}{"|"}{.spec.sourceRef.kind}{"|"}{.spec.sourceRef.name}{"|"}{.spec.sourceRef.namespace}') || { echo 'ERROR: Ragnarok Kustomization missing or inaccessible.' >&2; exit 1; }
  case "$source_url" in
    "ssh://git@github.com/$GITHUB_USER/$GITHUB_REPO"|"ssh://git@github.com/$GITHUB_USER/$GITHUB_REPO.git"|"https://github.com/$GITHUB_USER/$GITHUB_REPO"|"https://github.com/$GITHUB_USER/$GITHUB_REPO.git") ;;
    *) echo 'ERROR: Flux GitRepository URL differs from the expected repository.' >&2; exit 1 ;;
  esac
  [[ "$branch" == "$GITHUB_BRANCH" && "$parent" == "./$CLUSTER_PATH|GitRepository|flux-system|" && "$child" == './deploy/k8s/overlays/flux|GitRepository|flux-system|' ]] || { echo 'ERROR: Flux branch, paths or source references differ from the expected configuration.' >&2; exit 1; }
  for controller in source-controller kustomize-controller helm-controller notification-controller image-reflector-controller image-automation-controller; do
    kubectl -n flux-system get deployment "$controller" -o name >/dev/null || { echo "ERROR: Missing Flux controller: $controller" >&2; exit 1; }
  done
  flux check || { echo 'ERROR: Flux health check failed.' >&2; exit 1; }
  echo 'Existing Flux configuration verified; no changes made.'
  exit 0
fi
flux_crds=$(kubectl get customresourcedefinitions -o name) || { echo 'ERROR: Cannot inspect cluster CRDs.' >&2; exit 1; }
if printf '%s\n' "$flux_crds" | grep -Eq '\.((source|kustomize|helm|notification|image)\.toolkit\.fluxcd\.io|fluxcd\.controlplane\.io)$'; then
  echo 'ERROR: Flux CRDs exist without the flux-system namespace; manual review required.' >&2
  exit 1
fi
flux_deployments=$(kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}') || { echo 'ERROR: Cannot inspect cluster deployments.' >&2; exit 1; }
if printf '%s\n' "$flux_deployments" | grep -Eq '^((source|kustomize|helm|notification|image-reflector|image-automation)-controller|flux-operator)$'; then
  echo 'ERROR: Flux controllers exist outside the flux-system namespace; manual review required.' >&2
  exit 1
fi
[[ "$mode" != --check ]] || { echo 'ERROR: Flux is not installed.' >&2; exit 1; }
flux check --pre
echo "Bootstrap will modify the cluster and GitHub repository $GITHUB_USER/$GITHUB_REPO on branch $GITHUB_BRANCH."
read -r -p 'Type BOOTSTRAP to confirm: ' confirmation || { echo 'ERROR: Confirmation required.' >&2; exit 1; }
[[ "$confirmation" == BOOTSTRAP ]] || { echo 'ERROR: Bootstrap cancelled.' >&2; exit 1; }
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  read -r -s -p 'GitHub token: ' GITHUB_TOKEN || { echo 'ERROR: Token required.' >&2; exit 1; }
  echo
  [[ -n "$GITHUB_TOKEN" ]] || { echo 'ERROR: Token required.' >&2; exit 1; }
  export GITHUB_TOKEN
fi
flux bootstrap github --owner="$GITHUB_USER" --repository="$GITHUB_REPO" --branch="$GITHUB_BRANCH" --path="$CLUSTER_PATH" --components-extra="$FLUX_EXTRA_COMPONENTS" --personal --token-auth=false --read-write-key=true