#!/usr/bin/env bash
# Fresh application bootstrap. Flux is never resumed; no namespace is deleted.
set -euo pipefail
set +x
cd "$(dirname "$0")/../../.."
mode=check
reconcile=false
for argument in "$@"; do
  case "$argument" in
    --check) mode=check ;;
    --apply) mode=apply ;;
    --reconcile) reconcile=true ;;
    *) echo 'Usage: bash scripts/sh/k8s/k8s-all.sh [--check|--apply] [--reconcile]' >&2; exit 2 ;;
  esac
done
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export ENV_FILE="${ENV_FILE:-$PWD/.env}"
[[ -f "$ENV_FILE" ]] || { echo 'Missing operator-owned .env' >&2; exit 1; }
set -a
source "$ENV_FILE" >/dev/null 2>&1
set +a
export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
export CLIENT_SOURCE_DIR="${CLIENT_SOURCE_DIR:-$PWD/client}"
export HOST="${HOST:-127.0.0.1}"
export PORT_HTTP="${PORT_HTTP:-30080}" PORT_FRONTEND="${PORT_FRONTEND:-30000}" PORT_WSPROXY="${PORT_WSPROXY:-30599}"
for executable in kubectl python3 envsubst tar; do command -v "$executable" >/dev/null; done
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
chmod 700 "$workdir"
python3 scripts/py/render-k8s-bootstrap.py --env-file "$ENV_FILE" --output-dir "$workdir" >/dev/null
# Use reviewed, scanned release pins by default rather than an unrelated latest tag.
image_tag() {
  awk -v image="ghcr.io/raiken-mf/$1" '
    $1=="-" && $2=="name:" {selected=($3==image)}
    selected && $1=="newTag:" {print $2; exit}
  ' deploy/k8s/overlays/flux/kustomization.yaml
}
export REMOTE_IMAGE_TAG="${REMOTE_IMAGE_TAG:-${ROBROWSER_IMAGE_TAG:-$(image_tag remote)}}"
export VITE_IMAGE_TAG="${VITE_IMAGE_TAG:-$(image_tag robrowser)}"
export RATHENA_IMAGE_TAG="${RATHENA_IMAGE_TAG:-$(image_tag rathena)}"
export WSPROXY_IMAGE_TAG="${WSPROXY_IMAGE_TAG:-$(image_tag wsproxy)}"
for tag in "$REMOTE_IMAGE_TAG" "$VITE_IMAGE_TAG" "$RATHENA_IMAGE_TAG" "$WSPROXY_IMAGE_TAG"; do
  [[ -n "$tag" && "$tag" != stable ]] || { echo 'Select reviewed published SHA tags before bootstrap' >&2; exit 1; }
done
# Every failed API lookup is fatal; an auth/connectivity error is never "not found".
namespace=$(kubectl get namespace "$NAMESPACE" --ignore-not-found -o name)
if [[ "$mode" == apply && -n "$namespace" && "$reconcile" != true ]]; then
  echo 'Namespace already exists; use --reconcile only for an approved retry. Nothing deleted.' >&2
  exit 1
fi
kubectl get crd mariadbs.k8s.mariadb.com >/dev/null
kubectl get storageclass longhorn >/dev/null
kubectl -n mariadb-operator get deployments -o json > "$workdir/operator.json"
python3 - "$workdir/operator.json" <<'PY'
import json,sys
items=json.load(open(sys.argv[1]))['items']
for name in ('mariadb-operator','mariadb-operator-webhook'):
 o=next(o for o in items if o['metadata']['name']==name)
 assert o.get('status',{}).get('availableReplicas',0)>=o['spec'].get('replicas',1), name+' not available'
PY
if [[ -n "$(kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io --ignore-not-found -o name)" ]]; then
  kubectl -n flux-system get kustomizations flux-system ragnarok-stack --ignore-not-found -o json > "$workdir/flux.json"
  python3 - "$workdir/flux.json" <<'PY'
import json,sys
for o in json.load(open(sys.argv[1]))['items']:
 assert o['spec'].get('suspend') is True, o['metadata']['name']+' must stay suspended during manual bootstrap'
PY
fi
kubectl get services -A -o json > "$workdir/services.json"
python3 - "$workdir/services.json" "$NAMESPACE" "$PORT_HTTP" "$PORT_FRONTEND" "$PORT_WSPROXY" <<'PY'
import json,sys
ports=list(map(int,sys.argv[3:])); assert len(set(ports))==3 and all(1<=p<=65535 for p in ports)
for o in json.load(open(sys.argv[1]))['items']:
 for p in o['spec'].get('ports',[]):
  if p.get('nodePort') in ports:
   assert o['metadata']['namespace']==sys.argv[2] and o['metadata']['name'] in ('remote','robrowser','wsproxy'), 'NodePort already allocated elsewhere'
PY
python3 - "$CLIENT_SOURCE_DIR" <<'PY'
import configparser,pathlib,sys
base=pathlib.Path(sys.argv[1]);resources=(base/'resources').resolve()
for directory in ('AI','BGM','data','System','resources'):assert (base/directory).is_dir(), 'Missing client folder: '+directory
ini=configparser.ConfigParser(); assert ini.read(resources/'DATA.INI'), 'Missing DATA.INI'
section=next(s for s in ini.sections() if s.lower()=='data'); assert ini[section]
for name in ini[section].values():
 p=(resources/name).resolve(); assert p.is_relative_to(resources) and p.is_file() and p.stat().st_size>46, 'Missing/invalid referenced GRF'
PY
ENV_FILE="$ENV_FILE" bash scripts/sh/k8s/render-web-manifests.sh "$workdir/web"
for component in namespace network-policy mariadb rathena; do
  envsubst < "deploy/k8s/templates/$component.yaml" > "$workdir/$component.yaml"
done
if [[ "$mode" == check ]]; then
  echo 'READY: local configuration, private bootstrap, client sources, operators, storage and free/configured NodePorts checked; no cluster writes.'
  exit 0
fi
# Execute only after the operator separately approves installation.
kubectl apply -f "$workdir/namespace.yaml"
kubectl apply -f "$workdir/network-policy.yaml"
kubectl apply -f "$workdir/bootstrap.json"
kubectl apply -f "$workdir/web/robrowser-config.yaml"
kubectl apply -f "$workdir/mariadb.yaml"
kubectl wait -n "$NAMESPACE" --for=condition=Ready "mariadbs.k8s.mariadb.com/$MARIADB_HOST" \
  "databases.k8s.mariadb.com/$MARIADB_DATABASE" "users.k8s.mariadb.com/$MARIADB_USER" \
  "grants.k8s.mariadb.com/$MARIADB_USER-grant" --timeout=300s
# Populate the readonly runtime volume before the web deployments start.
bash scripts/sh/k8s/k8s-client-data.sh
kubectl apply -f "$workdir/rathena.yaml"
for deployment in ragnarok-login ragnarok-char ragnarok-map; do
  kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout=300s
done
# The login entrypoint initializes the empty DB, including the interserver account.
# Passwords expand only inside the pod environment, never into local command arguments.
kubectl exec -n "$NAMESPACE" deployment/ragnarok-login -- sh -ec '
  export MYSQL_PWD="$MARIADB_PASSWORD"
  test "$(mariadb -h "$MARIADB_HOST" -u "$MARIADB_USER" "$MARIADB_DATABASE" -sN -e "SELECT COUNT(*) FROM login WHERE account_id=1 AND sex=CHAR(83)")" = 1
'
for component in wsproxy remote robrowser; do
  kubectl apply -f "$workdir/web/$component.yaml"
  kubectl rollout status "deployment/$component" -n "$NAMESPACE" --timeout=300s
done
kubectl exec -i -n "$NAMESPACE" deployment/wsproxy -- node - < images/wsproxy/tests/check-wsproxy.cjs
kubectl exec -i -n "$NAMESPACE" deployment/remote -- php <<'PHP'
<?php
chdir('/var/www/localhost/htdocs/remote');
require 'Debug.php'; require 'GrfDES.php'; require 'Grf.php';
$ini=parse_ini_file('resources/DATA.INI',true);
$section=[]; foreach ($ini as $name=>$values) { if (strcasecmp($name,'Data')===0) $section=$values; }
if (!$section) exit(1); ksort($section);
$grf=new Grf('resources/'.array_values($section)[0]); $grf->load();
if (!$grf->loaded) exit(1);
echo "RemoteClient mounted GRF parser check passed\n";
PHP
kubectl get pods,services,pvc -n "$NAMESPACE"
echo 'Stack bootstrapped. Flux remains paused. Verify browser/frontend and approve GitOps adoption separately.'
