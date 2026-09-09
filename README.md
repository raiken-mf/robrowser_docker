# robrowser_docker

This project sets up a database, downloads and compiles the latest versions of [rathena](https://github.com/rathena/rathena)/[Hercules](https://github.com/HerculesWS/Hercules) and [roBrowserLegacy](https://github.com/MrAntares/roBrowserLegacy).
The translation of the project is used from llchrisll's repository [ROEnglishRE](https://github.com/llchrisll/ROenglishRE).
You can override files in `repository_override` if you feel like changing settings, npcs or source files.

## Features

- **Dual Orchestration**: Supports both Docker Compose and Kubernetes deployment
- **Flexible Server Options**: Choose between rathena or Hercules server implementations
- **Dynamic Configuration**: All ports configurable via `.env` file
- **Consistent Architecture**: Same configuration patterns for both deployment methods
- **Easy Setup**: Simple one-command deployment for both environments

## Prerequisites

- **Docker Compose** (for Docker deployment)
- **Kubernetes cluster** with `kubectl` access (for Kubernetes deployment)
- **Client files** (DATA.INI and GRF files) in the `client/` directory

## How to Use the Project

### 1. Clone the Repository
```bash
git clone https://github.com/raiken-mf/robrowser_docker.git
cd robrowser_docker
```

### 2. Prepare Client Files
Put your client files in the `client/` folder:
- Make sure `DATA.INI` is all caps
- Add required GRF files to the appropriate subdirectories

### 3. Configure Environment Variables
Copy the template and customize:
```bash
cp .env-tmpl .env
# Edit .env to set your preferences
```

### 4. Choose Your Deployment Method

#### Docker Compose Deployment
```bash
# Run with rathena (default)
./start.sh

# Run with Hercules
./start.sh hercules

# Run detached with rathena
./start.sh detached

# Run detached with Hercules
./start.sh hercules detached
```

#### Kubernetes Deployment
```bash
# Deploy all components to Kubernetes
./scripts/k8s-all.sh

# Deploy only MariaDB
./scripts/k8s-mariadb.sh

# Deploy only rathena server
./scripts/k8s-rathena.sh

# Deploy only roBrowser
./scripts/k8s-robrowser.sh

# Deploy only client data
./scripts/k8s-client-data.sh
```

## Configuration Options

All configuration is managed through the `.env` file:

Variable | Description | Default
---------|-------------|--------
`MARIADB_ROOT_USER` | MariaDB root user | `root`
`MARIADB_ROOT_PASSWORD` | MariaDB root password | `SomeRootPassword`
`MARIADB_HOST` | MariaDB hostname | `database`
`MARIADB_DATABASE` | Database name | `ragnarok`
`MARIADB_USER` | Database user | `ragnarok`
`MARIADB_PASSWORD` | Database password | `SomePassword`
`SET_INTERSRV_USER` | Inter-server user | `u1`
`SET_INTERSRV_PASSWORD` | Inter-server password | `p1`
`SET_MOTD` | Message of the day | `SORCERY!!!`
`PACKETVER` | Packet version | `20211103`
`SET_PRERENEWAL` | Enable pre-renewal mode | `0`
`HOST` | Host address | `127.0.0.1`
`PORT_HTTP` | HTTP port for roBrowser | `30080`
`PORT_WSPROXY` | WebSocket proxy port | `30599`
`PORT_FRONTEND` | Frontend port for roBrowser | `30000`

## Useful Commands

### WSL (Run as Administrator):
Replace `(wsl hostname -I)` with the 1st IP that's printed when running the command
```bash
netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=(wsl hostname -I)
netsh interface portproxy add v4tov4 listenport=5999 listenaddress=0.0.0.0 connectport=5999 connectaddress=(wsl hostname -I)
```

### Linux:
```bash
sudo apt-get install ufw
sudo ufw allow 80
sudo ufw allow 5999
sudo ufw allow 22
sudo ufw enable
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Make sure you have proper permissions for Docker/Kubernetes
2. **Port Conflicts**: Change ports in `.env` if needed
3. **Missing Client Files**: Ensure all required client files are present in `client/` directory
4. **Kubernetes Not Available**: Verify your Kubernetes cluster is accessible

### Debugging Tips

- Check container logs: `docker logs <container-name>` or `kubectl logs <pod-name>`
- Verify network connectivity between services
- Confirm `.env` file has correct values
- Ensure sufficient system resources for all containers/services

## Contributing

Contributions are welcome! Please submit issues and pull requests to the repository.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.