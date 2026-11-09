#!/usr/bin/env bash
exec bash "$(dirname "$0")/sh/k8s/render-web-manifests.sh" "$@"