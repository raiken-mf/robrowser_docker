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
