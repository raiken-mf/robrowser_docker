# Controlled Flux migration to split web images

The image/CI PR intentionally leaves `deploy/k8s/` and
`deploy/overlays/flux/` identical to main. New templates are preparation only.
No cluster changes are part of that PR. Publication opens draft GitOps image
update PRs without auto-merge; keep them unmerged until this migration is reviewed.

The original split live-manifest snapshot is preserved on the local branch
`migration/split-web-kubernetes` at commit
`69702899af2444c7ec82096398254bed64900b56`. It is a design reference, not a
merge-ready migration. A follow-up must be based on the eventual merged main and
must not apply that snapshot as a single unattended rollout.

The current selected image revisions and their verified registry digests are
listed in [Image revision guide](image-revisions.md). Keep the migration's image
overrides aligned with main; do not reintroduce an old image-bump PR or a duplicate
Vite stable override while resolving conflicts.

## Prerequisites

- Confirm both new images passed AMD64/ARM64 vulnerability scans and have SBOMs.
  Record their exact scanned digests and each component source revision.
  Only Vite fetches roBrowserLegacy; Apache fetches RemoteClient and ROEnglishRE.
- Review the actual namespace, existing ConfigMap keys, HOST and all `.env` port
  values with the deployment operator. Do not commit credentials or replace live
  configuration with example values. Preserve custom external port values.
- Keep `pull_policy: always`, `imagePullPolicy: Always`, probes, non-root settings,
  capability restrictions and all current PHP/runtime hardening.
- Agree an explicit maintenance window, rollback images/configuration and the
  boundary between the separate GitOps stages. Flux watches main automatically;
  Actions completion is not a gate on applying manifests from Git.

## Separate reviewed stages

1. Publish and verify the two matching scanned images without updating live image
   overrides. Do not merge a generated draft image-update PR prematurely.
2. During the approved maintenance window, remove only the frontend port from
   Service `robrowser`, releasing the configured PORT_FRONTEND NodePort. Keep the
   Apache Service/NodePort and persistent data. Expect frontend interruption.
3. Apply the reviewed real web configuration and update Apache to the split image.
   Check readiness, PHP, `/remote/` delivery and mounted client data before exposing
   the new frontend. Start the new Vite Deployment with the matching image and
   shared configuration. Verify its readiness and access to the RemoteClient.
4. In a further reviewed change, expose Vite through the released PORT_FRONTEND
   NodePort. Validate the external URLs, CORS, WebSocket routing and browser login.
   Close the maintenance window only after those checks pass.

The standard NodePorts remain PORT_HTTP=30080 and PORT_FRONTEND=30000;
PORT_WSPROXY retains its existing value/fallback. Internal listener/target ports
remain Apache 8080, Vite 3000 and wsProxy 5999. Do not rename the port variables.
The template renderer reads `.env`; Flux reads reviewed Git manifests, not `.env`.

## Failure and rollback

Stop before advancing a stage if its checks fail. Restore the previous image and
configuration as reviewed; if returning frontend traffic to the old combined
container, first release Vite's NodePort, then restore the old Service port.
Never assign the same NodePort to both Services or delete the namespace/PVCs.
Existing pods do not reread ConfigMap environment values until recreated.

The old combined roBrowser SHA override must not be paired with the new Vite
frontend expecting `/remote/`. Keep generated image-update PRs in draft until the
intended image pairing and current migration stage are verified. Independent
scheduled dependency automation is not approval for a deployment stage.


The prepared ConfigMap in PR #73 now uses the operator-generated preview:
HOST=pi, PORT_HTTP=30080, PORT_FRONTEND=30000 and PORT_WSPROXY=30599.
These agree with the reviewed .env/live web settings; PORT_FRONTEND is added
explicitly for the separate Vite service. Recheck them before an approved rollout.
This configuration update does not authorize applying the combined migration in
one unattended step; the NodePort handover stages above remain required.
