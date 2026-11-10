#!/usr/bin/env bash
set -euo pipefail

load_image() {
    local image="$1" built="$2" needed="$3" reference metadata digest revision scope
    [ "$built" != true ] && [ "$needed" = true ] || return 0
    reference="ghcr.io/$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')/$image"
    metadata=$(docker buildx imagetools inspect "$reference:stable" --format '{{json .Manifest}}')
    digest=$(printf '%s' "$metadata" | jq -er '.digest')
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'Invalid fixture digest' >&2; return 1; }
    revision=$(docker buildx imagetools inspect --raw "$reference@$digest" | jq -er '.annotations["org.opencontainers.image.revision"]')
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid fixture source' >&2; return 1; }
    git merge-base --is-ancestor "$revision" HEAD || { echo 'Fixture source is not an ancestor' >&2; return 1; }
    scope=$(python3 scripts/py/ci-scope.py "$revision" "$(git rev-parse HEAD)" --image "$image")
    [ "$scope" = changed=false ] || { echo "$image fixture inputs differ; refusing an implicit rebuild" >&2; return 1; }
    docker pull "$reference@$digest"
    docker tag "$reference@$digest" "$image:ci"
}

remote_needed=${REMOTE_TESTS:-false}
robrowser_needed=${ROBROWSER_TESTS:-false}
if [ "${WEB_TESTS:-false}" = true ]; then
    remote_needed=true
    robrowser_needed=true
fi
load_image remote "${REMOTE_BUILD:-false}" "$remote_needed"
load_image robrowser "${ROBROWSER_BUILD:-false}" "$robrowser_needed"
load_image rathena "${RATHENA_BUILD:-false}" "${RATHENA_TESTS:-false}"
load_image wsproxy "${WSPROXY_BUILD:-false}" "${WSPROXY_TESTS:-false}"