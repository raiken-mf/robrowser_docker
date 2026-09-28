#!/usr/bin/env sh
set -eu

DEPENDENCIES_FILE="${1:-build/dependencies.env}"
[ -f "$DEPENDENCIES_FILE" ] || { echo "Missing dependency file: $DEPENDENCIES_FILE" >&2; exit 1; }
# This file is versioned project configuration, not a credentials file.
. "$DEPENDENCIES_FILE"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

checkout() {
  name=$1 repo=$2 ref=$3
  git clone --quiet "$repo" "$workdir/$name"
  git -C "$workdir/$name" checkout --quiet --detach "$ref"
}
require_dir() {
  [ -d "$1" ] || { echo "Missing required directory: $1" >&2; exit 1; }
}
require_file() {
  [ -f "$1" ] || { echo "Missing required file: $1" >&2; exit 1; }
}

checkout robrowser "$ROBROWSER_REPOSITORY" "$ROBROWSER_REF"
require_file "$workdir/robrowser/package.json"
require_file "$workdir/robrowser/vite.config.js"
require_file "$workdir/robrowser/src/DB/DBManager.js"

checkout rathena "$RATHENA_REPOSITORY" "$RATHENA_REF"
require_file "$workdir/rathena/configure"
require_file "$workdir/rathena/src/custom/defines_pre.hpp"
require_dir "$workdir/rathena/conf"

checkout roenglish "$ROENGLISH_REPOSITORY" "$ROENGLISH_REF"
require_dir "$workdir/roenglish/Translation/Renewal/data"
require_dir "$workdir/roenglish/Translation/Renewal/SystemEN"
require_dir "$workdir/roenglish/Translation/Pre-Renewal/data"
require_dir "$workdir/roenglish/Translation/Pre-Renewal/SystemEN"

echo "All pinned upstream layouts are compatible with the Dockerfiles."
