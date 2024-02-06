# robrowser_docker

netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=(wsl hostname -I)
netsh interface portproxy add v4tov4 listenport=5999 listenaddress=0.0.0.0 connectport=5999 connectaddress=(wsl hostname -I)


sudo apt-get install ufw
sudo ufw allow 80
sudo ufw allow 5999
sudo ufw allow 22
sudo ufw enable


192.168.2.102