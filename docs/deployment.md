# Deployment Guide

## Overview

This guide explains how to deploy the robrowser_docker project using either Docker Compose or Kubernetes.

## Docker Compose Deployment

### Prerequisites

- Docker Compose installed
- Proper permissions for Docker daemon

### Deployment Steps

1. **Clone Repository**
   ```bash
   git clone https://github.com/raiken-mf/robrowser_docker.git
   cd robrowser_docker
   ```

2. **Prepare Client Files**
   Place your client files in the `client/` directory:
   - Ensure `DATA.INI` is all caps
   - Add required GRF files to appropriate subdirectories

3. **Configure Environment**
   ```bash
   cp .env-tmpl .env
   # Edit .env to set your preferences
   ```

4. **Deploy Services**
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

### Docker Compose Configuration

The Docker Compose setup uses:
- **database**: MariaDB with persistent storage
- **wsproxy**: WebSocket proxy for game connections
- **rathena/hercules**: Game server components
- **network**: Internal network for service communication

## Kubernetes Deployment

### Prerequisites

- Kubernetes cluster with `kubectl` access
- Helm installed (for MariaDB operator)
- Proper RBAC permissions

### Deployment Steps

1. **Clone Repository**
   ```bash
   git clone https://github.com/raiken-mf/robrowser_docker.git
   cd robrowser_docker
   ```

2. **Prepare Client Files**
   Place your client files in the `client/` directory:
   - Ensure `DATA.INI` is all caps
   - Add required GRF files to appropriate subdirectories

3. **Configure Environment**
   ```bash
   cp .env-tmpl .env
   # Edit .env to set your preferences
   ```

4. **Deploy Components**

   #### All-in-One Deployment
   ```bash
   ./scripts/k8s-all.sh
   ```

   #### Individual Deployments
   ```bash
   # Deploy only MariaDB
   ./scripts/k8s-mariadb.sh
   
   # Deploy only rathena server
   ./scripts/k8s-rathena.sh
   
   # Deploy only roBrowser
   ./scripts/k8s-robrowser.sh
   
   # Deploy only client data
   ./scripts/k8s-client-data.sh
   ```

### Kubernetes Architecture

The Kubernetes deployment consists of:

1. **Namespace**: Dedicated namespace for the application
2. **MariaDB**: Database service with persistence
3. **rathena/hercules**: Game server deployments
4. **roBrowser**: Web client deployment
5. **wsProxy**: WebSocket proxy service
6. **Persistent Volumes**: For client data and database storage

## Configuration Management

### Environment Variables

All configuration is managed through the `.env` file:

- **Database Settings**: Connection parameters for MariaDB
- **Server Settings**: Game server configuration
- **Client Settings**: Web client configuration
- **Security Settings**: Packet obfuscation and authentication

### Kubernetes ConfigMaps and Secrets

- **ConfigMaps**: Non-sensitive configuration data
- **Secrets**: Sensitive data like passwords and keys
- **Environment Variables**: Passed to containers from ConfigMaps/Secrets

## Scaling and High Availability

### Docker Compose Scaling

Docker Compose deployments are limited to single-instance deployments. For scaling, use Kubernetes.

### Kubernetes Scaling

The Kubernetes deployment supports horizontal scaling:

1. **Game Servers**: Scale rathena/hercules deployments independently
2. **Web Client**: Scale roBrowser deployment as needed
3. **Database**: Use MariaDB operator for high availability

## Monitoring and Logging

### Docker Compose Monitoring

- Container logs via `docker logs <container>`
- Resource usage via `docker stats`
- Health checks built into services

### Kubernetes Monitoring

- Pod logs via `kubectl logs <pod>`
- Metrics via Prometheus and Grafana
- Service monitoring via Kubernetes Dashboard
- Application logging via centralized logging solutions

## Backup and Recovery

### Database Backup

1. **Manual Backup**
   ```bash
   kubectl exec -it <mariadb-pod> -- mysqldump -u root -p database_name > backup.sql
   ```

2. **Automated Backup**
   - Use MariaDB operator backup features
   - Implement cron jobs for regular backups
   - Store backups in persistent storage

### Client Data Backup

1. **Persistent Volume Backup**
   - Backup PVC contents regularly
   - Use snapshots for rapid recovery
   - Implement versioning for data recovery

## Troubleshooting

### Common Docker Compose Issues

1. **Permission Denied**
   - Ensure Docker daemon is running
   - Check user permissions for Docker socket

2. **Port Conflicts**
   - Change ports in `.env` file
   - Stop conflicting services

3. **Network Issues**
   - Verify Docker network configuration
   - Check firewall settings

### Common Kubernetes Issues

1. **Pod Not Starting**
   - Check pod logs: `kubectl logs <pod>`
   - Verify resource limits
   - Check image pull secrets

2. **Service Connectivity**
   - Verify service endpoints
   - Check network policies
   - Validate DNS resolution

3. **Persistent Storage**
   - Check PVC status: `kubectl get pvc`
   - Verify storage class configuration
   - Confirm volume mounting

## Performance Optimization

### Docker Compose Optimization

1. **Resource Limits**
   - Set memory and CPU limits in docker-compose.yml
   - Monitor resource usage regularly

2. **Network Optimization**
   - Use bridge networks efficiently
   - Minimize external network dependencies

### Kubernetes Optimization

1. **Resource Requests and Limits**
   - Define appropriate resource requests/limits
   - Use Horizontal Pod Autoscaler for scaling

2. **Node Affinity**
   - Use node selectors for optimal placement
   - Implement pod affinity/anti-affinity

3. **Storage Optimization**
   - Use appropriate storage classes
   - Implement storage capacity monitoring