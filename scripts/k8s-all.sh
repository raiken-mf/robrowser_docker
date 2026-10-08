#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export NAMESPACE="${K8S_NAMESPACE:-ragnarok}"

# check_namespace_state: queries whether $1 exists and stores the result in
# the NAMESPACE_STATE global ("active" or "notfound").
#
# This deliberately distinguishes a successful "not found" lookup from any
# other kubectl failure (API server unreachable, auth/RBAC errors, invalid
# kubeconfig, etc.). A real error is NEVER mapped to "notfound"; the caller
# must check the return code and abort on failure instead of silently
# treating the namespace as missing.
#
# Returns 0 on a successful lookup (NAMESPACE_STATE set), 1 on any other
# kubectl error (diagnostic printed to stderr, NAMESPACE_STATE left unset).
check_namespace_state() {
  local ns="$1" output status
  output=$(kubectl get namespace "${ns}" -o name 2>&1)
  status=$?
  if [ "${status}" -eq 0 ]; then
    NAMESPACE_STATE="active"
    return 0
  fi
  if printf '%s' "${output}" | grep -qi 'NotFound'; then
    NAMESPACE_STATE="notfound"
    return 0
  fi
  echo "Error: failed to query namespace '${ns}' via kubectl (exit code ${status}); treating as a hard failure, NOT as 'missing':" >&2
  echo "${output}" >&2
  return 1
}

if ! check_namespace_state "${NAMESPACE}"; then
  echo "Error: aborting before any deployment or deletion because the namespace lookup for '${NAMESPACE}' failed (see above). Check cluster connectivity/credentials and retry." >&2
  exit 1
fi

if [ "${NAMESPACE_STATE}" == "active" ]; then
  if [ ! -t 0 ]; then
    echo "Error: interactive confirmation required before deploying to existing namespace '${NAMESPACE}'." >&2
    exit 1
  fi

  read -r -p "Delete namespace '${NAMESPACE}' and all its resources before deployment? [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES)
      # Revalidate right before deleting: time has passed since the initial
      # check (user had to answer the prompt), so another process may have
      # already deleted the namespace, or a lookup error may now occur.
      if ! check_namespace_state "${NAMESPACE}"; then
        echo "Error: aborting reset; namespace lookup for '${NAMESPACE}' failed on revalidation (see above)." >&2
        exit 1
      fi

      if [ "${NAMESPACE_STATE}" == "notfound" ]; then
        echo "==> 1. Namespace '${NAMESPACE}' was already removed by the time of confirmation; nothing to delete."
      else
        echo "==> 1. Deleting namespace '${NAMESPACE}'..."
        echo "    Note: this removes namespaced resources (and their PVC claims), but whether the"
        echo "    underlying persistent storage/data is actually erased depends on the storage"
        echo "    provisioner's reclaim policy and is NOT guaranteed by this script."
        if ! kubectl delete namespace "${NAMESPACE}" --wait=true --timeout=180s; then
          echo "Error: failed to delete namespace '${NAMESPACE}' (timeout, Terminating/finalizer stall, or API error). Aborting; deployment was NOT attempted and the reset must be treated as failed." >&2
          exit 1
        fi

        echo "==> 1.1. Verifying namespace '${NAMESPACE}' is fully gone before recreating it..."
        wait_deadline=$((SECONDS + 60))
        while :; do
          if ! check_namespace_state "${NAMESPACE}"; then
            echo "Error: aborting reset; namespace lookup for '${NAMESPACE}' failed while waiting for removal (see above)." >&2
            exit 1
          fi
          if [ "${NAMESPACE_STATE}" == "notfound" ]; then
            break
          fi
          if [ "${SECONDS}" -ge "${wait_deadline}" ]; then
            phase=$(kubectl get namespace "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            if [ "${phase}" == "Active" ]; then
              echo "Error: namespace '${NAMESPACE}' is Active again after deletion was issued, likely re-created by another process (race). Aborting without deploying; the namespace must NOT be assumed reset." >&2
            else
              echo "Error: namespace '${NAMESPACE}' is still present after deletion (phase: '${phase}', likely stuck Terminating due to finalizers). Aborting without deploying; the namespace must NOT be assumed reset." >&2
            fi
            exit 1
          fi
          phase=$(kubectl get namespace "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
          echo "Waiting for namespace '${NAMESPACE}' to be fully removed before recreation (current phase: '${phase}')..."
          sleep 3
        done
        echo "==> Namespace '${NAMESPACE}' confirmed fully removed."
      fi
      ;;
    n|N|no|NO|"")
      echo "==> 1. Keeping existing namespace '${NAMESPACE}' and its persistent resources; continuing with normal deployment reconciliation (component scripts may still restart workloads)."
      ;;
    *)
      echo "Error: expected yes or no; deployment cancelled." >&2
      exit 1
      ;;
  esac
else
  echo "==> 1. Namespace '${NAMESPACE}' does not exist; proceeding directly with normal creation/deployment (no reset prompt needed)."
fi

echo "==> 2. Creating hardened namespace '${NAMESPACE}'..."
if ! envsubst < deploy/k8s-templates/namespace.yaml | kubectl apply -f -; then
  echo "Error: failed to create/apply namespace '${NAMESPACE}'. Aborting before deploying components." >&2
  exit 1
fi

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
