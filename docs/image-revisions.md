# Image references and provenance

The authoritative desired selection is
[deploy/k8s/overlays/flux/kustomization.yaml](https://github.com/raiken-mf/robrowser_docker/blob/main/deploy/k8s/overlays/flux/kustomization.yaml),
not whichever local test image or stable tag happens to exist.

## Verified installation selection

The following source tags were selected at the confirmed `109430d1` operating
baseline (2026-11-02). This table is a dated reference; future approved image PRs
can update the overlay independently per component.

| Image | Role | Selected source tag |
| --- | --- | --- |
| robrowser | Node.js/Vite frontend, including the iframe module fix | sha-d32fa0e2a793eac80274fcc8d1206a871f4a1376 |
| remote | Apache/PHP/RemoteClient/ROEnglishRE | sha-6c00eb847d9f65c9b0f4c941140b790177c37470 |
| rathena | Login/char/map servers | sha-a9c11e46784f25a75cd85cb91cc7fe97e41533f9 |
| wsproxy | Game WebSocket proxy | sha-ddc424509d376dc1e77f4b6925f3df37fc4caf27 |

The final-name releases support AMD64 and ARM64. The frontend d32fa0e release
passed main CI/security/SBOM/promotion in
[run 41448256973](https://github.com/raiken-mf/robrowser_docker/actions/runs/41448256973).
The initial final-name web release passed
[run 41435931124](https://github.com/raiken-mf/robrowser_docker/actions/runs/41435931124).
Those are evidence for those releases, not a claim that later unchanged images
were rescanned on every documentation/image-pin commit.

## Source SHA versus registry digest

- build/dependencies.env pins **upstream** source repositories. Their commit
  hashes are not infrastructure release tags.
- sha-infrastructure-commit tags identify the source build revision for each
  released image. Components can legitimately have different tags when their
  build inputs did not change.
- The OCI org.opencontainers.image.revision annotation records the build source.
- sha256:… is the exact registry manifest/index digest. A SHA-named tag is still
  a tag; verify its digest/platform/provenance rather than treating its spelling
  as cryptographic immutability. stable is explicitly mutable.
- Newest main can be a documentation/manifest-only commit with no image release.
  Do not substitute main HEAD into all tags or compare SHA strings alphabetically.

With Docker/buildx available, inspect the actual selected registry reference;
this does not deploy it:

```bash
docker buildx imagetools inspect ghcr.io/raiken-mf/robrowser:sha-d32fa0e2a793eac80274fcc8d1206a871f4a1376
```

Check the exact digest, source annotation, both architectures and corresponding
successful security/promotion artifacts. Runtime inspection should match the
intended role: frontend has Node/Vite, remote has Apache/PHP and client files.

## Publishing protocol

Main validation and all four release-security jobs must succeed before the reusable
publisher runs. `promote-main` permits one registry writer; CI and publishing use
GitHub's `queue: max` (at most 100 pending runs). Queue admission and runner start
order are not release chronology: component source commits are ordered by Git
ancestry, never by SHA spelling or run number. Overflowed/canceled runs require
a rerun; no guarantee extends to unjournaled work that never reached publishing.
Executable publisher code is checked out at the validated initiating `github.sha`,
not moving main. Current main pins are read only as reconciliation data.
An unadopted release alone no longer forces a rebuild: unchanged components use
the verified journal/proof recovery path. Invalid/missing prior revisions and
actual component changes still require builds and existing security gates.

The publisher verifies each three-line ready record against this run's candidate
digest and OCI source annotation. Before any registry write it records approvals
on `automation/image-release-state`, in `image-releases.json`. This state branch
is not a deployment branch and must never be merged into main or tracked by Flux.
The journal retains source, digest, run and attempt for each image/source pair.
Restrict its writers to the trusted publishing identity and repository maintainers;
it is a security boundary, not an input for arbitrary contributors. Existing
Contents/Pull requests/Packages write and Actions read permissions are unchanged.

Publication promotes exact approved digests without rebuilding. Existing `sha-*`
tags are verified, never overwritten; the first journaled digest for a given
image/source remains authoritative even if a rerun builds a different digest.
`stable` advances only along main ancestry and never backwards. Source histories
that diverge or registry tags that disagree with the journal fail closed.

One `gitops/image-bump` draft accumulates independent component releases. An
existing single bot-owned legacy image-bump PR is reused instead. The Contents
API updates only the Flux overlay using its blob SHA; conflicts trigger bounded
re-read/reconciliation, preserving other PR files and newer pins. Main pins that
advanced while a PR was pending are carried forward, not reverted. No force push,
automatic merge, branch-protection change or alternate token is used. Multiple
already-open legacy PRs require a one-time human consolidation before rollout;
the publisher refuses to choose or close them automatically.

Interrupted registry or PR updates are recovered from the journal on a subsequent
successful invocation, including one with no new ready records. Published legacy
`stable`/open-PR tags absent from the journal require a retained ready artifact
from a main CI run whose four security jobs succeeded, plus matching registry
digest/source. Missing/expired proof requires human investigation or a fresh gated
release, not a bypass. Journal updates must succeed before new publication.
There is no background retry daemon; rerun the failed CI publishing job or allow
the next successful main release. Preserve the state branch and approved digests.

### GitHub prerequisites and limitations

- Repository settings must permit `GITHUB_TOKEN` to create/update PRs and write
  the two automation branches; rulesets restricting these writes can fail closed.
- GitHub currently puts `GITHUB_TOKEN`-created/updated PR workflows in an
  approval-required state. A user with write access selects **Approve workflows
  to run** for the current head. Required checks and human approval still gate
  merge; approve again after later updates where required. No additional secret
  or automated approval bypass is configured.
- Configure branch protection to require checks on the current head/up-to-date
  base and dismiss stale approvals as appropriate. These external settings have
  not been inspected or modified. Do not merge using an earlier head's checks.
- All automated registry writers must share `promote-main`. External writers,
  deletion of protected journal/tag state, manual force-pushes or main-history
  rewrites are outside the lock guarantee and require operator reconciliation.
- A PR can merge while publishing runs; main is reread before pin updates, but
  GitHub merge checks remain the final concurrency boundary. The API/registry
  protocol, permissions, queue syntax, approval banners, artifact retention and
  exact digest preservation require real Actions acceptance testing.
- Old automation branches may retain outdated non-image content or need a base
  update. The publisher intentionally does not reset/rebase human PR work;
  resolve merge conflicts through normal review before merging.

Local regressions exercise the current Python publisher only; the retired shell
workflow emulator is no longer maintained. Missing publisher code fails the check.
Local regression command: `python3 scripts/py/check-publishing.py`; it is also
called by the existing CI/Dockerfile contract checker. Twenty isolated cases
cover the six requested scenarios plus CAS, legacy proof, digest mismatch,
same-source rebuilds, new main pins and permission failures. Scheduling is modeled
under the declared single-writer lock; this is not a live concurrency certification.

References: [GitHub concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
and [token-triggered workflows](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

## Adoption and rollback

The generated draft GitOps PR accumulates security-approved pending component tags.
With active Flux, **merging the approved pin change** deploys it automatically;
publishing a registry tag does not update an already SHA-pinned Deployment.
Do not infer automatic merge approval from installed Flux image controllers.

Record the prior component reference before a rollout. Roll back to its verified
tag/digest through a narrow Git change, retaining the other image pins. Follow
[operations](operations.md#rollback-and-failure-handling) for explicitly approved
emergency imperative changes. No old pre-rename Apache image should be mistaken
for today's frontend robrowser image.
