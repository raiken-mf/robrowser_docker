# FluxCD lifecycle and release adoption

## Source of truth and current state

`deploy/clusters/default/flux-system/gotk-sync.yaml` defines the GitRepository and
parent Kustomization flux-system. Its desired path is `deploy/clusters/default`;
it manages the child object in ragnarok-app.yaml. Both use the same source.
The child path is `deploy/k8s/overlays/flux`, whose base is deploy/k8s/base.
The shared base retains the existing host during migration stage one; the existing
cluster's child Kustomization patches `robrowser-config` with its installation-specific browser hostname. Set
that patch to your own reachable hostname or IP before adopting this configuration.
For an existing installation, first deploy this stage-one child patch while retaining
the old shared HOST, then verify the parent has applied it before a separate change
sets the shared HOST to `127.0.0.1`. Otherwise the child can reconcile loopback before the
parent applies its patch. Roll back by restoring the previous shared HOST before
removing the child patch. These are separate reviewed changes, not automatic steps.
There is no explicit dependsOn in these manifests; the parent/child management
relationship is not an application-health dependency.

## Cluster path migration

The former paths `clusters/pi-cluster` and `deploy/overlays/flux` are absent from
the migration commit. An operator must suspend **both** existing Kustomizations
before merging it and keep them suspended until both live paths are patched.
Record their inventories, applied revisions and workload health before the merge;
compare the rendered resources and live inventories, including namespaces, PVCs
and StatefulSets. Both reconcilers prune: stop if identities or ownership differ.
Do not rebootstrap Flux. The external bootstrap wrapper may still default to the
former path; explicitly set `CLUSTER_PATH=deploy/clusters/default`.

After the reviewed migration is merged, set `APPROVED_SHA` to its exact main
commit. The following commands are operator actions on the intended cluster:

```bash
: "${APPROVED_SHA:?Set the reviewed migration commit SHA}"
kubectl -n flux-system get kustomizations flux-system ragnarok-stack -o jsonpath='{range .items[*]}{.metadata.name}{" path="}{.spec.path}{" suspended="}{.spec.suspend}{"\n"}{end}'
kubectl -n flux-system patch kustomization flux-system --type=merge -p '{"spec":{"path":"./deploy/clusters/default","suspend":true}}'
kubectl -n flux-system patch kustomization ragnarok-stack --type=merge -p '{"spec":{"path":"./deploy/k8s/overlays/flux","suspend":true}}'
flux reconcile source git flux-system -n flux-system
kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.status.artifact.revision}{"\n"}'
kubectl -n flux-system get kustomizations flux-system ragnarok-stack -o jsonpath='{range .items[*]}{.metadata.name}{" path="}{.spec.path}{" suspended="}{.spec.suspend}{"\n"}{end}'
```

Stop unless both paths and `suspended=true` are correct and the source artifact
revision is exactly `main@sha1:$APPROVED_SHA`. Freeze merges to main until both
reconcilers have applied that revision; the GitRepository continues polling while
Kustomizations are suspended. The Git child spec is `suspend:false`: resuming the parent can resume
the child immediately, before the parent reports Ready. Both paths, source and
inventories must therefore be approved before resuming the parent:

```bash
flux resume kustomization flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system
kubectl -n flux-system get kustomizations flux-system ragnarok-stack -o yaml
```

Verify the parent Ready condition and applied revision, and the child path and
state. If the child is still suspended, resume it with
`flux resume kustomization ragnarok-stack -n flux-system`. Verify both applied
revisions, inventories and workload health using the commands below. Flux Ready
does not prove application health (`wait: false`).

```bash
flux get sources git -n flux-system
flux get kustomizations -n flux-system
kubectl -n flux-system get kustomizations flux-system ragnarok-stack -o yaml
kubectl -n ragnarok get deployments,statefulsets,pods,pvc
kubectl -n ragnarok get mariadb database
kubectl -n ragnarok rollout status deployment/ragnarok-login
kubectl -n ragnarok rollout status deployment/ragnarok-char
kubectl -n ragnarok rollout status deployment/ragnarok-map
kubectl -n ragnarok rollout status deployment/remote
kubectl -n ragnarok rollout status deployment/robrowser
kubectl -n ragnarok rollout status deployment/wsproxy
```

Record the inventory and applied revision securely without publishing private
configuration. For rollback, suspend both reconcilers immediately. Keep them
suspended while a reviewed revert restores both former directories and matching
pins; merge it and verify the source artifact is exactly the approved revert SHA.
Freeze merges to main until rollback completes. Only then patch both old paths
while retaining the suspension:

```bash
flux suspend kustomization flux-system -n flux-system
flux suspend kustomization ragnarok-stack -n flux-system
# Merge the reviewed revert and verify its source artifact revision first.
flux reconcile source git flux-system -n flux-system
kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.status.artifact.revision}{"\n"}'
kubectl -n flux-system patch kustomization flux-system --type=merge -p '{"spec":{"path":"./clusters/pi-cluster","suspend":true}}'
kubectl -n flux-system patch kustomization ragnarok-stack --type=merge -p '{"spec":{"path":"./deploy/overlays/flux","suspend":true}}'
kubectl -n flux-system get kustomizations flux-system ragnarok-stack -o jsonpath='{range .items[*]}{.metadata.name}{" path="}{.spec.path}{" suspended="}{.spec.suspend}{"\n"}{end}'
```

Stop unless the artifact is the approved revert revision, both old paths and
suspensions are correct, and the source and inventories are approved. Then resume
the parent:

```bash
flux resume kustomization flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system
```

The parent may resume the child immediately here too. Verify both paths, source,
inventories and health after resuming; resume the child separately only if it
remains suspended. If the revert is unavailable, leave both suspended and the
existing workloads running. Never delete or recreate Flux objects, workloads,
PVCs or PVs. A fresh install requires the suspended-child procedure below.
The later shared-HOST migration remains a separate change after the child patch is
confirmed; this path migration does not activate it.

The last operator-verified operating state had both reconcilers active/Ready. The child Git
spec is suspend:false. An absent suspend field on the parent also means active.
The last operator-confirmed installation revision was `109430d1` (2026-11-02);
later documentation-only merges can advance source/applied revisions without
changing workload specifications.

Local `.env` is not read by Flux. Review and commit non-secret ConfigMaps,
selectors, ports and release pins explicitly. Private bootstrap supplies Secrets
and client PVC contents. `wait:false` on the application means Flux Ready proves
reconciliation, not healthy DB/game/frontend processes.

## Controlled first activation

This section is for a **new installation**, not normal operation. It describes the
hold used during installation; it is not a request to reapply it to today's
working stack.

1. Have a reviewed Git installation state explicitly holding the child at
   suspend:true. During manual bootstrap both existing reconcilers stay paused.
   The full application installer refuses an active reconciler and never resumes it.
   The GitRepository manifest in that installation state must also reference the
   intended repository and installation branch, not the checked-in main branch.
   Verify the rendered source and live source revision before resuming the parent;
   otherwise the parent can switch sources and remove the installation hold.
2. After bootstrap/acceptance and activation approval, confirm the intended source
   revision and SSH Secret. Resume **only the parent** while the Git child hold
   remains true; wait for the parent's Ready condition and exact applied revision.
   Verify the child remains suspended. Do not infer application health from this.
3. Review a separate Git change lifting the child hold (suspend:false). With the
   parent active, merging it lets the parent update the child and start its
   reconciliation. A one-off CLI child resume while Git still says true is not
   durable: the parent would restore the hold.
4. Verify both Flux revisions/conditions, then actual pods, PVCs, endpoints,
   frontend, RemoteClient, WebSocket and browser login. Resolve manifest drift
   from any `.env`-based manual bootstrap before accepting GitOps ownership.

The completed installation used the reviewed child activation in PR #90. Do not
repeat bootstrap or pause/resume working reconcilers for a routine image update.

## Normal approved-release path

1. Source/dependency changes pass required PR validation and enter main through
   human review and the repository's branch protection.
2. Main CI validates the affected images. Container Security builds changed
   candidates for AMD64/ARM64, applies the existing HIGH/CRITICAL vulnerability
   gate and emits platform SBOMs/approved digest records.
3. Publish promotes the **exact scanned digests**, checks their source revision
   and rejects publication if main moved during the scan. It sets sha-source and
   stable tags; unchanged components retain their previous releases.
4. Publish opens a **draft GitOps image-bump PR**, without enabling auto-merge,
   updating only the corresponding overlay image tags.
5. Approve any GitHub Actions runs awaiting approval on the bot-created PR, then
   review the actual registry digest/source/platforms, CI, component pairing and
   release approval, then merge that image-pin PR. Active Flux automatically
   applies the new Git desired state; a manual reconcile command is not required.

This is automatic **adoption after approval**, not automatic approval of all
published images. Publishing stable alone does not change SHA-pinned pods. Review
any externally configured auto-merge separately; it is not promised by these
workflows. See [upstream updates](upstream-updates.md) for source-PR and
Dependabot review requirements.

## Normal inspection and optional reconciliation

Read-only:

```bash
flux get sources git -n flux-system
flux get kustomizations -n flux-system
kubectl -n flux-system get kustomizations flux-system ragnarok-stack
```

If an operator explicitly needs to accelerate an **approved** desired-state
change, these are mutating reconciliation requests, not passive health checks:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
flux reconcile kustomization ragnarok-stack -n flux-system --with-source
```

Do not run them, resume/suspend Flux or bootstrap the cluster during unrelated
documentation/cleanup work. Normal polling already reconciles Git automatically.

## Recovering from a bad release

Prefer a reviewed Git revert to the last verified component tag/digest, preserving
other image pins and configuration. Once merged, verify Flux and application
health. Do not substitute newest main into every component tag or roll stable
back blindly.

An imperative deployment-only rollback is an emergency action needing explicit
approval and coordination with active Flux; otherwise it will reconcile back to
Git. Record the previous reference, actual container name and scope. Never use
namespace/PVC deletion as rollback, and never restore DB storage without a
separate verified recovery plan. See [operations](operations.md#rollback-and-failure-handling).
