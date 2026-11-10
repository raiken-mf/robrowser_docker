# Repository audit and conservative cleanup

## Implementation follow-up

The original findings below describe the audit snapshot, not current status.
No additional general audit was performed during implementation.

- F01: temporary sibling uploads, size checks, sync and atomic rename; failed
  streams preserve old files. Cleanup depends on API availability.
- F02: inherited namespace preserved; explicit environment-file value wins.
- F03: executable publisher checkout pinned to validated initiating commit.
- F10: unchanged unadopted releases recover without rebuilding; invalid revisions
  and changed component inputs still require security-gated builds.
- F06/F07: expected suspended Flux owners required, active Kustomizations rejected;
  old web entrypoint delegates to check-only full bootstrap.
- F05/F11: fresh MariaDB requires explicit chart version, rejects existing Flux/
  operator, checks prerequisites and aborts webhook timeout. Compatible chart
  release and live upgrade remain uncertified.
- Requested renderer/standards renames completed with callers updated. Unused
  disabled rAthena placeholder removed; Compose start wrapper retained.
- F04: concrete persistence plan only; existing data/volumes untouched. Operator
  upgrade plan likewise requires approval and restore testing.
- F08/F09/F12/F13/F14 remain open. No unrelated runtime/resource/translation edits
  or new dependencies were introduced. Deployment/operations describe limits.

### Implementation verification

- Tested on macOS with the existing Python 3.15 environment: publisher (20 cases),
  Dockerfile/configuration contracts, bootstrap/namespace/secret/installer mocks,
  upload success/interruption/newline filenames, Flux guards, script layout,
  Compose contract, XERJ monitor, K3s/Flux setup mocks, shell syntax, strict MkDocs
  and whitespace checks. Dockerfile contracts do not build images.
- Initial regression failures were expected and became green after fixes.
  Initial PATH failures for gettext/Docker were resolved using installed tools;
  no dependencies were installed.
- Not tested: real Kubernetes/Kustomize/platform rendering (kubectl unavailable),
  live Actions/registry promotion, AMD64/ARM64 image builds, operator compatibility,
  data migration/restoration or game login. Network upstream checks and known
  unsafe override-build tests were not rerun. No live cluster/private client access.
- Failed gate: platform-config check stops because kubectl is unavailable.
  Generated documentation remains in owned temporary directories, not the repo.

## Scope and evidence

This audit covers the working tree based on commit
`ee80c52835e137bad1e672161ff37452260da1d4`, including the publishing changes
already present before the audit. The cleanup branch is
`audit/repository-cleanup-20261110`. Existing changes were preserved; no commit,
push, pull request, production action or workstation dependency installation was
performed. Findings describe this working tree, not necessarily the committed
main branch. This is a static audit with selected local regression checks, not
production certification.

Before adding this report, the deduplicated Git inventory contained **147 existing
public project files: 144 tracked and 3 untracked**. One tracked but deleted empty
frontend marker is excluded from that count. This report adds one untracked file,
bringing the existing public inventory to **148**. Directory counts before this
report: root 11, `.github` 10, `.vscode` 1, `build` 1, `client` 5, `deploy` 31,
`docs` 18, `images` 42, `scripts` 28. The inventory below records each path and
its role; a role is not a claim that every optional external use was demonstrated.

All project-owned scripts, Dockerfiles, workflow definitions, deployment
configuration and public documentation were reviewed across bounded read-only
reviews and direct checks. Exceptions to full text inspection:

- The generated Flux components manifest was inspected for structure, images
  and RBAC, not every generated CRD field (7,390 lines).
- npm lockfiles were parsed structurally: lockfile version 3, 471 frontend and
  6 proxy package records including their roots. Registry and integrity metadata
  were inspected; transitive dependency implementations were not audited.
- The GPLv3 license was identified from its metadata, not analyzed legally.
- No private configuration or credential contents were inspected.
- Case-insensitive audio/archive exclusions: **185 MP3 and 3 GRF files**. No
  contents were examined or changed. MP3 names are 01-31, 33-172, 174-186 and
  997 under the client BGM directory; the GRFs are CR2, data and rdata under
  client resources.
- Other ignored project files: four Finder metadata files and the 40-byte
  client resource selection INI, inspected only for metadata and public callers.
  The INI contents were not opened. The ignored inventory also contains 18,507
  virtual-environment files and 13 generated Python cache files, excluded.
  Git internals were not traversed.

## Architecture judgment

The ownership split is sound: each of the five images owns its runtime and
image-specific tests; shared validation/rendering lives under language-specific
scripts; Compose, Kubernetes templates, Kustomize bases and Flux installation
configuration have distinct homes. Hercules is a supported Compose alternative,
not an abandoned duplicate of rAthena. RemoteClient and the Vite frontend are
separate services with distinct mounts, build inputs and runtime contracts.

The main complexity is deployment ownership: manual Kubernetes installers,
offline rendering and Flux reconciliation coexist. Removing one merely because
there is another installer would break operational contracts. Instead, establish
one guarded bootstrap owner and make manual entry points enforce that boundary.
Base/template duplication supports both fixed GitOps and configurable bootstrap;
retain it until generation and parity tests can replace it without identity drift.

The existing unpublished publisher improves release durability with approved
digest records, ancestry ordering, a persistent approval journal, compare-and-swap
Git updates and one consolidated draft proposal. Its supported recovery states
justify the journal and legacy-release recovery tests. They do not justify the
retired shell-workflow test emulator, which was removed.

## Prioritized findings

No P0 was demonstrated. Priorities indicate consequences, not confirmed live
incidents. Runtime and external repository settings remain unverified.

Source links use GitHub main for published documentation compatibility. Line
references describe the audited local working tree and may differ from main,
especially for unpublished publishing changes; the inventory identifies local
paths. Remote link availability was not verified.

| ID | Priority | Evidence and consequence | Recommendation |
| --- | --- | --- | --- |
| F01 | P1 | [Client uploader](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-client-data.sh#L54) streams directly into the final PVC pathname with `tee`; the size check runs afterwards. A failed retry can truncate a previously valid asset. | Stream into a unique sibling temporary file, verify length or digest, then rename atomically; test interrupted overwrite against an existing fixture. Do not test on private assets. |
| F02 | P1 | [Bootstrap renderer](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/py/render-k8s-bootstrap.py#L25) reconstructs the subprocess environment from PATH and defaults, while [bootstrap owner](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-all.sh#L23) inherits `K8S_NAMESPACE`. A namespace supplied only through the environment can place Secrets/ConfigMap in `ragnarok` and workloads elsewhere. | Resolve one validated settings snapshot for all renderers; test environment-only namespace and precedence. |
| F03 | P1 | [Publish checkout](https://github.com/raiken-mf/robrowser_docker/blob/main/.github/workflows/publish.yml#L24) selects moving `main`, then runs repository publisher code with a write token. A queued approved run can execute publisher code newer than its own validated revision. | Check out the initiating SHA for executable code; fetch current main separately for ancestry and CAS. Retain the approval journal and exact scanned digests. This finding is in the pre-existing unpublished workflow changes. |
| F04 | P1 | [Compose database](https://github.com/raiken-mf/robrowser_docker/blob/main/deploy/compose/docker-compose-common.yml#L13) mounts configuration but does not declare `/var/lib/mysql`. Persistence relies on the image's anonymous-volume behavior; recreation can detach the old data from the replacement container. | Add an explicitly managed persistent volume only with a reviewed migration/backup procedure. Do not migrate or delete existing anonymous volumes automatically. |
| F05 | P1 | [MariaDB installation](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-mariadb.sh#L37) uses unversioned `helm upgrade --install` for operator and CRDs. Repeating an installation can introduce an unreviewed operator/schema change. | Pin a reviewed compatible chart pair and separate installation from approved upgrade. |
| F06 | P2 | [Flux bootstrap guard](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-all.sh#L64) iterates only returned resources from two named lookups with `--ignore-not-found`; an empty list passes. Other matching reconcilers are not checked. | Require the intended resources when Flux is present and verify all owners of the application resources are suspended before writes. Add absent-resource and extra-owner fixtures. |
| F07 | P2 | [Standalone web installer](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-robrowser.sh#L32) deletes ingress/configuration and restarts workloads without the guarded bootstrap/Flux protocol. No repository caller was established, but external use is plausible. | Retain until the external contract is resolved; then delegate to the guarded owner or formally deprecate with a fail-closed migration path. |
| F08 | P2 | [rAthena workloads](https://github.com/raiken-mf/robrowser_docker/blob/main/deploy/k8s/base/rathena.yaml) and their template lack application readiness/liveness probes and resource requests/limits. Successful rollout alone does not demonstrate an accepting game server. | Add measured resource settings and appropriate readiness checks; avoid restart probes that interfere with DB initialization. Keep template/base parity. |
| F09 | P2 | [Override test](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/py/check-image-overrides.py#L20) copies the full local images tree, including ignored override payloads, into its build context; fixed image tags remain afterwards. | Build an allowlisted public fixture, use unique tags and provide clearly scoped cleanup. Do not transmit local override data or prune user images. |
| F10 | P2 | [Security scope](https://github.com/raiken-mf/robrowser_docker/blob/main/.github/workflows/security.yml#L66) marks an image changed whenever stable differs from the adopted GitOps pin before comparing inputs. A pending human approval can trigger repeated unrelated rebuilds. | Separate release recovery from input-change detection using the existing journal. Keep both-platform vulnerability gates; prove that recovered digests cannot bypass approval. |
| F11 | P2 | [MariaDB installer](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-mariadb.sh#L53) continues after the webhook endpoint loop exhausts; the later network-policy apply requires envsubst despite an earlier fallback. Failures can occur after partial cluster mutation. | Check all prerequisites before writes and fail explicitly on webhook timeout; either require envsubst or provide one complete renderer. |
| F12 | P2 | [Frontend HTML template](https://github.com/raiken-mf/robrowser_docker/blob/main/images/robrowser/index.html.template) receives shell substitution into JavaScript without context-specific encoding. Operator-controlled malformed settings can break or inject script. No remote attacker control was established. | Validate numeric/date settings and serialize string configuration as JSON instead of raw substitution. |
| F13 | P3 | [Security policy](https://github.com/raiken-mf/robrowser_docker/blob/main/SECURITY.md#L20) describes password command arguments, while current rAthena DB invocation uses MYSQL_PWD; [Apache configuration](https://github.com/raiken-mf/robrowser_docker/blob/main/images/remote/httpd.conf) enables OS tokens/signatures. | Correct the credential boundary description; reduce server identification independently. MYSQL_PWD still exposes credentials through process environment to sufficiently privileged readers. |
| F14 | P3 | Kubernetes MariaDB/BusyBox tags and documentation tooling are not uniformly digest/version pinned or covered by update automation. | Add reviewed pin/update ownership rather than treating current scanners as a complete dependency inventory. |

Further limited-scope observations: default Kubernetes NodePort validation accepts
1-65535 but does not preflight the cluster's configured service range; storage
diagnostics suppress some journal errors and assume an mmcblk0 boot-device naming
pattern; historical English-project documentation contains German passages;
four public resource/audit pages are not included in the MkDocs navigation.
These are follow-up candidates, not evidence of unused functionality.

## Naming and removal decisions

Keep kebab-case helpers with `check-*` for validation and `render-*` for offline
generation, image-specific entrypoints under their image, and shared helpers under
the existing language/purpose directories. Preserve documented external names
and Kubernetes/Flux resource identities. A cosmetic rename is not enough benefit.

| Component | Decision and evidence |
| --- | --- |
| Empty frontend Git marker | Removed. Tracked API HTML/bootstrap files already keep the directory present; the Compose assertion now checks actual payload rather than bookkeeping. |
| Old publishing workflow emulator | Removed from [publisher tests](image-revisions.md). No external caller was found; all 19 tests now exercise the current Publisher. Supported legacy-release recovery tests remain. |
| K3s unused parent/root variables and server-join branch | Removed from [setup](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-setup.sh). Variables had no consumers; the earlier guard rejects server joins. Added a rejection regression, preserving that security boundary. |
| Duplicate obsolete publication statements | Updated [GitOps](gitops.md) and [upstream updates](upstream-updates.md) to match ancestry/approval ordering rather than claiming any main advance rejects publication. |
| [Root start wrapper](https://github.com/raiken-mf/robrowser_docker/blob/main/start.sh) | Retained: documented public Compose entry point. |
| Retired rAthena installer placeholder | Removed with its execution test: no necessary internal caller or documented compatibility requirement found. The old unsafe installer remains disabled without replacement; no unsafe alternative enabled. |
| [Web manifest renderer](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-render-web-manifests.sh) | Renamed at user request; CI/bootstrap/documentation callers updated. |
| [Best practices](best-practices.md) | Renamed at user request; agent/contribution/navigation references updated. |
| Standalone web installer and old override mounts | Retained pending contract evidence. No current installer consumer of the Compose `/opt/repository_override` mounts was found; local overrides may have external consumers. |
| Empty client/other-image placeholders | Retained: intentional directory/mount and override interfaces, unlike the redundant frontend marker. |
| Historical ROEnglish audits | Retained: compatibility evidence, not executable duplicates. Translate/correct separately rather than delete. |
| npm dependencies and lockfiles | Retained: no unused dependency was proven; upstream module/build/test consumers exist. |

No files were renamed. No assets, source pins, variables, ports, credentials,
storage resources or Flux identities were changed. The publisher implementation
and the user's workflow refactor were not replaced by this cleanup.

## CI/CD decision matrix

| Change or stage | Current path | Decision |
| --- | --- | --- |
| Documentation-only | Documentation workflow; some main CI paths ignored | Keep a strict documentation build and explicit link/navigation policy; no image build needed. |
| Script/deployment contracts | Main validation, bootstrap mocks, Compose/Kustomize checks | Keep. Scope executable checks to touched ownership; retain contract validation for shared changes. |
| Web image inputs | One broad smoke switch builds RemoteClient/frontend and proxy integration | Keep integrated behavior checks; split image scope only with a dependency map proving equivalent coverage. |
| rAthena inputs/pin | Dedicated pin-scope and entrypoint/build checks | Keep; shared dependency-file edits need semantic component detection. |
| Affected PR images | Five-image PR scanner, AMD64/ARM64 | Keep security gates; Hercules remains covered despite not being published. |
| Approved main candidates | Four published components, both platforms, HIGH/CRITICAL gate and SBOM | Keep exact digests and approval artifacts; do not substitute a rebuilt tag during promotion. |
| Queued/recovered release | Journal, ancestry, immutable SHA tag and stable promotion | Keep recovery. Fix executable checkout provenance and repeated-build detection separately. |
| GitOps adoption | Consolidated draft proposal, human review, active Flux after merge | Keep human approval. External auto-merge/branch protection were not verified. |
| Fork/dependency updates | Pinned revisions, updater PRs, XERJ reviewed revision | Keep separation of proposal and acceptance; the 40-byte reviewed revision file is not empty despite zero newline count. |

## Small implementation plan

1. Fix F01/F02 with isolated failure/precedence fixtures before any operational use.
2. Resolve F03 and F10 together against the publisher's current 19-regression
   suite; add queued-checkout and pending-adoption cases without changing gates.
3. Plan F04 persistence migration and F05 operator pinning with backups and human
   approval. No live change is implied by this audit.
4. Consolidate guarded manual ownership for F06/F07; add readiness/resources and
   installer preflight checks. Resolve uncertain external consumers before removal.
5. Address F09 fixture isolation and remaining documentation/pinning drift in
   separate small changes, not a repository-wide rename or framework rewrite.

## Verification and side effects

**Tested:** macOS, local Python 3.15.2 environment, Bash 3.2 and local Docker.
`check-script-layout.py` passed; `check-publishing.py` passed all 19 tests;
`check-k8s-setup.sh` passed isolated mocked K3s/Flux cases including server-join
rejection; strict MkDocs build passed using the existing environment and a
temporary output directory; editor diagnostics found no errors in touched
scripts; `git diff --check` passed. The real override test passed for RemoteClient
and frontend startup overrides.

The override test was mistakenly treated as a lightweight check before its
side effects were inspected. It built local `remote-override-test:remote` and
`remote-override-test:robrowser` images and ephemeral containers. The containers
were removed by the test; image tags and build cache remain. Build-time npm
installation occurred inside the fixture image, not the workstation environment.
No production cluster or private asset content was intentionally tested.

**Not tested:** full Compose smoke after its changed payload assertion, all-image
builds, live registry/GitHub workflows and settings, both Linux architectures,
hardware/storage behavior, browser/gameplay, deployment/migration, excluded
assets and every generated Flux CRD field. Local passing checks do not certify
these requirements. MkDocs reports four existing pages outside navigation.

**Failed:** initial rg lookup (tool unavailable), initial PATH MkDocs lookup
(executable available only in the existing virtual environment), and some
read-only agent/helper queries; compatible replacements completed. The first
strict build of this report failed on relative links to non-documentation source
files; links were corrected and the same strict build passed. No behavioral
regression test executed in this cleanup failed.

## File inventory

Each bullet lists a directory and every inventoried basename beneath that
directory, with a role for each group. Paths combine the stated directory and
basename. This is the 147-file inventory plus this report; ignored assets/caches
are described above rather than presented as audited public source.

- Root: `.dockerignore` (build exclusions), `.env-tmpl` (public settings),
  `.gitignore` (Git exclusions), `AGENTS.md` (agent rules), `CHANGELOG.md`
  (history), `CONTRIBUTING.md` (validation), `LICENSE` (GPLv3), `README.md`
  (entry documentation), `SECURITY.md` (reporting/boundaries), `mkdocs.yml`
  (docs navigation), `start.sh` (Compose public wrapper).
- `.github`: `copilot-instructions.md` (agent guardrails), `dependabot.yml`
  (updates), `xerj-reviewed-revision.txt` (accepted reference SHA).
- `.github/workflows`: `ci.yml` (validation), `dependency-update.yml` (fork
  proposals), `docs.yml` (docs publication), `pr-image-security.yml` (PR scans),
  `publish.yml` (approved promotion), `security.yml` (candidate scans/SBOM),
  `xerj-reference-monitor.yml` (reference proposals).
- `.vscode`: `settings.json` (editor approval rules).
- `build`: `dependencies.env` (public pinned revisions).
- `client/AI`: `add-AI-folder-files-here.txt`; `client/BGM`:
  `add-bgm-here.txt`; `client/System`: `add-system-folder-files-here.txt`;
  `client/data`: `add-data-folder-files-here.txt`; `client/resources`:
  `add-resources-folder-files-here.txt` (directory/interface placeholders).
- `deploy/clusters/default`: `kustomization.yaml` (cluster bundle),
  `ragnarok-app.yaml` (application reconciler).
- `deploy/clusters/default/flux-system`: `gotk-components.yaml` (generated
  controllers/CRDs/RBAC), `gotk-sync.yaml` (Git synchronization),
  `kustomization.yaml` (Flux bundle).
- `deploy/compose`: `docker-compose-common.yml` (shared services),
  `docker-compose-hercules.yml`, `docker-compose-rathena.yml` (alternative game
  stacks); `deploy/compose/conf.d`: `mariadb.cnf` (DB settings).
- `deploy/k8s/base`: `kustomization.yaml` (bundle), `mariadb.yaml` (DB),
  `namespace.yaml` (scope), `network-policy.yaml` (DB isolation),
  `pvc-client-data.yaml` (storage), `pvc-helper.yaml` (loader),
  `rathena-config.yaml` (public settings), `rathena.yaml` (game servers),
  `remote.yaml` (resource service), `robrowser-config.yaml` (public web settings),
  `robrowser.yaml` (frontend), `wsproxy.yaml` (proxy).
- `deploy/k8s/overlays/flux`: `kustomization.yaml` (adopted image pins).
- `deploy/k8s/templates`: `mariadb.yaml`, `namespace.yaml`,
  `network-policy.yaml`, `pvc-client-data.yaml`, `pvc-helper.yaml`,
  `rathena.yaml`, `remote.yaml`, `robrowser.yaml`, `wsproxy.yaml`
  (configurable equivalents of named base resources).
- `docs`: `best-practices.md` (standards), `ci-audit.md` (existing unpublished
  CI report), `cluster-installation.md` (host setup), `deployment.md` (settings),
  `development.md` (contributing checks), `fresh-install-runbook.md` (bootstrap),
  `frontend-api-module.md` (iframe regression), `gitops.md` (ownership/adoption),
  `image-revisions.md` (provenance), `index.md` (entry),
  `loose-client-resources.md` (resource behavior), `operations.md` (recovery),
  `roenglish-additions-audit.md`, `roenglish-addon-audit.md`,
  `roenglish-upstream-inventory.md` (translation compatibility evidence),
  `security.md` (controls), `upstream-updates.md` (update acceptance),
  `validation.md` (recorded coverage), `repository-audit.md` (this new report).
- `images/hercules`: `Dockerfile` (build), `docker-entrypoint.sh` (runtime);
  `repository_override/put_files_to_override_here.txt` (override interface).
- `images/rathena`: `Dockerfile` (build), `entrypoint.sh` (runtime);
  `repository_override/put_files_to_override_here.txt` (override interface).
- `images/rathena/templates`: `char_conf.txt.template`,
  `defines_pre.hpp.template`, `inter_conf.txt.template`, `login_conf.txt.template`,
  `map_conf.txt.template` (server/build settings); `images/rathena/tests`:
  `check-entrypoint.sh` (runtime regression).
- `images/remote`: `Dockerfile` (build), `apache-access.conf` (HTTP boundary),
  `entrypoint.sh` (runtime), `httpd.conf` (Apache), `index.html` (service page),
  `roenglish-generate.php` (translation generation), `roenglish-startup.php`
  (atomic translation publication), `security.ini` (PHP controls);
  `repository_override/put_files_to_override_here.txt` (override interface).
- `images/remote/tests`: `check-php.php` (HTTP/PHP fixture),
  `check-roenglish-generator.php` (generator fixtures), `check-roenglish.py`
  (byte comparison), `check-roenglish.sh` (integration).
- `images/robrowser`: `Dockerfile` (build), `entrypoint.sh` (runtime),
  `index.html.template` (client settings), `package.json` (dependencies),
  `package-lock.json` (locked resolutions), `vite.config.js` (dev server rules).
- `images/robrowser/repository_override/applications/api`: `api-bootstrap.js`
  (iframe/module handshake), `api.html` (embedding entry).
- `images/robrowser/tests`: `check-api-handshake.cjs` (protocol),
  `check-api-module.py` (Vite resolution), `check-api-override.py` (upstream
  parity), `normalize-cursor-test.cjs` (upstream test adaptation).
- `images/wsproxy`: `Dockerfile` (build), `compat.js` (compatibility),
  `package.json` (dependency), `package-lock.json` (locked resolution);
  `tests/check-wsproxy.cjs` (connection regression).
- `scripts/py`: `check-compose-contract.py` (settings contract),
  `check-compose.py` (isolated web smoke), `check-dockerfile-configs.py`
  (CI/build contracts), `check-fork-update-cycle.py` (update protocol),
  `check-image-overrides.py` (real override builds), `check-k8s-all.py`
  (bootstrap protocol), `check-k8s-bootstrap.py` (private render fixtures),
  `check-publishing.py` (existing unpublished publisher regressions),
  `check-script-layout.py` (layout), `check-xerj-monitor.py` (monitor fixtures),
  `publish-images.py` (existing unpublished promotion owner),
  `render-k8s-bootstrap.py` (offline private renderer).
- `scripts/sh/ci`: `check-image-boundaries.sh` (image isolation),
  `check-k8s-setup.sh` (mocked infrastructure guards), `check-platform-config.sh`
  (manifest contracts), `check-rathena-pin-scope.sh` (semantic pin scope),
  `check-upstream-layout.sh` (source contracts), `check-xerj-updates.sh`
  (reference proposals).
- `scripts/sh/compose`: `start-compose.sh` (Compose lifecycle).
- `scripts/sh/k8s`: `k8s-all.sh` (guarded application bootstrap),
  `k8s-client-data.sh` (asset uploader), `k8s-mariadb.sh` (operator installer),
  `k8s-robrowser.sh` (guarded bootstrap compatibility entrypoint),
  `k8s-setup-flux.sh` (Flux setup/check), `k8s-setup-storage.sh`
  (storage guards/diagnostics), `k8s-setup.sh` (host infrastructure),
  `k8s-render-web-manifests.sh` (offline public manifests).