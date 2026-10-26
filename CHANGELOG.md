# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Security

- Require PHP 8.4.27 or newer in the 8.4 branch for CVE-2026-109618/CVE-2026-109619, disable session upload progress for CVE-2026-115560, and verify Apache/mod_php in CI.
- Rebuild roBrowser without Docker layer caching in CI, security scans, and publishing to pick up current Alpine PHP packages.
- Update Electron to 44.9.3 (CVE-2026-115570), patch undici 7 to 7.30.1 (CVE-2026-109869), and refresh the locked undici 8 dependency to 8.12.3.
- Bump `source-map-js` in the roBrowser image to 1.2.2 (CVE-2026-93749).
- Upgrade Alpine `zlib` to 1.3.2-r1 in the robrowser, wsproxy, rathena, and hercules images (CVE-2026-85091), until patched base images are available.

### Changed

- `.github/workflows/security.yml`: Container Security scan now fails only on HIGH and CRITICAL findings as configured, instead of also failing on MEDIUM due to a SARIF severity-filtering quirk in trivy-action.
- `.github/dependabot.yml`: Dependabot now also tracks npm dependencies of `/images/wsproxy`.

### Fixed

- Retry actual wsProxy WebSocket handshakes until ready instead of treating Docker's running state as readiness.
- Compare the correct base/head revisions on both pull requests and pushes, fall back to full CI validation when no valid base exists, and validate workflow/script-only pushes.
- `start.sh`: Install Docker only when it is missing, then verify Docker Compose and daemon availability before starting services.
- `scripts/k8s-all.sh`: Require confirmation before resetting an existing namespace; fail safely on namespace lookup or deletion errors, and wait for deletion to complete before deploying.
