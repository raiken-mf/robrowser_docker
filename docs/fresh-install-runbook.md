# Fresh Ragnarok stack on an existing cluster

This runbook is for an **empty application installation** on an already prepared
cluster. It is not the maintenance procedure for the running GitOps stack. The
Pi installation has completed: both Flux Kustomizations are active/Ready and
browser login succeeded. Nothing here says to suspend that working installation.

## Prerequisites and approval gate

K3s/node access, Longhorn, a ready MariaDB operator/webhook and its CRDs must
already exist. The [cluster guide](cluster-installation.md) explains the separate
infrastructure scripts and their side effects. k8s-all.sh checks these prerequisites;
it does not install/upgrade them.

For a genuinely new stack, obtain installation approval, review storage and image
pins, and ensure the target namespace is absent. Do not delete a working namespace
or reuse this procedure as a backup restore. The verified installation deliberately
used a new empty `ragnarok` database; no old data required recovery.

The manual bootstrap requires both existing Flux Kustomizations paused. The
Git state used for activation must hold ragnarok-stack at suspend:true until its
release is approved. See [controlled activation](gitops.md#controlled-first-activation).
The current operational main has suspend:false; it is not an installation hold.
Establish a reviewed hold for the target installation before bootstrap, rather
than assuming a one-off pause survives parent reconciliation.

## Local configuration and context

Use a reviewed current checkout without overwriting local `.env`, client files
or ignored override payloads. A separate worktree can use the originals by
absolute path. For example, after choosing the intended checkout:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export ENV_FILE=/home/pi/git/robrowser_docker/.env
export CLIENT_SOURCE_DIR=/home/pi/git/robrowser_docker/client
kubectl config current-context
kubectl get nodes -o wide
flux get kustomizations -n flux-system
```

These are environment/read-only checks. Never print kubeconfig, `.env`, Secret
data or registry credentials. On another host use its authorized kubeconfig;
copying a Pi file with a localhost server address is not sufficient.

The verified Pi uses HOST=pi, PORT_FRONTEND=30000, PORT_HTTP=30080 and
PORT_WSPROXY=30599. Keep the existing variable names and fallbacks. All database
and interserver credentials are read from local `.env` exactly as configured;
bootstrap does not invent passwords or restore backups.

Expected local layout:

```text
client/
  resources/DATA.INI   # case-sensitive, references the available GRFs
  resources/*.grf
  AI/
  BGM/
  data/
  System/
```

Before installation, verify source files fit the 15Gi client PVC. MariaDB uses
new 5Gi Longhorn storage. A previous namespace's Bound PVC status does not
establish a recovery path after deletion; this runbook assumes an empty new DB.

## Read-only bootstrap check

```bash
bash scripts/k8s-all.sh --check
```

No argument also defaults to --check. It loads the local configuration, renders
private temporary Secrets/ConfigMaps, checks API errors, operator/storage
availability, image tag selection, paused Flux, port ownership and DATA.INI/GRF
source completeness. It performs no cluster writes and removes its private
temporary files. It intentionally rejects **active** Flux even though this mode
is read-only; it is a bootstrap preflight, not a general operations health check.

The web renderer can emit non-secret review files separately, but its standalone
image defaults may be stable. The full bootstrap chooses reviewed SHA tags from
the Flux overlay unless compatible image-tag overrides were explicitly supplied.
Review those overrides; never treat an invented old-name SHA or stable as release
provenance. See [configuration sources](deployment.md#configuration-sources).

## Full installation — changes the cluster

Only after the installation approval and a successful preflight:

```bash
bash scripts/k8s-all.sh --apply
```

The script runs the complete application sequence:

1. Recheck paused Flux/prerequisites. An existing namespace requires an expressly
   approved --reconcile retry. API/auth failures abort, not masquerade as NotFound.
   The script never deletes a namespace or resumes Flux.
2. Apply the labeled/hardened namespace and restrictive DB network policy, then
   private mariadb-root-secret/mariadb-user-secret and rathena-config, followed
   by the `.env`-derived robrowser-config.
3. Apply MariaDB, Database, User and Grant CRs and wait for their Ready conditions.
   The user Secret contains both password (operator) and MARIADB_PASSWORD
   (rAthena), plus the configured interserver user/password. No password goes in
   a Git-managed ConfigMap or local command argument.
4. Create the client PVC/non-root loader, upload CLIENT_SOURCE_DIR folders and
   check streamed file sizes. Stop on failure before starting the web services.
5. Start login, char and map in dependency order. Login's INIT_DB=true entrypoint
   imports the empty schema and Renewal/Pre-Renewal SQL according to
   SET_PRERENEWAL, then configures the interserver account. Char/map do not
   initialize the DB. A private in-pod SQL check verifies the account row.
6. Deploy/wait for wsProxy, remote and robrowser. Check an actual wsProxy
   WebSocket handshake and parse the mounted first GRF using RemoteClient PHP.
   List pods/services/PVCs; Flux remains paused for the separate adoption gate.

Secret output is an owner-only temporary file (directory 0700, file 0600), not
logged or committed. The offline renderer rejects overwriting an existing output
file. A failure aborts; it does not reset data or suppress SQL failures. Diagnose
it before approving `--apply --reconcile` for a partial-install retry.

## Acceptance and GitOps adoption

Use the [read-only operations checks](operations.md#health-checks), then test the
frontend in a real browser: rendered host/ports, iframe startup, RemoteClient
requests/CORS, external WebSocket connection, login and map loading. Keep client
content errors distinct from Kubernetes readiness.

For first adoption, activate the parent while the child is explicitly held in
Git; verify parent revision/Ready and the child pause, then separately review the
Git change enabling the child. See [the precise sequence](gitops.md#controlled-first-activation).
Git-managed configuration/pins must match the installed `.env`-derived settings.
Secrets and populated client contents remain private/bootstrap managed; do not
commit or recreate them to make GitOps adopt the stack.

## What was actually verified

The completed Pi installation and login were confirmed by the operator on
2026-11-02. The empty MariaDB 11.8.6 schema/bootstrap was also tested in disposable
Docker containers against the published rAthena image. CI tests secret rendering,
failure/ordering behavior through a fake kubectl, and the frontend/remote images.
Those fake-API tests are not substitutes for live acceptance. Commands in this
runbook are future procedures and were not re-executed during documentation cleanup.
