# Fresh namespace installation — deployment hold

The operator replaced the two-phase in-place migration with a full, manually
controlled deletion and recreation of namespace `ragnarok`. PR #85 is superseded
and closed without merging. Do not execute its old NodePort handover. PR #73
remains draft, without auto-merge, and must not be merged or applied yet.

The operator owns Flux suspension/resumption and namespace deletion. Repository
preparation is authorized; no agent-driven namespace/PVC deletion, Flux
reconciliation, resource application, rollout or deployment merge is authorized.
Wait for the operator to confirm the namespace has been removed. That confirmation
alone is not approval to resume Flux or merge deployment changes.

## Target names and port compatibility

| Responsibility | Previous service | Target service | External variable / reviewed value | Internal listener |
| --- | --- | --- | --- | --- |
| Node.js/Vite/roBrowserLegacy frontend | vite | robrowser | PORT_FRONTEND / 30000 | 3000 |
| Apache/PHP/RemoteClient/ROEnglishRE/resources | robrowser | remote | PORT_HTTP / 30080 | 8080 |
| WebSocket proxy | wsproxy | wsproxy | PORT_WSPROXY / 30599 | 5999 |

The runtime remains split. Both components keep independent repository_override
payloads. Preserve `.env` names and fallbacks, PORT_FRONTEND rendering, `/remote/`
URLs, Apache `.htaccess`, readonly resource mounts, pull Always policies and all
security restrictions. Keep the shared ConfigMap name `robrowser-config`; changing
service responsibilities does not require renaming configuration variables.

The reviewed ConfigMap remains HOST=pi, PORT_HTTP=30080, PORT_FRONTEND=30000,
PORT_WSPROXY=30599, PACKETVER=20211103, SET_PRERENEWAL=0 and
SERVER_NAME=Ragnarok Online. No credentials belong in Git. The renderer consumes
`.env`; Flux consumes reviewed manifests in Git, not the local `.env`.

## Rename preparation and release gate

Implement the rename as a coordinated change across Compose services, Kubernetes
Deployments/Services/selectors, templates, renderer/deployment scripts, tests and
documentation. Keep upstream Vite dependencies, vite.config.js, roBrowserLegacy
source URLs and source revision pins unchanged: they are implementation/source
identities rather than deployment service names.

If image/build names are renamed too, move the Apache build to `images/remote`
and the frontend build to `images/robrowser`, including their separate override
folders. Update CI build contexts, security matrices, SBOM/release records,
change detection, publication, image boundary/Compose/override tests, Dependabot
paths and Flux image overrides together. Preserve existing configuration variable
names or explicit compatibility fallbacks; never silently reinterpret a previous
image-tag variable as the other runtime.

IMPORTANT: the currently published `ghcr.io/raiken-mf/robrowser` image contains
Apache/PHP; `ghcr.io/raiken-mf/vite` contains the frontend. Replacing a service label
or directory does not change those artifacts. Never point the renamed frontend
at the existing Apache `robrowser` tag, or invent an unpublished `remote` tag.
The image naming cutover needs its own validated current-source build, multiarch
security scans, SBOMs and exact-digest publication. A new frontend `robrowser:stable`
would change the meaning of an existing registry reference and requires an
explicit controlled release decision before publication.

The digests in [Image revision guide](image-revisions.md) describe the published
PRE-RENAME artifacts only. They remain evidence for the previous runtime split,
not proof that final-name images already exist. Keep deployment held until names,
actual published digests and runtime roles are verified together.

## Fresh-install gates

1. Obtain operator confirmation of the namespace reset and their intended Flux
   state. Do not delete resources, recreate the namespace or resume Flux yourself.
2. Before any deployment merge, review the final rename diff, required CI, exact
   image roles/digests and the actual non-secret ConfigMap. The existing #73 snapshot
   is not a ready final-name installation. Synchronize it with current main.
3. Confirm the operator's storage/restore plan. Namespace deletion also removes
   namespaced PVC objects; Bound status before deletion does not prove data will
   survive a reset. Do not alter reclaim policies or storage yourself.
4. Only after explicit deployment approval may final resources be merged into the
   Flux-watched main. Existing deployments must remain untouched until then.
5. After the operator-authorized fresh installation, check Flux's exact applied
   revision, namespace/PVC readiness, final service selectors/endpoints, pod probes,
   Apache 30080/8080, frontend 30000/3000, RemoteClient GRF/loose-file access/CORS,
   an actual WebSocket upgrade and browser/game connectivity.

## Observed baseline and RemoteClient health caveat

Before the strategy change, all five existing Deployments were ready, the
client-data PVC was Bound, Apache served HTTP 200 on 30080, and the old Apache
Service still owned 30000. No Vite Deployment/Service existed. The reviewed
ConfigMap matched the operator preview; PORT_FRONTEND is the explicit new key.

The pinned RemoteClient defaults INDEX_CACHE_ENABLED to false. Its quick health
endpoint reports HTTP 503 / grfsLoaded=0 because Client initialization opens GRFs
without loading their indexes, while HealthCheck counts only loaded indexes.
This result alone does not prove the mounted GRFs are invalid. Read-only checks
confirmed CR2.grf, rdata.grf and data.grf are readable; explicitly loading CR2.grf
with the shipped parser succeeded (941 files). Do not enable a large index/cache
or change upstream code just to make this metric green. Validate actual GRF and
loose-file access, routing and Kubernetes probes in each approved phase, and
record the existing health-endpoint limitation separately. Browser/game checks
remain required after Vite is exposed.
