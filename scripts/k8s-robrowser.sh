#!/usr/bin/env bash
set -euo pipefail

# Ensure Kubeconfig fallback
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

# Check if .env file exists
if [ ! -f .env ]; then
  echo "Error: .env file not found!"
  exit 1
fi

echo "==> 1. Ensuring namespace exists..."
kubectl create namespace ragnarok --dry-run=client -o yaml | kubectl apply -f -

echo "==> 2. Creating/updating ConfigMap from .env..."
kubectl create configmap robrowser-config \
  --from-env-file=.env \
  -n ragnarok \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 3. Applying PVCs & wsproxy..."
kubectl apply -f k8s/pvc-client-data.yaml
kubectl apply -f k8s/wsproxy.yaml

echo "==> 4. Applying roBrowser deployment & service..."
kubectl apply -f k8s/robrowser.yaml

echo "==> 5. Waiting for deployment rollout..."
kubectl rollout status deployment/robrowser -n ragnarok --timeout=120s

echo "==> roBrowser successfully deployed and ready!"
