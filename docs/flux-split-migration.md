# Controlled Flux migration to split web images

PR #85 is Phase A; PR #73 is Phase B. Both are deployment changes because
`ragnarok-stack` watches `deploy/overlays/flux` on main automatically. Keep both
without auto-merge. Obtain explicit operator approval immediately before each
phase merge; green CI alone does not authorize a cluster change. Do not merge
them together or apply all resources manually alongside active Flux.

## Reviewed inputs

The operator-rendered ConfigMap uses HOST=pi, PORT_HTTP=30080,
PORT_FRONTEND=30000, PORT_WSPROXY=30599, PACKETVER=20211103,
SET_PRERENEWAL=0 and SERVER_NAME=Ragnarok Online. It contains no credentials.
The renderer reads the existing `.env` variables and fallbacks; Flux consumes the
reviewed generated Git manifests, not `.env`. Preserve custom values when rendering
for another installation. Do not rename variables or replace these values with
examples.

External NodePorts differ from internal listeners: Apache uses 30080 -> 8080,
Vite 30000 -> 3000 and wsProxy 30599 -> 5999 here. Both image pull policies,
non-root runtime, probes, dropped capabilities and PHP hardening remain in place.
Only Vite fetches roBrowserLegacy; Apache supplies PHP RemoteClient at `/remote/`.

See [Image revision guide](image-revisions.md) for verified published digests.
Source SHA tags can differ between components when their inputs have not changed.
Never invent a tag from the newest main SHA or select an unscanned candidate.

## Phase A — release the legacy frontend port (#85)

1. Before merging, confirm current main, successful required CI, the live ConfigMap,
   healthy existing Deployments, Bound client-data PVC and rollback reference.
   Agree a maintenance window: frontend access on 30000 is unavailable between
   the phases. Obtain the explicit Phase A deployment approval.
2. Merge only #85. Its sole resource change removes the frontend port from the
   Apache Service. Apache Deployment/image, ConfigMap, NodePort 30080, wsProxy,
   rAthena, namespace and PVCs remain unchanged. Do not merge #73 yet.
3. Wait for Flux `ragnarok-stack` Ready=True at the exact Phase A merge revision;
   inspect reconciliation errors/events as well. Flux currently uses wait=false,
   so Ready alone does not establish application health.
4. Inspect all Services and confirm no Service owns NodePort 30000. Verify Apache
   still owns 30080 and wsProxy 30599, existing Deployments are available, and PVCs
   remain Bound. Check Apache/PHP routing, actual mounted GRF readability/parsing
   and loose-file delivery, wsProxy listener and rAthena readiness. Record the
   RemoteClient health response with the lazy-loading caveat below. Stop on an
   actual resource, routing or readiness failure.

## Phase B — deploy the independent frontend (#73)

1. After Phase A is verified, synchronize #73 with its merged main and rerun CI.
   Its effective diff must not include another legacy-port release. Recheck all
   four image digests, actual ConfigMap values and the absence of a 30000 owner.
   Obtain separate explicit Phase B deployment approval immediately before merge.
2. Merge #73. It adds the Vite Deployment/Service, applies the reviewed ConfigMap,
   sets Apache's web role and uses the selected published image releases. Vite
   claims the NodePort already released by Phase A. Preserve Apache 30080.
3. Wait for Flux Ready=True at the exact Phase B merge revision, then verify both
   Deployments have their desired available/ready replicas, probes pass, Service
   endpoints exist and the ConfigMap environment is loaded in the new pods.
4. Verify frontend HTTP 200 on PORT_FRONTEND, rendered HOST/ports, Apache PHP and
   `/remote/` routing, mounted GRF/loose-file access and cross-origin requests.
   Confirm an actual WebSocket upgrade through PORT_WSPROXY, then browser login
   and game connectivity. An HTTP response alone does not prove WebSocket/game
   functionality. Record any browser-only check that still needs the operator.

No phase is complete until these checks pass. Before approval only read-only
cluster/registry inspection and isolated local tests are permitted.

## Rollback

Stop before advancing on any error. Before Phase B, a separately approved revert
of the small Phase A Service change restores its previous port ownership, but it
does not restore a missing frontend in an Apache-only image. For a working legacy
frontend rollback use the recorded compatible combined image/configuration.
After Phase B, release Vite's port before restoring the legacy Service port; never
assign the same NodePort to both Services. Restore reviewed images/configuration
through controlled Git changes. Do not delete the namespace or PVCs. Pods must
be recreated to consume changed ConfigMap environment values.

## Observed baseline and RemoteClient health caveat

Before either deployment phase, all five existing Deployments were ready, the
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
