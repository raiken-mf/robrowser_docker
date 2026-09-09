#!/bin/bash

set -e

function install_docker() {
    if [ ! -x "$(command -v docker)" ]; then
        echo "Installing docker..."
        apt-get -y install ca-certificates curl gnupg
        mkdir -m 0755 -p /etc/apt/keyrings

        if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
            distribution=$(lsb_release -si)
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${distribution,,}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        fi;

        if [ ! -f "/etc/apt/sources.list.d/docker.list" ]; then
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distribution,,} \
                $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
        fi;

        apt-get update
        apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        #update-alternatives --set iptables /usr/sbin/iptables-legacy
        #update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        systemctl enable docker
    fi;
    service docker start
}

install_docker
