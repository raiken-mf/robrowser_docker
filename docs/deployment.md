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

| Setting | Template value | Compose fallback | Kubernetes fallback | Internal port |
| --- | --- | --- | --- | --- |
| PORT_FRONTEND | 30000 | 3000 | 30000 | 3000 |
| PORT_HTTP | 30080 | 8080 | 30080 | 8080 |
| PORT_WSPROXY | 30599 | 5999 | 30599 | 5999 |

Compose uses these variables for **host** ports; Kubernetes templates use them
for **NodePorts**. Changing them does not change container listeners/target ports.
HOST must resolve from the browser; the template uses `127.0.0.1` for local access.
The Kubernetes base retains the existing host until the staged Flux migration is
complete. Set a reachable hostname or IP for remote clients.
Vite accepts this hostname, localhost and IP addresses; cross-origin reads are
disabled. Configure the browser-facing hostname explicitly when using DNS.
Internal names `database` and `ragnarok-login` are not public browser hostnames;
wsProxy resolves game-service names inside the cluster/network.

- **Compose:** the root `.env` supplies interpolation; the rAthena stack passes
  selected variables explicitly. Mounts refer to this checkout's `client/` directories.
- **Full bootstrap:** `k8s-all.sh` honors ENV_FILE (default repository `.env`),
  CLIENT_SOURCE_DIR (default repository `client`), K8S_NAMESPACE (default
  ragnarok) and KUBECONFIG (default `/etc/rancher/k3s/k3s.yaml`). It changes to the
  repository root internally. Use absolute ENV_FILE/CLIENT_SOURCE_DIR paths when
  running from another worktree.
- **Offline renderers:** `render-web-manifests.sh` honors ENV_FILE;
  `render-k8s-bootstrap.py` accepts `--env-file` explicitly.
- **Flux:** reads `deploy/k8s/base/` through `deploy/k8s/overlays/flux`; it does not read
  local `.env`, rerun the renderer or upload local client files. The existing
  cluster's Flux Kustomization patches its own
  hostname; configure that patch for your installation before reconciliation.
- **Legacy component scripts:** several still source `.env` directly. They are
  not the normal GitOps update path and do not all implement ENV_FILE semantics.
  The MariaDB component installer accepts ENV_FILE and defaults to `.env`.

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
./scripts/sh/compose/start-compose.sh rathena detached
./scripts/sh/compose/start-compose.sh hercules detached
```

The starter uses the repository-root `.env` for Compose interpolation; set
`ENV_FILE` to select another file. Shell environment variables take precedence.
The first argument selects the emulator; `./scripts/sh/compose/start-compose.sh detached` is not valid.
Default `./scripts/sh/compose/start-compose.sh` runs rAthena in the foreground. `./scripts/sh/compose/start-compose.sh stop` stops the
Compose stacks; `./scripts/sh/compose/start-compose.sh down` removes them.
Stopping or removing the stacks does not require database credentials or an env file.
Starting the rAthena stack requires nonempty database and interserver passwords;
MariaDB also requires a root password for initialization.

The starter checks Docker and Compose but does not install them. The historical
`./start.sh` entrypoint forwards to it. Compose mounts `deploy/compose/conf.d` read-only;
local configuration files there are ignored by Git. Before restarting an existing
Compose installation, copy any operator-owned overrides from the former
`database/conf.d` directory to `deploy/compose/conf.d` and review them. The old
directory remains ignored to protect overrides left behind. Kubernetes explicitly configures `utf8mb4_unicode_ci`
and UTC. Verify collation and time-zone requirements before moving data between
the two environments. Compose does not configure persistent database storage;
plan and test persistence and backups before using it for valuable data.

## Kubernetes

The legacy `scripts/sh/k8s/k8s-rathena.sh` installer is disabled because it exposed
credentials and interpolated SQL. Use the reviewed fresh-install procedure;
its preflight is read-only and cluster changes require separate approval.

[Cluster setup](cluster-installation.md), [fresh stack installation](fresh-install-runbook.md)
and [normal operation](operations.md) are separate procedures. Existing K3s,
Longhorn, MariaDB operator and Flux must not be reinstalled as routine updates.

To review web manifests without changing the cluster:

```bash
ENV_FILE=/absolute/path/to/.env bash scripts/sh/k8s/render-web-manifests.sh /tmp/ragnarok-web-review
kubectl kustomize deploy/k8s/overlays/flux
```

The renderer emits remote.yaml, robrowser.yaml, wsproxy.yaml and
robrowser-config.yaml. Review ports, namespace, public HOST, image references and
non-secret values before proposing Git changes. It does not automatically replace
the concrete manifests or update Flux. Never copy private bootstrap output into
`deploy/k8s/base/`.

## Translation, mounts and overrides

The remote image includes the pinned ROEnglishRE source. At container startup,
`SET_PRERENEWAL=1` selects the Pre-Renewal translation layer; `0` selects Renewal.
Restart the container after changing runtime settings. The rAthena image also
uses `SET_PRERENEWAL` at build time to select its server ruleset; keep the build
and runtime settings consistent. Required source directories are checked, and
the `ROENGLISH_*` runtime options control optional layers.

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
