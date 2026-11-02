# Development and repository layout

## Ownership

- images/robrowser: Node.js/Vite frontend, package/lockfile overlay and client template.
- images/remote: Apache/PHP, RemoteClient, translations and client-file configuration.
- images/rathena and images/hercules: game-server images; images/wsproxy: proxy.
- build/dependencies.env: exact upstream Git revision pins.
- deploy/compose: local runtime; deploy/k8s: concrete GitOps base;
  deploy/k8s-templates: `.env`-based bootstrap/preview templates;
  deploy/overlays/flux: reviewed release selection.
- clusters/pi-cluster: Flux parent/source and child application configuration.
- scripts: bootstrap, renderers and isolated validation helpers.
- docs: installation, operation, development, release and security guidance.

The separate custom-scripts repository owns K3s/Longhorn/Flux bootstrap wrappers;
it is not vendored here. Do not change its storage/bootstrap behavior as a side
effect of an application or documentation fix.

## Safe local work

Use a feature branch or separate worktree based on current main. Keep existing
`.env`, client assets and ignored overrides outside any cleanup/reset operation.
Never run broad git clean, hard resets or image/volume pruning to make a checkout
look tidy. Inspect the worktree's tracked, untracked AND ignored files before
removing it; archive any configuration that must survive.

A branch is not proved merged merely because its PR is closed: rebased/squashed
history may need further review. Preserve ambiguous refs rather than force-delete
them. Remote-branch deletion requires explicit permission.

The full bootstrap can use absolute ENV_FILE and CLIENT_SOURCE_DIR paths from
another worktree. Compose's bind paths/env_file remain rooted in its checkout;
ENV_FILE is not a general Compose override. See [deployment](deployment.md).

## Build the two web images

These commands build **local test images**, not Kubernetes deployments or registry
releases. Source the versioned dependency pins, not an arbitrary upstream HEAD:

```bash
set -a
source build/dependencies.env
set +a
docker build -f images/remote/Dockerfile \
  --build-arg REMOTECLIENT_REPOSITORY="$REMOTECLIENT_REPOSITORY" \
  --build-arg REMOTECLIENT_REF="$REMOTECLIENT_REF" \
  --build-arg ROENGLISH_REPOSITORY="$ROENGLISH_REPOSITORY" \
  --build-arg ROENGLISH_REF="$ROENGLISH_REF" -t remote:ci .
docker build -f images/robrowser/Dockerfile \
  --build-arg ROBROWSER_REPOSITORY="$ROBROWSER_REPOSITORY" \
  --build-arg ROBROWSER_REF="$ROBROWSER_REF" -t robrowser:ci .
```

The remote build accepts SET_PRERENEWAL=1 for its additional translation layer.
The frontend alone fetches roBrowserLegacy; do not add that source tree to remote.
Project-owned npm manifest/lockfile are installed with npm ci. Update the lockfile
and source pin together when the new upstream revision needs a dependency change.

## Validation without Kubernetes deployment

Offline/fake-API checks:

```bash
python3 scripts/check-k8s-bootstrap.py
python3 scripts/check-k8s-all.py
kubectl kustomize deploy/overlays/flux >/dev/null
```

The bootstrap tests use synthetic fixtures/fake kubectl, check confidentiality,
abort paths and component ordering. They do not install a real stack. Real
`k8s-all.sh --check` contacts the selected cluster read-only and expects paused
Flux; it is unsuitable as an active-cluster CI/operations command.

After building the local images, the Docker checks start/remove their own test
containers/networks. Do not confuse them with cluster acceptance:

```bash
bash scripts/check-roenglish.sh remote:ci
bash scripts/check-image-boundaries.sh remote:ci robrowser:ci
python3 scripts/check-image-overrides.py
python3 scripts/check-api-module.py robrowser:ci
python3 scripts/check-compose.py remote:ci robrowser:ci
```

check-compose.py reads this checkout's `.env` and actual Compose configuration,
then isolates the web services on temporary networks and loopback ephemeral ports.
CLIENT_TEST_ROOT optionally points to readonly client fixtures. check-roenglish.sh
builds/tests the additional Pre-Renewal variant. The upstream-layout check clones
pinned sources temporarily; it does not modify their original repositories.

The [API iframe override](frontend-api-module.md) is bound to the pinned upstream
HTML. The layout gate detects changes needing a rebase. Other local override
payloads stay ignored and are not supplied to clean GitHub Actions builds.

## Documentation checks

The existing documentation workflow installs mkdocs-material and publishes the
site on main changes to docs or mkdocs.yml. A local strict build is the relevant
pre-PR check:

```bash
python3 -m venv /tmp/robrowser-docs-tools
/tmp/robrowser-docs-tools/bin/pip install mkdocs-material
/tmp/robrowser-docs-tools/bin/mkdocs build --strict --site-dir /tmp/robrowser-docs-site
```

Use a fresh temporary directory if those paths already contain someone else's
work. Do not commit generated site files, test output, reports or private bootstrap
artifacts. PR CI's required validate check is scope-sensitive: documentation-only
changes do not exercise image builds. Record the actual local/CI checks in the PR.

## Contribution scope

Keep changes small, describe behavior and validation, and obtain the appropriate
merge/deployment approvals. Current application fixes use their own reviewed PRs;
remaining graphics/Lua/GRF-content/gameplay issues are outside documentation
cleanup. See [validation boundaries](validation.md) and [security](security.md).
