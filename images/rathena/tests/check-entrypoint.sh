#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
image=${1:-rathena:ci}
entrypoint="$root/images/rathena/entrypoint.sh"

for credential in MARIADB_PASSWORD SET_INTERSRV_PASSWORD; do
  docker run --rm --network none --entrypoint sh \
    --mount "type=bind,src=$entrypoint,dst=/tmp/entrypoint.sh,readonly" \
    -e INIT_DB=false -e "$credential=" \
    "$image" -c 'sh /tmp/entrypoint.sh true; result=$?; test "$result" -ne 0'
done

docker run --rm --network none --entrypoint sh \
  --mount "type=bind,src=$entrypoint,dst=/tmp/entrypoint.sh,readonly" \
  -e INIT_DB=true -e MARIADB_HOST=127.0.0.1 -e MARIADB_PASSWORD=fixture-db-only \
  "$image" -c 'sh /tmp/entrypoint.sh true; result=$?; test "$result" -ne 0'

docker run --rm --network none --entrypoint sh \
  --mount "type=bind,src=$entrypoint,dst=/tmp/entrypoint.sh,readonly" \
  -e INIT_DB=false -e MARIADB_PASSWORD=$'fixture\ninjected' \
  "$image" -c 'sh /tmp/entrypoint.sh true; result=$?; test "$result" -ne 0'

docker run --rm --network none --entrypoint sh \
  --mount "type=bind,src=$entrypoint,dst=/tmp/entrypoint.sh,readonly" \
  -e INIT_DB=false -e 'MARIADB_PASSWORD=fixture$literal' \
  "$image" -c 'sh /tmp/entrypoint.sh sh -c '\''test -z "${MYSQL_PWD+x}" && grep -Fx "login_server_pw: fixture\$literal" /opt/ragnarok/conf/import/inter_conf.txt >/dev/null'\'''

printf '%s\n' 'PASS rAthena entrypoint failure and configuration checks'