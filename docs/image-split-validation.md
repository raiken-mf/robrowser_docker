> Historical sections below use the former names: robrowser = Apache/PHP,
> vite = frontend. Final names are remote = Apache/PHP and robrowser = frontend.
> See the final-name validation section at the end; do not interpret old registry
> digests or build commands as releases under the new names.

# Image split validation — 2026-11-02

Branch: `fix/roBrowserLegacyUpdate`. Local builds and runtime tests ran on ARM64.
Initial local validation preceded publication of the branch. The reviewed
snapshot was subsequently committed and opened as draft PR #72 with authorization.
No cluster reconciliation or deployment was performed.

## Changes

- Kubernetes base and templates use the standalone Vite image. Flux has an
  independent Vite override, so the roBrowser SHA override no longer selects it.
- Deployment scripts apply and monitor both web Deployments. A local renderer
  prepares their manifests and shared non-sensitive ConfigMap from `.env`.
  Flux consumes the reviewed Git files, not the host's `.env`.
- Kubernetes port fallbacks remain Apache 30080, Vite 30000 and wsProxy 30599.
  Compose retains its existing host-port variables and fallbacks. Internal
  container/target ports remain 8080, 3000 and 5999.
- Compose mount paths point to the actual repository directories. Its Git-ref
  fallbacks match `build/dependencies.env`; user-supplied overrides still apply.
- Both image override directories enter the Docker build context. Credentials,
  local configuration directories, Git metadata, backups and client resources
  are excluded. Vite's override payloads are ignored by Git.
- Apache merges mounted loose files after baked translations and executes the
  encoding mapper from the RemoteClient directory. AI, BGM and GRF mounts remain
  available. Required translation directories fail the build when missing.
- Both runtime images remain non-root. PHP hardening, TRACE protection,
  Kubernetes security contexts and Always pull policies remain in place.
  Apache blocks Git paths at server level; Vite also explicitly upgrades zlib.
- CI builds Vite separately, renders templates and checks both translation
  variants and disposable Compose services. Security builds/scans and SBOMs cover
  Vite on AMD64 and ARM64; release records and digest promotion include Vite.
  Dependabot follows the active npm overlay under `images/vite`.

## Completed checks

| Check | Result |
| --- | --- |
| Final Apache builds, `SET_PRERENEWAL=0` and `1` | Passed on ARM64 |
| Final Vite build | Passed; zlib updated from 1.3.2-r0 to 1.3.2-r1 |
| Installed Renewal translations | 625 SHA-256 matches |
| Installed Renewal → Pre-Renewal translations | 684 SHA-256 matches; 10 differing overwritten files |
| Shared Apache/Vite Compose runtime | Passed with Renewal and Pre-Renewal test images |
| HTTP and Vite GR2 module transformation | Passed |
| Cross-container RemoteClient loose-file request and CORS | Passed |
| Apache PHP runtime/security check | Passed: PHP 8.4.27, apache2handler |
| Git-path blocking and TRACE protection | Passed: HTTP 404 and 405 |
| Mounted loose files and both override payloads | Passed |
| Encoding mapping from mounted GRFs | Generated successfully and parsed as JSON with GRF entries |
| Runtime non-root and forwarded Vite PORT_FRONTEND | Passed in final Renewal/Vite test |
| Apache Node.js/npm absence | Passed |
| Compose rAthena/Hercules configurations | Passed; custom host ports and read-only mount sources checked |
| Kubernetes base and Flux overlay rendering | Passed; independent image, ConfigMap and security contexts checked |
| Template rendering | Passed with default and custom NodePorts; no unresolved variables |
| Base web manifests versus `.env-tmpl` rendering | Matched |
| Docker build-context exclusion/inclusion test | Passed |
| Git-ref format | Full 40-character SHA pins |
| GitHub Actions/actionlint and shell syntax | Passed |
| Git whitespace check | Passed |

Test containers used ephemeral loopback ports. Final Compose tests used unique
project networks and removed their own containers and networks afterwards. An
earlier test inherited existing network names from resolved Compose configuration;
its containers were removed and subsequent tests explicitly removed those names
before starting. Existing deployment containers were not updated or restarted.
Local `robrowser-split-test` image tags remain available for review.

## Pending checks and rollout constraints

- GitHub-hosted AMD64 builds and the actual authenticated multi-platform security
  scans/SBOM uploads/digest promotion have not run. Workflows were validated
  locally; no registry publication was attempted.
- No Kubernetes server-side validation or deployment was performed. Before
  rollout, render and review the environment-specific ConfigMap, including HOST
  and ports; the committed base contains example/default values.
- Confirm the new Vite release exists in GHCR before deployment. Transfer
  NodePort 30000 (or configured PORT_FRONTEND) in two reviewed GitOps stages:
  remove the old frontend port from Service robrowser first, then add Service
  vite. Do not depend on Flux apply ordering. See deployment.md for details.
- Browser gameplay, login through wsProxy and full database/emulator startup
  remain untested. GRF mapping and web delivery checks do not establish gameplay
  compatibility for a particular PACKETVER.
- Optional upstream Additions/Compatibility/Addons are not automatically applied.
  SET_PRERENEWAL selects build-time content, not a runtime translation switch.
- Local ignored override payloads are not automatically present in Actions.
  The current architecture correction removes the unused historical npm manifests
  under images/robrowser; images/vite owns the frontend manifests and template.

## Pre-PR review — 2026-11-02

Recommendation: a draft PR can be prepared for review; this change is not ready
for an unattended merge into main. No workflow or Flux automation was disabled
as part of this review, and no cluster state was queried or changed.

Blocking rollout findings:

1. Flux follows main and can reconcile before Actions have built, scanned and
   published the new images. The security gate controls publication, not the
   first application of manifests from Git.
2. This single diff both removes and reassigns NodePort 30000. A coordinated
   two-stage migration or an agreed operator-controlled rollout gate is required.
3. The new Git-managed ConfigMap contains example/default values, including
   HOST=127.0.0.1. Applying it may overwrite the live values; pods only reread
   environment variables when recreated. Review all required existing keys.
4. The roBrowser Flux override still pins the former combined-image revision
   sha-6cfa563fd1c0c2bf2842345c1499b5bc485847c9, while Vite uses stable. Confirm
   both matching new scanned images before switching to the split architecture.
5. Publication requests auto-merge of the generated image-bump PR. Scheduled
   dependency updates and Dependabot also request auto-merge for their own PRs.
   These are existing automation paths, not an approval barrier for this rollout.
   Actual branch protections, auto-merge availability and live Flux state were
   not inspected.

The two builds use ROBROWSER_REF=7181f0f54f9785829839bb15459822ac511c58ab in the
resolved local Compose configuration and the shared Actions pin source. This
confirms build inputs, not the contents of already-published registry tags.
Future scheduled pin updates only modify build/dependencies.env; Compose's
literal fallback pins must be kept aligned in subsequent dependency changes.

The resources placeholder is included explicitly. Local .env, credential paths,
backup/editor files, node_modules, reports/ready artifacts and Python caches
are excluded from Git and/or the build context as appropriate. Pattern scanning
of all changed/untracked candidate files and comparison with non-template local
credential values found no exposed credentials; this is not a proof against
all possible secret formats.

Repeated local checks passed: Compose variants and shared revision, YAML/Python
and shell syntax, default/custom template ports, Kustomize base/Flux rendering,
Git whitespace checks, Git exclusions and Actions validation. Earlier ARM64
runtime/translation results above remain applicable; this pre-PR pass does not
claim new registry scans, AMD64 builds, server-side validation or gameplay tests.

### Files in the initially approved 35-file snapshot

The initial approved snapshot contained the following files. The current PR
defers its live Kubernetes/Flux changes; use the actual PR diff for its final scope. Do not use force-add
for ignored resources, credentials, override payloads or test output.

```text
.dockerignore
.github/dependabot.yml
.github/workflows/ci.yml
.github/workflows/publish.yml
.github/workflows/security.yml
.gitignore
client/resources/add-resources-folder-files-here.txt
deploy/compose/docker-compose-common.yml
deploy/compose/docker-compose-rathena.yml
deploy/k8s-templates/robrowser.yaml
deploy/k8s-templates/vite.yaml
deploy/k8s-templates/wsproxy.yaml
deploy/k8s/kustomization.yaml
deploy/k8s/robrowser-config.yaml
deploy/k8s/robrowser.yaml
deploy/k8s/vite.yaml
deploy/overlays/flux/kustomization.yaml
docs/deployment.md
docs/development.md
docs/image-split-validation.md
docs/security.md
images/robrowser/Dockerfile
images/robrowser/entrypoint.sh
images/robrowser/index.html.template
images/vite/Dockerfile
images/vite/entrypoint.sh
images/vite/package-lock.json
images/vite/package.json
images/vite/repository_override/.gitkeep
scripts/check-compose.py
scripts/check-roenglish.py
scripts/check-roenglish.sh
scripts/check-upstream-layout.sh
scripts/k8s-robrowser.sh
scripts/render-web-manifests.sh
```

## Merge-safe scope of PR #72

The live `deploy/k8s/` and `deploy/overlays/flux/` trees are restored to main.
Consequently this PR neither transfers NodePort 30000, manages/overwrites the live
ConfigMap, nor selects split images for existing Kubernetes Deployments. The new
split-image templates and rendering tools are offline preparation only.

The publication workflow now opens only draft GitOps image-bump PRs and does not
request auto-merge. All existing image scanning and digest-promotion gates remain.
The tested roBrowser source pin is retained for both images, rather than adopting
an unrelated concurrent main pin update without validation.

The original five deployment blockers are isolated from this PR's live manifests;
the actual migration remains pending in a separately controlled follow-up. See
`docs/flux-split-migration.md` for the required stages. Main's configured automatic
Flux reconciliation continues, but its rendered application resources are unchanged.

## Architecture correction after PR #72

PR #72 was already merged when the frontend boundary correction was requested.
The correction is prepared on `fix/apache-remoteclient-only` against current main;
it is not added to the independently gated deployment migration in PR #73.
No merge or deployment is authorized as part of this correction.

Dependency inspection found all RemoteClient PHP includes within its own pinned
repository. The only frontend dependency was the browser start page generated by
Apache, referencing applications/api/api.js. That page/template now belongs only
to Vite. Apache serves a minimal static status page at `/` for existing probes,
clones only RemoteClient/ROEnglishRE, and retains `/remote/`, its original .htaccess,
loose-file overlay order and GRF/BGM/AI mounts. Its frontend build arguments and
unused npm manifests are removed. Existing hardening and port variables remain.

The CI and local smoke tests now distinguish Apache's static service page from
Vite's browser configuration. They verify filesystem boundaries, absence of a
frontend clone in Apache's build history, and actual `.htaccess` fallback to the
RemoteClient PHP health API. Each image still accepts its own repository_override.

### Correction validation results

- Local ARM64 builds passed for Apache Renewal, Apache Pre-Renewal and Vite.
- Installed translations passed 625 SHA-256 comparisons for Renewal and 684 for
  Renewal → Pre-Renewal, including 10 differing overrides.
- Both extracted Apache images retain byte-identical pinned RemoteClient .htaccess.
- Filesystem and image-history checks passed for both Apache variants and Vite:
  no frontend checkout/build arguments/artifacts in Apache; no Apache/PHP runtime
  in Vite. The frontend API path on Apache returns HTTP 404.
- Both translation variants passed isolated Compose tests with Vite, including
  static Apache status, rendered Vite configuration, GR2 transforms, PHP 8.4.27,
  non-root UID, TRACE/Git-path blocking, CORS, loose-file mounts and GRF mapping.
- /remote/api/health/simple reached RemoteClient PHP through the preserved
  .htaccess fallback; it returns semantic JSON health, not a filesystem 404.
- Separate fixture builds passed independent marker and index overrides after
  container startup for both images; Vite also rendered HOST/PORT_HTTP correctly.
- Compose source arguments, existing port configuration/pull policies, shell and
  Python/YAML syntax, actionlint, whitespace and unchanged live Flux files checked.
- Existing local deployment containers remained untouched; disposable test
  containers/networks were removed. No upstream repository was modified.

These are local correction results. GitHub PR CI must also pass. New registry
security scans/publication and the controlled deployment migration remain gated;
this correction does not authorize merging or deployment.

## Refresh on current main and publishing assessment

The correction is preserved on a new local branch,
`fix/apache-remoteclient-current-main`, created from main commit
`a8c96f6d06971eb0d97aa1b7bf6e197ae9b809ad`. Original correction commit
`241b77428c6bed63b5aba835e0aaa661c32af2f5` remains in its ancestry; no work was
rebased away or force-pushed. The existing separate correction PR #81 is reused
through a normal fast-forward update, avoiding a duplicate PR.

Local ARM64 builds and tests were repeated on this refreshed tree: both Apache
translation variants, Vite, filesystem/build-history boundaries, isolated Compose
with PHP/RemoteClient routing and GRF mapping, and independent built overrides.
Translation checks again passed 625/684 SHA-256 comparisons and ten differing
Pre-Renewal overrides. RemoteClient .htaccess stayed byte-identical. BuildKit cache
was reused where inputs were unchanged. Live Kubernetes/Flux files remain equal
to the checked main tree. PR #73 and live deployments were not modified.

### Observed Dependabot behavior

PR #77 merged automatically after its validate check succeeded. The active main
ruleset requires validate, an up-to-date branch and zero human approvals; it has
no bypass actors. The Dependabot workflow explicitly enables auto-merge. Security
and publish are skipped on PR events, so passing PR validation does not imply that
these dependency changes have had registry image scans before entering main.
No Dependabot policy, pending auto-merge setting or branch protection was changed
by this refresh.

There is no main CI run recorded for the checked main SHA. The dependency merge
was performed by github-actions using GITHUB_TOKEN. GitHub documents that pushes
originating from GITHUB_TOKEN do not trigger another push workflow:
[Workflow triggers](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).
This explains the observed missing post-merge run; it is not evidence that the
required validate check was bypassed.

### Current main cannot be published by replaying the old run

The old failed release run 41366736177 belongs to commit
`388fb5f43c2f58ad1fba7dc34f92dd603fced371`, not the checked current main SHA.
GitHub reruns retain the original GITHUB_SHA/GITHUB_REF:
[Workflow reruns](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).
The current CI workflow exposes no workflow_dispatch trigger; security and publish
are reusable workflows called only from a successful main push chain. Therefore
replaying the old run would not be a fresh validation/release of current main.

No rerun, dispatch, release, main merge or stable-tag promotion was initiated.
The source/digest and main-freshness checks remain intact. A separately reviewed
full-chain trigger for the intended main revision is needed before publishing;
validation, multiarch security scanning and promotion must remain connected.
Updating stable tags can affect installations on a later pull/restart, so no
release is authorized by this read-only assessment.

## Apache Alpine 3.24.3 / PHP CLI correction (PR #75)

Alpine 3.24.3 installs the explicitly requested PHP 8.4 CLI as `/usr/bin/php84`
without the unversioned `php` command used by the Dockerfile and RemoteClient
entrypoint. The previous PR build failed with `php: not found`. The Dockerfile
now checks the versioned executable exists and links `/usr/bin/php` to it.
The PHP >=8.4.27 and <8.5 guard, PHP upload-progress hardening, Apache restrictions,
non-root runtime and immutable base-image digest are retained.

Native ARM64 builds passed for Apache Renewal, Apache Pre-Renewal and Vite on the
updated tree based on main `35adbdc1cda0a2b80e7eee0e741cd6ba2dc9a81a`.
Both Apache CLI runtimes report PHP 8.4.27. Translation checks passed 625/684
SHA-256 comparisons, including ten differing Pre-Renewal overrides; both retain
the byte-identical pinned RemoteClient `.htaccess`. Independent marker/index
fixture builds passed for both images. Shell/Python/workflow syntax and actionlint
also passed locally.

GitHub PR validation must pass on the pushed correction. Registry vulnerability
scans, publication and any Kubernetes migration remain separate guarded steps;
this base-image fix does not change Flux image selections or authorize a rollout.

## Final-name architecture validation

The final trees are `images/remote` (Apache/PHP/RemoteClient/ROEnglishRE/resources)
and `images/robrowser` (Node.js/Vite/frontend). Compose, Kubernetes and template
services/selectors, CI/security/SBOM/promotion matrices and Dependabot follow
those names. Source revisions and upstream repositories are unchanged. Both
local override trees remain independently tested.

Native ARM64 builds of remote Renewal/Pre-Renewal and robrowser frontend passed.
Translation checks passed 625/684 SHA-256 comparisons, including all ten differing
Pre-Renewal overrides and byte-identical pinned .htaccess. Non-default external
ports and legacy/explicit image tag mappings passed for Compose and templates.
Both modes passed image/history boundaries and isolated Compose with actual
read-only client resources: HTTP pages, GR2 transform, PHP 8.4.27 runtime security,
TRACE/Git blocking, /remote/ routing, GRF encoding mapping and cross-service CORS.
Independent marker/index override builds passed for both renamed trees. These
checks do not create Kubernetes resources or restart existing local containers.
The operator-deleted namespace is absent and both Flux Kustomizations remain
suspended. New-name registry publication/security results must be recorded after
the reviewed main release; local tests do not claim unpublished artifacts exist.
