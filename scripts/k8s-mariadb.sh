#!/usr/bin/env bash
set -euo pipefail

# Ensure Kubeconfig fallback
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

# Check if .env exists
if [ ! -f .env ]; then
  echo "Error: .env file not found!"
  exit 1
fi

# Load .env variables
set -a
source .env
set +a

# Fallback values if not set in .env
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-"ragnarok_root_pass"}
MARIADB_PASSWORD=${MARIADB_PASSWORD:-"ragnarok_db_pass"}

echo "==> 1. Updating Helm repositories..."
helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator || true
helm repo update

echo "==> 2. Installing/upgrading CRDs..."
helm upgrade --install mariadb-operator-crds mariadb-operator/mariadb-operator-crds

echo "==> 3. Installing/upgrading MariaDB Operator..."
helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
  --namespace mariadb-operator \
  --create-namespace

echo "==> 4. Waiting for Operator deployment rollout..."
kubectl rollout status deployment/mariadb-operator -n mariadb-operator --timeout=60s

echo "==> 5. Ensuring target namespace exists..."
kubectl create namespace ragnarok --dry-run=client -o yaml | kubectl apply -f -

echo "==> 6. Creating/updating MariaDB secrets..."
kubectl create secret generic mariadb-root-secret \
  --from-literal=password="${MARIADB_ROOT_PASSWORD}" \
  -n ragnarok \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mariadb-user-secret \
  --from-literal=password="${MARIADB_PASSWORD}" \
  -n ragnarok \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 7. Applying MariaDB custom resources..."
kubectl apply -f k8s/mariadb.yaml

echo "==> 8. Waiting for MariaDB instance to become ready..."
kubectl wait --for=condition=Ready mariadb/mariadb -n ragnarok --timeout=180s

echo "==> MariaDB Operator and instance are fully ready! 🦭"
