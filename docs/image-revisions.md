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

## Adoption and rollback

The generated draft GitOps PR supplies reviewed tags only for changed images.
With active Flux, **merging the approved pin change** deploys it automatically;
publishing a registry tag does not update an already SHA-pinned Deployment.
Do not infer automatic merge approval from installed Flux image controllers.

Record the prior component reference before a rollout. Roll back to its verified
tag/digest through a narrow Git change, retaining the other image pins. Follow
[operations](operations.md#rollback-and-failure-handling) for explicitly approved
emergency imperative changes. No old pre-rename Apache image should be mistaken
for today's frontend robrowser image.
