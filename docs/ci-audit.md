# CI/CD audit

Audit date: 2026-11-10. Evidence combines repository source, isolated contracts,
GitHub PR metadata and Actions job/step results. Local environment: macOS ARM64,
Python 3.15.2, Bash 3.2. This is not certification of a live deployment.

## Workflow inventory

### Scope optimization

The shared `scripts/py/ci-scope.py` resolver drives CI, PR scans and release
scans. Image scopes follow Dockerfile COPY inputs, owned Dockerfiles and ignore
files, plus consumed repository/ref values. Root `.dockerignore` affects only the
two root-context web images. There are no local cross-image COPY dependencies.
Tests are not image build inputs. A contract checks that current COPY sources
remain covered; new Dockerfile inputs must update the resolver and contract.

CI starts nine independent validation-group jobs and retains `validate` as the
required aggregate. Each group runs only for its declared dependencies. Image
smoke builds have independent image gates. The ten PR scan jobs and four release
jobs retain their names and success aggregation; starting a job is not building
or scanning an image. CI runs on every PR and main push so required checks do not
remain pending and publishing can recover interrupted releases without new
image inputs. MkDocs retains its docs/config/workflow path filters.

| Change | Previous smoke builds / PR scans | New smoke builds / PR scans | Applicable validation |
| --- | --- | --- | --- |
| CI workflow only | remote, frontend, proxy / none | none / none | All validation groups and test scripts |
| Frontend npm lockfile | all web/proxy / frontend | frontend / frontend | Contracts, layout, frontend tests, web integration/boundaries/own overrides |
| Remote runtime file | all web/proxy / remote | remote / remote | Contracts, layout, remote tests, web integration/boundaries/own overrides |
| wsproxy runtime file | all web/proxy / proxy | proxy / proxy | Contracts, layout, proxy tests |
| rAthena runtime file | all web/proxy plus rAthena / rAthena | rAthena / rAthena | Contracts, layout, entrypoint tests |
| Hercules runtime file | all web/proxy / Hercules | none / Hercules | Contracts, layout; no Hercules release pipeline |
| One consumed source pin | all web/proxy, possibly rAthena / multiple unrelated images | consuming image only / consuming image only | Pin/layout contracts, upstream layouts, Compose and affected image tests |
| Pin comments only | all web/proxy / multiple images | none / none | Dependency and Compose contracts |
| Compose helper only | all web/proxy / none | none / none | Integration and script layout |
| Owned image test only | all web/proxy / owning image | none / none | Owning tests and applicable contracts |
| Bootstrap or monitor helper | none / none | none / none | Bootstrap/setup or monitor and script layout |
| Kubernetes/Flux manifest | often all web/proxy / none | none / none | Platform, bootstrap and applicable template/contracts |
| Root ignore file | all web/proxy / web images | web images / web images | Contracts, layout, web tests |
| Documentation only | none / none | none / none | MkDocs; CI aggregates succeed without heavy work |

Release comparisons deliberately differ from the event matrix: each image is
compared to the source annotation on its published stable OCI index. A skipped
event does not discard an earlier unpublished image change. Missing history,
invalid revisions, Git errors or malformed dependency declarations conservatively
enable checks/builds/scans, never report uncertainty as unchanged. NUL-delimited
Git paths preserve newline filenames; disabling rename detection includes both
ends of renames and deleted inputs. Pins are parsed as data, never executed.

Script-only runtime tests load unchanged partner images from stable by immutable
digest. The source must be an ancestor of HEAD and its image inputs must still
match. Missing or incompatible published fixtures fail validation explicitly;
there is no implicit rebuild or fallback to an unverified mutable image. Override
tests rebuild only changed components; script-only override tests inject isolated
payloads before startup without building. Build fixtures copy tracked files only,
not ignored local overrides. Main promotion, exact-digest two-architecture security
gates, approval journaling and rebuild-free recovery remain unchanged.

`check-ci-scope.py` exercises synthetic commits for isolated image inputs, both
pin fields, comments, script dependencies, multiple changes, renames, deletions,
newline filenames and error fallbacks. Mocked fixture-loader checks cover the
no-build path and metadata rejection. Local contracts cannot prove registry
availability, runner execution or repository branch-protection configuration;
maintainers must verify the existing `validate` and `PR image security` required
checks on GitHub before merging.

### Historical inventory

The following inventory and findings record the pre-optimization audit. The scope
optimization above supersedes its broad `build`/`relevant` gates and open per-pin
scope finding; release recovery findings remain applicable.

| Workflow | Trigger and path filter | Jobs and dependency gates | Actual expensive work |
| --- | --- | --- | --- |
| `ci.yml` | Every PR; main pushes except docs, README and `.gitignore` only | PR security -> validate; main validate -> security -> publish. Validate uses `always()` but explicitly rejects failed PR security. Main release jobs require successful prerequisites. | Web/proxy smoke builds use `build`; rAthena uses its separate input/pin check. Infrastructure and contract validations use `relevant`. |
| `pr-image-security.yml` | Reusable call only from CI | Ten native matrix jobs: five images x AMD64/ARM64; aggregate result requires matrix success | Each job first checks image input paths. Unchanged jobs succeed without building/scanning. Changed images run Trivy, blocking fixable HIGH/CRITICAL findings. |
| `security.yml` | Reusable call from successful main validation | Four image jobs: remote, frontend, rAthena, wsproxy | Reliable stable source revision and input paths determine builds; pending GitOps adoption alone does not. Changed candidates build both architectures, scan exact digests, create SBOMs, then ready records. Hercules is not a release image. |
| `publish.yml` | Reusable call after successful main security | One serialized promotion job, bounded pending queue, unchanged permissions | Candidate/source/digest checks precede durable approval journaling. Reconcile current and interrupted partial releases into one draft PR; no records can still recover journaled releases. No rebuild here. |
| `dependency-update.yml` | Manual or daily 12:23 UTC; default branch only | One serialized updater; weekly-cycle gate, layout check, cycle/freshness recheck before PR write | Four fork heads become exact SHA pins. Dedicated `UPSTREAM_PR_TOKEN`, fixed branch and force-with-lease; existing PR is edited. No automerge. |
| `docs.yml` | PR and main push touching docs, MkDocs config or workflow | PR validation or main publication | Strict site build; main publication now also uses strict mode. No image build. |
| `xerj-reference-monitor.yml` | Manual or Monday 08:17 UTC; default branch only | One serialized reference monitor | Compares reference changes and proposes human review. Does not accept a new baseline automatically. |

Dependabot is separate configuration, not another Actions workflow: a weekly
Monday noon Europe/Berlin multi-ecosystem group covers GitHub Actions, all five
Dockerfile directories and both project npm manifests. Security update groups
exist for npm and Actions. The fork updater waits at least 24 hours and for open
Dependabot version PRs, then limits proposals to one per weekly cycle.

## Findings and priorities

| Priority / status | Location | Cause and observed impact | Correction or remaining action |
| --- | --- | --- | --- |
| P1 locally fixed | `security.yml`, publisher recovery | Stable can move before GitOps PR creation/adoption. The old design lost recovery without new candidate records. | Durable approval journal recovers interrupted releases without adoption-only rebuilds; changed inputs and unreliable revision still require builds and both security scans. |
| P1 locally fixed | `publish.yml`, `scripts/py/publish-images.py` | Per-source branches and partial ready records allowed overlapping proposals; interruption lost published components and retries failed. | One proposal, pre-promotion approval journal, ancestry ordering, immutable source tags and API compare-and-swap. Six original regressions failed before the correction; twenty-two scenarios now pass. GitHub/registry acceptance remains required. |
| P2 fixed | `ci.yml`, scope step | Every `scripts/` change previously enabled all web/proxy smoke builds, even monitor or bootstrap-only work. | Restrict script build inputs to Compose smoke, image override and boundary helpers. Keep relevant validations and required scan gate. Positive/negative path contracts pass. |
| P2 fixed | `security.yml`, wsproxy paths | Root `.dockerignore` was treated as wsproxy input despite image-local build context. | Remove that path from wsproxy release scope. PR/release path and context contracts pass; web root contexts retain it. |
| P2 fixed | `docs.yml` | Main publication lacked strict validation and workflow-only pushes did not invoke it. | Strict deployment and matching workflow push filter, covered by contracts. |
| P2 open | Compose/Kubernetes MariaDB image declarations | MariaDB runtime tags are outside the Dockerfile directories configured for Dependabot. No reviewed automatic tag refresh is established for these manifests. | Establish a manifest-aware update proposal and parity/security checks; do not change database versions without upgrade review. |
| P3 open | `docs.yml`, dependency installation | Unversioned MkDocs Material installs make identical revisions depend on current PyPI state. | Pin a reviewed toolchain and provide its update mechanism; avoid an unmaintained one-off pin. |
| P3 partially fixed | CI concurrency and scoped validators | Default concurrency replaced pending runs. Generic dependency-file edits still trigger both root-context image scans even when only a different fork pin changes. | CI and publishing use `queue: max`, bounded to 100 pending runs; ancestry checks do not depend on dispatch order. Per-pin scope optimization remains open. |

## Why scripts changes start jobs

CI has no top-level path filter. Ten scan jobs starting is not ten images being
built: their scope steps can skip every build and Trivy step. `validate` requires
the aggregate security result and all validation-group results. Main release jobs
compare published inputs before deciding whether candidates are needed. Script
and deployment changes run applicable contracts or tests, not image builds.
Missing comparison history conservatively enables required work.

## PR #115 and #117 evidence

- #115 originated from CI run 42680458516, source
  `4f448188aec2fad9ecccd0472263b2ad9e1ffcd8`, created 2026-11-09 19:18:09 UTC.
  The source commit was Dependabot #114, changing frontend npm metadata/lockfile.
  Its proposal included remote, frontend and rAthena pins, including the then
  legacy overlay path. This alone does not prove all were direct commit inputs:
  release comparison uses the prior published revision.
- #117 originated from CI run 42687363768, source
  `4577ec240ae6d90b9808b7870664787c1e090bc2`, created 19:58:16 UTC. Source #116
  moved repository layout and the wsproxy-owned stdin fixture; that image input
  really changed. It also migrated the Flux path.
- #117 was manually consolidated with #115's three pins at 2026-11-10 09:32:43
  UTC and merged at 09:43:27; #115 closed unmerged at 09:44:12.

These were different source releases, not duplicate events from one run. The
Actions step results confirm that #115 built/scanned remote, frontend and
rAthena while wsproxy was skipped; #117 built/scanned only wsproxy. Both main
validation jobs built all three smoke images and skipped the rAthena smoke build.
This is direct evidence that started jobs, smoke builds and release builds must
be counted separately.

The former per-source partial-PR design required manual consolidation when several
releases awaited review. Neither draft status nor successful publication proves
GitOps adoption. See [publishing protocol](image-revisions.md#publishing-protocol)
for the replacement and migration prerequisites.

## Editor warnings

All eight `Context access might be invalid` warnings in `security.yml` concern
`REMOTECLIENT_REPOSITORY`, `REMOTECLIENT_REF`, `ROENGLISH_REPOSITORY`,
`ROENGLISH_REF`, `ROBROWSER_REPOSITORY`, `ROBROWSER_REF`, `RATHENA_REPOSITORY`
and `RATHENA_REF`. The versioned pin file is loaded into `GITHUB_ENV` before
the consuming build-action steps. GitHub documents subsequent-step availability;
historical builds succeeded. These are static-editor false positives, not absent
runtime values. The same pattern appears in CI. No dummy defaults were added to
hide the warnings. This conclusion does not replace workflow linting or a new
runner execution after changes.

## Deployment and security boundaries

Root-context web images copy explicit owned inputs, not the entire repository.
The root ignore rules exclude private client files, credentials and generated
artifacts. Game/proxy images use owned contexts. Base image digests are pinned;
npm uses lockfiles. Mutable OS repositories still affect reproducibility and
require fresh security scans. PR scans include Hercules; release scans do not.

Compose preserves existing ports and environment names; database is backend-only
and client resources are read-only. Runtime `stable` defaults and published host
ports are intentional deployment behavior, not local-test isolation guarantees.
Kubernetes web pods drop capabilities, disallow privilege escalation, use
non-root UID 1000 and RuntimeDefault seccomp. The database ingress policy admits
only the named clients and operator; it is not a namespace-wide default-deny
egress policy. Flux overlays select reviewed source tags and preserve resource
identities/pruning. No live changes were made.

Setup source inspection found explicit storage/installer prerequisites, checksum
verification, refusal of existing data and interrupted setup, plus existing-node
no-change checks. Flux bootstrap requires confirmation; existing installations
are checked first. Offline fixtures cannot prove hardware mount behavior,
Longhorn readiness, real token permissions or a successful fresh installation.

## Verification limits

### Final pre-commit source and trigger check

Only `workflow_call` is enabled in publish/security. The sole repository caller
is CI; its actual events are PR and main push. Security requires a main push and
successful validation, and publish additionally requires successful security.
PRs cannot reach promotion; dispatch, schedule and workflow_run are not enabled.
Relative workflow calls resolve at the caller commit, and workflow_call inherits
the caller SHA/context. Thus executable `github.sha`, validated checkout, candidate
revision, ready-record SHA and publisher source refer to the same main-push commit,
even when main advances while the run waits.

Scans address the exact candidate digest on both architectures before ready
artifacts are uploaded. Download-artifact uses this same run (no cross-run ID).
Publisher rejects mismatched source/run/attempt and candidate digest/revision
before journal writes or promotion; registry tags are created from approved
digests and verified. Recovery retains its journal/historical proof and ancestry
checks. No permissions or workflow triggers were changed in this final check.

For workflow_run, `github.sha` would instead be the default-branch commit and
`github.event.workflow_run.head_sha` the triggering revision. Supporting it would
require trusted event/repository/branch/conclusion validation plus explicit source,
run/attempt and artifact binding; substituting head_sha alone is insufficient.
The new regression uses different default-branch and approved SHAs: the wrong
source fails without registry/GitOps mutation, the approved source succeeds.
Trigger/gate contracts prohibit accidentally enabling workflow_run or dispatch.

The final targeted cleanup found no necessary internal caller or documented
compatibility requirement for the disabled rAthena placeholder. The exit-only
script and its execution test were removed. The old unsafe installer remains
disabled without replacement; no alternative unsafe installation was enabled.
Unknown external callers now receive a missing-file error instead of exit guidance.
Both renamed-file references were checked in tracked and untracked public files.
Before documentation edits the existing tracked diff matched its starting hash;
only additive test/documentation edits were made, with no reset, staging or commit.

Current-session unavailable tools: kubectl (platform/Kustomize checks), actionlint
and shellcheck. Live Actions/registry, image builds/scans and deployment acceptance
remain untested. The historical results below are not current-session evidence.

- **Tested** (macOS ARM64, Python 3.15.2, Bash 3.2):
  `python scripts/py/check-publishing.py` passed 22 tests; all six CONTRIBUTING
  Python commands (`check-script-layout`, `check-dockerfile-configs`,
  `check-compose-contract`, `check-k8s-bootstrap`, `check-k8s-all`,
  `check-xerj-monitor`) passed using `.venv/bin/python` and the Homebrew tool PATH.
  `bash scripts/sh/ci/check-k8s-setup.sh`, `bash -n scripts/sh/k8s/*.sh`,
  `.venv/bin/mkdocs build --strict --site-dir <temporary-directory>` and
  `git diff --check` passed. Publisher/test editor diagnostics are clear;
  eight existing CI dynamic-environment warnings remain. The final tracked
  binary diff hash still matches the starting hash.
- **Not tested**: `bash scripts/sh/ci/check-platform-config.sh` and
  `kubectl kustomize deploy/k8s/overlays/flux` require missing kubectl;
  actionlint/shellcheck are unavailable. Networked upstream-layout checks,
  image builds/scans and live GitHub/registry/cluster acceptance were not run
  in this scoped offline check.
- **Failed**: none of the executed validations. Tool discovery found the missing
  prerequisites listed above; skipped checks are not counted as passing.

References: [GitHub trigger semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
[same-commit reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).

The recovery regression executes the actual release scope in an isolated Git
repository with a fake registry. Only Bash-4 Owner lowercasing is normalized for
macOS Bash 3.2. It reproduced the recovery failure before the fix and passed
afterward. Scope contracts exercise the workflow's actual grep expressions.
They do not prove every runner/action interaction. Publishing regressions execute
the replacement state machine with isolated GitHub/registry adapters; the original
six cases executed the former workflow shell steps against local command mocks.
Additional fixtures cover adapter request fields/errors, not live API semantics.

Remaining required operational checks: real AMD64/ARM64 candidate builds and
Trivy, actual registry promotion, branch protection/token approval
settings, cluster installation/recovery and application login. Do not infer any
of these from local contract success. No commit, push, merge or deployment was
performed. This audit leaves the explicitly open findings unresolved.

Observed local results: all six CONTRIBUTING Python contract/fixture commands,
the platform-config shell check, Flux Kustomize rendering, `git diff --check`
and strict MkDocs build passed. No expensive image builds were repeated.
The initial recovery check failed as intended after correcting a macOS Bash
compatibility blocker; a fixture interpreter-symlink defect was also repaired.
No remaining failure was observed in those executed checks. Workflow linting
with actionlint and shellcheck was not run because those tools were unavailable.

Reference: [GitHub environment-file semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#setting-an-environment-variable).