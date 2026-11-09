#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
kubectl kustomize deploy/k8s/overlays/flux > "$work/resources.yaml"
diff -u "$work/resources.yaml" <(kubectl kustomize deploy/overlays/flux)
diff -u <(kubectl kustomize deploy/clusters/default) <(kubectl kustomize clusters/pi-cluster)
mkdir -p "$work/fixture"
cp -R deploy clusters "$work/fixture/"
diff -u <(kubectl kustomize "$work/fixture/deploy/clusters/default") <(kubectl kustomize "$work/fixture/clusters/pi-cluster")
diff -u <(kubectl kustomize "$work/fixture/deploy/k8s/overlays/flux") <(kubectl kustomize "$work/fixture/deploy/overlays/flux")
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
printf '%s\n' 'PASS staged Flux host migration and custom installation host'