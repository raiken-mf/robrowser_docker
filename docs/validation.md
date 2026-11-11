# Validation coverage and completed installation

## Confirmed operating baseline

The operator confirmed on 2026-11-02:

- K3s on Raspberry Pi and Longhorn working.
- flux-system and ragnarok-stack active/Ready; last confirmed application revision
  `109430d1` after merged PRs #87, #88, #89 and #90.
- MariaDB, rAthena login/char/map, remote, robrowser and wsProxy working: seven
  pods Running, each 1/1 at the one-replica baseline.
- Ragnarok login in the real browser successful.

This is an operator-confirmed, dated observation; it was not rechecked during
this documentation cleanup. Documentation-only merges may advance
Flux source/applied revisions without changing application specifications.
No infrastructure setup, Kubernetes deployment, Flux action or storage operation
was performed during that cleanup.

## Actually executed checks from the implementation work

| Check | What it established | Limit |
| --- | --- | --- |
| Native web builds and filesystem/history boundary checks | Only robrowser contains the frontend; remote contains PHP/client resources | Local builds are not registry release provenance |
| Translation SHA-256 comparisons | Renewal 625 files; Pre-Renewal 684, with ten differing overlay replacements; pinned .htaccess preserved | Optional translation Addons are not installed |
| Isolated web Compose | HTTP/module transformation, PHP security, routing, readonly GRF mapping, loose files and CORS | Not full game login |
| Independent override fixtures | Each image serves its own marker/index after startup | Ignored local overrides are not present in clean CI builds |
| API regression on cold Vite | Old cache-busted HTML proxy fails with 500; external bootstrap resolves | Node protocol tests stub engine execution |
| Registry release evidence | Both architectures, source annotations, approved digest records, platform SBOMs and promotion | Does not prove every client asset is correct |
| Empty MariaDB 11.8.6 + published rAthena in isolated Docker | Schema, Renewal tables and interserver account initialized automatically | Not a backup/restore test |
| Offline bootstrap fixtures and fake kubectl protocol | Private rendering, credential mappings, no leaks/overwrite, aborts and ordering | Not actual Kubernetes scheduling or volume provisioning |
| Actual bootstrap --check before installation | Read-only source/operator/port/bootstrap readiness on the paused target | Not appropriate for normal active Flux |
| Operator's final Kubernetes/browser test | Healthy application stack and successful login | Remaining rendering/Lua/content issues are not resolved |

## Repeatable tests

See [development](development.md#validation-without-kubernetes-deployment) for the
local/CI commands and [operations](operations.md#health-checks) for live read-only
checks. The existing PR validate gate is scope-sensitive: documentation-only
changes can pass without image builds. A strict MkDocs build and local link checks
are the relevant documentation validation.

The final documentation cleanup runs offline bootstrap fixture/protocol tests,
syntax/Kustomize checks and a strict documentation build. It does not claim those
commands execute a new real cluster installation. Future installation examples
must be reviewed against the target context and current external scripts.

## Scope intentionally left open

The rAthena multi-stage image built and passed entrypoint checks on local ARM64
for Renewal and Pre-Renewal. Two local AMD64 builds under emulation failed with
compiler segmentation faults at different compilation steps. The cause is not
established; the AMD64 build and entrypoint tests must pass on a native GitHub
runner before merging. Local ARM64 results do not establish AMD64 compatibility.

Graphics, Lua, GRF-content and other client/gameplay errors are separate tasks.
Do not hide them by weakening security/readiness checks or resetting a working
namespace/database. Capture sanitized browser/server diagnostics and use a
separately reviewed fix when that work is authorized.
