#!/bin/bash

dir="$(dirname "$0")"

"$dir/scripts/install_docker.sh"

EMULATOR=${1:-rathena}
EMULATOR=$(echo "$EMULATOR" | tr '[:upper:]' '[:lower:]')

MODE=""
if [ "$2" == "detached" ]; then
    MODE="-d"
fi

case "$EMULATOR" in
  rathena)
    sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml up --build $MODE
    ;;
  hercules)
    sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-hercules.yml up --build $MODE
    ;;
  stop)
    sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml down
    sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-hercules.yml down
    ;;
  *)
    exit 1
    ;;
esac
