# Image security and software inventory

## Vulnerability scan

The **Container Security** workflow runs after CI succeeds. It rebuilds the roBrowser, rAthena, and wsProxy images from the validated source revision and scans them with [Trivy](https://github.com/aquasecurity/trivy). Publishing builds the images again; these are not promoted copies of the CI image artifacts.

Trivy is configured with `severity: HIGH,CRITICAL`, `ignore-unfixed: true`, and `exit-code: 1`. A fixable HIGH or CRITICAL finding fails the security workflow and blocks publishing. Findings that Trivy cannot currently match to a fix are reported but do not block; lower-severity findings are outside this workflow's reporting threshold. A green scan means no blocking findings at this threshold, not that an image is vulnerability-free.

Download the `trivy-robrowser`, `trivy-rathena`, or `trivy-wsproxy` artifact from the workflow run to inspect the SARIF report. The same run generates an SPDX SBOM per image.

## SBOM

An **SBOM** (Software Bill of Materials) is an inventory of the packages contained in an image. It is useful when a vulnerability is announced later: instead of guessing whether an image contains the affected library, the SBOM identifies it.

The workflow creates one SPDX JSON SBOM artifact per scanned image:

- `sbom-robrowser`
- `sbom-rathena`
- `sbom-wsproxy`

The SBOM and Trivy report are workflow artifacts, not public client data and not runtime secrets.

## Runtime hardening

The Kubernetes deployments run containers as non-root, drop Linux capabilities, use the runtime-default seccomp profile, define liveness/readiness probes, and set initial CPU/memory requests and limits. wsProxy also uses a read-only root filesystem; roBrowser cannot yet do so because Apache, Vite, and the generated client configuration require writable runtime paths.

## PHP security updates and rollout

`images/robrowser/Dockerfile` installs PHP from the package repositories of its pinned Alpine release. The package constraint `php84>=8.4.27` accepts newer PHP 8.4 patches without automatically switching to PHP 8.5. Both package selection and a build-time version check reject versions older than the fixes for CVE-2026-109618 and CVE-2026-109619. CI also checks the version and security configuration through an actual Apache/mod_php HTTP request.

`images/robrowser/security.ini` disables `session.upload_progress.enabled` before request parsing, following the [PHP advisory of 23 October 2026](https://www.php.net/archive/2026.php#2026-10-23-1) for CVE-2026-115560. Alpine packages the session extension separately; it is currently not installed, but the setting also applies if it is added later.

CI, Container Security, and Publish Images disable Docker layer caching for roBrowser builds, so the `apk add --no-cache` installation is executed again. These are two different caches: `apk --no-cache` alone does **not** invalidate a cached Docker build layer. Package versions still depend on what Alpine publishes for the selected release and architecture.

There is no scheduled PHP-package rebuild. A package becoming available does not trigger an image build or change an existing container. The update chain is:

1. An image-relevant change on `main` passes CI and Container Security (or an operator explicitly starts the corresponding workflows).
2. Publish Images builds and pushes a new image.
3. Its GitOps update PR updates `deploy/overlays/flux/kustomization.yaml` to the new SHA tag.
4. After that update merges, Flux reconciles the deployment and replaces the pods.
5. Verify the running container, not just the build log:

   ```bash
   kubectl -n ragnarok exec deployment/robrowser -- php -v
   kubectl -n ragnarok exec deployment/robrowser -- php -r \
     'echo "upload_progress config=", get_cfg_var("session.upload_progress.enabled"), "\n";'
   ```

For the current PHP 8.4 branch, expect PHP 8.4.27 or newer and `upload_progress config=0`. A restart or rollout using the old image does not update PHP. The minimum version must be reviewed when future advisories arrive; this guard is not a guarantee against future vulnerabilities.

## Local wsProxy smoke test

The readiness check retries a real WebSocket handshake for up to 30 seconds. Docker's `running` state alone is not application readiness. To run the same check as CI:

```bash
docker build -t wsproxy:local ./images/wsproxy
docker run -d --name wsproxy-local wsproxy:local -a ragnarok-login:6900
docker exec -i wsproxy-local node - < scripts/check-wsproxy.cjs
docker rm -f wsproxy-local
```

This checks wsProxy startup and its WebSocket handshake; it does not require a live Ragnarok server or verify a game login. An optional URL and timeout in milliseconds allow checking the failure path, for example `node - ws://127.0.0.1:5998/ragnarok-login:6900 1500` with the same script on stdin.

## Reproducibility controls

- Base images are pinned to immutable Alpine manifest digests.
- roBrowserLegacy, roBrowserLegacy-RemoteClient-PHP, rAthena, and ROenglishRE are pinned to Git commit SHAs in `build/dependencies.env`.
- The roBrowser source revision has no lockfile. The project-owned `images/robrowser/package.json` and `package-lock.json` define its reproducible dependency overlay and are installed with `npm ci`. `granny-ro-js@1.5.0` is pinned there because the source imports `granny-ro-js/wasm`.
- CI checks all four upstream layouts, builds the images, starts the services, and requests Vite's transformed GR2 renderer module to catch missing frontend dependencies.
- Third-party GitHub Actions are pinned to complete commit SHAs rather than mutable version tags.
- Dependabot checks GitHub Actions, Alpine base-image digests, and the project-owned npm dependency overlay weekly. Its security updates are enabled for this public repository; review and validate its PRs through CI and the image-security workflow.
- The upstream-fork updater is separate from Dependabot: it checks the four pinned forks every six hours, opens a PR for newer SHAs, and enables auto-merge after required CI validation. This can deploy upstream changes automatically; layout checks and smoke tests are not a substitute for gameplay regression testing.

## GitHub repository secret protections

The public GitHub repository has **Secret scanning**, **Push protection**, and **Dependabot security updates** enabled in its repository security settings. Secret scanning checks for supported leaked-secret patterns; push protection blocks recognized secrets before a push is accepted. These controls do not protect secrets stored on the Pi, detect every possible custom credential format, or rotate a secret that was already exposed. Revoke and rotate any exposed credential promptly.

The upstream PR automation also uses the repository Actions secret `UPSTREAM_PR_TOKEN`. It should be a fine-grained, repository-scoped token with only **Contents: Read and write** and **Pull requests: Read and write**. Never place its value in the repository, logs, docs, or chat; rotate it if it may have leaked.

When updating `ROBROWSER_REF`, regenerate the lockfile before merging:

```bash
workdir=$(mktemp -d)
git clone https://github.com/raiken-mf/roBrowserLegacy.git "$workdir/robrowser"
git -C "$workdir/robrowser" checkout --detach <new-ROBROWSER_REF>
cd "$workdir/robrowser"
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
cp package-lock.json /path/to/robrowser_docker/images/robrowser/package-lock.json
```

Then commit the updated dependency reference and lockfile together. CI validates that `npm ci` can consume the lockfile during the image build.
