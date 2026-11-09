#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
kubectl kustomize deploy/k8s/overlays/flux > "$work/resources.yaml"
diff -u "$work/resources.yaml" <(kubectl kustomize deploy/overlays/flux)
diff -u <(kubectl kustomize deploy/clusters/default) <(kubectl kustomize clusters/pi-cluster)
kubectl kustomize clusters/pi-cluster | ruby -ryaml -e '
    resources = YAML.load_stream(STDIN.read).compact
    expected = {"flux-system" => "./clusters/pi-cluster", "ragnarok-stack" => "./deploy/overlays/flux"}
    expected.each do |name, path|
        matches = resources.select { |resource| resource["apiVersion"] == "kustomize.toolkit.fluxcd.io/v1" && resource["kind"] == "Kustomization" && resource.dig("metadata", "namespace") == "flux-system" && resource.dig("metadata", "name") == name }
        abort "Invalid Flux identity or path: #{name}" unless matches.length == 1 && matches.first.dig("spec", "path") == path && matches.first.dig("spec", "prune") == true
    end
    identities = resources.map { |resource| [resource["apiVersion"], resource["kind"], resource.dig("metadata", "namespace"), resource.dig("metadata", "name")] }
    abort "Duplicate parent resource identity" unless identities.uniq.length == identities.length
'
ruby -ryaml -e '
    resources = YAML.load_stream(File.read(ARGV.fetch(0))).compact
    identities = resources.map { |resource| [resource["apiVersion"], resource["kind"], resource.dig("metadata", "namespace"), resource.dig("metadata", "name")] }
    abort "Duplicate child resource identity" unless identities.uniq.length == identities.length
    abort "Missing application namespace" unless identities.include?(["v1", "Namespace", nil, "ragnarok"])
' "$work/resources.yaml"
mkdir -p "$work/fixture"
cp -R deploy clusters "$work/fixture/"
diff -u <(kubectl kustomize "$work/fixture/deploy/clusters/default") <(kubectl kustomize "$work/fixture/clusters/pi-cluster")
diff -u <(kubectl kustomize "$work/fixture/deploy/k8s/overlays/flux") <(kubectl kustomize "$work/fixture/deploy/overlays/flux")
kubectl kustomize "$work/fixture/deploy/clusters/default" > "$work/parent-before.yaml"
ruby -ryaml -e '
    parent, child = ARGV
    [[parent, "./deploy/clusters/default"], [child, "./deploy/k8s/overlays/flux"]].each do |path, replacement|
        content = File.read(path)
        old = path == parent ? "./clusters/pi-cluster" : "./deploy/overlays/flux"
        abort "Expected exactly one old path in #{path}" unless content.scan(old).length == 1
        File.write(path, content.sub(old, replacement))
    end
' "$work/fixture/deploy/clusters/default/flux-system/gotk-sync.yaml" "$work/fixture/deploy/clusters/default/ragnarok-app.yaml"
kubectl kustomize "$work/fixture/deploy/clusters/default" > "$work/parent-after.yaml"
ruby -ryaml -e '
    before, after = ARGV.map { |path| YAML.load_stream(File.read(path)).compact }
    expected = {"flux-system" => ["./clusters/pi-cluster", "./deploy/clusters/default"], "ragnarok-stack" => ["./deploy/overlays/flux", "./deploy/k8s/overlays/flux"]}
    expected.each do |name, paths|
        old = before.find { |resource| resource["kind"] == "Kustomization" && resource.dig("metadata", "namespace") == "flux-system" && resource.dig("metadata", "name") == name }
        new = after.find { |resource| resource["kind"] == "Kustomization" && resource.dig("metadata", "namespace") == "flux-system" && resource.dig("metadata", "name") == name }
        abort "Unexpected migration path: #{name}" unless old && new && [old.dig("spec", "path"), new.dig("spec", "path")] == paths
        new.fetch("spec")["path"] = paths.first
    end
    abort "Migration changes other parent resources" unless before == after
' "$work/parent-before.yaml" "$work/parent-after.yaml"
test "$(awk '/^  HOST:/{print $2}' "$work/resources.yaml")" = pi
grep -Fq 'path: ./clusters/pi-cluster' deploy/clusters/default/flux-system/gotk-sync.yaml
grep -Fq 'path: ./deploy/overlays/flux' deploy/clusters/default/ragnarok-app.yaml
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