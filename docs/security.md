# Image security and software inventory

## Vulnerability scan

The **Container Security** workflow runs after CI succeeds. It scans the same roBrowser, rAthena, and wsProxy images CI built with [Trivy](https://github.com/aquasecurity/trivy).

The scan fails on **HIGH** or **CRITICAL** vulnerabilities that have a fix available. Findings without an available fix are reported by the scanner but do not block the build; otherwise Alpine base-image findings could make routine development impossible to ship.

Download the `trivy-robrowser` or `trivy-rathena` artifact from the workflow run to inspect the SARIF report.

## SBOM

An **SBOM** (Software Bill of Materials) is an inventory of the packages contained in an image. It is useful when a vulnerability is announced later: instead of guessing whether an image contains the affected library, the SBOM identifies it.

The workflow creates one SPDX JSON SBOM artifact per scanned image:

- `sbom-robrowser`
- `sbom-rathena`
- `sbom-wsproxy`

The SBOM and Trivy report are workflow artifacts, not public client data and not runtime secrets.

## Runtime hardening

The Kubernetes deployments run containers as non-root, drop Linux capabilities, use the runtime-default seccomp profile, define liveness/readiness probes, and set initial CPU/memory requests and limits. wsProxy also uses a read-only root filesystem; roBrowser cannot yet do so because Apache, Vite, and the generated client configuration require writable runtime paths.

## Reproducibility controls

- Base images are pinned to immutable Alpine manifest digests.
- roBrowserLegacy, rAthena, and ROenglishRE are pinned to Git commit SHAs.
- roBrowser's upstream revision has no lockfile. The project-owned `robrowser/package-lock.json` was generated for the pinned upstream revision and is installed with `npm ci`.
- Third-party GitHub Actions are pinned to complete commit SHAs rather than mutable version tags.
- Dependabot opens weekly reviewable pull requests for GitHub Actions, Alpine base-image digests, and the project-owned npm lockfile overlay. Review them through the same CI, security scan, and selective publish flow; do not auto-merge them blindly.

When updating `ROBROWSER_REF`, regenerate the lockfile before merging:

```bash
workdir=$(mktemp -d)
git clone https://github.com/raiken-mf/roBrowserLegacy.git "$workdir/robrowser"
git -C "$workdir/robrowser" checkout --detach <new-ROBROWSER_REF>
cd "$workdir/robrowser"
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
cp package-lock.json /path/to/robrowser_docker/robrowser/package-lock.json
```

Then commit the updated dependency reference and lockfile together. CI validates that `npm ci` can consume the lockfile during the image build.
