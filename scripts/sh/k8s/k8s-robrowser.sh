#!/usr/bin/env bash
set -euo pipefail
exec bash "$(dirname "$0")/k8s-all.sh" "$@"
