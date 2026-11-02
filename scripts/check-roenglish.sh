#!/usr/bin/env bash
# The Renewal image must already exist (CI builds robrowser:ci first).
set -euo pipefail
source build/dependencies.env
workdir=$(mktemp -d)
container=""
cleanup() {
  if [ -n "$container" ]; then docker rm -f "$container" >/dev/null; fi
  rm -rf "$workdir"
}
trap cleanup EXIT
git clone --quiet "$ROENGLISH_REPOSITORY" "$workdir/source"
git -C "$workdir/source" checkout --quiet --detach "$ROENGLISH_REF"
docker build -f images/robrowser/Dockerfile \
  --build-arg SET_PRERENEWAL=1 \
  --build-arg REMOTECLIENT_REPOSITORY="$REMOTECLIENT_REPOSITORY" \
  --build-arg REMOTECLIENT_REF="$REMOTECLIENT_REF" \
  --build-arg ROENGLISH_REPOSITORY="$ROENGLISH_REPOSITORY" \
  --build-arg ROENGLISH_REF="$ROENGLISH_REF" \
  -t robrowser:ci-prerenewal .
for mode in 0 1; do
  image="${1:-robrowser:ci}"
  if [ "$mode" = 1 ]; then image=robrowser:ci-prerenewal; fi
  container=$(docker create "$image")
  mkdir "$workdir/installed-$mode"
  docker cp "$container:/var/www/localhost/htdocs/remote/." "$workdir/installed-$mode"
  python3 scripts/check-roenglish.py "$workdir/source" "$workdir/installed-$mode" "$mode"
  docker rm "$container" >/dev/null
  container=""
done
