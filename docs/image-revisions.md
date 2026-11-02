# Historical pre-rename image verification

Before the final naming change, PR #73 used the following published releases. Registry SHA tags, stable tags,
OCI source annotations and both linux/amd64 and linux/arm64 manifests were
verified after the successful main release of
`4e94f3a373936e95d17322970c26be09af1c7c7c`. Each selected digest matched stable
at verification. Stable remains mutable; this table records the verified snapshot.

| Image | Source tag | Verified multiarch digest |
| --- | --- | --- |
| rathena | `sha-a9c11e46784f25a75cd85cb91cc7fe97e41533f9` | `sha256:5c9b92fa605fb913fb69912d59eed60bb399e9fff1f5407eeea4f4db3b51d751` |
| robrowser | `sha-4e94f3a373936e95d17322970c26be09af1c7c7c` | `sha256:594dbf03bb6ec3cd660e7c919edac80103aabf77fa63d35de73af76d05a9712a` |
| vite | `sha-a9c11e46784f25a75cd85cb91cc7fe97e41533f9` | `sha256:8cd41ea55b546e9301d3b80084297f718d1468934804bd0a0d3efeb07401e40d` |
| wsproxy | `sha-ddc424509d376dc1e77f4b6925f3df37fc4caf27` | `sha256:d08424c38b0690d047082f7ecec230ee3f6054e39a4429f1bd67e42c1741d7d0` |

## Validation and provenance

- Apache: [main validation/security/publication](https://github.com/raiken-mf/robrowser_docker/actions/runs/41430841225)
  passed for the exact source above. Both architectures passed the unchanged
  HIGH/CRITICAL scan gate; the workflow retained its existing ignore-unfixed policy.
  The published digest equals the security-approved promoted digest. Artifacts
  include `sbom-robrowser` and `ready-robrowser`.
- Vite/rAthena retain the already released a9c11e4 images; wsProxy retains ddc4245.
  Their build inputs have not changed. Main security jobs correctly skip rebuilds
  for unchanged images; this is not a claim of fresh scans on this main run.
- Earlier successful release evidence:
  [ddc4245](https://github.com/raiken-mf/robrowser_docker/actions/runs/41372141533),
  [a9c11e4](https://github.com/raiken-mf/robrowser_docker/actions/runs/41375144869).
- Image source SHA tags refer to this infrastructure repository. Upstream pins
  in `build/dependencies.env` identify different source repositories. Only Vite
  fetches the pinned roBrowserLegacy frontend; Apache does not clone it.
- Never compare SHA strings alphabetically or assign main HEAD to unchanged
  images. A candidate tag is not a released image.

## Final naming cutover and installation hold

The final source trees, services, workflow matrices and registry targets now use
`remote` for Apache/PHP and `robrowser` for the Node.js/Vite frontend. The table
above is HISTORICAL pre-rename evidence, not an installation selection for the
new names. In particular its robrowser digest contains Apache, not the frontend.

PR #85 is closed without merging. The namespace has been removed by the operator;
both Flux Kustomizations are suspended and must stay paused until separate
installation approval. No two-stage port handover remains necessary.

The reviewed final-name source must pass CI and then the security-gated main
release. Only its actually promoted registry digests may supply final web image
pins. The publication workflow produces a draft GitOps PR with those source
SHA tags. Verify that remote contains PHP/Apache and robrowser contains Node/Vite
before closing the repository release work. Neither code/image-pin merges nor
registry publication authorize Flux resume or installation.

See [Fresh namespace installation](flux-split-migration.md). Existing ConfigMap
values, source pins, port variables and security restrictions are retained.
