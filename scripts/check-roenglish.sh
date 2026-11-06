#!/usr/bin/env bash
# Run both selections with the already-built image and the pinned upstream source.
set -euo pipefail
source build/dependencies.env
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
git clone --quiet "$ROENGLISH_REPOSITORY" "$workdir/source"
git -C "$workdir/source" checkout --quiet --detach "$ROENGLISH_REF"
image=${1:-remote:ci}
for mode in 0 1; do
  mkdir "$workdir/output-$mode"
  docker run --rm --user "$(id -u):$(id -g)" --entrypoint php \
    -e PACKETVER=20211103 -e SET_PRERENEWAL="$mode" \
    -e ROENGLISH_ADDITIONS=all -e ROENGLISH_ADDONS=compatible -e ROENGLISH_LEGACY_MAPS=0 \
    --mount "type=bind,src=$workdir/source,dst=/source,readonly" \
    --mount "type=bind,src=$workdir/output-$mode,dst=/output" \
    "$image" /usr/local/bin/roenglish-generate.php /source /output
  python3 scripts/check-roenglish.py "$workdir/source" "$workdir/output-$mode" "$mode"
  (cd "$workdir/output-$mode" && lua5.1 -e '
    dofile("data/luafiles514/lua files/skillinfoz/jobinheritlist.lub")
    local count = 0
    for id, parent in pairs(JOB_INHERIT_LIST) do
      if type(id)=="number" then assert(type(parent)=="number"); count=count+1 end
    end
    assert(count==148 and JOB_INHERIT_LIST[4353]==4351 and JOB_INHERIT_LIST[4355]==4353)
    print("PASS Lua job inheritance:", count)
  ')
  if [ "$mode" = 0 ]; then
    (cd "$workdir/output-$mode" && lua5.1 -e '
      dofile("SystemEN/itemInfo.lua")
      local items = 0
      for _, item in pairs(tbl) do
        if type(item) == "table" and type(item.identifiedDescriptionName) == "table" and #item.identifiedDescriptionName > 0 then items = items + 1 end
      end
      assert(items >= 26778, "item descriptions missing: " .. items)
      dofile("SystemEN/OngoingQuests.lub")
      local quests = 0
      for _ in pairs(QuestInfoList) do quests = quests + 1 end
      assert(quests == 11363, "quest entries differ: " .. quests)
      local lua = "data/luafiles514/lua files/datainfo/"
      dofile(lua .. "enumvar.lub")
      dofile(lua .. "addrandomoptionnametable.lub")
      local options = 0
      for id, description in pairs(NameTable_VAR) do
        assert(type(id)=="number" and type(description)=="string")
        options = options + 1
      end
      assert(options == 254 and NameTable_VAR[1] == "MaxHP +%d", "random option table differs")
      local starts, ends, needed, rewards = 0, 0, 0, 0
      InsertStartableMap = function(v) assert(type(v)=="string"); starts=starts+1; return 1 end
      InsertEndableMap = function(v) assert(type(v)=="string"); ends=ends+1; return 1 end
      InsertNeedItem = function(v) assert(type(v)=="number"); needed=needed+1; return 1 end
      dofile("SystemEN/PrivateAirplane.lub"); assert(main()); assert(starts>0 and ends>0 and needed>0)
      InsertCheckAttendanceConfig = function(_,a,b) assert(type(a)=="number" and type(b)=="number"); return 1 end
      InsertCheckAttendanceReward = function(a,b,c) assert(type(a)=="number" and type(b)=="number" and type(c)=="number"); rewards=rewards+1; return 1 end
      dofile("SystemEN/CheckAttendance.lub"); assert(main()); assert(rewards>0)
      local recipes, feeds = 0, 0
      InsertEvolutionRecipeLGU = function(a,b,c,d) assert(type(a)=="number" and type(b)=="number" and type(c)=="number" and type(d)=="number"); recipes=recipes+1 end
      InsertPetAutoFeeding = function(a) assert(type(a)=="number"); feeds=feeds+1 end
      dofile("SystemEN/PetEvolution.lub"); main(); assert(recipes==206 and feeds==53)
      local townCalls = 0
      AddTownInfo = function() townCalls=townCalls+1 end
      dofile("SystemEN/Towninfo.lub"); assert(main()==false and townCalls==1, "TownInfo callback limitation changed")
      print("PASS Lua 5.1 item descriptions, quests, airship and attendance:", items, quests, starts, ends, needed, rewards)
    ')
  fi
done
mkdir "$workdir/output-hat"
docker run --rm --user "$(id -u):$(id -g)" --entrypoint php \
  -e PACKETVER=20240417 -e SET_PRERENEWAL=0 \
  -e ROENGLISH_ADDITIONS=all -e ROENGLISH_ADDONS=compatible -e ROENGLISH_LEGACY_MAPS=0 \
  --mount "type=bind,src=$workdir/source,dst=/source,readonly" \
  --mount "type=bind,src=$workdir/output-hat,dst=/output" \
  "$image" /usr/local/bin/roenglish-generate.php /source /output
(cd "$workdir/output-hat" && lua5.1 -e '
  local path = "data/luafiles514/lua files/hateffectinfo/"
  dofile(path .. "hateffectids.lub")
  dofile(path .. "hateffectinfo.lub")
  dofile(path .. "footprinteffectinfo.lub")
  local ids, effects, footprints = 0, 0, 0
  for key, value in pairs(HatEFID) do assert(type(key)=="string" and type(value)=="number"); ids=ids+1 end
  for key, value in pairs(hatEffectTable) do assert(type(key)=="number" and type(value)=="table"); effects=effects+1 end
  for key, value in pairs(FootPrintEffectTable) do assert(type(key)=="number" and type(value)=="table"); footprints=footprints+1 end
  assert(ids==290 and effects==265 and footprints==25)
  print("PASS generated hat effects and footprints:", ids, effects, footprints)
')
# Audit unsupported and alternative datasets without modifying the pinned sources.
(cd "$workdir/source" && lua5.1 -e '
  package.path = "Translation/Renewal/?.lua;" .. package.path
  local hats = "Additions/data/luafiles514/lua files/hateffectinfo/"
  dofile(hats .. "HatEffectIDs.lub")
  dofile(hats .. "HatEffectInfo.lub")
  local ids, effects = 0, 0
  for _ in pairs(HatEFID) do ids = ids + 1 end
  for _ in pairs(hatEffectTable) do effects = effects + 1 end
  assert(ids == 290 and effects == 265, "hat effect tables differ")
  local footprint, reason = loadfile(hats .. "FootPrintEffectInfo.lub")
  assert(footprint == nil and reason:find("near", 1, true), "footprint source limitation changed")
  local root = "Addons/Stateiconimginfo Patch/"
  dofile(root .. "efstids.lub")
  dofile(root .. "stateiconinfo.lub")
  dofile(root .. "stateiconimginfo.lub")
  assert(EFST_IDs.EFST_PROPERTYFIRE_TK == 2000)
  for id=2000,2004 do assert(type(StateIconList[id]) == "table") end
  dofile("Addons/Signboard Legacy/signboardlist.lub")
  local count = 0
  for _, value in pairs(SignBoardList) do
    assert(type(value[1])=="string" and type(value[2])=="number" and type(value[3])=="number")
    assert(type(value[4])=="number" and type(value[5])=="number" and type(value[6])=="string")
    count = count + 1
  end
  assert(count == 625, "legacy signboard count differs: " .. count)
  print("PASS source Lua audit: hat effects, stateicon IDs and signboard fields", count)
')
