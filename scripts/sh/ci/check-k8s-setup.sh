#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo/scripts/sh/k8s" "$tmp/repo/deploy/clusters/default"
cp "$root/scripts/sh/k8s/k8s-setup"*.sh "$tmp/repo/scripts/sh/k8s/"
export TEST_LOG="$tmp/log" TEST_STATE=existing
cat > "$tmp/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$TEST_LOG"
case "$*" in
  'get nodes') exit 0 ;;
  'get namespace flux-system --ignore-not-found -o name') [[ "$TEST_STATE" == existing ]] && echo namespace/flux-system; exit 0 ;;
  'get customresourcedefinitions -o name') [[ "$TEST_STATE" != api-error ]] || exit 1; [[ "$TEST_STATE" != partial ]] || echo customresourcedefinition.apiextensions.k8s.io/gitrepositories.source.toolkit.fluxcd.io; [[ "$TEST_STATE" != partial-operator ]] || echo customresourcedefinition.apiextensions.k8s.io/fluxinstances.fluxcd.controlplane.io; exit 0 ;;
  'get deployments --all-namespaces -o jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}') exit 0 ;;
  *'get gitrepository flux-system'*'.spec.url'*) echo ssh://git@github.com/raiken-mf/robrowser_docker ;;
  *'get gitrepository flux-system'*'.spec.ref.branch'*) echo main ;;
  *'get kustomization flux-system'*) echo './deploy/clusters/default|GitRepository|flux-system|' ;;
  *'get kustomization ragnarok-stack'*) echo "${TEST_CHILD:-./deploy/k8s/overlays/flux}|GitRepository|flux-system|" ;;
  *'get deployment '*) echo deployment/mock ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/flux" <<'EOF'
#!/usr/bin/env bash
printf 'flux %s\n' "$*" >> "$TEST_LOG"
EOF
cat > "$tmp/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$TEST_LOG"
[[ "$1" != -v ]] || exit 0
if [[ "$1" == test ]]; then
  [[ "$*" != 'test -e /var/lib/robrowser-k3s-setup-in-progress' || "${TEST_STATE:-}" != interrupted ]] || exit 0
  [[ "${TEST_STATE:-}" != fresh ]] || exit 1
  case "$*" in
    'test -e /var/lib/rancher/k3s') [[ "${TEST_STATE:-}" == partial-k3s ]] && exit 0 || exit 1 ;;
    'test -e /etc/systemd/system/k3s-agent.service') exit 0 ;;
    'test ! -e /etc/systemd/system/k3s.service') exit 0 ;;
    *) exit 1 ;;
  esac
fi
exit 99
EOF
cat > "$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$TEST_LOG"
[[ "$*" == 'is-active --quiet k3s-agent.service' ]]
EOF
cat > "$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
flux_script="$tmp/repo/scripts/sh/k8s/k8s-setup-flux.sh"
k3s_script="$tmp/repo/scripts/sh/k8s/k8s-setup.sh"
if INITIALIZE_STORAGE=true bash "$k3s_script" >"$tmp/initialize-output" 2>&1; then echo 'FAIL: Storage initialization accepted' >&2; exit 1; fi
grep -q 'Automatic storage initialization is unsupported' "$tmp/initialize-output"
if ROLE=server STORAGE_DEVICE=skip bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: Longhorn without storage accepted' >&2; exit 1; fi
[[ ! -e "$TEST_LOG" ]] || { echo 'FAIL: Initialization rejection changed system state' >&2; exit 1; }
bash -c '
  set -euo pipefail
  source "$1"
  test() { [[ "$1" == -b ]]; }
  readlink() { printf "%s\n" "$2"; }
  lsblk() {
    case "$*" in
      "-dn -o TYPE /dev/ssd1") echo part ;;
      "-s -nrpo NAME,TYPE /dev/root1") [[ "${CASE:-}" != missing-root ]] || return 1; printf "/dev/root1 part\n/dev/root disk\n" ;;
      "-s -nrpo NAME,TYPE /dev/ssd1") if [[ "${CASE:-}" == root-disk ]]; then printf "/dev/ssd1 part\n/dev/root disk\n"; else printf "/dev/ssd1 part\n/dev/ssd disk\n"; fi ;;
      *) return 1 ;;
    esac
  }
  sudo() {
    case "$*" in
      "blkid -s UUID -o value /dev/ssd1") echo fixture ;;
      "blkid -s TYPE -o value /dev/ssd1") [[ "${CASE:-}" != wrong-type ]] && echo ext4 || echo xfs ;;
      "blkid -c /dev/null -t UUID=fixture -o device") echo /dev/ssd1; [[ "${CASE:-}" != duplicate ]] || echo /dev/other ;;
      *) return 1 ;;
    esac
  }
  findmnt() {
    case "$*" in
      "-rn -M / -o SOURCE") echo /dev/root1 ;;
      "-rn -M /mnt/longhorn -o SOURCE") [[ "${CASE:-}" != wrong-mount ]] && echo /dev/ssd1 || echo /dev/other ;;
      "-rn -M /mnt/longhorn -o FSTYPE") echo ext4 ;;
      "-rn -M /mnt/longhorn -o UUID") echo fixture ;;
      "-rn -M /mnt/longhorn -o FSROOT") echo / ;;
      "-rn -S /dev/ssd1 -o TARGET") echo /mnt/longhorn; [[ "${CASE:-}" != extra-mount ]] || echo /unexpected ;;
      *) return 1 ;;
    esac
  }
  [[ $(validate_storage_device /dev/ssd1 /mnt/longhorn) == fixture ]]
  for CASE in root-disk missing-root wrong-type duplicate wrong-mount extra-mount; do
    if validate_storage_device /dev/ssd1 /mnt/longhorn >/dev/null 2>&1; then echo "FAIL: Storage case $CASE accepted" >&2; exit 1; fi
  done
  findmnt() { printf "/\n/mnt/longhorn\n/var/lib/longhorn/nested\n"; }
  if reject_nested_mounts /var/lib/longhorn >/dev/null 2>&1; then echo "FAIL: Nested data mount accepted" >&2; exit 1; fi
  [[ $(mount_state /mnt/longhorn) == mounted && $(mount_state /missing) == absent ]]
  findmnt() { return 1; }
  if mount_state /missing >/dev/null 2>&1; then echo "FAIL: Mount query error accepted" >&2; exit 1; fi
' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh"
bash "$flux_script" --check >/dev/null
! grep -q 'flux bootstrap' "$TEST_LOG"
export TEST_CHILD=./wrong
if bash "$flux_script" --check >/dev/null 2>&1; then echo 'FAIL: Flux drift accepted' >&2; exit 1; fi
unset TEST_CHILD
export TEST_STATE=absent
if TEST_STATE=partial bash "$flux_script" </dev/null >/dev/null 2>&1; then echo 'FAIL: Partial Flux installation accepted' >&2; exit 1; fi
if TEST_STATE=partial-operator bash "$flux_script" </dev/null >/dev/null 2>&1; then echo 'FAIL: Partial Flux Operator installation accepted' >&2; exit 1; fi
if TEST_STATE=api-error bash "$flux_script" </dev/null >/dev/null 2>&1; then echo 'FAIL: Flux API error accepted' >&2; exit 1; fi
if bash "$flux_script" </dev/null >/dev/null 2>&1; then echo 'FAIL: Flux bootstrap without confirmation' >&2; exit 1; fi
! grep -q 'flux bootstrap' "$TEST_LOG"
printf 'BOOTSTRAP\n' | GITHUB_TOKEN=fixture bash "$flux_script" >/dev/null
grep -q -- '--path=deploy/clusters/default' "$TEST_LOG"
ROLE=agent bash "$k3s_script" >/dev/null
ROLE=agent bash "$k3s_script" >/dev/null
if ROLE=server bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: K3s role mismatch accepted' >&2; exit 1; fi
if TEST_STATE=fresh ROLE=server K3S_URL=https://fixture.invalid K3S_TOKEN=fixture bash "$k3s_script" >"$tmp/server-join-output" 2>&1; then echo 'FAIL: Server join accepted' >&2; exit 1; fi
grep -q 'Joining an existing server requires a separately reviewed procedure' "$tmp/server-join-output"
if TEST_STATE=fresh ROLE=agent bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: Missing agent prerequisites accepted' >&2; exit 1; fi
if TEST_STATE=interrupted ROLE=agent bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: Interrupted setup accepted' >&2; exit 1; fi
if TEST_STATE=partial-k3s ROLE=server bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: Partial K3s installation accepted' >&2; exit 1; fi
! grep -Eq 'sudo (mount|parted|mkfs|tee|systemctl)' "$TEST_LOG"
fstab="$tmp/fstab"
printf '%s\n' 'UUID=fixture /mnt/longhorn ext4 defaults,noatime,nofail 0 2' > "$fstab"
FSTAB_FILE="$fstab" bash -c 'source "$1"; ensure_fstab_entry /mnt/longhorn "UUID=fixture /mnt/longhorn ext4 defaults,noatime,nofail 0 2"' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh"
printf '%s\n' 'UUID=fixture /mnt/longhorn ext4 defaults,noatime,nofail 0 2' >> "$fstab"
if FSTAB_FILE="$fstab" bash -c 'source "$1"; ensure_fstab_entry /mnt/longhorn "UUID=fixture /mnt/longhorn ext4 defaults,noatime,nofail 0 2"' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh" >/dev/null 2>&1; then echo 'FAIL: Duplicate fstab entry accepted' >&2; exit 1; fi
printf '%s\n' 'UUID=wrong /mnt/longhorn ext4 defaults,noatime,nofail 0 2' > "$fstab"
if FSTAB_FILE="$fstab" bash -c 'source "$1"; ensure_fstab_entry /mnt/longhorn "UUID=fixture /mnt/longhorn ext4 defaults,noatime,nofail 0 2"' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh" >/dev/null 2>&1; then echo 'FAIL: Conflicting fstab entry accepted' >&2; exit 1; fi
bash -c '
  set -euo pipefail
  source "$1"
  findmnt() { case "$*" in *UUID) echo wrong ;; *FSROOT) echo /wrong ;; *) return 1 ;; esac; }
  if mount_matches /mnt/longhorn fixture /; then exit 1; fi
  if mount_matches /var/lib/longhorn wrong /data; then exit 1; fi
' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh"
bash -c '
  set -euo pipefail
  source "$1"
  findmnt() { case "$*" in *UUID) echo fixture ;; *FSROOT) case "$*" in */mnt/longhorn*) echo / ;; *) echo /k3s-etcd-data ;; esac ;; *) return 1 ;; esac; }
  systemd-escape() { printf "%s\n" fixture.mount; }
  sudo() { case "$1" in test) return 0 ;; cat) printf "%s\n" "BindsTo=fixture.mount" "UUID=fixture" ;; *) return 1 ;; esac; }
  if check_etcd_ssd_guard >/dev/null 2>&1; then exit 1; fi
' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh"
bash -c '
  set -euo pipefail
  source "$1"
  MOUNTPOINT=/mnt/longhorn ETCD_DIR=/var/lib/rancher/k3s/server/db/etcd ETCD_SSD_DIR=/mnt/longhorn/k3s-etcd-data
  mount_matches() { return 0; }
  findmnt() { printf "/\n%s\n" "$ETCD_DIR"; }
  systemd-escape() { printf "%s\n" fixture.mount; }
  sudo() { return 0; }
  write_if_missing_or_equal() {
    if [[ "$1" == */etcd-ssd.conf ]]; then
      [[ "$2" == *'"'"'$$'"'"'"(findmnt -n -o UUID"* && "$2" == *'"'"'$$'"'"'"(findmnt -n -o FSROOT"* ]]
      guard=${2##*ExecStartPre=/bin/sh -c }
      guard=${guard:1:${#guard}-2}
      guard=${guard//\$\$/\$}
      findmnt() { return 1; }
      if eval "$guard"; then echo "FAIL: systemd guard accepted mount query failure" >&2; return 1; fi
      findmnt() { printf "/\n%s\n" "$ETCD_DIR"; }
    fi
  }
  prepare_etcd_ssd fixture
' _ "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh"
printf '%s\n' '#!/bin/sh' > "$tmp/installer"
installer_sha=$(sha256sum "$tmp/installer")
export K3S_INSTALLER="$tmp/installer" K3S_INSTALLER_SHA256="${installer_sha%% *}" FSTAB_FILE="$tmp/fresh-fstab" TEST_FRESH_LOG="$tmp/fresh-log"
: > "$FSTAB_FILE"
sed 's/"$EUID" -eq 0/"${TEST_EUID:-$EUID}" -eq 0/' "$k3s_script" > "$tmp/fresh-setup.sh"
cp "$tmp/fresh-setup.sh" "$tmp/repo/scripts/sh/k8s/fresh-setup.sh"
bash -c '
  set -euo pipefail
  script=$1
  run_setup() {
    sudo() {
      case "$1" in
        -v) return 0 ;;
        test)
          case "$*" in
            "test -s /var/lib/rancher/k3s/server/db/etcd/member/snap/db"|"test -f /etc/rancher/k3s/k3s.yaml") [[ -e "$TEST_FRESH_LOG.installed" ]] ;;
            *) return 1 ;;
          esac ;;
        blkid)
          case "$*" in
            "blkid -s UUID -o value /dev/ssd1") echo fixture ;;
            "blkid -s TYPE -o value /dev/ssd1") echo ext4 ;;
            "blkid -c /dev/null -t UUID=fixture -o device") echo /dev/ssd1 ;;
            *) return 1 ;;
          esac ;;
        find) [[ "${FAIL_FIND:-false}" != true ]] ;;
        tee) printf "write %s\n" "$*" >> "$TEST_FRESH_LOG"; cat >/dev/null ;;
        mkdir|chmod|mount|systemctl|rmdir)
          printf "change %s\n" "$*" >> "$TEST_FRESH_LOG"
          [[ "$*" != "mkdir /var/lib/robrowser-k3s-setup-in-progress" ]] || : > "$TEST_FRESH_LOG.marker" ;;
        *) return 1 ;;
      esac
    }
    test() { [[ "$1" == -b ]]; }
    readlink() { printf "%s\n" "$2"; }
    lsblk() {
      case "$*" in
        "-dn -o TYPE /dev/ssd1") echo part ;;
        "-s -nrpo NAME,TYPE /dev/root1") printf "/dev/root1 part\n/dev/root disk\n" ;;
        "-s -nrpo NAME,TYPE /dev/ssd1") printf "/dev/ssd1 part\n/dev/ssd disk\n" ;;
        *) return 1 ;;
      esac
    }
    findmnt() {
      case "$*" in
        "-rn -o TARGET") [[ "${FAIL_MOUNT_QUERY:-false}" != true ]] || return 1; [[ "${FAIL_AFTER_MARKER:-false}" != true || ! -e "$TEST_FRESH_LOG.marker" ]] || return 1; printf "/\n/mnt/longhorn\n" ;;
        "-rn -M / -o SOURCE") echo /dev/root1 ;;
        "-rn -M /mnt/longhorn -o SOURCE") echo /dev/ssd1 ;;
        "-rn -M /mnt/longhorn -o FSTYPE") echo ext4 ;;
        "-rn -M /mnt/longhorn -o UUID"|"-rn -M /var/lib/longhorn -o UUID"|"-rn -M /var/lib/rancher/k3s/server/db/etcd -o UUID") echo fixture ;;
        "-rn -M /mnt/longhorn -o FSROOT") echo / ;;
        "-rn -M /var/lib/longhorn -o FSROOT") echo /data ;;
        "-rn -M /var/lib/rancher/k3s/server/db/etcd -o FSROOT") echo /k3s-etcd-data ;;
        "-rn -S /dev/ssd1 -o TARGET") echo /mnt/longhorn ;;
        *) return 1 ;;
      esac
    }
    systemctl() { return 0; }
    systemd-escape() { echo fixture.mount; }
    blkid() { return 1; }; mount() { return 1; }
    iscsiadm() { :; }; mount.nfs() { :; }; cryptsetup() { :; }; pigz() { :; }
    kubectl() { case "$*" in "get nodes"|"get namespace longhorn-system --ignore-not-found -o name") return 0 ;; *) return 1 ;; esac; }
    helm() { printf "helm %s\n" "$*" >> "$TEST_FRESH_LOG"; }
    sh() { printf "installer %s\n" "$*" >> "$TEST_FRESH_LOG"; : > "$TEST_FRESH_LOG.installed"; }
    source "$script"
  }
  if (TEST_EUID=0 FAIL_MOUNT_QUERY=true STORAGE_DEVICE=/dev/ssd1 run_setup) >/dev/null 2>&1; then echo "FAIL: Mount query failure accepted" >&2; exit 1; fi
  [[ ! -s "$TEST_FRESH_LOG" ]] || { echo "FAIL: Changes before mount query failure" >&2; exit 1; }
  if (TEST_EUID=0 FAIL_AFTER_MARKER=true STORAGE_DEVICE=/dev/ssd1 run_setup) >/dev/null 2>&1; then echo "FAIL: Late mount query failure accepted" >&2; exit 1; fi
  [[ -e "$TEST_FRESH_LOG.marker" ]] || { echo "FAIL: Setup marker missing" >&2; exit 1; }
  ! grep -Eq "^(write|installer|helm) " "$TEST_FRESH_LOG" || { echo "FAIL: Changes after mount query failure" >&2; exit 1; }
  : > "$TEST_FRESH_LOG"
  if (TEST_EUID=0 FAIL_FIND=true STORAGE_DEVICE=/dev/ssd1 run_setup) >/dev/null 2>&1; then echo "FAIL: Data inspection failure accepted" >&2; exit 1; fi
  ! grep -q "change mount /var/lib/longhorn" "$TEST_FRESH_LOG" || { echo "FAIL: Mount after data inspection failure" >&2; exit 1; }
  : > "$TEST_FRESH_LOG"
  (TEST_EUID=0 STORAGE_DEVICE=/dev/ssd1 run_setup) >/dev/null
  grep -q "installer .* server --cluster-init" "$TEST_FRESH_LOG"
  grep -q "helm install longhorn" "$TEST_FRESH_LOG"
  grep -q "change rmdir /var/lib/robrowser-k3s-setup-in-progress" "$TEST_FRESH_LOG"
' _ "$tmp/repo/scripts/sh/k8s/fresh-setup.sh"
mv "$tmp/repo/scripts/sh/k8s/k8s-setup-storage.sh" "$tmp/storage-helper"
if bash "$k3s_script" >/dev/null 2>&1; then echo 'FAIL: Missing storage helper accepted' >&2; exit 1; fi
echo 'PASS mocked K3s and Flux setup checks'