#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

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
kubectl wait --for=condition=Ready pod/client-data-loader -n "${NAMESPACE}" --timeout=90s

# Prepare target directories on PVC
kubectl exec -n "${NAMESPACE}" client-data-loader -- mkdir -p /data/resources /data/BGM /data/AI /data/System /data/data

# Detect environment: Multipass Lab (Mac) vs Bare-Metal (Pi)
if command -v multipass >/dev/null 2>&1 && multipass info lab-node-1 &>/dev/null; then
  echo "==> [Multipass Lab detected] Transferring assets via VM to prevent API timeouts..."
  
  VM_STAGE_DIR="/tmp/client-staging"
  multipass exec lab-node-1 -- rm -rf "${VM_STAGE_DIR}"
  
  echo "--> Copying assets to lab-node-1..."
  multipass transfer -r ./client "lab-node-1:${VM_STAGE_DIR}"
  
  echo "--> Ingesting assets from node into Pod volume..."
  multipass exec lab-node-1 -- bash -c "
    set -e
    for dir in resources BGM AI System data; do
      if [ -d '${VM_STAGE_DIR}/'\$dir ] && [ \"\$(ls -A '${VM_STAGE_DIR}/'\$dir 2>/dev/null)\" ]; then
        echo '    --> Streaming '\$dir'...'
        tar -cf - -C '${VM_STAGE_DIR}/'\$dir . | kubectl exec -i -n '${NAMESPACE}' client-data-loader -- tar -xf - -C '/data/'\$dir
      fi
    done
    rm -rf '${VM_STAGE_DIR}'
  "
else
  echo "==> [Native / Bare-Metal detected] Streaming directly..."
  stream_copy() {
    local src_dir="$1"
    local dest_dir="$2"
    if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
      echo "--> Streaming $src_dir to $dest_dir..."
      tar -cf - -C "$src_dir" . | kubectl exec -i -n "${NAMESPACE}" client-data-loader -- tar -xf - -C "$dest_dir"
    fi
  }

  stream_copy "./client/resources" "/data/resources"
  stream_copy "./client/BGM" "/data/BGM"
  stream_copy "./client/AI" "/data/AI"
  stream_copy "./client/System" "/data/System"
  stream_copy "./client/data" "/data/data"
fi

# Ensure all buffers are flushed to disk before tearing down
kubectl exec -n "${NAMESPACE}" client-data-loader -- sync

# Tear down helper pod
envsubst < k8s/pvc-helper.yaml | kubectl delete -f -
echo "==> Client data initialization completed!"