# Loose client resources

The proposed image keeps ROEnglishRE's `SystemEN` tree at its original path;
no translation tree is copied to `System` or to the client-data PVC. For a
request under `System`, the resolver checks the external PVC `System` first,
then the image's `System`, followed by an exact `System` GRF entry. Only after
those miss does `SYSTEM_ALIAS_SYSTEMEN=true` try external and baked `SystemEN`. An explicit `SystemEN` request checks its own
external directory and then the baked translation directory. Thus a real System
file always wins a conflict. `data`, `AI`, and `BGM` likewise prefer their own
external directory over the image; no directories are merged on disk. After
loose files, GRFs retain their normal order. An `AI/...` GRF miss also tries
`data/AI/...`, the layout used by the inspected client GRF.

The existing PVC is mounted read-only at `/opt/client_files`; the installer
also accepts an optional source `client/SystemEN` and copies it once to the
corresponding PVC path. It does not synthesize or rename client files. Compose
mounts the client directory read-only at the same path. `DATA.INI` and GRF
locations remain under `resources`. Root environment overrides are
`DATA_OVERRIDE_PATH`, `SYSTEM_PATH`, `SYSTEMEN_PATH`, `AI_PATH` and `BGM_PATH`.
The image enables `SYSTEM_ALIAS_SYSTEMEN`; other PHP installations default it
to false. The server rejects traversal before Apache URL normalization; PHP
validates path segments and canonical containment, including symlink targets.

## Observed baseline (2026-11-02)

The Pi's local and PVC `System`, `data` and `AI` contained only their respective
placeholder files; `SystemEN` was absent. The old image put ROEnglishRE under
`System` only. `System/itemInfo.lua` returned 200, while the referenced
`SystemEN/LuaFiles514/itemInfo_f.lua` returned 404. The three GRF indices
contained no entries rooted at `System`, `SystemEN`, or `AI`; `data.grf`
contains `data/ai/util.lua` and `data/LuaFiles514/Lua Files/datainfo/itemInfo.lub`.
Both corresponding `data/` HTTP requests returned 200. The old `AI/Util.lua`
request returned 404 because it did not search `data/ai`.

The names `OngoingQuestInfoList.lub`, `PetEvolutionCln.lub`, and `SCDream4.otf`
were not found in any of the three GRF indices or the loose directories and
returned 404 on their requested `System/` URLs. The proposed resolver cannot
supply files that do not exist. This is a dated inspection, not a claim about
other client archives or Lua contents.

The image is not yet released or deployed by this documentation. Image pins
must go through the existing scan, SBOM, draft GitOps PR and explicit review.
