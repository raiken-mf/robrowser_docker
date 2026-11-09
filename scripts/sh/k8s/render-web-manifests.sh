#!/usr/bin/env bash
# Render only non-sensitive web configuration for review and GitOps.
set -euo pipefail
cd "$(dirname "$0")/../../.."
if [ -f "${ENV_FILE:-.env}" ]; then
  set -a
  source "${ENV_FILE:-.env}"
  set +a
fi
export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
export HOST="${HOST:-127.0.0.1}"
export PORT_HTTP="${PORT_HTTP:-30080}"
export PORT_FRONTEND="${PORT_FRONTEND:-30000}"
export PORT_WSPROXY="${PORT_WSPROXY:-30599}"
export REMOTE_IMAGE_TAG="${REMOTE_IMAGE_TAG:-${ROBROWSER_IMAGE_TAG:-stable}}"
export VITE_IMAGE_TAG="${VITE_IMAGE_TAG:-stable}"
export WSPROXY_IMAGE_TAG="${WSPROXY_IMAGE_TAG:-stable}"
output_dir="${1:?Usage: bash scripts/sh/k8s/render-web-manifests.sh OUTPUT_DIRECTORY}"
mkdir -p "$output_dir"
for component in remote robrowser wsproxy; do
  envsubst '${NAMESPACE} ${PORT_HTTP} ${PORT_FRONTEND} ${PORT_WSPROXY} ${REMOTE_IMAGE_TAG} ${VITE_IMAGE_TAG} ${WSPROXY_IMAGE_TAG}' \
    < "deploy/k8s/templates/$component.yaml" > "$output_dir/$component.yaml"
done
kubectl create configmap robrowser-config --namespace "$NAMESPACE" \
  --from-literal=HOST="$HOST" \
  --from-literal=PORT_HTTP="$PORT_HTTP" \
  --from-literal=PORT_FRONTEND="$PORT_FRONTEND" \
  --from-literal=PORT_WSPROXY="$PORT_WSPROXY" \
  --from-literal=SERVER_NAME="${SERVER_NAME:-Ragnarok Online}" \
  --from-literal=SET_PRERENEWAL="${SET_PRERENEWAL:-0}" \
  --from-literal=PACKETVER="${PACKETVER:-20211103}" \
  --from-literal=ROENGLISH_ADDITIONS="${ROENGLISH_ADDITIONS:-all}" \
  --from-literal=ROENGLISH_ADDONS="${ROENGLISH_ADDONS:-compatible}" \
  --from-literal=ROENGLISH_LEGACY_MAPS="${ROENGLISH_LEGACY_MAPS:-0}" \
  --dry-run=client -o yaml > "$output_dir/robrowser-config.yaml"
