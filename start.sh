#!/bin/bash

dir="$(dirname "$0")"

# Install Docker only when it is not already available.
if ! command -v docker &> /dev/null; then
    "$dir/scripts/install_docker.sh" || exit 1
fi

# Check if docker and docker compose are available after installation.
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
if [ "$2" == "detached" ]; then
    MODE="-d"
fi

case "$EMULATOR" in
  rathena)
    docker compose -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-rathena.yml up $MODE
    ;;
  hercules)
    docker compose -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-hercules.yml up $MODE
    ;;
  stop)
    docker compose -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-rathena.yml stop
    docker compose -f ./deploy/compose/docker-compose-common.yml -f ./deploy/compose/docker-compose-hercules.yml stop
    ;;
  *)
    echo "Usage: $0 [rathena|hercules] [detached]"
    exit 1
    ;;
esac
