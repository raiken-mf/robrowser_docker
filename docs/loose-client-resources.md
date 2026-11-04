# Client resources with the unmodified PHP RemoteClient

The RemoteClient is pinned to the PHP fork's revert merge; its source tree is
identical to the pre-custom-resolver revision. `CLIENT_RESPATH` and
`CLIENT_DATAINI` select the directory containing `DATA.INI` and GRFs; the
existing `resources` mount supplies them. Its original PHP fallback accepts
`data/` and `BGM/` requests and searches the local data tree and GRFs. It does
not provide `SYSTEM_PATH`, `SYSTEMEN_PATH`, `AI_PATH`, `DATA_OVERRIDE_PATH`,
or a `System` to `SystemEN` alias.

The image installs ROEnglishRE's original `SystemEN` tree once, at its original
path. Apache can serve existing static `SystemEN/` files directly. The existing
roBrowser `customItemInfo` option selects `SystemEN/itemInfo.lua`, which loads
its original nested `SystemEN` files. `System/` is a separate symlink to the
read-only client-data mount, so real original System files remain accessible. Missing `SystemEN/`, `System/` and `AI/` files are not resolved from GRFs
by the PHP fallback. One Apache redirect maps a missing `AI/Util.lua` request
to the existing `data/ai/util.lua` GRF path; a loose `AI/Util.lua` takes priority.
The redirect has a relative location and includes the existing CORS policy.
The frontend proxies `/remote/` to the RemoteClient so browser requests and
the redirect remain on the frontend origin in Compose and Kubernetes.
An internal rewrite alone cannot replace the redirect: the upstream PHP 404
handler reads the original request URI, so it searches for `AI/Util.lua`
instead of the GRF's `data/ai/util.lua`.
The image also installs ROEnglishRE's `PetEvolution.lub` once in `SystemEN/`.
Apache serves it for a missing `System/PetEvolutionCln.lub`; a loose original
takes priority. Other `System/` requests are not mapped to `SystemEN/`.
Existing `AI` and `BGM` mounts are exposed by the image's existing symlinks.
The image does not copy external PVC `data/` files into its own tree at
startup; those files cannot be overlaid together with baked files using a
supported PHP setting. No copies or changes to original client
files are made. If those overlays or virtual aliases are required, the
unmodified software does not provide them and a separate decision is needed.

The pinned client's TownInfo callback returns no success value and replaces
each map's entries. The supplied English Towninfo stops after its first callback;
serving it at a different path does not fix that client incompatibility.
The client already falls back from the missing System quest aliases to
`SystemEN/OngoingQuests.lub`; its Lua 5.1 execution creates 11,363 entries.

The optional `System/Font/SCDream4.otf`, `data/msgstringtable.csv`,
`System/OngoingQuestInfoList.lub`, `System/Towninfo.lub`, `AI/AI_M.lua` and
`data/luafiles514/lua files/hateffectinfo/hateffectids.lub` depend on the
operator's client data. They are not supplied as placeholders. Availability
and warnings vary with the mounted loose files and GRFs.

The image retains upstream request handling and applies standard Apache access
controls to protect GRFs, configuration, application PHP files and internal
directories from direct HTTP access.
