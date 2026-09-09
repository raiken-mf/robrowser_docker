#!/bin/bash

dir="$(dirname "$0")"

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if docker compose is available
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose is not installed or not in PATH"
    exit 1
fi

"$dir/scripts/install_docker.sh"

EMULATOR=${1:-rathena}
EMULATOR=$(echo "$EMULATOR" | tr '[:upper:]' '[:lower:]')

MODE=""
if [ "$2" == "detached" ]; then
    MODE="-d"
fi

case "$EMULATOR" in
  rathena)
    docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml up $MODE
    ;;
  hercules)
    docker compose -f ./docker-compose-common.yml -f ./docker-compose-hercules.yml up $MODE
    ;;
  stop)
    docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml stop
    docker compose -f ./docker-compose-common.yml -f ./docker-compose-hercules.yml stop
    ;;
  *)
    echo "Usage: $0 [rathena|hercules] [detached]"
    exit 1
    ;;
esac
