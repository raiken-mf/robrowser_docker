#!/usr/bin/env bash
set -e

# 1. Load environment variables
if [ -f .env ]; then
  echo "==> 1. Loading environment variables from .env..."
  set -a
  source .env
  set +a
fi

NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
MARIADB_HOST="${MARIADB_HOST:-mariadb}"
MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
MARIADB_USER="${MARIADB_USER:-ragnarok-user}"

echo "==> 2. Ensuring target namespace '${NAMESPACE}' exists..."
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

echo "==> 3. Creating/updating rathena-config ConfigMap..."
kubectl create configmap rathena-config \
  --namespace "${NAMESPACE}" \
  --from-literal=MARIADB_HOST="${MARIADB_HOST}" \
  --from-literal=MARIADB_DATABASE="${MARIADB_DATABASE}" \
  --from-literal=MARIADB_USER="${MARIADB_USER}" \
  --from-literal=LOGIN_SERVER_HOST="ragnarok-login" \
  --from-literal=CHAR_SERVER_HOST="ragnarok-char" \
  --from-literal=MAP_SERVER_HOST="ragnarok-map" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4. Applying rAthena Kubernetes manifests..."
kubectl apply -f k8s/rathena.yaml

echo "==> 5. Waiting for Login Server rollout..."
kubectl rollout status deployment/ragnarok-login -n "${NAMESPACE}" --timeout=120s

echo "==> 6. Waiting for Char Server rollout..."
kubectl rollout status deployment/ragnarok-char -n "${NAMESPACE}" --timeout=120s

echo "==> 7. Waiting for Map Server rollout..."
kubectl rollout status deployment/ragnarok-map -n "${NAMESPACE}" --timeout=120s

echo "==> All rAthena services successfully rolled out!"
kubectl get pods -n "${NAMESPACE}" -l 'app.kubernetes.io/name in (ragnarok-login, ragnarok-char, ragnarok-map)'
