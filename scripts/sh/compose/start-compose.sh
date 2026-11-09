#!/bin/bash

cd "$(dirname "$0")/../../.." || exit 1

if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi
if ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose is not installed or not in PATH"
    exit 1
fi

# Verify the Docker daemon is actually reachable (CLI presence alone is not enough).
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not reachable. Is the Docker service running (and do you have permission to access it)?"
    exit 1
fi

EMULATOR=${1:-rathena}
EMULATOR=$(echo "$EMULATOR" | tr '[:upper:]' '[:lower:]')

MODE=""
if [ "${2:-}" == "detached" ]; then
    MODE="-d"
fi

ENV_FILE=${ENV_FILE:-.env}
COMPOSE_ENV=()
if [ -f "$ENV_FILE" ] && [ -r "$ENV_FILE" ]; then
    COMPOSE_ENV=(--env-file "$ENV_FILE")
elif [ "$EMULATOR" != stop ] && [ "$EMULATOR" != down ]; then
    echo "Error: Compose environment file is missing or unreadable" >&2
    exit 1
else
  COMPOSE_ENV=(--env-file /dev/null)
fi

case "$EMULATOR" in
  rathena)
    docker compose "${COMPOSE_ENV[@]}" -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-rathena.yml up $MODE
    ;;
  hercules)
    docker compose "${COMPOSE_ENV[@]}" -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-hercules.yml up $MODE
    ;;
  stop|down)
    docker compose "${COMPOSE_ENV[@]}" -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-rathena.yml "$EMULATOR" || exit $?
    override=$(mktemp "${TMPDIR:-/tmp}/compose-lifecycle.XXXXXXXX") || exit 1
    trap 'rm -f "$override"' EXIT
    printf 'services:\n  hercules:\n    env_file: !reset []\n' > "$override" || exit 1
    docker compose "${COMPOSE_ENV[@]}" -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-hercules.yml -f "$override" "$EMULATOR"
    ;;
  *)
    echo "Usage: $0 [rathena|hercules] [detached] | stop | down"
    exit 1
    ;;
esac
