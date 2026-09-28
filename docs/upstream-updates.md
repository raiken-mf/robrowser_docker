# Safe fork updates

The automated build pipeline uses fixed Git revisions, listed in [`build/dependencies.env`](../build/dependencies.env), for roBrowserLegacy, rAthena, and ROenglishRE. Syncing a GitHub fork alone therefore does **not** alter local or published images. Hercules remains available for local Docker Compose builds but is not built, published, or monitored by CI.

## Updating a fork safely

1. Sync the fork on GitHub, or select a specific upstream commit.
2. Create a branch in this repository.
3. Change only the corresponding `*_REF` value in `build/dependencies.env`.
4. Open a pull request. CI checks the exact source layout required by the Dockerfiles, validates Compose, and builds roBrowser and rAthena.
5. Test the PR image before merge. A merged `main` publishes immutable `sha-<repository commit>` tags plus the moving `stable` tag to GHCR.
6. Point Compose or Kubernetes at the verified immutable image tag for production.

## Layout checks

The CI check deliberately verifies paths that the Dockerfiles rely on:

- **roBrowserLegacy:** `package.json`, `vite.config.js`, and `src/DB/DBManager.js`
- **rAthena:** `configure`, `src/custom/defines_pre.hpp`, and `conf/`
- **ROenglishRE:** both Renewal and Pre-Renewal `Translation/.../data` and `SystemEN` directories

If a synced fork changed a required structure, the pull request fails before publication. It cannot prove gameplay compatibility; the smoke test only verifies that roBrowser's Apache and Vite endpoints start. Run a login/map/effect regression test before promoting the image.

## Rollback

Deploy the preceding immutable `sha-...` image tag, or revert the dependency-update pull request. Do not rely on `stable` as a rollback target.
