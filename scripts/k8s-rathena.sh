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
export MARIADB_HOST="${MARIADB_HOST:-mariadb}"
export MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
export MARIADB_USER="${MARIADB_USER:-ragnarok-user}"
export SET_INTERSRV_USER="${SET_INTERSRV_USER:-u1}"
export SET_INTERSRV_PASSWORD="${SET_INTERSRV_PASSWORD:-p1}"
export SET_PRERENEWAL="${SET_PRERENEWAL:-0}"
export SET_NEW_ACCOUNT="${SET_NEW_ACCOUNT:-yes}"
export SET_PINCODE_ENABLED="${SET_PINCODE_ENABLED:-no}"
export SET_MOTD="${SET_MOTD:-SORCERY!!!}"

echo "==> 2. Ensuring target namespace '${NAMESPACE}' exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> 3. Creating/updating rathena-config ConfigMap..."
kubectl create configmap rathena-config \
  --namespace "${NAMESPACE}" \
  --from-literal=LOGIN_SERVER_HOST="ragnarok-login" \
  --from-literal=CHAR_SERVER_HOST="ragnarok-char" \
  --from-literal=MAP_SERVER_HOST="ragnarok-map" \
  --from-literal=MARIADB_HOST="${MARIADB_HOST}" \
  --from-literal=MARIADB_DATABASE="${MARIADB_DATABASE}" \
  --from-literal=MARIADB_USER="${MARIADB_USER}" \
  --from-literal=SET_INTERSRV_USER="${SET_INTERSRV_USER}" \
  --from-literal=SET_INTERSRV_PASSWORD="${SET_INTERSRV_PASSWORD}" \
  --from-literal=SET_PRERENEWAL="${SET_PRERENEWAL}" \
  --from-literal=SET_NEW_ACCOUNT="${SET_NEW_ACCOUNT}" \
  --from-literal=SET_PINCODE_ENABLED="${SET_PINCODE_ENABLED}" \
  --from-literal=SET_MOTD="${SET_MOTD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4. Applying rAthena Kubernetes manifests..."
envsubst < k8s/rathena.yaml | kubectl apply -f -

echo "==> 5. Waiting for Login Server rollout..."
kubectl rollout status deployment/ragnarok-login -n "${NAMESPACE}" --timeout=120s

echo "==> 6. Ensuring database schema & inter-server credentials..."
DB_PASS=$(kubectl get secret mariadb-user-secret -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

# Check if login table exists
TABLE_EXISTS=$(kubectl exec -i "${MARIADB_HOST}-0" -n "${NAMESPACE}" -- mariadb -u "${MARIADB_USER}" -p"${DB_PASS}" -D "${MARIADB_DATABASE}" -sN -e "SHOW TABLES LIKE 'login';" || true)

if [ -z "${TABLE_EXISTS}" ]; then
  echo "==> Schema not found. Importing rAthena SQL files from login-server container..."
  LOGIN_POD=$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/name=ragnarok-login -o jsonpath='{.items[0].metadata.name}')
  
  for sql in main.sql logs.sql item_db.sql mob_db.sql item_db_re.sql mob_db_re.sql; do
    kubectl exec -i "${LOGIN_POD}" -n "${NAMESPACE}" -c login-server -- cat "/opt/ragnarok/sql-files/${sql}" 2>/dev/null \
      | kubectl exec -i "${MARIADB_HOST}-0" -n "${NAMESPACE}" -- mariadb -u "${MARIADB_USER}" -p"${DB_PASS}" "${MARIADB_DATABASE}" 2>/dev/null || true
  done
fi

echo "==> Updating inter-server account (${SET_INTERSRV_USER})..."
kubectl exec -i "${MARIADB_HOST}-0" -n "${NAMESPACE}" -- mariadb -u "${MARIADB_USER}" -p"${DB_PASS}" "${MARIADB_DATABASE}" <<EOSQL
INSERT INTO \`login\` (\`account_id\`, \`userid\`, \`user_pass\`, \`sex\`, \`group_id\`)
VALUES (1, '${SET_INTERSRV_USER}', '${SET_INTERSRV_PASSWORD}', 'S', 99)
ON DUPLICATE KEY UPDATE \`userid\`='${SET_INTERSRV_USER}', \`user_pass\`='${SET_INTERSRV_PASSWORD}', \`sex\`='S';
EOSQL

echo "==> 7. Restarting Login, Char and Map servers..."
kubectl rollout restart deployment/ragnarok-login -n "${NAMESPACE}"
kubectl rollout restart deployment/ragnarok-char -n "${NAMESPACE}"
kubectl rollout restart deployment/ragnarok-map -n "${NAMESPACE}"

echo "==> 8. Waiting for rAthena rollout..."
kubectl rollout status deployment/ragnarok-login -n "${NAMESPACE}" --timeout=120s
kubectl rollout status deployment/ragnarok-char -n "${NAMESPACE}" --timeout=120s
kubectl rollout status deployment/ragnarok-map -n "${NAMESPACE}" --timeout=120s

echo "==> All rAthena services successfully running! ⚔️"
kubectl get pods -n "${NAMESPACE}" -l 'app.kubernetes.io/name in (ragnarok-login, ragnarok-char, ragnarok-map)'
