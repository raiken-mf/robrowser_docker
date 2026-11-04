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
      print("PASS Lua 5.1 require/dofile, item descriptions and quests:", items, quests)
    ')
  fi
done
