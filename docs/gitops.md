# FluxCD lifecycle and release adoption

## Source of truth and current state

`clusters/pi-cluster/flux-system/gotk-sync.yaml` defines the GitRepository and
parent Kustomization flux-system. The parent reconciles clusters/pi-cluster and
therefore manages the child object in ragnarok-app.yaml. Both use the same source.
The child ragnarok-stack reconciles deploy/overlays/flux, whose base is deploy/k8s.
There is no explicit dependsOn in these manifests; the parent/child management
relationship is not an application-health dependency.

The verified operating state has both reconcilers active/Ready. The child Git
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
   review or the repository's configured dependency auto-merge policy.
2. Main CI validates the affected images. Container Security builds changed
   candidates for AMD64/ARM64, applies the existing HIGH/CRITICAL vulnerability
   gate and emits platform SBOMs/approved digest records.
3. Publish promotes the **exact scanned digests**, checks their source revision
   and rejects publication if main moved during the scan. It sets sha-source and
   stable tags; unchanged components retain their previous releases.
4. Publish opens a **draft GitOps image-bump PR**, without enabling auto-merge,
   updating only the corresponding overlay image tags.
5. Review the actual registry digest/source/platforms, CI, component pairing and
   release approval, then merge that image-pin PR. Active Flux automatically
   applies the new Git desired state; a manual reconcile command is not required.

This is automatic **adoption after approval**, not automatic approval of all
published images. Publishing stable alone does not change SHA-pinned pods. Review
any externally configured auto-merge separately; it is not promised by these
workflows. See [upstream updates](upstream-updates.md) for the distinct source-PR
and Dependabot auto-merge rules.

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
