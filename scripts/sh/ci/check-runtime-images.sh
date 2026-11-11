#!/usr/bin/env bash
set -euo pipefail

hercules_image="${1:?Hercules image required}"
wsproxy_image="${2:?wsProxy image required}"
root="$(cd "$(dirname "$0")/../../.." && pwd)"

docker run --rm --network none --entrypoint sh "$hercules_image" -ec '
  test "$(id -u)" != 0
  test -w /opt/ragnarok/conf/import
  test -w /opt/ragnarok/conf/global
  test -w /opt/ragnarok/npc
  command -v mariadb
  ! command -v git
  ! command -v gcc
  for binary in login-server char-server map-server; do
    ldd "/opt/ragnarok/$binary"
  done
'
for renewal in 0 1; do
  docker run --rm --network none -e MARIADB_PASSWORD=fixture \
    -e SET_INTERSRV_PASSWORD=fixture -e SET_PRERENEWAL="$renewal" \
    -e INIT_ONLY=true "$hercules_image"
done

docker run --rm --network none --entrypoint sh "$wsproxy_image" -ec '
  test "$(id -u)" = 1000
  ! command -v npm
'
container=$(docker run -d --network none "$wsproxy_image" -a ragnarok-login:6900)
trap 'docker stop "$container" >/dev/null' EXIT
docker exec -i "$container" node - < "$root/images/wsproxy/tests/check-wsproxy.cjs"