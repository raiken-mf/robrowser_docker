#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

if [ -f .env ]; then
  echo "==> 1. Loading environment variables from .env..."
  set -a
  source .env
  set +a
fi

export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
export HOST="${HOST:-127.0.0.1}"
export PORT_HTTP="${PORT_HTTP:-30080}"
export PORT_WSPROXY="${PORT_WSPROXY:-30599}"
export SERVER_NAME="${SERVER_NAME:-Ragnarok Online}"
export SET_PRERENEWAL="${SET_PRERENEWAL:-0}"
export PACKETVER="${PACKETVER:-20211103}"

echo "==> 2. Ensuring target namespace exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 3. Cleanup old Ingress / IngressRoutes..."
kubectl delete ingress ragnarok-ingress -n "${NAMESPACE}" --ignore-not-found
kubectl delete ingressroute ragnarok-ingress -n "${NAMESPACE}" --ignore-not-found
kubectl delete configmap robrowser-template -n "${NAMESPACE}" --ignore-not-found

echo "==> 4. Creating robrowser-config ConfigMap..."
kubectl create configmap robrowser-config \
  --namespace "${NAMESPACE}" \
  --from-literal=HOST="${HOST}" \
  --from-literal=PORT_HTTP="${PORT_HTTP}" \
  --from-literal=PORT_WSPROXY="${PORT_WSPROXY}" \
  --from-literal=SERVER_NAME="${SERVER_NAME}" \
  --from-literal=SET_PRERENEWAL="${SET_PRERENEWAL}" \
  --from-literal=PACKETVER="${PACKETVER}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 5. Applying PVCs & wsproxy..."
envsubst < k8s/pvc-client-data.yaml | kubectl apply -f -
envsubst < k8s/wsproxy.yaml | kubectl apply -f -

echo "==> 6. Applying roBrowser deployment & service..."
envsubst < k8s/robrowser.yaml | kubectl apply -f -

echo "==> 7. Restarting roBrowser rollout..."
kubectl rollout restart deployment/robrowser -n "${NAMESPACE}"
kubectl rollout status deployment/robrowser -n "${NAMESPACE}" --timeout=120s

echo "==> roBrowser successfully deployed on NodePorts! 🎮"
