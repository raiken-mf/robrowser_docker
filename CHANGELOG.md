# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Security

- Bump `source-map-js` in the roBrowser image to 1.2.2 (CVE-2026-93749).
- Upgrade Alpine `zlib` to 1.3.2-r1 in the robrowser, wsproxy, rathena, and hercules images (CVE-2026-85091), until patched base images are available.

### Changed

- `.github/workflows/security.yml`: Container Security scan now fails only on HIGH and CRITICAL findings as configured, instead of also failing on MEDIUM due to a SARIF severity-filtering quirk in trivy-action.
- `.github/dependabot.yml`: Dependabot now also tracks npm dependencies of `/images/wsproxy`.

### Fixed

- `start.sh`: Install Docker only when it is missing, then verify Docker Compose and daemon availability before starting services.
- `scripts/k8s-all.sh`: Require confirmation before resetting an existing namespace; fail safely on namespace lookup or deletion errors, and wait for deletion to complete before deploying.
