#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

if [ ! -f .env ]; then
  echo "Error: .env file not found!"
  exit 1
fi

set -a
source .env
set +a

# Defaults / Fallbacks
export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"
export MARIADB_HOST="${MARIADB_HOST:-mariadb}"
export MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
export MARIADB_USER="${MARIADB_USER:-ragnarok-user}"
export MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-ragnarok_root_pass}"
export MARIADB_PASSWORD="${MARIADB_PASSWORD:-ragnarok_db_pass}"

echo "==> 1. Updating Helm repositories..."
helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator 2>/dev/null || true
helm repo update mariadb-operator

echo "==> 2. Installing/upgrading MariaDB CRDs..."
helm upgrade --install mariadb-operator-crds mariadb-operator/mariadb-operator-crds

echo "==> 3. Installing/upgrading MariaDB Operator..."
helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
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

echo "==> 5. Ensuring target namespace exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 6. Creating/updating MariaDB secrets..."
kubectl create secret generic mariadb-root-secret \
  --from-literal=password="${MARIADB_ROOT_PASSWORD}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mariadb-user-secret \
  --from-literal=password="${MARIADB_PASSWORD}" \
  --from-literal=MARIADB_PASSWORD="${MARIADB_PASSWORD}" \
  --from-literal=MARIADB_HOST="${MARIADB_HOST}" \
  --from-literal=MARIADB_DATABASE="${MARIADB_DATABASE}" \
  --from-literal=MARIADB_USER="${MARIADB_USER}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 7. Applying MariaDB custom resources (templated from .env)..."
if command -v envsubst >/dev/null 2>&1; then
  envsubst < k8s/mariadb.yaml | kubectl apply -f -
else
  # Fallback if envsubst is not installed
  python3 -c '
import os, sys, string
template = open("k8s/mariadb.yaml").read()
print(string.Template(template).safe_substitute(os.environ))
' | kubectl apply -f -
fi

envsubst < k8s/network-policy.yaml | kubectl apply -f -

echo "==> 8. Waiting for MariaDB instance '${MARIADB_HOST}' to become ready..."
kubectl wait --for=condition=Ready "mariadb/${MARIADB_HOST}" -n "${NAMESPACE}" --timeout=180s

echo "==> MariaDB Operator and instance are fully ready! 🦭"
