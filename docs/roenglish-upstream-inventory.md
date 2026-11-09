# ROEnglishRE upstream inventory

This is a read-only source inventory of ROEnglishRE revision
`680a2f2126c8eb5872bf06cf441685c408ed1358`. “Verified” means directly observed
in that revision's files or in this repository's implementation; it does not mean
that the upstream Windows scripts were executed or the resources tested in a
client. “Unclear” identifies intent, runtime behavior, or compatibility that the
source inspection does not establish.

The detailed selection and compatibility reviews are in the
[Additions audit](roenglish-additions-audit.md) and the
[Addon audit](roenglish-addon-audit.md). Both identify remaining unverified
components; neither audit asserts complete browser compatibility.

## Integration before the runtime-generation work

**Verified at baseline `7a53448`:** `images/remote/Dockerfile` copied `Translation/Renewal/data` and
`SystemEN`, then overlaid the corresponding Pre-Renewal trees when the build
argument `SET_PRERENEWAL=1`. It also copied `Additions/SystemEN/PetEvolution.lub`.
It did not run upstream generators or apply Compatibility or other Additions or
Addons. `images/remote/tests/check-roenglish.py` checks the resulting base/Pre-Renewal
translation hashes and PetEvolution, not the omitted layers. Repository overrides
and mounted client resources may affect what is served separately from this build.

**Unclear:** Upstream client-date compatibility does not establish compatibility
with roBrowser, its Lua execution, the PHP RemoteClient, a particular GRF, or
client patches. See `docs/loose-client-resources.md` for this repository's
specific System/SystemEN and GRF fallback limitations. Parts of
`docs/deployment.md` describe System paths and runtime merging differently from
the Dockerfile and that more specific document; verify implementation before
relying on those statements.

## ClientGenerator

**Verified:** `Tools/ClientGenerator.bat` offers Renewal or Pre-Renewal and the
following fixed selections, in this order:

| Index | Client date | Index | Client date | Index | Client date |
|---:|---|---:|---|---:|---|
| 1 | 2012-04-10 | 10 | 2022-03-30 | 19 | 2024-03-11 |
| 2 | 2015-05-13 | 11 | 2022-04-06 | 20 | 2024-04-03 |
| 3 | 2015-10-29 | 12 | 2022-06-02 | 21 | 2024-05-02 |
| 4 | 2017-06-14 | 13 | 2022-08-31 | 22 | 2024-08-07 |
| 5 | 2017-12-13 | 14 | 2022-09-28 | 23 | 2024-10-16 |
| 6 | 2018-06-20 | 15 | 2022-12-07 | 24 | 2025-01-22 |
| 7 | 2019-06-05 | 16 | 2023-01-18 | 25 | 2025-06-18 |
| 8 | 2020-09-02 | 17 | 2023-08-02 | 26 | 2025-09-02 |
| 9 | 2021-10-28 | 18 | 2023-09-20 | 27 | 2025-12-17 |

2012-04-10 is restricted to Pre-Renewal. After confirmation, the script removes
`Tools/Client`, copies Renewal, and overlays Pre-Renewal when selected. For
indices 1 and 2 it calls the corresponding dated copy first; index 3 exits after
the base layers. For other paths it runs a cumulative loop from counter 5
through the selected index, then copies the selected date itself. Each dated
copy uses the mode subdirectory if present; otherwise it copies the entire date
directory. Later copies overwrite earlier ones.

**Verified discrepancy:** loop counter 5 selects 2017-06-14, counter 6 selects
2017-12-13, and so on through counter 27 selecting 2025-09-02: these are one
selection behind the menu indices. Selection 4 has no cumulative loop, though
its exact date is subsequently copied. Selections 1 and 2 also proceed to the
exact-date copy after their initial copy. `Compatibility/2020-01-22` exists but
is not selected in the menu or loop. Starting at selection 19 (2024-03-11), the
script removes the output `data/luafiles514/lua files/hateffectinfo` directory;
starting at selection 25 (2025-06-18), it deletes output
`selectpackage/selectpackageitem.lub`.

**Unclear:** Whether the index offset, duplicate old-date copies and omissions
are intentional. The observed algorithm must not be replaced silently by a
simple chronological overlay if exact upstream behavior is required.

## AdditionsGenerator

**Verified:** `Tools/AdditionsGenerator.bat` is an interactive, repeatable
selection tool intended to run after ClientGenerator; it does not clear the
existing Client tree. Its categories and choices are:

- **Data folder:** all top-level `.txt` files, or individually
  `bookitemnametable`, `buyingstoreitemlist`, the card group
  (`carditemnametable`, `cardpostfixnametable`, `num2cardillustnametable`),
  `etcinfo`, `exceptionminimapnametable`, `fogParameterTable`,
  `indoorrswtable`, `itemmoveinfov5`, `leveluseskillspamount`, `manner`,
  `mapobjlighttable`, `mappostable`, `metalprocessitemtable`, `mp3nametable`,
  `resnametable`, and `viewpointtable`.
- **data/luafiles514:** all-in-one or Headgears, changedirectorylist,
  DrawItemOnAura, exceptionitemproducer, jobidentity, kaframovemapservicelist,
  npclocationradius, shadowtable, robes/costume garments, cash-shop banner,
  attendance banner, weapons, World Map, effecttool, hateffectinfo,
  skilleffectinfo, skillinfoz, stateicon, stylingshop, ItemDBNameTbl,
  EquipmentProperties, CashEmotion, probabilityinfo and AdventureGuide.
- **System:** all-in-one or ChangeMaterial, CheckAttendance,
  monster_size_effect, PetEvolution, PrivateAirplane, Signboard_C,
  OngoingQuests/RecommendedQuests, mapinfo_C, Towninfo_C and Rune. The quests
  choice also copies `datainfo/questinfo_f.lub` into data.
- **Legacy Maps:** all top-level GAT/GND/RSW files plus selected BMPs, or airport
  maps (Einbroch, Lighthalzen, Yuno), gefenia01, tur_d03_i, aldeg_cas01,
  gef_fild02, gl_cas01, mjolnir_07 through _11, moc_fild01, paramk,
  pay_fild04, prt_fild00–07 and 09–10, 2009rwc, 2012rwc, poring_c01,
  poring_c02, sch_lab, airplane, payon, ra_temple, spl_fild01 or aldebaran.
  Individual choices copy the file extensions and any BMP explicitly specified
  by their branches; they do not all consist of the same file types.
- **Legacy Minimaps:** all listed BMPs or individually ama_dun01, ayo_dun01,
  ice_dun04, map2_int, new_zone02, new_zone04, ra_temsky, tha_t07, tha_t08,
  thana_boss, tur_dun05, tur_dun06, yggdrasil01 and yuno_in02.

The date comparisons use the entered `YYYYMMDD` as follows:

| Date condition | Rule |
|---|---|
| ≤ 2017-06-14 | Copy `monster_size_effect 20170614.lub` to the normal target name; otherwise copy the normal file. |
| ≥ 2019-06-05 | Include `mapinfo_C.lub`. |
| ≥ 2021-10-28 | Include `ItemDBNameTbl.lub`. |
| ≥ 2022-12-07 | Include `ChangeMaterial.lub`. |
| ≥ 2023-08-02 | Include EquipmentProperties, CashEmotion and Rune. For dates before 2024-10-16, remove Rune `set_reward.lub` after copying. |
| ≥ 2024-03-11 | Include probabilityinfo `simplecashshopscript.lub`. |
| ≥ 2024-04-17 | Include hateffectinfo. |
| ≥ 2024-05-02 | Include AdventureGuide. |
| ≥ 2025-06-18 | Include `skilldelaylist.lub` in skillinfoz and its all-in-one branch. |

**Verified defects and limitations:**

- The prompt advertises default `20220406`, but tests and sets `date` rather
  than `cdate`; an empty client-date input therefore does not reliably receive
  that default. Input is not validated.
- Several all-in-one Lua copy paths omit `lua files` for effecttool,
  skilleffectinfo, stylingshop and CashEmotion, unlike the corresponding
  individual branches and the checked-in layout. The script also references
  Additions sources `skillinfoz/skillid.lub`, `stateicon/stateiconinfo.lub`
  and `SystemEN/Signboard_C.lub` that are absent at those paths in this revision.
- The checked-in dated `PrivateAirplane 20260520.lub` and
  `EquipmentProperties 202509.lub` variants are not selected by date in the
  generator. The menu labels both mjolnir_10 and mjolnir_11 as 11; branch 12
  actually copies mjolnir_11.
- All-in-one map copying is not identical to the union of individual branches:
  for example the individual sch_lab branch requests a BMP that the all-in-one
  map branch does not request. A “Copied” indicator is set without checking
  successful copies, and `xcopy /C` continues after errors.

**Unclear:** Whether missing sources and path discrepancies are intentional,
what a particular Windows environment actually copies when an error occurs, and
whether dated variants should be selected for any client. No generator was run.

## Addons

All groups present at the pinned revision are listed below. Their presence does
not imply installation or compatibility.

| Group | Verified contents and rules | Unclear or prerequisite |
|---|---|---|
| Custom Lua Support | 28 CLS Lua files; `CLSGenerator.bat` has all-in-one and groups for headgears, random options, hat effects, NPC/mob/pets, Lapine boxes, signboards, robes, weapons, World Map and skill info. All-in-one contains additional files without individual menu groups. | Script says Nemo/WARP patches are needed to read these files. Each selection below 12 first deletes the output CLS directory, so sequential individual selections do not accumulate. Patch and client support were not tested. |
| Legacy Pre-Re Skillinfoz | One alternative skill description file in a data tree. | Appropriate client and interaction with other skill overlays. |
| Navigation Legacy | 16 navigation Lua files in krpri/krsak pairs. | Placement and client-specific support are not established by a generator here. |
| NonkROLuaEntries | Nine Lua files plus a readme; readme says to merge the non-kRO entries manually and use caution. | No automatic merge or conflict resolution is provided. |
| Official Fonts | 13 EOT fonts under `System/Font`. | Actual client/font usage and availability in this deployment. |
| Signboard Legacy | One `signboardlist.lub`. | Client/version and placement requirements. |
| Stateiconimginfo Patch | `efstids`, `stateiconimginfo`, `stateiconinfo`. | Compatibility and replacement/merge requirements. |
| WARP Sessions | Seven translation YAML sessions for 2015, 2018, 2019-06, 2022-09, 2022-12, 2023-08 and 2024-10. | These are patch-tool sessions, not proof that patches work with a given executable. |
| iRO QuestInfo | One `OngoingQuestInfoList_iRO.lub`. | Client integration and placement. |
| itemInfo per Char Server | 2015-10-29 SystemEN itemInfo and helper. Readme requires the “Load iteminfo with char server” patch and checks server name `Pre-Renewal`. | Readme reports NEMO success for 2015-10-29, WARP failure for 2018-06-20 and 2022-04-06; exact upper supported version is unknown. These claims were not independently tested. |
| jRO Enchants Display | Four data card tables: card item, postfix, prefix and illustration mapping. | They may replace or conflict with other card tables; choose and validate deliberately. |

For the current runtime selection, `ROENGLISH_ADDONS=compatible` does not
automatically install any of these groups: none has yet been verified end to
end with this pinned client and its dependencies. In particular, the six
Legacy Navigation tables load as Lua, but their monster and distance entries
do not all match the assumptions of the client's navigation code. WARP
sessions are patch-tool inputs rather than roBrowser resources. CLS and
per-character-server itemInfo require client patches, and non-kRO entries
explicitly require a manual merge. The remaining alternative datasets and
fonts are not yet sufficiently verified for automatic activation.

The initial `ROENGLISH_ADDITIONS=all` implementation selects the additions
listed explicitly in `images/remote/roenglish-generate.php`, not every file in
the upstream Additions tree. The generator supplies `datainfo/enumvar.lub`
for the base `addrandomoptionnametable.lub`; together the pinned originals
execute as 254 numeric-keyed string entries under Lua 5.1. Client-local GRFs
can still take precedence, so the actual displayed options depend on the
loaded GRFs and server. Other client-loaded candidates, including hat effects,
require format, dependency and version checks before they can safely be enabled. This is an
open integration gap rather than a claim that the remaining files are
incompatible. `ROENGLISH_LEGACY_MAPS=1` selects the two upstream all-in-one
legacy map/minimap choices; `0` leaves those additions out.

The client also loads `skillinfoz/jobinheritlist.lub` before its skill tree.
The pinned Additions source references five undefined job constants and stops
under Lua 5.1. The generator supplies these five values from the pinned
roBrowser's `JobConst.js` only in a generated copy, after checking the exact
canonical source hash and one expected insertion point. The source and user
overrides are left untouched. The resulting inheritance table has 148 numeric
entries; the tests exercise both Renewal modes and the client's HTTP path.
The chosen skill-tree data and displayed skills remain dependent on the loaded
client and server data; this does not establish every version's full UI behavior.

Similarly, the selected `Additions/data/luafiles514/lua files/worldviewdata/worldviewdata_table.lub`
references six `WORLD_MSGID` keys (`MSI_102_CH1_FILD1`, `MSI_2_CH1_ZERO1`
through `MSI_2_CH1_ZERO4`, and `MSI_DUN51`) that were added in upstream commit
`d336ab454031fda5868e710cbf2435216474bff4` (`8e71824234385c7cd5084ccbd6976c8dbeb44019`)
for `2025-08-02` but omitted from `Translation/Renewal/.../worldviewdata_language.lub`
when `worldviewdata_table.lub` was moved into `Additions/` (`a2e9b9dd94511a345a730faad9fa988f182a8fa2`).
The generator restores those six upstream strings only in its generated copy of
`worldviewdata_language.lub` after verifying the canonical source SHA-256 and a
single replacement count, leaving the pinned source and user overrides untouched.
With those six keys restored, all 424 Renewal and 384 Pre-Renewal WorldMap table
entries resolve non-empty display strings under Lua 5.1.

For the upstream HatEffect addition (selected by the Windows generator from
2024-04-17), the pinned `HatEffectIDs.lub` and `HatEffectInfo.lub` execute
under Lua 5.1 and define 290 IDs and 265 effects. The same source directory's
`FootPrintEffectInfo.lub` does not parse: its first invalid assignment is at
line 214, and `Type = STR = 4` occurs five times. The pinned client loads the
footprint file after the other two. From 2024-04-17 the generator supplies those
three client paths and repairs the five assignments only in its generated copy.
It checks the source SHA-256 after CRLF-to-LF normalization and the replacement
count before writing, preserving the source line endings; an
unexpected source fails generation explicitly. The original source is unchanged.
The corrected copy executes with 25 footprint entries. Correct display still
depends on the server's IDs and on effect assets in the client GRFs. Tests
check the date boundary, source immutability, Lua execution and HTTP paths.

## Other tools and Linux limits

**Verified:** `LuaConverter.bat` invokes bundled `luac.exe` to produce `.lub`;
the executable is a 32-bit Windows PE program. The script also mentions
uncompressed `.lub` files. `Tools/msgstringtable/encode.py` and
`Tools/simplemsg/encode.py` Base64-encode individual CSV fields into new CSV
files. Repute and MacroReport batch wrappers call their `jsonbson.py` converters;
the converters identify `py-bson` as a dependency. These tools use relative
working-directory paths and produce output files when run.

**Porting limits:** Windows batch commands, `xcopy`, code page 1252 and the
bundled executable are not native Linux equivalents. Linux case-sensitive paths,
spaces and legacy encoded non-ASCII path bytes require explicit handling; do not
blindly normalize or transcode names. Reproduce or deliberately correct ordered
overwrites, mode fallback, deletions, missing sources and menu behavior. Any
replacement Lua compiler must match the target runtime's bytecode expectations;
a `.lub` extension alone proves nothing. Nemo/WARP patches, GRF lookup and
resource loading are separate from copying files. No native Linux port, Windows
execution, generated output comparison or end-to-end client test was performed
for this inventory.
