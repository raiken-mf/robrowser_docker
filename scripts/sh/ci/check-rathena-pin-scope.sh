#!/usr/bin/env bash
set -euo pipefail

comparison=${1:?Git comparison required}
if git diff --quiet "$comparison" -- build/dependencies.env; then
    exit 0
fi

diff=$(git diff --no-ext-diff --no-textconv --no-color --unified=0 "$comparison" -- build/dependencies.env) || exit 1
printf '%s\n' "$diff" | awk '
    /^diff --git / || /^index / || /^--- / || /^\+\+\+ / || /^@@ / { next }
    /^[-+]/ {
        if ($0 !~ /^[-+](ROBROWSER|REMOTECLIENT|ROENGLISH|HERCULES)_REF=[0-9a-f]+$/ || length($0) - index($0, "=") != 40) exit 1
        changes++
        next
    }
    { exit 1 }
    END { if (!changes) exit 1 }
'