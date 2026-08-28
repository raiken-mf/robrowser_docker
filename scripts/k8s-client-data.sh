#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"

# Ensure namespace & PVC exist
envsubst < k8s/namespace.yaml | kubectl apply -f -
envsubst < k8s/pvc-client-data.yaml | kubectl apply -f -

# Start helper loader pod
envsubst < k8s/pvc-helper.yaml | kubectl apply -f -

# Wait until helper pod is ready
kubectl wait --for=condition=Ready pod/client-data-loader -n "${NAMESPACE}" --timeout=60s

# Prepare target directories on PVC
kubectl exec -n "${NAMESPACE}" client-data-loader -- mkdir -p /data/resources /data/BGM /data/AI

# Clear existing data for a clean state
kubectl exec -n "${NAMESPACE}" client-data-loader -- rm -rf /data/resources/* /data/BGM/* /data/AI/*

# Copy local client assets to Longhorn volume
echo "==> Copying client resources..."
kubectl cp ./client/resources/. "${NAMESPACE}/client-data-loader:/data/resources/"
kubectl cp ./client/BGM/. "${NAMESPACE}/client-data-loader:/data/BGM/"
kubectl cp ./client/AI/. "${NAMESPACE}/client-data-loader:/data/AI/"

# Tear down helper pod
envsubst < k8s/pvc-helper.yaml | kubectl delete -f -
echo "==> Client data initialization completed!"
