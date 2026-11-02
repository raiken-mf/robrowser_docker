# Image split validation — 2026-11-02

Branch: `fix/roBrowserLegacyUpdate`. Local builds and runtime tests ran on ARM64.
No commits, pushes, PRs, publication or cluster reconciliation were performed.

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
  The unused historical npm manifests under images/robrowser remain preserved;
  images/vite contains the active manifests.

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

### Files intended for the commit

Only the following reviewed files belong to this change. Do not use force-add
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
