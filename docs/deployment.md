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
- **remote**: Apache/PHP RemoteClient and baked ROEnglishRE translations
- **robrowser**: Node.js/Vite serving roBrowserLegacy
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
   # Read-only check; installation needs separate approval
   ./scripts/k8s-all.sh --check
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

### Flux fresh installation on the Pi

The operator has removed namespace `ragnarok` and suspended both `flux-system`
and `ragnarok-stack`. Keep them suspended until explicit installation approval.
No in-place migration or two-stage NodePort handover is needed. #85 is superseded.
See [Fresh namespace installation](flux-split-migration.md) for the deployment hold
and image release gates. Do not run deployment scripts or resume Flux during
repository preparation.

The final services/images are `robrowser` (frontend, Node.js/Vite, port 3000) and
`remote` (Apache/PHP/client files, port 8080). Flux uses `deploy/k8s/` through
`deploy/overlays/flux/`; the legacy scripts use `deploy/k8s-templates/`.
Flux does not read `.env`. Render without changing the cluster:

```bash
bash scripts/render-web-manifests.sh /tmp/ragnarok-web
kubectl kustomize deploy/overlays/flux
```

Review `remote.yaml`, `robrowser.yaml`, `wsproxy.yaml` and `robrowser-config.yaml`
before copying generated configuration into Git. The renderer only emits reviewed
non-secret web keys; never commit `.env`. The reviewed Pi values remain HOST=pi,
PORT_HTTP=30080, PORT_FRONTEND=30000 and PORT_WSPROXY=30599.

`PORT_HTTP`, `PORT_FRONTEND` and `PORT_WSPROXY` configure external NodePorts
(fallbacks 30080/30000/30599); target ports remain 8080/3000/5999. Compose retains
its host-port fallbacks 8080/3000/5999. Both web services consume the shared
`robrowser-config`; PORT_FRONTEND never changes Vite's internal listener.

For compatibility, `VITE_IMAGE_TAG` still selects the frontend tag;
`ROBROWSER_IMAGE_TAG` remains the legacy Apache tag setting. `REMOTE_IMAGE_TAG`
can explicitly override the latter. Their registry names are now robrowser and
remote respectively. Existing custom tag values must identify an actually
published artifact under the new repository; old-name tags are not copied or
invented automatically. The first new-name main release must pass all security,
SBOM and digest-promotion gates before its generated image-pin PR is reviewed.
Never deploy the old Apache `robrowser:stable` as the new frontend. The new
frontend readiness probe requests its API module to reject that wrong runtime.
Keep the reviewed release pins and Flux paused until the separate installation
approval.

### Override folder rename

The versioned trees are renamed, but existing untracked user overrides are not
moved by Git. Before building in an existing checkout, preserve/move the OLD
Apache `images/robrowser/repository_override` payload to
`images/remote/repository_override`, and the OLD `images/vite/repository_override`
payload to `images/robrowser/repository_override`. Do not let Apache overrides
silently enter the renamed frontend build. Each image's independent fixture tests
verify its own marker and index override.

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

Apache's `images/remote/repository_override/` is copied into the document root
after translations (use `remote/data/` and `remote/System/` for translation
overrides). Vite's `images/robrowser/repository_override/` is copied into `/app/` after
npm installation and the default template. Vite alone owns and renders `images/robrowser/index.html.template`; override its
`index.html.template` to customize the browser configuration. Apache serves a
static `images/remote/index.html` status page at `/` for existing probes;
override `index.html` in its own override directory to customize that page.
Apache does not clone roBrowserLegacy or generate frontend configuration.
Loose files mounted at `/opt/client_files/data` and `/opt/client_files/System`
are merged into the Apache translation directories at startup, taking precedence
without hiding the translated base. GRF resources, BGM and AI remain read-only
external mounts. Override payloads are included in local Docker builds but ignored
by Git; therefore they are not automatically available to GitHub Actions builds.

### Local validation without deployment

After building local `remote:ci` and `robrowser:ci` images using the pins in
`build/dependencies.env`, run:

```bash
bash scripts/check-roenglish.sh remote:ci
bash scripts/check-image-boundaries.sh remote:ci robrowser:ci
python3 scripts/check-image-overrides.py
python3 scripts/check-compose.py remote:ci robrowser:ci
```

The translation check builds a separate Pre-Renewal test image and checks every
installed translation against the ordered source layers using SHA-256. The
Compose check derives the two web services from the actual Compose configuration,
uses unique project networks and ephemeral loopback host ports, checks PHP and
Vite, and removes its test containers and networks afterwards. It intentionally
uses `--pull never` for these local test tags; deployment `pull_policy: always`
remains unchanged. The game server and database are not started by this web test.


### Image source boundaries

Only Vite accepts `ROBROWSER_REPOSITORY` and `ROBROWSER_REF` and clones the
roBrowserLegacy frontend. Apache accepts only RemoteClient and ROEnglishRE source
arguments plus `SET_PRERENEWAL`. Its PHP includes and routing come entirely from
the pinned RemoteClient repository; no frontend checkout is needed. The upstream
`remote/.htaccess` remains installed, including `ErrorDocument 404 /remote/index.php`.

A request to `/remote/api/health/simple` exercises that fallback and PHP execution.
It returns 200 with valid GRFs or a JSON health status with 503 when GRFs are absent
(as in clean CI). The static `/` remains 200 without GRFs and contains no frontend
script. Frontend configuration is tested on Vite rather than Apache.

`check-image-boundaries.sh` rejects frontend directories/manifests in Apache and
also checks image build history so a deleted frontend checkout cannot pass the
filesystem check. Both images retain independent build-time overrides. Changing
an Apache override does not change the Vite frontend configuration.

### Complete fresh bootstrap

See [Fresh-install runbook](fresh-install-runbook.md). `k8s-all.sh` defaults to
read-only `--check`; after approval `--apply` provisions the complete application
stack from local `.env`, including private Secrets, ConfigMaps, PVC/data, MariaDB
and automatic rAthena schema initialization. It never resumes Flux or deletes a
namespace. Existing namespace retries require explicit `--reconcile`.
