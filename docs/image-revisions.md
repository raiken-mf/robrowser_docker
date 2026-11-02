# Which image revision is current?

The authoritative desired image selection is
`deploy/overlays/flux/kustomization.yaml`, not the newest Git commit and not a
pending image-bump PR. This snapshot was checked against main commit
`35adbdc1cda0a2b80e7eee0e741cd6ba2dc9a81a`, the registry manifest annotations,
SHA tags, stable digests, AMD64/ARM64 manifests and successful promotion logs.

| Image | Selected tag | Verified manifest digest |
| --- | --- | --- |
| rathena | `sha-a9c11e46784f25a75cd85cb91cc7fe97e41533f9` | `sha256:5c9b92fa605fb913fb69912d59eed60bb399e9fff1f5407eeea4f4db3b51d751` |
| robrowser | `sha-ddc424509d376dc1e77f4b6925f3df37fc4caf27` | `sha256:0c233128e6e666d3ee6744059153ed59c72740c4414ccfeb32ef831cf5c4eab4` |
| vite | `sha-a9c11e46784f25a75cd85cb91cc7fe97e41533f9` | `sha256:8cd41ea55b546e9301d3b80084297f718d1468934804bd0a0d3efeb07401e40d` |
| wsproxy | `sha-ddc424509d376dc1e77f4b6925f3df37fc4caf27` | `sha256:d08424c38b0690d047082f7ecec230ee3f6054e39a4429f1bd67e42c1741d7d0` |

At verification, each selected tag and stable pointed to the same digest.
This is a time-specific audit; stable is mutable. Do not select releases by
alphabetically comparing SHA strings or by copying main HEAD into every tag.

## Why the tags differ

- `sha-ddc4245...` identifies the infrastructure-repository commit that built and
  released the current Apache/RemoteClient and wsProxy images.
- `sha-a9c11e4...` identifies the later build/release of Vite and rAthena, including
  the dependency changes from #82. The other two image inputs had not changed.
- Main commit `35adbdc...` updates desired image references only. It is not a new
  build of every image. Unchanged images correctly retain their previous tags.
- Upstream pins in `build/dependencies.env` (roBrowserLegacy, RemoteClient,
  ROEnglishRE, rAthena) are source-repository revisions, not deployment image tags.
- The registry `sha256:` digest identifies the exact image manifest. Its
  `org.opencontainers.image.revision` annotation records the source build commit.

Successful release evidence:
[ddc4245 release](https://github.com/raiken-mf/robrowser_docker/actions/runs/41372141533),
[a9c11e4 release](https://github.com/raiken-mf/robrowser_docker/actions/runs/41375144869).
Their logged promoted digests match the table. These release workflows keep the
multiarch security and exact-digest promotion gates; this audit does not rerun or
promote any images.

## Resolving the outstanding PRs

- #71 targets obsolete `sha-6899978...` releases and is superseded by #83/#84.
  Closing it avoids rolling current references back to an older generation.
- #83 has already merged; #84 then updated Vite/rAthena. There is no remaining
  conflict to repair in the closed #83 PR.
- #73 retains the current four image pins from main. Its duplicate Vite stable
  entry and older wsProxy pin are removed by the conflict resolution. It remains
  draft, without auto-merge, until the deployment stages and real ConfigMap are
  reviewed. Conflict-free YAML is not approval for a rollout.
- #75 keeps the Apache base-image/PHP CLI correction in its own PR. It does not
  change the deployment image pins selected here.

Main currently selects the split Apache image but still lacks the separate Vite
Deployment. If Flux is active, that desired combination can leave the old frontend
Service targeting an unserved port. A read-only cluster check confirmed that Vite
has no Deployment/Service yet and the old Apache Service still owns NodePort
30000. No live resources were changed. The prepared ConfigMap now uses the
operator-rendered HOST=pi and reviewed ports. The fix still requires the controlled
migration in `flux-split-migration.md`, rather than merging an older image-bump PR
or applying all migration resources together.
