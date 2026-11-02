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
- **robrowser**: Apache/PHP RemoteClient and baked ROEnglishRE translations
- **vite**: Node.js/Vite serving roBrowserLegacy
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

### External host and ports

`HOST` is embedded into the roBrowser client configuration. It must be reachable from the browser used to play the game. It controls the URL for the client files and the WebSocket proxy address. The login server address in the client is the internal service name `ragnarok-login`; wsProxy routes that connection inside the Compose/Kubernetes network. The rAthena login, character, and map ports are internal services and are not exposed as Kubernetes NodePorts.

Use `HOST=127.0.0.1` only when the browser runs on the same machine as the deployment. For LAN access, set it to the server's reachable IP address or DNS name, for example `HOST=192.168.2.210` or `HOST=raspberrypi.local`.

Compose defaults are frontend `3000`, HTTP/client files `8080`, and WebSocket proxy `5999`. The legacy Kubernetes scripts use NodePorts `30000`, `30080`, and `30599` respectively.

Names such as `database` and `ragnarok-login` are internal Compose/Kubernetes service names and must not be used as the externally visible `HOST`.

### Flux updates on the Pi

The Flux deployment uses the concrete Kustomize base in `deploy/k8s/` and the overlay in `deploy/overlays/flux/`. The legacy `scripts/k8s-*.sh` scripts use the configurable templates in `deploy/k8s-templates/`.

Flux does not read the local `.env`, and the concrete manifests are not automatically
generated from the templates. To prepare the web manifests using `.env`, run
`bash scripts/render-web-manifests.sh /tmp/ragnarok-web` and review the output.
Copy the reviewed `robrowser.yaml`, `vite.yaml`, `wsproxy.yaml` and
`robrowser-config.yaml` into `deploy/k8s/`, and include `robrowser-config.yaml` in
its `kustomization.yaml` if it is not already listed. Review the Flux overlay with
`kubectl kustomize deploy/overlays/flux` before submitting the Git change.
The renderer only exports the non-sensitive web ConfigMap fields; never commit `.env`.
It performs no cluster writes. Custom namespaces also require reviewing the base
resources and the overlay's namespace setting.

`PORT_HTTP`, `PORT_FRONTEND` and `PORT_WSPROXY` configure external NodePorts;
their Kubernetes fallbacks remain 30080, 30000 and 30599. Container and Service
target ports remain 8080, 3000 and 5999. In Compose, the same variables configure
host ports. Vite receives the shared `robrowser-config`, including `PORT_FRONTEND`;
its internal listener remains 3000 regardless of the external frontend port.

#### First rollout of the separate Vite image

The frontend NodePort moves from Service `robrowser` to Service `vite`, retaining
the configured `PORT_FRONTEND` (30000 by default). Kubernetes cannot allocate that
NodePort to both Services simultaneously. Schedule a short frontend interruption
and ensure the old frontend port is removed from Service `robrowser` before the
new Service `vite` is created. Do not rely on Flux's resource ordering for this
handover: use a reviewed two-stage GitOps rollout, first removing the old Service
port, then introducing the Vite resources. Coordinate with the Flux operator;
do not run an unreviewed reconciliation or delete the namespace.
Verify that a scanned `ghcr.io/raiken-mf/vite:stable` image exists before the
second stage. Vite has its own image override; the roBrowser override must never
select the Vite Deployment. Subsequent publication can pin Vite independently
to its security-approved `sha-<commit>` tag.

#### Merge gate for this migration

The checked-in Flux GitRepository follows `main`. With that configuration active,
merging these manifests can trigger reconciliation automatically; manually
running `flux reconcile` is not required. The application Kustomization has no
suspend flag and no dependency on completion of GitHub Actions. Therefore the
image security/publish workflow does not gate application of these manifests.

Do not merge this migration as a single unattended rollout. The current change
contains both sides of the NodePort handover and a newly managed ConfigMap with
example `HOST=127.0.0.1`. Flux can overwrite existing ConfigMap values, while
already-running pods keep their old environment until recreated. Also, the Flux
roBrowser override still selects `sha-6cfa563fd1c0c2bf2842345c1499b5bc485847c9`,
whose source Dockerfile builds the former combined image. That old Apache image
must not be paired with the new Vite frontend expecting `/remote/`.

Before merging, agree an operator-controlled rollout gate or prepare separate
migration changes, review the real ConfigMap values, and ensure both matching
new images are scanned and available. Preserve the existing ConfigMap keys that
the deployment needs when taking it under Git management. The publish workflow
also creates a GitOps image-bump PR and requests auto-merge; review that automation
as part of the migration plan. Repository code does not establish the live Flux
state, branch protections or whether GitHub auto-merge is enabled. No live state
was changed during local validation.

For routine Pi updates, reconcile Flux:

```bash
flux reconcile source git flux-system
flux reconcile kustomization ragnarok-stack -n flux-system --with-source
```

Do not use `scripts/k8s-all.sh` for routine Flux updates: it can delete and recreate
the namespace after explicit confirmation, and otherwise reconciles/restarts components.

### Environment Variables

Compose and the template-rendering scripts read `.env`. Flux uses the reviewed,
rendered manifests committed to Git; it does not read `.env` on the host:

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

### Translation and override order

The Apache build installs `Translation/Renewal/{data,SystemEN}` from the pinned
ROEnglishRE revision. With build argument `SET_PRERENEWAL=1`, it overlays
`Translation/Pre-Renewal/{data,SystemEN}` afterwards. `SystemEN` is installed as
`remote/System`, preserving Linux path case. Missing required layers fail the
build. Changing this flag at container runtime does not rebuild translations.
Optional upstream Additions, Compatibility patches and Addons are not installed
automatically.

Apache's `images/robrowser/repository_override/` is copied into the document root
after translations (use `remote/data/` and `remote/System/` for translation
overrides). Vite's `images/vite/repository_override/` is copied into `/app/` after
npm installation and the default template. To customize the generated index,
override `index.html.template`; the entrypoints regenerate `index.html` on start.
Loose files mounted at `/opt/client_files/data` and `/opt/client_files/System`
are merged into the Apache translation directories at startup, taking precedence
without hiding the translated base. GRF resources, BGM and AI remain read-only
external mounts. Override payloads are included in local Docker builds but ignored
by Git; therefore they are not automatically available to GitHub Actions builds.

### Local validation without deployment

After building local `robrowser:ci` and `vite:ci` images using the pins in
`build/dependencies.env`, run:

```bash
bash scripts/check-roenglish.sh robrowser:ci
python3 scripts/check-compose.py robrowser:ci vite:ci
```

The translation check builds a separate Pre-Renewal test image and checks every
installed translation against the ordered source layers using SHA-256. The
Compose check derives the two web services from the actual Compose configuration,
uses unique project networks and ephemeral loopback host ports, checks PHP and
Vite, and removes its test containers and networks afterwards. It intentionally
uses `--pull never` for these local test tags; deployment `pull_policy: always`
remains unchanged. The game server and database are not started by this web test.
