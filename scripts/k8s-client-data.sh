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

# Helper function for reliable data transfer using streamed tar
stream_copy() {
  local src_dir="$1"
  local dest_dir="$2"

  if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
    echo "--> Streaming $src_dir to $dest_dir..."
    tar -czf - -C "$src_dir" . | kubectl exec -i -n "${NAMESPACE}" client-data-loader -- tar -xzf - -C "$dest_dir"
  else
    echo "--> Skipping $src_dir (directory empty or does not exist)."
  fi
}

echo "==> Copying client resources via tar stream..."
stream_copy "./client/resources" "/data/resources"
stream_copy "./client/BGM" "/data/BGM"
stream_copy "./client/AI" "/data/AI"

# Tear down helper pod
envsubst < k8s/pvc-helper.yaml | kubectl delete -f -
echo "==> Client data initialization completed!"
