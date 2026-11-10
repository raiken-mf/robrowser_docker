#!/usr/bin/env bash
set -euo pipefail
set +x
cd "$(dirname "$0")/../../.."

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
for executable in kubectl helm python3 envsubst; do command -v "$executable" >/dev/null; done

ENV_FILE="${ENV_FILE:-.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: environment file not found!"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a
: "${MARIADB_OPERATOR_VERSION:?Select a reviewed MariaDB operator chart version before installation}"
[[ "$MARIADB_OPERATOR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid MariaDB operator chart version' >&2; exit 1; }
existing=$(kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io mariadbs.k8s.mariadb.com --ignore-not-found -o name)
[[ -z "$existing" ]] || { echo 'Existing Flux or MariaDB operator detected; use a separately approved upgrade procedure' >&2; exit 1; }
existing=$(kubectl get deployment mariadb-operator -n mariadb-operator --ignore-not-found -o name)
[[ -z "$existing" ]] || { echo 'Existing MariaDB operator detected; refusing installer upgrade' >&2; exit 1; }

# Defaults / Fallbacks
export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
export MARIADB_HOST="${MARIADB_HOST:-mariadb}"
export MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
export MARIADB_USER="${MARIADB_USER:-ragnarok-user}"
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD must be set}"
: "${SET_INTERSRV_USER:?SET_INTERSRV_USER must be set}"
: "${SET_INTERSRV_PASSWORD:?SET_INTERSRV_PASSWORD must be set}"
workdir=$(mktemp -d)
trap 'rm -r "$workdir"' EXIT
chmod 700 "$workdir"
python3 scripts/py/render-k8s-bootstrap.py --env-file "$ENV_FILE" --output-dir "$workdir" --installer-defaults >/dev/null

echo "==> 1. Updating Helm repositories..."
helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator 2>/dev/null || true
helm repo update mariadb-operator

echo "==> 2. Installing/upgrading MariaDB CRDs..."
helm upgrade --install mariadb-operator-crds mariadb-operator/mariadb-operator-crds --version "$MARIADB_OPERATOR_VERSION"

echo "==> 3. Installing/upgrading MariaDB Operator..."
helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
  --version "$MARIADB_OPERATOR_VERSION" \
  --namespace mariadb-operator \
  --create-namespace

echo "==> 4. Waiting for Operator deployment rollout..."
kubectl rollout status deployment/mariadb-operator -n mariadb-operator --timeout=90s

echo "==> 4.1. Waiting for MariaDB Webhook deployment & endpoints..."
if kubectl get deployment mariadb-operator-webhook -n mariadb-operator >/dev/null 2>&1; then
  kubectl rollout status deployment/mariadb-operator-webhook -n mariadb-operator --timeout=90s
fi

# Warte bis der Webhook-Service tatsächliche Endpoints registriert hat
for i in {1..30}; do
  ENDPOINTS=$(kubectl get endpoints mariadb-operator-webhook -n mariadb-operator -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [ -n "$ENDPOINTS" ]; then
    echo "Webhook endpoints ready: ${ENDPOINTS}"
    break
  fi
  echo "Waiting for webhook endpoints to register ($i/30)..."
  sleep 2
done
[[ -n "${ENDPOINTS:-}" ]] || { echo 'MariaDB webhook endpoints unavailable; refusing resource changes' >&2; exit 1; }

echo "==> 5. Ensuring target namespace exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 6. Creating/updating MariaDB secrets..."
python3 - "$workdir/bootstrap.json" <<'PY' | kubectl apply -f -
import json, sys
with open(sys.argv[1]) as stream:
  manifest = json.load(stream)
manifest['items'] = [item for item in manifest['items'] if item['kind'] == 'Secret']
json.dump(manifest, sys.stdout)
PY

echo "==> 7. Applying MariaDB custom resources (templated from .env)..."
envsubst < deploy/k8s/templates/mariadb.yaml | kubectl apply -f -

envsubst < deploy/k8s/templates/network-policy.yaml | kubectl apply -f -

echo "==> 8. Waiting for MariaDB instance '${MARIADB_HOST}' to become ready..."
kubectl wait --for=condition=Ready "mariadb/${MARIADB_HOST}" -n "${NAMESPACE}" --timeout=180s

echo "==> MariaDB Operator and instance are fully ready! 🦭"
