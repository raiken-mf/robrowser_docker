#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
kubectl kustomize deploy/k8s/overlays/flux > "$work/resources.yaml"
yaml_json() {
    awk 'BEGIN { print "services:\n  fixture:\n    image: fixture\nx-resources:"; document=0 }
         /^---[[:space:]]*$/ { document=0; next }
         !document && /^[^#[:space:]]/ { print "  -"; document=1 }
         document { print "    " $0 }' "$1" |
        docker compose --env-file /dev/null -f - config --format json --no-interpolate
}
kubectl kustomize deploy/clusters/default > "$work/parent.yaml"
yaml_json "$work/parent.yaml" > "$work/parent.json"
yaml_json "$work/resources.yaml" > "$work/resources.json"
python3 - "$work/parent.json" "$work/resources.json" <<'PY'
import json, sys
parent, child = [json.load(open(path))["x-resources"] for path in sys.argv[1:]]
def identities(resources):
    return [(resource["apiVersion"], resource["kind"], resource["metadata"].get("namespace"), resource["metadata"]["name"]) for resource in resources]
for resources in (parent, child):
    assert len(identities(resources)) == len(set(identities(resources))), "Duplicate resource identity"
assert ("v1", "Namespace", None, "ragnarok") in identities(child)
for name, path in (("flux-system", "./deploy/clusters/default"), ("ragnarok-stack", "./deploy/k8s/overlays/flux")):
    matches = [resource for resource in parent if (resource["apiVersion"], resource["kind"], resource["metadata"].get("namespace"), resource["metadata"]["name"]) == ("kustomize.toolkit.fluxcd.io/v1", "Kustomization", "flux-system", name)]
    assert len(matches) == 1 and matches[0]["spec"]["path"] == path and matches[0]["spec"]["prune"] is True
    assert matches[0]["spec"]["sourceRef"] == {"kind": "GitRepository", "name": "flux-system"}
    assert matches[0]["spec"].get("suspend", False) is False
PY
test ! -e "clusters/""pi-cluster"
test ! -e "deploy/""overlays/flux"
test "$(awk '/^  HOST:/{print $2}' "$work/resources.yaml")" = pi
grep -Fq 'path: ./deploy/clusters/default' deploy/clusters/default/flux-system/gotk-sync.yaml
grep -Fq 'path: ./deploy/k8s/overlays/flux' deploy/clusters/default/ragnarok-app.yaml
grep -Fq 'prune: true' deploy/clusters/default/flux-system/gotk-sync.yaml
grep -Fq 'prune: true' deploy/clusters/default/ragnarok-app.yaml
scope=$(sed -n "s/.*grep -Eq '\([^']*\)' <<< \"\$changed\".*/\1/p" .github/workflows/ci.yml | head -n 1)
test -n "$scope"
printf '%s\n' 'deploy/clusters/default/ragnarok-app.yaml' | grep -Eq "$scope"
if grep -Fq -- "- 'clusters/**'" .github/workflows/ci.yml; then
    printf '%s\n' 'Cluster changes must not be excluded from CI.' >&2
    exit 1
fi
awk '
    /^  patches:$/ { copying=1; print "patches:"; next }
    copying && /^  [^ ]/ { exit }
    copying { sub(/^  /, ""); print }
' deploy/clusters/default/ragnarok-app.yaml > "$work/patches.yaml"
printf '%s\n' 'apiVersion: kustomize.config.k8s.io/v1beta1' 'kind: Kustomization' 'resources:' '- resources.yaml' > "$work/kustomization.yaml"
cat "$work/patches.yaml" >> "$work/kustomization.yaml"
test "$(kubectl kustomize "$work" | awk '/^  HOST:/{print $2}')" = pi
kubectl kustomize "$work" > "$work/patched.yaml"
diff -u <(grep -E '^(apiVersion|kind):|^  (name|namespace):' "$work/resources.yaml") <(grep -E '^(apiVersion|kind):|^  (name|namespace):' "$work/patched.yaml")
sed 's/^  HOST: pi$/  HOST: 127.0.0.1/' "$work/resources.yaml" > "$work/neutral.yaml"
sed 's/resources.yaml/neutral.yaml/' "$work/kustomization.yaml" > "$work/neutral-kustomization.yaml"
mv "$work/neutral-kustomization.yaml" "$work/kustomization.yaml"
test "$(kubectl kustomize "$work" | awk '/^  HOST:/{print $2}')" = pi
sed 's/value: pi/value: example.invalid/' "$work/kustomization.yaml" > "$work/custom-kustomization.yaml"
mv "$work/custom-kustomization.yaml" "$work/kustomization.yaml"
test "$(kubectl kustomize "$work" | awk '/^  HOST:/{print $2}')" = example.invalid
printf '%s\n' 'PASS Flux paths, identities, pruning and custom installation host'