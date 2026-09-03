#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Client Data Initializer (Universal Throttled Streaming)
# ==============================================================================

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"

# 1. Ensure target namespace and PVC exist
echo "==> [1/4] Ensuring namespace and client-data PVC..."
envsubst < k8s/namespace.yaml | kubectl apply -f -
envsubst < k8s/pvc-client-data.yaml | kubectl apply -f -

# 2. Deploy helper loader pod
echo "==> [2/4] Deploying loader helper pod..."
envsubst < k8s/pvc-helper.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/client-data-loader -n "${NAMESPACE}" --timeout=90s

# 3. Create directory layout inside the Longhorn PVC
echo "==> [3/4] Preparing volume directory structure..."
kubectl exec -n "${NAMESPACE}" client-data-loader -- mkdir -p /data/resources /data/BGM /data/AI /data/System /data/data

# 4. Ingest assets file-by-file with rate limiting
echo "==> [4/4] Ingesting client assets file-by-file (25MB/s throttled)..."

for cat_dir in resources BGM AI System data; do
  src_path="./client/${cat_dir}"
  
  if [ -d "${src_path}" ] && [ "$(ls -A "${src_path}" 2>/dev/null)" ]; then
    echo "  --> Processing ${cat_dir}..."

    # Iterate over every file individually to avoid API streaming timeouts
    find "${src_path}" -mindepth 1 -type f | while IFS= read -r file; do
      rel_path="${file#"${src_path}/"}"
      target_file="/data/${cat_dir}/${rel_path}"
      target_parent="$(dirname "${target_file}")"

      # Ensure parent directory exists inside the volume
      kubectl exec -n "${NAMESPACE}" client-data-loader -- mkdir -p "${target_parent}"

      # Stream file with rate limiting (25 MB/s) if pv is present, otherwise fallback to cat
      if command -v pv >/dev/null 2>&1; then
        pv -q -L 25M "${file}" | kubectl exec -i -n "${NAMESPACE}" client-data-loader -- tee "${target_file}" >/dev/null
      else
        cat "${file}" | kubectl exec -i -n "${NAMESPACE}" client-data-loader -- tee "${target_file}" >/dev/null
      fi

      # 100ms pause to let Kubernetes API server process heartbeats and pings
      sleep 0.1
    done
  fi
done

# 5. Flush pending disk buffers before removing the loader pod
echo "==> Flushing disk buffers to storage volume..."
kubectl exec -n "${NAMESPACE}" client-data-loader -- sync

# 6. Clean up helper pod
echo "==> Cleaning up helper pod..."
envsubst < k8s/pvc-helper.yaml | kubectl delete -f -
echo "==> Client data initialization completed successfully! 🚀"