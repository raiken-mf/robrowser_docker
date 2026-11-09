# Upstream source updates and release automation

[build/dependencies.env](https://github.com/raiken-mf/robrowser_docker/blob/main/build/dependencies.env)
pins the roBrowserLegacy, RemoteClient-PHP, rAthena and ROEnglishRE forks. A fork
sync does not itself change a deployed image. Check Fork Updates runs daily and
supports manual dispatch. It compares the configured repository HEADs, updates
changed pins together and validates the candidate source layouts.

## Dependency update cycle

Dependabot checks npm overlays, Dockerfiles and GitHub Actions in one
multi-ecosystem version-update group on Mondays at 12:00 Europe/Berlin.
GitHub may omit incompatible updates or create additional PRs when grouping is
not possible; inspect the Dependabot logs and review the complete diff. Security
updates are separate from version updates and are not held for this schedule.
GitHub groups security updates only within an ecosystem; review and merge urgent
security PRs promptly, independently of the regular cycle. npm and GitHub Actions
have explicit security groups; grouping across npm directories additionally
depends on the repository or organization setting. Dependabot security updates
were enabled at the 2026-11-09 review; verify that grouping setting separately.
Docker does not support
Dependabot security updates, so retain the existing image security scans.

The updater waits at least 24 hours after Monday 12:00 Europe/Berlin and checks
all open Dependabot PRs targeting main before proposing pins. Open version PRs
block the update; PRs explicitly labeled `security` do not. An unlabeled
security PR is conservatively treated as a version PR and can delay the pin PR.
The daily retry also handles weeks with no version PR and cycles that take longer
to review. The updater checks again after layout validation and skips if main
changed. It creates at most one pin PR per weekly cycle, or updates an existing
pin PR once per cycle. A cycle marker in the PR body prevents another update or
PR in the same cycle; do not remove it. Later fork changes wait for the next
cycle. Fork synchronization remains independent and is not performed by this
workflow. An operator can also dispatch the same guarded check on `main`:

```bash
gh workflow run dependency-update.yml --repo raiken-mf/robrowser_docker --ref main
```

It creates or updates one PR containing all changed fork HEAD pins, not one PR
per dependency. Review the exact commits, upstream compatibility and required
`validate` check before merging. The updater does not sync forks itself and does
not update the Hercules pin; handle Hercules separately when explicitly needed.
GitHub does not expose a reliable completion event for the scheduled Dependabot
run: the 24-hour window is a heuristic, not proof that a delayed or failed run
finished. A PR opened after the final check can still race with pin creation.
Review Dependabot logs and the pin PR before merging; security updates remain
independent and should be reviewed promptly.

At the time of the 2026-11-09 review there were no open PRs. After enabling the
group, inspect open Dependabot PRs and alerts again: merge urgent security fixes
independently, and review or close superseded regular PRs only after confirming
their updates are included in the new group. Do not close unresolved security PRs
merely to reduce PR count. Verify the group in Insights > Dependency graph >
Dependabot after the configuration reaches the default branch and inspect the
first scheduled run. See GitHub's [multi-ecosystem configuration](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configuring-multi-ecosystem-updates)
and [security update documentation](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-security-updates).

## Distinct approval boundaries

- The source updater uses UPSTREAM_PR_TOKEN to create/update
  automation/upstream-dependency-update. It force-pushes that dedicated branch
  only with a lease against the observed remote revision.
- Dependabot checks actions, image bases and the project npm overlays. Neither
  workflow requests auto-merge; human review and branch protection remain required.
- Dependabot PRs must receive the required `validate` check. If GitHub requires
  approval for a workflow run, an authorized maintainer must approve it; do not
  bypass the check or execute untrusted PR code with elevated permissions.
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
