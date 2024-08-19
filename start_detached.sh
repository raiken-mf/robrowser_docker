#!/bin/bash

dir="$(dirname "$0")"

"$dir/scripts/install_docker.sh"
sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml up --build -d
