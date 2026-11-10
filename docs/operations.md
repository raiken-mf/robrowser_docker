# Existing GitOps cluster: operation and recovery

## Compose database persistence plan

This is a proposed migration, not an executed change. Shared Compose currently
does not declare `/var/lib/mysql` persistence; an existing container may own an
anonymous image volume. Never attach a fresh empty volume as an automatic upgrade.

1. With explicit target approval, record the actual database volume, engine/image
	version, ownership and free space without exposing credentials.
2. Create a private consistent backup and prove restoration into an isolated
	database. Retain the original volume and test rollback before migration.
3. Stop writers in an approved maintenance window and take a final backup. For
	existing installations, prepare an installation-only external-volume override
	pointing to the verified original volume. Do not commit host-specific identity.
4. For fresh installations, propose a named `/var/lib/mysql` volume only after
	testing both emulator stacks, initialization and persistence across recreation.
5. Verify accounts, schema and game login before resuming writes. Retain original
	data until human acceptance. Never use volume pruning/deletion in this plan.

## MariaDB operator upgrade plan

The fresh-only installer requires `MARIADB_OPERATOR_VERSION` for both charts and
refuses existing Flux/operator infrastructure before Helm writes. No chart version
has been certified here and no installed release was inspected.

1. With permission, record installed chart/CRD, Kubernetes and application versions,
	Flux ownership and database/PVC state. Verify authoritative compatibility and
	release notes for the exact proposed pair; equal versions alone prove nothing.
2. Test backup restoration and operator/CRD transitions in an isolated environment
	matching relevant architectures/schema. Review conversion, webhooks and storage
	immutability. Define forward recovery where CRD downgrades are unsafe; Helm
	rollback is not database restoration.
3. Propose exact verified versions through the owning GitOps manifests and human
	review. Do not run fresh installers or create competing Helm ownership live.
4. Obtain explicit maintenance/target approval, adopt the reviewed Git change and
	verify operator/webhook, database readiness, unchanged PVC identity and login.
	PVC/data migration requires separate approval; retain backups until acceptance.

In the verified example installation, both Flux Kustomizations were active/Ready and seven
application pods were confirmed Running/ready with successful browser login on
2026-11-02. Do not use installation or bootstrap modes, k8s-all.sh --apply, namespace
resets or blanket image/volume pruning for routine maintenance.

## Health checks

Select the intended authorized kubeconfig/context before any action. The
application scripts default to /etc/rancher/k3s/k3s.yaml; an operator can instead
explicitly use an authorized user kubeconfig:

```bash
export KUBECONFIG="$HOME/.kube/config"
kubectl config current-context
kubectl get nodes -o wide
flux get sources git -n flux-system
flux get kustomizations -n flux-system
bash scripts/sh/k8s/k8s-setup-flux.sh --check
bash scripts/sh/k8s/k8s-setup-storage.sh --check
kubectl -n ragnarok get deployments,statefulsets,pods
kubectl -n ragnarok get pvc,services,endpointslices
kubectl -n ragnarok get events --field-selector type=Warning --sort-by=.lastTimestamp
kubectl -n longhorn-system get pods
kubectl get storageclass
```

These commands inspect state; they do not reconcile/install/restart resources.
Expected application roles: database-0 (operator StatefulSet), rAthena login/char/map,
remote, robrowser and wsProxy. There are six application Deployments plus MariaDB;
the confirmed one-replica baseline has seven pods, each 1/1. Names/counts can change
with a deliberate reviewed scaling/version change.

Check Ready/available replicas, Bound PVCs, populated EndpointSlices, current Flux
source/applied revision and no repeated scheduling/pull/crash errors. Longhorn
controller readiness and an existing StorageClass alone do not prove volume
health or data recovery; inspect actual relevant volumes when investigating a
storage incident, without deleting them.

Read-only workload details, scoped to the actual failing service:

```bash
kubectl -n ragnarok describe deployment robrowser
kubectl -n ragnarok logs deployment/robrowser --tail=100
kubectl -n ragnarok logs deployment/remote --tail=100
kubectl -n ragnarok get deployments -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image
```

Do not dump Secret data, full environments, kubeconfigs or remote URLs with
embedded credentials. Sanitize console/network diagnostics, including tokens in
Vite/HMR WebSocket query strings, before sharing reports.

## HTTP, module and game checks

Set these values to the browser-reachable host and ports of your installation,
not internal cluster DNS names:

```bash
HOST=127.0.0.1
PORT_HTTP=30080
PORT_FRONTEND=30000
curl -fsS "http://$HOST:$PORT_HTTP/" >/dev/null
curl -fsS "http://$HOST:$PORT_HTTP/remote/System/add-system-folder-files-here.txt" >/dev/null
curl -fsS "http://$HOST:$PORT_FRONTEND/" >/dev/null
curl -fsS "http://$HOST:$PORT_FRONTEND/applications/api/api.js" >/dev/null
curl -fsS "http://$HOST:$PORT_FRONTEND/applications/api/api.html?0.138571" >/dev/null
curl -fsS "http://$HOST:$PORT_FRONTEND/applications/api/api-bootstrap.js" >/dev/null
curl -fsS "http://$HOST:$PORT_FRONTEND/src/Renderer/GR2/GR2ModelRenderer.js" >/dev/null
```

A successful HTML request is not proof that all browser modules work. Inspect the
iframe's module requests and JavaScript console. The API iframe fix in PR #88
externalizes the inline module; [its regression checks](frontend-api-module.md)
cover the cache-busted HTML path that previously failed with HTTP 500.

A scoped WebSocket test can be run with operator permission:

```bash
kubectl -n ragnarok exec -i deployment/wsproxy -- node - < images/wsproxy/tests/check-wsproxy.cjs
```

It checks a real handshake, not a game login. A new browser session should verify
iframe readiness, public HOST/ports, RemoteClient/CORS and actual login/map
loading. The operator confirmed login on the completed installation; continuing
graphics, Lua, GRF-content or client issues are separate investigations.

### RemoteClient quick-health caveat

The pinned RemoteClient defaults to lazy GRF indexes. Its quick health endpoint
can report 503/grfsLoaded=0 before indexes are loaded, even when the mount is
readable and an explicit parser/resource request succeeds. Distinguish this
known metric limitation from missing DATA.INI, wrong file case, absent GRFs,
permissions, real parse failures or HTTP rewrite errors. Do not enable a large
index/cache solely to turn the quick metric green.

## Normal changes

Use [approved release/image-pin PRs](gitops.md#normal-approved-release-path).
Changing a local `.env` does not update GitOps-managed ConfigMaps. Review the
non-secret rendered Git changes; existing pods need a controlled replacement to
consume changed environment values. Credentials remain private; a password
change may require coordinated DB/operator/game-account updates, not merely a
file edit.

`k8s-all.sh --check` is deliberately not the active-cluster health command: it
requires paused Flux for a manual-bootstrap preflight. Neither --apply nor
--reconcile is the ordinary update path.

## Rollback and failure handling

On failure, collect scoped status/events/logs and identify the failed layer before
retrying. Do not rerun installers blindly, bootstrap Flux again, format storage,
reset namespaces or delete PVC/PV/Longhorn volumes.

For an image regression, inspect Git history for the last verified component pin
and propose a narrow revert. Keep the other component pins unchanged, rerun
required checks, then adopt through normal approved GitOps reconciliation.
Tag names identify infrastructure source commits, not chronological ordering;
verify the registry digest and architecture. Stable is mutable and is not a
rollback record.

Emergency imperative example (requires explicit target-only approval and Flux
coordination; not executed during cleanup):

```bash
kubectl -n ragnarok get deployment robrowser -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{.image}{"\n"}{end}'
# Record OLD_IMAGE and the actual CONTAINER before changing anything.
kubectl -n ragnarok set image deployment/robrowser "$CONTAINER=$OLD_IMAGE"
kubectl -n ragnarok rollout status deployment/robrowser --timeout=180s
```

An active reconciler restores its Git desired state; make the approved rollback
consistent with Git rather than leaving uncontrolled drift. Do not touch MariaDB,
other deployments, configuration or storage for a frontend-only incident.

Storage/DB recovery is a separate operation with a verified backup, scope,
credentials and maintenance approval. The fresh-install runbook's automatic
empty-DB import is not a restore procedure.
