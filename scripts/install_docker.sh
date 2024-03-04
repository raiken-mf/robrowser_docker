#!/bin/bash

function install_docker() {
    if [ ! -x "$(command -v docker)" ]; then
        echo "Installing docker..."
        sudo apt-get -y install ca-certificates curl gnupg
        sudo mkdir -m 0755 -p /etc/apt/keyrings

        if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
            distribution=$(lsb_release -si)
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${distribution,,}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
        fi;

        if [ ! -f "/etc/apt/sources.list.d/docker.list" ]; then
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distribution,,} \
                $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
        fi;
        
        sudo apt-get update
        sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        #sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
        #sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        sudo systemctl enable docker
    fi;
    sudo service docker start
}

install_docker