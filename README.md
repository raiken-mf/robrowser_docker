# robrowser_docker
This project sets up a database, downloads and compiles the latest versions of [rathena](https://github.com/rathena/rathena)/[Hercules](https://github.com/HerculesWS/Hercules) and [roBrowserLegacy](https://github.com/MrAntares/roBrowserLegacy).
The translation of the project is used from llchrisll's repository [ROEnglishRE](https://github.com/llchrisll/ROenglishRE).
You can override files in `repository_override` if you feel like changing settings, npcs or source files.

# How to use the project
1. Clone the git repository:
   ```
   git clone https://github.com/raiken-mf/robrowser_docker.git
   ```
2. Put your client files in the client folder (Make sure DATA.INI is all caps)
3. Copy the `.env-tmpl` and name it `.env`
4. Edit the settings in `.env`
5. To run the project simply run `./start.sh`, this will install docker if it isn't already and sets up rathena as server
   - Run the project detached with rathena
     ```sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-rathena.yml up --build -d```
   - Run the project detached with Hercules
     ```sudo docker compose -f ./docker-compose-common.yml -f ./docker-compose-hercules.yml up --build -d```

# Useful commands on WSL (Run as Administrator):
Replace `(wsl hostname -I)` with the 1st IP that's printed when running the command
```
netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=(wsl hostname -I)
netsh interface portproxy add v4tov4 listenport=5999 listenaddress=0.0.0.0 connectport=5999 connectaddress=(wsl hostname -I)
```

# Useful commands on Linux:
```
sudo apt-get install ufw
sudo ufw allow 80
sudo ufw allow 5999
sudo ufw allow 22
sudo ufw enable
```