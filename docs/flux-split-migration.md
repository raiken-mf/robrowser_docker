# Final web architecture — fresh installation held

The operator confirmed namespace `ragnarok` was completely removed. Read-only
inspection confirmed it absent and both `flux-system` and `ragnarok-stack`
Kustomizations suspended. Keep both paused. No Kubernetes resources may be
created and Flux must not be resumed before separate installation approval.
PR #85 is closed without merging; no old NodePort handover is required.

## Final runtime ownership

| Service / GHCR image | Build tree | Responsibility | External / internal port |
| --- | --- | --- | --- |
| robrowser | images/robrowser | Node.js, Vite, roBrowserLegacy frontend | PORT_FRONTEND / 3000 |
| remote | images/remote | Apache, PHP 8.4, RemoteClient, ROEnglishRE, GRF/BGM/AI | PORT_HTTP / 8080 |
| wsproxy | images/wsproxy | WebSocket proxy | PORT_WSPROXY / 5999 |

The reviewed ConfigMap stays `robrowser-config`: HOST=pi, PORT_HTTP=30080,
PORT_FRONTEND=30000, PORT_WSPROXY=30599, PACKETVER=20211103,
SET_PRERENEWAL=0 and SERVER_NAME=Ragnarok Online. Existing variables/fallbacks,
non-root security, dropped capabilities, probes, readonly resource mounts,
pull Always, independent overrides, source pins and `/remote/` routing remain.
`REMOTE_IMAGE_TAG` explicitly overrides legacy `ROBROWSER_IMAGE_TAG` for Apache;
`VITE_IMAGE_TAG` continues to select the frontend. See the deployment guide before
moving existing local override payloads into the renamed build folders.

## Repository and release gates

The source/build/runtime names are changed together across Docker, Compose,
Kubernetes/templates, scripts, CI smoke tests, multiarch security/SBOM/publication
and Dependabot. Vite engine/package names and upstream source identities remain.

The registry's OLD robrowser image still contains Apache until a new-name release
is actually published. Old vite releases contain the frontend. Do not reuse their
source SHA tags under different repositories. The historical digest table is
pre-rename evidence only. Current target web overrides temporarily use stable;
they are NOT installation-ready release pins. After a reviewed main merge, the
unchanged security-gated publication workflow builds the two new-name images,
scans both architectures, emits SBOMs and promotes exact candidate digests only
while source main is current. Its generated draft GitOps PR then supplies the
new immutable source tags. Review and verify those registry digests/roles before
installation approval. Frontend readiness checks its API module rather than only
HTTP `/`, so the old Apache image cannot appear as a ready frontend.

PR #73 remains unmerged unless its repository merge is explicitly authorized.
No force-push, image-security bypass, Kubernetes write or Flux resume is part of
repository validation. A repository merge/release is separate from installation.

## Installation approval remains separate

After final-name images and immutable Flux pins are available, review storage
restore/provisioning and all actual configuration. The old namespace/PVC objects
are gone; prior Bound status is not a storage restore guarantee. Do not create
PVCs, change reclaim policies or resume Flux yourself. The operator will approve
the fresh installation separately.

After that approval, verify Flux's exact applied revision, PVC/pod readiness,
service selectors/endpoints, probes, frontend on 30000, Apache on 30080,
RemoteClient GRF/loose-file delivery/CORS, a real WebSocket upgrade and browser/game
connectivity. No two-stage Service port transfer is needed in the empty namespace.

## Observed baseline and RemoteClient health caveat

Historical baseline before the namespace deletion: all five existing Deployments were ready, the
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
