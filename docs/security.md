# Security and private configuration

The fork pin updater runs only from the default branch, checks pull requests
through the GitHub API before and after candidate validation, and fails closed
on API errors. Its 24-hour Dependabot window is a heuristic, not proof of a
completed update run; see [upstream updates](upstream-updates.md).

## Image release controls

Main CI gates the existing Container Security workflow. It builds changed
remote, robrowser, rAthena and wsProxy candidates for AMD64/ARM64, scans each
platform and generates SPDX SBOMs. Publication does **not** rebuild them: it
promotes the exact approved digest, verifies its source SHA/candidate digest and
refuses a stale release when main moved during the scan.

The configured Trivy threshold is HIGH/CRITICAL, ignore-unfixed=true, exit-code=1.
Fixable findings at that threshold block publishing; lower severities and
unfixed findings are not equivalent blocking guarantees. A green result is not
proof that every vulnerability is absent. Unchanged images are not rebuilt or
rescanned just because a documentation/manifest commit reached main.

Rebuilt components provide sbom-remote, sbom-robrowser, sbom-rathena or
sbom-wsproxy artifacts, each containing platform inventories. The ready-component
record ties source and digest to promotion. Review the run/artifacts and registry
metadata, not just stable. See [image provenance](image-revisions.md).

## Runtime controls

The project application Deployments retain non-root UID/GID 1000, dropped Linux
capabilities, no privilege escalation, runtime-default seccomp and configured
probes/resources. MariaDB and infrastructure operators use their own charts/images;
do not claim every cluster container uses the application UID. wsProxy also has
a readonly root filesystem; frontend/PHP use separate writable runtime paths.

The namespace labels enforce Pod Security baseline and audit/warn restricted.
The DB NetworkPolicy allows only the selected game/loader peers and the labeled
MariaDB controller in its own namespace on TCP3306. The operator needs SQL access
to reconcile Database/User/Grant; do not remove the policy or broadly open ingress
as a bootstrap workaround. Client mounts remain readonly to remote.

Vite restricts DNS hostnames to the configured `HOST` and disables CORS; this
does not replace network isolation or authentication. Several workloads still
need writable root filesystems. Harden them only after identifying and testing
every required writable path. The rAthena entrypoint retains compatibility
defaults for credentials; supply unique credentials. The MariaDB client receives
its password through `MYSQL_PWD`, which may be visible to processes with access
to its environment; restrict process access.

Both Compose game stacks pass explicitly selected environment variables to each
service. Their entrypoints reject empty database or interserver passwords; MariaDB
rejects initialization without a root password. Hercules uses `MYSQL_PWD` for
database initialization and removes it before starting the server. Its login
server suppresses Info and Notice messages because upstream logs passwords in
those categories; this also reduces operational visibility. Restrict access to
container environments, generated configuration and the game network. Hercules
is scanned in the PR image-security matrix but is not published by the release
workflow. A scan and isolated integration test do not establish production safety.
The starter's lifecycle commands can render without credentials.
The standalone MariaDB installer renders private Secret files
and includes interserver credentials; it still changes cluster resources and must
only be run with explicit approval. The shared Flux base retains the historical
host until the separately reviewed second migration stage. Runtime integration
and release security scans remain required before deployment.

## PHP branch and request-time hardening

images/remote/Dockerfile requires php84 >=8.4.27 and a build-time/runtime guard
rejects PHP >=8.5 or older 8.4 packages. On Alpine 3.24 the generic CLI explicitly
links to php84; Apache uses its PHP8.4 module. security.ini disables session upload
progress before request parsing. TRACE/Git-path blocking and the pinned
RemoteClient .htaccess remain tested. The frontend image has no Apache/PHP, and
remote does not fetch the frontend tree or Node/npm.

The no-cache remote candidate build reruns Alpine package installation; apk's
--no-cache alone is not Docker layer-cache invalidation. There is no scheduled
PHP-package rebuild or general CI workflow_dispatch release path. New packages
do not update an existing container automatically; an approved source/build
change must pass the normal release/image-pin chain.

A scoped read-only diagnostic after an approved rollout can check:

```bash
kubectl -n ragnarok exec deployment/remote -- php -v
kubectl -n ragnarok exec deployment/remote -- php -r 'echo get_cfg_var("session.upload_progress.enabled"), PHP_EOL;'
```

Expect PHP in the permitted 8.4 branch and upload progress 0. Do not weaken checks
or restart an old image and call it a security update.

## Secrets and local files

`.env`, client files and unversioned overrides are local configuration, not CI
inputs automatically copied to GHCR. Keep actual credentials outside Git. The
bootstrap uses the supplied `.env` values exactly; it does not silently generate
or rotate passwords. Review template defaults before production use.

The private offline bootstrap renderer requires the operator-owned configuration,
writes owner-only output and refuses overwrites. Database and interserver
credentials are Secret fields; ConfigMaps contain non-secret settings only.
Default --check and fake-API tests perform no installation. --apply is a separately
approved cluster-changing operation and never deletes namespaces/resumes Flux.
The legacy standalone rAthena installer is disabled; it previously exposed
interserver credentials in a ConfigMap and interpolated them into SQL.

Use SSH/credential helpers for Git authentication rather than embedding tokens
in remote URLs. Do not print .git/config, `git remote -v`, kubeconfigs, Secret
values, full environments or private bootstrap JSON in public logs. Even a URL
inspection can expose a token. Redact browser/HMR token queries from diagnostics.
If a credential appears in output, revoke/replace it; deleting a local log does
not revoke it or remove every copy.

The upstream updater's UPSTREAM_PR_TOKEN belongs in Actions Secrets, with the
minimum repository-scoped Contents/Pull requests permissions required. GitHub
secret scanning, push protection and branch rules are external repository
settings; verify them separately rather than assuming this Markdown enforces
them. Their presence does not make leaked credentials safe or rotate them.

## Updates and recovery

Dependencies/base images/actions are pinned as described in
[upstream updates](upstream-updates.md). Source/dependency PRs require human
review, separately from draft GitOps image release approval. Active Flux adopts merged
manifests automatically; it must be coordinated during emergency imperative work.
Dependabot security updates are independent of the scheduled version-update group;
review them promptly. Configured security groups are limited to one ecosystem;
grouping across directories also depends on repository or organization settings.
Docker image vulnerabilities still
require the existing image scans; Dependabot does not provide Docker security PRs.

Do not use setup scripts, namespace resets, blanket image/containerd pruning or
PVC/Longhorn deletion to fix an application incident. Keep private rollback and
backup material, but never commit it. Follow [operations](operations.md) and
separately reviewed DB/storage recovery procedures.
