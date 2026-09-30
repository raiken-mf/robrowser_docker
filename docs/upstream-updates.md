# Fork updates and image releases

Build inputs are pinned to full Git commit SHAs in [`build/dependencies.env`](../build/dependencies.env). The four monitored fork repositories are:

- `roBrowserLegacy`
- `roBrowserLegacy-RemoteClient-PHP`
- `rAthena`
- `ROenglishRE`

Syncing one of these GitHub forks does **not** immediately change a deployed image. The scheduled **Check Fork Updates** workflow checks their default-branch `HEAD`s every six hours (and can also be run manually from Actions). A sync is picked up on the next check, so there can be up to roughly six hours of detection delay.

## Automated update path

When one or more fork heads differ from their pins, the workflow updates only those SHAs in `build/dependencies.env`, validates the candidate source layouts, and creates or updates a single PR on `automation/upstream-dependency-update`.

If the PR's required `validate` check passes, auto-merge merges it. No per-update human approval is intended for this dependency PR. The rest of the release path is:

1. CI builds the images and runs smoke tests.
2. After CI passes on `main`, Container Security scans the images for **HIGH/CRITICAL** findings (unfixed findings are reported but do not block).
3. Only after the security workflow succeeds does Publish Images publish the affected image(s) to GHCR, using immutable `sha-<robrowser_docker commit>` tags as well as `stable`.
4. Publish opens a GitOps PR that updates Flux's immutable image references. Auto-merge plus Flux reconciliation rolls the changed image(s) out to Kubernetes.

rAthena is published separately. Changes to roBrowserLegacy, RemoteClient-PHP, or ROenglishRE affect the roBrowser image. Unaffected images are not rebuilt by selective publishing.

### One-time setup

The scheduled updater needs the repository secret `UPSTREAM_PR_TOKEN` in **Settings → Secrets and variables → Actions**. Use a fine-grained token restricted to this repository with **Contents: Read and write** and **Pull requests: Read and write**. Do not put the token in source files or paste it into chat. Rotate it if it expires or is revoked.

GitHub can put workflow runs from PRs created by `github-actions[bot]` into `action_required`. If that happens for a GitOps PR, a repository writer must approve that run before its required CI check can execute; auto-merge waits for the check. Dependency-update PRs created with `UPSTREAM_PR_TOKEN` are authenticated as the token owner and normally run CI without that bot approval gate.

## What CI validates

The layout check verifies the paths required by the Dockerfiles:

- **roBrowserLegacy:** `package.json`, `vite.config.js`, and `src/DB/DBManager.js`
- **RemoteClient-PHP:** `index.php`, `Client.php`, `configs.php`, `data/`, and `System/`
- **rAthena:** `configure`, `src/custom/defines_pre.hpp`, and `conf/`
- **ROenglishRE:** Renewal and Pre-Renewal `Translation/.../data` and `SystemEN` directories

The roBrowser image pins the RemoteClient-PHP SHA too. Its project-owned npm manifest and lockfile also pin `granny-ro-js@1.5.0`, required by the fork's `granny-ro-js/wasm` import. CI's roBrowser smoke test requests Vite's transformed `GR2ModelRenderer.js` and verifies the WASM module exports resolve; a basic HTTP readiness probe alone would not catch this class of frontend module-resolution error.

These checks prove the expected paths exist, the images build, services start, and the tested frontend module resolves. They do **not** prove full gameplay compatibility or exercise a complete login/map/effect session. The update process currently auto-merges after CI, so a compatible layout and passing smoke test can still precede a runtime issue. Monitor the post-merge Security → Publish → GitOps/Flux pipeline and test gameplay after an update.

## Manual update or recovery

You can still run **Actions → Check Fork Updates → Run workflow** to check immediately. If no fork head is newer than its pin, the run succeeds without opening a PR or building images.

If an update is incompatible, deploy a preceding immutable `sha-...` image tag or revert the dependency-pin PR. Do not use the mutable `stable` tag as a rollback target.
