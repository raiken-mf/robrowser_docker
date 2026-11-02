# Changelog

All notable changes to this project are documented in this file.

## 2026-11-02 — completed split-stack installation and documentation

- Final runtime names: robrowser is Node.js/Vite frontend; remote is Apache/PHP,
  RemoteClient, ROEnglishRE and client resources. Compose/Kubernetes/Flux/CI use
  the separate images and preserved port variables.
- Completed the fresh empty-MariaDB bootstrap, private .env-based Secrets/ConfigMaps,
  client-data upload and controlled Flux adoption (PRs #87–#90).
- Fixed Vite cache-busted API iframe module resolution through a project-owned
  external bootstrap override; added HTTP/module/source-parity/protocol tests.
- Operator confirmed both Flux objects active/Ready at revision 109430d1, seven
  ready pods and successful browser login. Graphics/Lua/GRF-content issues remain
  separate follow-up work.
- Consolidated obsolete intermediate migration/validation notes into current
  cluster setup, fresh application installation, GitOps, operations and validation
  guides. Infrastructure scripts in custom-scripts were inspected, not modified.
- Current k8s-all.sh defaults to read-only --check; approved --apply installs the
  complete stack and --reconcile allows an approved retry. It never deletes a
  namespace or resumes Flux and is not the routine active-cluster update path.

## Earlier implementation changes (historical)

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
- Historical bootstrap work added namespace lookup/reset safeguards; the current replacement has no namespace-deletion path and uses explicit --check/--apply/--reconcile modes.
