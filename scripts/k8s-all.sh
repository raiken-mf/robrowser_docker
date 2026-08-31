#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"

echo "==> 1. Wiping namespace '${NAMESPACE}'..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
kubectl wait --for=delete namespace/"${NAMESPACE}" --timeout=120s 2>/dev/null || true

echo "==> 2. Creating hardened namespace '${NAMESPACE}'..."
envsubst < k8s/namespace.yaml | kubectl apply -f -

echo "==> 3. Deploying MariaDB..."
./scripts/k8s-mariadb.sh

echo "==> 3.1. Ensuring MariaDB Operator Webhook is ready..."
if kubectl get deployment mariadb-operator-webhook -n mariadb-operator >/dev/null 2>&1; then
  kubectl rollout status deployment/mariadb-operator-webhook -n mariadb-operator --timeout=90s
fi

echo "==> 4. Initializing Client Data..."
./scripts/k8s-client-data.sh

echo "==> 5. Deploying rAthena Server..."
./scripts/k8s-rathena.sh

echo "==> 6. Deploying roBrowser & wsProxy..."
./scripts/k8s-robrowser.sh

echo "==> Verification: All Pods in '${NAMESPACE}':"
kubectl get pods -n "${NAMESPACE}"
