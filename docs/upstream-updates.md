# Upstream source updates and release automation

[build/dependencies.env](https://github.com/raiken-mf/robrowser_docker/blob/main/build/dependencies.env)
pins the roBrowserLegacy, RemoteClient-PHP, rAthena and ROEnglishRE forks. A fork
sync does not itself change a deployed image. Check Fork Updates runs every six
hours (and supports workflow_dispatch), compares the configured repository HEADs,
updates changed pins and validates the candidate source layouts.

## Distinct approval boundaries

- The source updater uses UPSTREAM_PR_TOKEN to create/update
  automation/upstream-dependency-update. Its branch-update implementation
  force-pushes that dedicated automation branch; review that policy separately.
- Dependabot checks actions, image bases and the project npm overlays. Neither
  workflow requests auto-merge; human review and branch protection remain required.
- These are **source/dependency PR** behaviors. Publish opens a separate **draft
  GitOps image-pin PR**, and does not request its auto-merge. It requires release
  approval before an active Flux reconciler adopts it.

Repository rules and externally configured automation must also be checked for
unintended bypasses; these workflows cannot enforce repository settings.

The updater requires a repository-scoped UPSTREAM_PR_TOKEN with Contents and Pull
requests write access. Keep it in Actions Secrets, never Git or chat. A workflow
rerun retains its original source SHA; do not replay an old publishing run to
release newer main or bypass the publication freshness/security gates.

## Validation and publication

CI validates the pinned Dockerfile-required source layout, API override parity,
Compose/templates, translations, runtime isolation and frontend modules. Changed
main candidates pass both platform scans and SBOM generation before exact-digest
promotion. The workflow refuses a stale publication when main moved during scans.
Unchanged image components retain their existing release tags.

roBrowserLegacy changes affect the frontend robrowser image. RemoteClient and
ROEnglishRE changes affect remote. rAthena and wsProxy are separate images.
The project-owned frontend package/lockfile supplies dependencies required by the
pinned source, including granny-ro-js; update it deliberately when necessary.
The API HTML/module override must be reviewed if upstream initialization changes.

Only after approving/merging the generated image-pin PR does active Flux adopt
the changed release. See [GitOps lifecycle](gitops.md) and [image provenance](image-revisions.md).
Layout/module/CI checks do not prove all gameplay/content compatibility. The
completed installation's successful login does not close unrelated graphics,
Lua or GRF-content issues.
