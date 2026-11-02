# Deployment and configuration

## Architecture

| Image / service | Contents | Build tree |
| --- | --- | --- |
| robrowser | Node.js, Vite, pinned roBrowserLegacy frontend | images/robrowser |
| remote | Apache, PHP 8.4, PHP RemoteClient, ROEnglishRE, client resources | images/remote |
| wsproxy | WebSocket proxy to internal game services | images/wsproxy |
| rathena | Login/character/map servers | images/rathena |
| hercules | Alternative Compose game-server image | images/hercules |

The Apache image does not clone or contain the frontend. Only the frontend owns
`index.html.template`. `/remote/` and the pinned RemoteClient `.htaccess` remain
on the Apache service; `/` on that service is its static status page.

## Configuration sources

`.env-tmpl` is a starting template; preserve/edit the existing local `.env`.
Never commit passwords, private bootstrap output or client assets.

| Setting | Template/Pi value | Compose fallback | Kubernetes fallback | Internal port |
| --- | --- | --- | --- | --- |
| PORT_FRONTEND | 30000 | 3000 | 30000 | 3000 |
| PORT_HTTP | 30080 | 8080 | 30080 | 8080 |
| PORT_WSPROXY | 30599 | 5999 | 30599 | 5999 |

Compose uses these variables for **host** ports; Kubernetes templates use them
for **NodePorts**. Changing them does not change container listeners/target ports.
HOST must resolve from the browser: the verified Pi configuration uses HOST=pi.
Internal names `database` and `ragnarok-login` are not public browser hostnames;
wsProxy resolves game-service names inside the cluster/network.

- **Compose:** the root `.env` supplies interpolation and explicit service
  `env_file` configuration; mounts refer to this checkout's `client/` directories.
- **Full bootstrap:** `k8s-all.sh` honors ENV_FILE (default repository `.env`),
  CLIENT_SOURCE_DIR (default repository `client`), K8S_NAMESPACE (default
  ragnarok) and KUBECONFIG (default `/etc/rancher/k3s/k3s.yaml`). It changes to the
  repository root internally. Use absolute ENV_FILE/CLIENT_SOURCE_DIR paths when
  running from another worktree.
- **Offline renderers:** `render-web-manifests.sh` honors ENV_FILE;
  `render-k8s-bootstrap.py` accepts `--env-file` explicitly.
- **Flux:** reads `deploy/k8s/` through `deploy/overlays/flux`; it does not read
  local `.env`, rerun the renderer or upload local client files.
- **Legacy component scripts:** several still source `.env` directly. They are
  not the normal GitOps update path and do not all implement ENV_FILE semantics.

The web ConfigMap contains HOST, the three ports, SERVER_NAME, SET_PRERENEWAL
and PACKETVER. rathena-config contains non-secret DB/game configuration. The
private bootstrap Secret supplies both `password` (operator) and
`MARIADB_PASSWORD` (game containers), plus configured interserver credentials.
Passwords never belong in a Git-managed ConfigMap.

### Image-tag compatibility

`VITE_IMAGE_TAG` still selects the frontend/robrowser image. Legacy
`ROBROWSER_IMAGE_TAG` remains an Apache/remote fallback; REMOTE_IMAGE_TAG takes
precedence for that service. RATHENA_IMAGE_TAG and WSPROXY_IMAGE_TAG remain.
Do not silently reinterpret these existing variables during the image rename.

`k8s-all.sh` defaults to reviewed SHA tags from the Flux overlay and rejects empty
or stable selections. The standalone renderer/component scripts can default to
stable, so explicitly select reviewed releases before using their output for
production. See [Image revisions](image-revisions.md).

## Docker Compose

Docker Engine/Compose and local client files are prerequisites. From repository
root, validate without printing the expanded environment:

```bash
docker compose --env-file .env -f deploy/compose/docker-compose-common.yml -f deploy/compose/docker-compose-rathena.yml config --quiet
```

Starting Compose changes local containers; use it only for the intended local
installation, not to update a Kubernetes deployment:

```bash
./start.sh rathena detached
./start.sh hercules detached
```

The first argument selects the emulator; `./start.sh detached` is not valid.
Default `./start.sh` runs rAthena in the foreground. `./start.sh stop` stops the
Compose stacks. These are script interfaces, not commands executed during the
final documentation cleanup.

## Kubernetes

[Cluster setup](cluster-installation.md), [fresh stack installation](fresh-install-runbook.md)
and [normal operation](operations.md) are separate procedures. Existing K3s,
Longhorn, MariaDB operator and Flux must not be reinstalled as routine updates.

To review web manifests without changing the cluster:

```bash
ENV_FILE=/absolute/path/to/.env bash scripts/render-web-manifests.sh /tmp/ragnarok-web-review
kubectl kustomize deploy/overlays/flux
```

The renderer emits remote.yaml, robrowser.yaml, wsproxy.yaml and
robrowser-config.yaml. Review ports, namespace, public HOST, image references and
non-secret values before proposing Git changes. It does not automatically replace
the concrete manifests or update Flux. Never copy private bootstrap output into
`deploy/k8s/`.

## Translation, mounts and overrides

The remote build copies Renewal `data` and `SystemEN` (installed as `remote/System`)
from pinned ROEnglishRE. SET_PRERENEWAL=1 is a **build argument** adding the
Pre-Renewal layer afterwards. Runtime changes cannot rebuild those translations.
Required source directories are checked; optional Addons/Compatibility layers
are not silently installed.

`images/remote/repository_override/` is copied after translations into the Apache
document root. Use remote/data and remote/System for translation overrides.
`images/robrowser/repository_override/` is copied into /app after npm install and
the default frontend template. Most local payloads stay ignored by Git and are
not present in clean CI builds; the two API-module fix files are intentional
versioned exceptions. See [the iframe fix](frontend-api-module.md).

At startup, remote merges readonly /opt/client_files/data and System into its
writable translation tree, preserving the base and giving user loose files
precedence. Resources/BGM/AI retain their readonly mounts. Bootstrap uploads
local assets into the client-data PVC before starting the web deployments.

### Existing-checkout override folder rename

Git does not move ignored user files. If converting an OLD checkout, preserve the
old Apache images/robrowser/repository_override payload under images/remote,
and the old images/vite/repository_override frontend payload under
images/robrowser. Do not mix the two runtime payloads. This is a manual local-file
migration, not a reason to reset a namespace or overwrite working assets.
