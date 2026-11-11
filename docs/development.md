# Development and repository layout

## Ownership

- images/robrowser: Node.js/Vite frontend, package/lockfile overlay and client template.
- images/remote: Apache/PHP, RemoteClient, translations and client-file configuration.
- images/rathena and images/hercules: game-server images; images/wsproxy: proxy.
- build/dependencies.env: exact upstream Git revision pins.
- deploy/compose: local runtime; deploy/k8s/base: concrete GitOps base;
  deploy/k8s/templates: bootstrap templates; deploy/k8s/overlays: release selection.
  The base is authoritative for shared resource definitions; CI compares each
  parameterized bootstrap template with its base using standard values.
- deploy/clusters/default: Flux parent/source and installation-specific child.
- scripts/sh, scripts/py and scripts/js: project-wide administration and checks;
  image-specific tests and helpers, including the wsproxy stdin test, live with
  their image. The root `start.sh` remains the Compose entrypoint.
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

The remote container selects its translation layer at startup with SET_PRERENEWAL;
the rAthena build uses the same setting to select its compiled ruleset.
The frontend alone fetches roBrowserLegacy; do not add that source tree to remote.
Both web images fetch their pinned sources in separate build stages; Git is not
installed in their runtime images. Remote retains the complete ROEnglishRE tree
for runtime generation. The frontend retains its full locked npm dependencies
because CI runs its tests in the same image.
Project-owned npm manifest/lockfile are installed with npm ci. Update the lockfile
and source pin together when the new upstream revision needs a dependency change.
The locked jsdom 31 test dependency requires Node.js ^22.22.2, ^24.15.0 or >=26.
The cursor test normalizes its expected zero translation through the DOM CSS
serializer; its position and scene-loop assertions remain unchanged.
The rAthena build preserves the upstream or override custom header and applies
validated packet-key build arguments after it. The Compose initializer runs the
image entrypoint with database initialization enabled before starting the servers.

## Validation without Kubernetes deployment

Offline/fake-API checks:

```bash
python3 scripts/py/check-k8s-bootstrap.py
python3 scripts/py/check-k8s-all.py
bash scripts/sh/ci/check-platform-config.sh
kubectl kustomize deploy/k8s/overlays/flux >/dev/null
```

The bootstrap tests use synthetic fixtures/fake kubectl, check confidentiality,
abort paths and component ordering. They do not install a real stack. Real
`k8s-all.sh --check` contacts the selected cluster read-only and expects paused
Flux; it is unsuitable as an active-cluster CI/operations command.

After building the local images, the Docker checks start/remove their own test
containers/networks. Do not confuse them with cluster acceptance:

```bash
bash images/remote/tests/check-roenglish.sh remote:ci
bash scripts/sh/ci/check-image-boundaries.sh remote:ci robrowser:ci
python3 scripts/py/check-image-overrides.py
python3 images/robrowser/tests/check-api-module.py robrowser:ci
python3 scripts/py/check-compose.py remote:ci robrowser:ci
python3 scripts/py/check-dockerfile-configs.py
bash images/rathena/tests/check-entrypoint.sh
```

The Dockerfile configuration check requires PyYAML, `envsubst` and a C compiler.
check-compose.py reads this checkout's `.env-tmpl` by default; `COMPOSE_TEST_ENV_FILE`
selects an explicit alternative. It isolates the web services on temporary networks
and loopback ephemeral ports. `CLIENT_TEST_ROOT` optionally points to readonly client
fixtures. On case-insensitive filesystems, the two case-conflict fixtures are skipped;
run them on a case-sensitive filesystem for full coverage. check-roenglish.sh
builds/tests the additional Pre-Renewal variant. The upstream-layout check clones
pinned sources temporarily; it does not modify their original repositories.

The [API iframe override](frontend-api-module.md) is bound to the pinned upstream
HTML. The layout gate detects changes needing a rebase. Other local override
payloads stay ignored and are not supplied to clean GitHub Actions builds.

## CI build caches and release boundaries

The required `validate` job runs on every pull request, including documentation
changes; documentation-only PRs skip Docker builds. Image, workflow, deployment
and selected integration-helper changes exercise web and proxy smoke tests.
Isolated monitor and bootstrap script changes retain configuration checks but
skip those smoke builds. See the [CI/CD audit](ci-audit.md) for the full inventory.
rAthena validation builds only when its inputs or dependency pins change.
Hercules is Compose-config validated and included in the AMD64/ARM64 PR image
security scan matrix; it is not published by the release workflow.
Hercules builds in a separate stage and retains its complete built server tree
in the runtime image without the compiler or Git. wsProxy installs its locked
dependencies in a build stage; its runtime image contains Node.js but not npm.
After building both images, run `bash scripts/sh/ci/check-runtime-images.sh
hercules:ci wsproxy:ci` to check runtime dependencies, permissions and the proxy
handshake without a database or external network.
The root `.dockerignore` affects the root-context web images, not wsProxy, whose
build context is `images/wsproxy`; changing it alone does not rebuild wsProxy.

Buildx stores AMD64 test layers in separate GitHub Actions scopes
`ci-remote-amd64`, `ci-robrowser-amd64`, `ci-wsproxy-amd64` and
`ci-rathena-amd64`. Renewal and Pre-Renewal remote builds share the same local
Buildx builder in the validation job, as do the isolated override fixtures. GitHub isolates PR caches from main;
never store credentials in layers or cache. BuildKit matches Dockerfile commands,
base images, build arguments and copied inputs, so affected layers and subsequent
layers rebuild when their inputs change. External package repositories are not
cache keys: cached test images are not proof that the latest patches were fetched.

Release candidates are built separately on main and scanned on **both** AMD64 and
ARM64. The remote and robrowser release builds deliberately use `no-cache` to
refresh mutable OS packages. wsproxy retains its uncached release build. rAthena
imports the AMD64 CI scope and its multi-platform GHCR `buildcache` and exports
only the latter; BuildKit matches platform-specific layers. The scoped CI cache
has one writer per workflow/ref, while the release cache has one writer per image
and main CI runs are serialized. Publish promotes the exact security-approved
candidate digests; it never rebuilds from these caches. The scans, SBOMs, release
tags and draft image-pin PR remain mandatory. If stable's source revision differs
from the reviewed Flux pin, release recovery rebuilds and rescans the image.
This can repeat expensive work while a GitOps PR awaits review. Publishing now
reconciles a durable approval journal into one PR with immutable source tags;
see [publishing protocol](image-revisions.md#publishing-protocol). The rebuild
cost remains separate from publishing idempotency.

On a cold or evicted cache, BuildKit rebuilds normally; exports use
`ignore-error=true` so an unavailable cache does not skip a test. Inspect the
build action's import/export messages and `CACHED` lines, image scope, branch,
platform and changed build arguments when diagnosing misses. GitHub cache eviction,
limits and first-run warmup affect hit rates. To diagnose stale cache, compare a
fresh no-cache test build and inspect its inputs; do not bypass release scans.
BuildKit cache mounts are not exported by the GHA backend by default, so no
cross-run npm cache-mount persistence is assumed.

## Documentation checks

The documentation workflow runs a strict build on relevant pull requests and
publishes the site on main changes to docs or mkdocs.yml. A local strict build is
the relevant pre-PR check:

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
