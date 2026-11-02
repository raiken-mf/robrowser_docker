# Approved fresh installation: runbook and current preparation

No commands in the installation sections have been executed. Namespace `ragnarok`
is absent; both `flux-system` and `ragnarok-stack` stay suspended. The operator
explicitly selected an empty new `ragnarok` database, with no backup restoration.
All credentials and variables come from the operator's local `.env`; it is never
committed. In particular preserve HOST=pi and PORT_FRONTEND=30000.

## Prepared inputs

- #87 selects the published/scanned `remote` and `robrowser` releases from source
  `6c00eb847d9f65c9b0f4c941140b790177c37470`. rAthena and wsProxy keep their
  independently verified existing releases. All four images allow anonymous
  registry access, support ARM64/AMD64 and need no imagePullSecret on this cluster.
- `robrowser-config` contains the reviewed non-secret web settings. New
  `rathena-config` supplies the previously missing game-server/DB configuration,
  excluding passwords/interserver credentials.
- `render-k8s-bootstrap.py` renders `mariadb-root-secret`, `mariadb-user-secret`
  and the `.env`-derived rathena-config locally. The user Secret supplies BOTH
  `password` (MariaDB operator) and `MARIADB_PASSWORD` (rAthena), plus the configured
  interserver user/password. No defaults/generated passwords replace `.env`.
  Secret output is owner-only (directory 0700/file 0600), never printed or pushed;
  an existing output file is not overwritten. It does not contact Kubernetes.
- Longhorn, the MariaDB operator/webhook and their CRDs are already available.
  The DB network policy keeps existing application restrictions and additionally
  permits only the labeled MariaDB controller in namespace mariadb-operator on
  port 3306. This is required by the installed operator
  [SQL reconciler](https://github.com/mariadb-operator/mariadb-operator/blob/v26.6.0/pkg/controller/sql/controller.go),
  which creates the Database/User/Grant over SQL.
  Client PVC: 15Gi RWX; database: new 5Gi Longhorn storage. Old ragnarok PVs are
  gone; no old data is needed. Local client AI/BGM/data/System/resources and the
  three DATA.INI-referenced GRFs are available for the new client volume.
- The reviewed NodePorts are free: remote 30080 -> 8080, frontend 30000 -> 3000,
  wsProxy 30599 -> 5999. Existing variable names/fallbacks are preserved.

## Read-only preparation — permitted before approval

Use the CURRENT main scripts, not an older checkout's old destructive k8s-all.sh.
The original working checkout/ignored client files do not need to be moved:

```bash
git fetch origin main
git worktree add --detach /tmp/ragnarok-approved-install origin/main
cd /tmp/ragnarok-approved-install
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export ENV_FILE=/home/pi/git/robrowser_docker/.env
export CLIENT_SOURCE_DIR=/home/pi/git/robrowser_docker/client
bash scripts/k8s-all.sh --check
kubectl kustomize deploy/overlays/flux > /tmp/ragnarok-reviewed-manifests.yaml
```

`--check` (also the no-argument default) loads `.env`, renders private temporary
bootstrap data, checks API errors, operators/storage, Flux suspension, port
ownership and client-source completeness, then removes its temporary files.
It never applies resources, deletes namespaces, restarts workloads or resumes
Flux. Inspect the reviewed non-secret rendering before approving installation.

## Installation — DO NOT EXECUTE before separate operator approval

From the reviewed worktree and environment above:

```bash
bash scripts/k8s-all.sh --apply
```

This is the full automatic application bootstrap; it does not install/upgrade
cluster infrastructure operators, which are checked as prerequisites. It:

1. Rechecks prerequisites with Flux still paused. Existing namespaces require
   `--apply --reconcile` for an expressly approved retry; the script never deletes
   a namespace. API/auth failures abort rather than being treated as NotFound.
2. Applies the hardened namespace, restrictive DB network policy, Secrets and
   both `.env`-derived ConfigMaps. Secret values stay out of local CLI arguments
   and logs. Existing passwords from `.env` are used exactly as configured.
3. Creates MariaDB/Database/User/Grant resources and waits for their Ready
   conditions. The database is new and empty; there is no backup import.
4. Creates/populates the client PVC using the non-root loader. Client paths are
   relative to CLIENT_SOURCE_DIR, not the caller's working directory. Every
   streamed file's byte count is checked; failures stop before web deployments.
5. Starts rAthena in login/char/map dependency order. The login entrypoint with
   INIT_DB=true automatically imports the fresh schema, Renewal/Pre-Renewal data
   according to SET_PRERENEWAL, and the configured interserver account. Char/map
   use INIT_DB=false. The script verifies the initialized interserver DB row
   without exposing credentials or putting passwords in local command arguments.
6. Deploys/waits for wsProxy, remote and robrowser using the selected release tags.
   It checks a real wsProxy WebSocket handshake and parses the mounted first GRF
   through RemoteClient's PHP implementation. Both Flux objects remain paused.

An error aborts the next steps; no namespace/PVC reset is attempted. Inspect the
failure and approve a `--reconcile` retry if needed. No SQL errors are suppressed.

## Application acceptance checks

Use the same kubeconfig/context; do not infer health solely from Flux Ready:

```bash
kubectl -n ragnarok get pods,deployments,services,endpointslices,pvc
kubectl -n ragnarok get events --field-selector type=Warning
kubectl -n ragnarok rollout status deployment/remote --timeout=180s
kubectl -n ragnarok rollout status deployment/robrowser --timeout=180s
curl -fsS http://pi:30080/ >/dev/null
curl -fsS http://pi:30080/remote/System/add-system-folder-files-here.txt >/dev/null
curl -fsS http://pi:30000/ >/dev/null
curl -fsS http://pi:30000/applications/api/api.js >/dev/null
curl -fsS http://pi:30000/src/Renderer/GR2/GR2ModelRenderer.js >/dev/null
kubectl -n ragnarok exec -i deployment/wsproxy -- node - < scripts/check-wsproxy.cjs
```

Expect all six deployments available (login, char, map, wsProxy, remote, frontend),
PVCs Bound, populated endpoints, the exact released runtime images and no
ImagePullBackOff/CrashLoopBackOff. Check rendered HOST/ports and CORS, the external
WebSocket path through PORT_WSPROXY, then actual browser login/map loading.
The quick RemoteClient health endpoint can report 503 for lazily loaded GRF
indexes even when actual reads/parsing work; do not enable a large cache just to
change that metric. See the existing health caveat in flux-split-migration.md.

## Controlled Flux adoption — also requires approval

Never run manual bootstrap with an active reconciler for the same resources.
`ragnarok-app.yaml` explicitly commits `suspend: true`, so resuming the parent
cannot accidentally start the child. There is no cyclic dependsOn/health wait:
parent readiness means its cluster configuration applied, not application health.

After the operator approves Flux adoption of the healthy installation:

1. Keep the child suspended. Confirm the GitRepository has fetched the reviewed
   main revision and the existing `flux-system` SSH Secret is present. Resume
   ONLY the parent `flux-system`; wait for its Ready condition and exact applied
   revision, then verify ragnarok-stack is still suspended.
2. Review that Git-managed ConfigMaps, image pins and resources agree with the
   `.env`-rendered installed resources. Secrets and populated PVC contents remain
   private/bootstrap-managed; do not commit them or wipe/recreate them.
3. Submit/approve a separate Git change lifting the child `suspend: true` hold.
   With the parent active, merging that approved change resumes the application
   reconciler. Do not rely on a one-off CLI resume while Git still says suspend:
   the parent would restore the hold on its next reconciliation.
4. Confirm both exact Flux applied revisions, no reconciliation errors and repeat
   application acceptance checks. ragnarok-stack uses wait:false, so Flux Ready
   is not a substitute for pods, DB, GRFs, frontend and gameplay checks.

No resumption, namespace creation or deployment is authorized by this runbook or
by merging the image-pin/preparation PR. The operator gives that approval later.
