#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'The legacy rAthena installer is disabled because it exposed credentials and interpolated SQL.' >&2
printf '%s\n' 'Use scripts/sh/k8s/k8s-all.sh --check for a read-only preflight; installation requires separate approval.' >&2
exit 1