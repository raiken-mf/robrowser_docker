#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Relative Directory Traversal
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configurable environment variables
ROLE="${ROLE:-server}"                          # server | agent
K3S_URL="${K3S_URL:-}"                          # Required if ROLE=agent or joining control plane
K3S_TOKEN="${K3S_TOKEN:-}"                      # Required if ROLE=agent or joining control plane
INSTALL_LONGHORN="${INSTALL_LONGHORN:-true}"    # Enabled by default
STORAGE_DEVICE="${STORAGE_DEVICE:-}"            # e.g., /dev/sda (optional, auto-detected if empty)
MOUNTPOINT="${MOUNTPOINT:-/mnt/longhorn}"       # Target mountpoint for storage
LONGHORN_DATA_DIR="${MOUNTPOINT}/data"
REPLICA_COUNT="${REPLICA_COUNT:-1}"
ETCD_DIR="${ETCD_DIR:-/var/lib/rancher/k3s/server/db/etcd}"
ETCD_SSD_DIR="${ETCD_SSD_DIR:-$MOUNTPOINT/k3s-etcd-data}"
ETCD_FSROOT="/${ETCD_SSD_DIR#"$MOUNTPOINT"/}"
INITIALIZE_STORAGE="${INITIALIZE_STORAGE:-false}"
if [[ ! -r "${SCRIPT_DIR}/k8s-setup-storage.sh" ]]; then
  echo "ERROR: Missing storage helper: ${SCRIPT_DIR}/k8s-setup-storage.sh" >&2
  exit 1
fi
# shellcheck source=k8s-setup-storage.sh
source "${SCRIPT_DIR}/k8s-setup-storage.sh"

[[ "$ROLE" == server || "$ROLE" == agent ]] || { storage_fail 'ROLE must be server or agent.'; exit 1; }
[[ "$INITIALIZE_STORAGE" == true || "$INITIALIZE_STORAGE" == false ]] || { storage_fail 'INITIALIZE_STORAGE must be true or false.'; exit 1; }
[[ "$INITIALIZE_STORAGE" == false ]] || { storage_fail 'Automatic storage initialization is unsupported; prepare the SSD separately.'; exit 1; }
[[ "$INSTALL_LONGHORN" == true || "$INSTALL_LONGHORN" == false ]] || { storage_fail 'INSTALL_LONGHORN must be true or false.'; exit 1; }
[[ "$ROLE" != server || "$INSTALL_LONGHORN" != true || "$STORAGE_DEVICE" != skip ]] || { storage_fail 'Longhorn requires dedicated storage.'; exit 1; }
for command in sudo systemctl findmnt; do
  command -v "$command" >/dev/null 2>&1 || { storage_fail "Missing prerequisite: $command"; exit 1; }
done
sudo -v || { storage_fail 'Administrative access is required to inspect K3s state.'; exit 1; }
if sudo test -e /var/lib/robrowser-k3s-setup-in-progress; then
  storage_fail 'An earlier setup was interrupted; inspect and recover manually before retrying.'
  exit 1
fi
server_present=false
agent_present=false
if sudo test -e /etc/systemd/system/k3s.service || sudo test -e /var/lib/rancher/k3s/server; then server_present=true; fi
if sudo test -e /etc/systemd/system/k3s-agent.service || sudo test -e /var/lib/rancher/k3s/agent; then agent_present=true; fi
if [[ "$server_present" == true || "$agent_present" == true ]] || command -v k3s >/dev/null 2>&1 || sudo test -e /etc/rancher/k3s || sudo test -e /var/lib/rancher/k3s || sudo test -e /usr/local/bin/k3s || sudo test -e /etc/systemd/system/k3s.service.d; then
  if [[ "$ROLE" == server ]]; then
    sudo test -e /etc/systemd/system/k3s.service || { storage_fail 'Existing K3s state is incomplete or has a different role.'; exit 1; }
    sudo test ! -e /etc/systemd/system/k3s-agent.service || { storage_fail 'Conflicting K3s roles detected.'; exit 1; }
    systemctl is-active --quiet k3s.service || { storage_fail 'Existing K3s server is not active.'; exit 1; }
    if [[ "$STORAGE_DEVICE" != skip && ( "$INSTALL_LONGHORN" == true || -n "$STORAGE_DEVICE" ) ]]; then
      selected_device="$STORAGE_DEVICE"
      if [[ -z "$selected_device" ]]; then
        selected_device=$(findmnt -rn -M "$MOUNTPOINT" -o SOURCE) || { storage_fail 'Prepared storage is not mounted.'; exit 1; }
        selected_device=${selected_device%%\[*}
      fi
      validate_storage_device "$selected_device" "$MOUNTPOINT" >/dev/null || exit 1
      check_etcd_ssd_guard || exit 1
      if [[ "$INSTALL_LONGHORN" == true ]]; then
        current_uuid=$(findmnt -rn -M "$MOUNTPOINT" -o UUID) || exit 1
        mount_matches /var/lib/longhorn "$current_uuid" /data || { storage_fail 'Longhorn data mount mismatch.'; exit 1; }
        command -v kubectl >/dev/null 2>&1 || { storage_fail 'Missing prerequisite: kubectl'; exit 1; }
        kubectl -n longhorn-system get deployment longhorn-driver-deployer -o name >/dev/null || { storage_fail 'Longhorn is missing or inaccessible; no installation attempted.'; exit 1; }
      fi
    fi
  else
    sudo test -e /etc/systemd/system/k3s-agent.service || { storage_fail 'Existing K3s state is incomplete or has a different role.'; exit 1; }
    sudo test ! -e /etc/systemd/system/k3s.service || { storage_fail 'Conflicting K3s roles detected.'; exit 1; }
    systemctl is-active --quiet k3s-agent.service || { storage_fail 'Existing K3s agent is not active.'; exit 1; }
  fi
  echo 'Existing K3s installation verified; no changes made.'
  exit 0
fi
[[ "$ROLE" != agent || ( -n "$K3S_URL" && -n "$K3S_TOKEN" ) ]] || { storage_fail 'K3S_URL and K3S_TOKEN are required for an agent.'; exit 1; }
[[ -z "$K3S_URL" || -n "$K3S_TOKEN" ]] || { storage_fail 'K3S_TOKEN is required when joining a server.'; exit 1; }
[[ "$ROLE" != server || -z "$K3S_URL" ]] || { storage_fail 'Joining an existing server requires a separately reviewed procedure.'; exit 1; }
[[ "$MOUNTPOINT" =~ ^/[a-zA-Z0-9_./-]+$ && "$MOUNTPOINT" != / && "$MOUNTPOINT" != *..* && "$MOUNTPOINT" != *//* && "$MOUNTPOINT" != */ ]] || { storage_fail 'Unsafe storage mountpoint.'; exit 1; }
[[ "$ETCD_DIR" == /var/lib/rancher/k3s/server/db/etcd && "$ETCD_SSD_DIR" == "$MOUNTPOINT/"* && "$ETCD_SSD_DIR" != *..* && "$ETCD_SSD_DIR" != *//* ]] || { storage_fail 'Unsafe etcd paths.'; exit 1; }
[[ "$REPLICA_COUNT" =~ ^[1-9][0-9]*$ ]] || { storage_fail 'Invalid Longhorn replica count.'; exit 1; }
[[ "$EUID" -eq 0 ]] || { storage_fail 'New installations must run as root.'; exit 1; }
[[ -n "${K3S_INSTALLER:-}" && -f "$K3S_INSTALLER" && "${K3S_INSTALLER_SHA256:-}" =~ ^[a-fA-F0-9]{64}$ ]] || { storage_fail 'Provide K3S_INSTALLER and its trusted K3S_INSTALLER_SHA256.'; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { storage_fail 'Missing prerequisite: sha256sum'; exit 1; }
actual_sha=$(sha256sum "$K3S_INSTALLER")
[[ "${actual_sha%% *}" == "$K3S_INSTALLER_SHA256" ]] || { storage_fail 'K3s installer checksum mismatch.'; exit 1; }
if [[ "$INSTALL_LONGHORN" == true && "$ROLE" == server ]]; then
  for command in helm kubectl; do command -v "$command" >/dev/null 2>&1 || { storage_fail "Missing prerequisite: $command"; exit 1; }; done
fi

# Refuse existing unmounted etcd data before changing the host.
# Never re-run the upstream installer or overwrite kubeconfig on an existing node.
if sudo test -e /etc/systemd/system/k3s.service || sudo test -e /etc/systemd/system/k3s-agent.service || sudo test -e /var/lib/rancher/k3s/server/db/state.db; then
  if [[ "$ROLE" == server && "$STORAGE_DEVICE" != skip && ( "$INSTALL_LONGHORN" == true || -n "$STORAGE_DEVICE" ) ]]; then
    current_uuid=$(findmnt -rn -M "$MOUNTPOINT" -o UUID) || { storage_fail 'Existing server: SSD mount unavailable.'; exit 1; }
    mount_matches "$MOUNTPOINT" "$current_uuid" / && mount_matches "$ETCD_DIR" "$current_uuid" "$ETCD_FSROOT" || { storage_fail 'Existing server: SSD etcd mount is not configured; separate migration required.'; exit 1; }
    sudo test -e /etc/systemd/system/k3s.service.d/etcd-ssd.conf || { storage_fail 'Existing server: SSD start guard is missing.'; exit 1; }
  fi
  echo 'Existing K3s installation detected; no installation or configuration changes made.'
  exit 0
fi
echo "==> [1/6] Checking kernel and cgroup configurations..."
for cmdline_path in "/boot/firmware/cmdline.txt" "/boot/cmdline.txt"; do
  if [ -f "$cmdline_path" ]; then
    PARAMS="cgroup_memory=1 cgroup_enable=memory"
    if ! grep -qF "$PARAMS" "$cmdline_path"; then
      storage_fail "Missing cgroup parameters in $cmdline_path; configure and reboot before installation."
      exit 1
    fi
    break
  fi
done

echo "==> [2/6] Checking OS prerequisites for Longhorn..."
if [ "$INSTALL_LONGHORN" = "true" ]; then
  for command in iscsiadm mount.nfs cryptsetup pigz; do
    command -v "$command" >/dev/null 2>&1 || { storage_fail "Missing prerequisite: $command"; exit 1; }
  done
  systemctl is-active --quiet iscsid || { storage_fail 'iscsid must be active before installation.'; exit 1; }
fi

if [[ "$ROLE" == server && "$STORAGE_DEVICE" != skip && ( "$INSTALL_LONGHORN" == true || -n "$STORAGE_DEVICE" ) ]]; then
  for command in lsblk blkid readlink systemd-escape awk diff mount; do
    command -v "$command" >/dev/null 2>&1 || { storage_fail "Missing prerequisite: $command"; exit 1; }
  done
  [[ -r "${FSTAB_FILE:-/etc/fstab}" ]] || { storage_fail 'Cannot read fstab.'; exit 1; }
fi
setup_marked=false
mark_setup_started() {
  if [[ "$setup_marked" == false ]]; then
    sudo mkdir /var/lib/robrowser-k3s-setup-in-progress || { storage_fail 'Cannot create setup marker; manual review required.'; return 1; }
    setup_marked=true
  fi
}
echo "==> [3/6] Configuring storage..."
SSD_UUID=""
if [[ "$ROLE" == server && "$STORAGE_DEVICE" != skip && ( "$INSTALL_LONGHORN" == true || -n "$STORAGE_DEVICE" ) ]]; then
  if [[ -z "$STORAGE_DEVICE" ]]; then
    TARGET_PART=$(findmnt -rn -M "$MOUNTPOINT" -o SOURCE)
    TARGET_PART=${TARGET_PART%%\[*}
  else
    TARGET_PART=$STORAGE_DEVICE
  fi
  SSD_UUID=$(validate_storage_device "$TARGET_PART" "$MOUNTPOINT") || exit 1
  for target in "$MOUNTPOINT" "$ETCD_DIR" "$ETCD_SSD_DIR" "$LONGHORN_DATA_DIR" /var/lib/longhorn; do
    resolved_target=$(readlink -m "$target") || { storage_fail "Cannot resolve data path: $target"; exit 1; }
    [[ "$resolved_target" == "$target" ]] || { storage_fail "Data path contains a symbolic link: $target"; exit 1; }
  done
  reject_nested_mounts "$ETCD_DIR" "$ETCD_SSD_DIR" "$LONGHORN_DATA_DIR" /var/lib/longhorn || exit 1
  for target in "$ETCD_DIR" "$ETCD_SSD_DIR" "$LONGHORN_DATA_DIR" /var/lib/longhorn; do
    if sudo test -d "$target"; then
      existing_data=$(sudo find "$target" -mindepth 1 -maxdepth 1 -print -quit) || { storage_fail "Cannot inspect existing data: $target"; exit 1; }
      [[ -z "$existing_data" ]] || { storage_fail "Existing data requires manual review: $target"; exit 1; }
    fi
  done
  mount_matches "$MOUNTPOINT" "$SSD_UUID" / || { storage_fail "Wrong SSD mounted at $MOUNTPOINT"; exit 1; }
  expected_ssd_fstab="UUID=$SSD_UUID $MOUNTPOINT ext4 defaults,noatime,nofail 0 2"
  existing_ssd_fstab=$(awk -v target="$MOUNTPOINT" '$1 !~ /^#/ && $2 == target {print}' "${FSTAB_FILE:-/etc/fstab}") || exit 1
  [[ -z "$existing_ssd_fstab" || "$existing_ssd_fstab" == "$expected_ssd_fstab" ]] || { storage_fail 'Conflicting or duplicate SSD fstab entry.'; exit 1; }
  if [[ "$INSTALL_LONGHORN" == true ]]; then
    longhorn_fstab="$LONGHORN_DATA_DIR /var/lib/longhorn none bind,nofail,x-systemd.requires-mounts-for=$MOUNTPOINT 0 0"
    existing_longhorn_fstab=$(awk '$1 !~ /^#/ && $2 == "/var/lib/longhorn" {print}' "${FSTAB_FILE:-/etc/fstab}") || exit 1
    [[ -z "$existing_longhorn_fstab" || "$existing_longhorn_fstab" == "$longhorn_fstab" ]] || { storage_fail 'Conflicting or duplicate Longhorn fstab entry.'; exit 1; }
  fi
  mark_setup_started
  mount_matches "$MOUNTPOINT" "$SSD_UUID" / || { storage_fail "Wrong SSD mounted at $MOUNTPOINT"; exit 1; }
  if [[ "$INSTALL_LONGHORN" == true ]]; then
    longhorn_mount_state=$(mount_state /var/lib/longhorn) || exit 1
  fi
  ensure_fstab_entry "$MOUNTPOINT" "UUID=$SSD_UUID $MOUNTPOINT ext4 defaults,noatime,nofail 0 2"
  if [[ "$INSTALL_LONGHORN" == true ]]; then
  sudo mkdir -p "$LONGHORN_DATA_DIR" /var/lib/longhorn
  longhorn_fstab="$LONGHORN_DATA_DIR /var/lib/longhorn none bind,nofail,x-systemd.requires-mounts-for=$MOUNTPOINT 0 0"
  if [[ "$longhorn_mount_state" == mounted ]]; then
    mount_matches /var/lib/longhorn "$SSD_UUID" /data || { storage_fail 'Unexpected Longhorn mount; refusing to unmount.'; exit 1; }
    ensure_fstab_entry /var/lib/longhorn "$longhorn_fstab"
  else
    existing_data=$(sudo find /var/lib/longhorn -mindepth 1 -maxdepth 1 -print -quit) || { storage_fail 'Cannot inspect Longhorn data.'; exit 1; }
    [[ -z "$existing_data" ]] || { storage_fail 'Existing unmounted Longhorn data would be hidden; manual review required.'; exit 1; }
    ensure_fstab_entry /var/lib/longhorn "$longhorn_fstab"
    sudo systemctl daemon-reload
    sudo mount /var/lib/longhorn
    mount_matches /var/lib/longhorn "$SSD_UUID" /data || { storage_fail 'Longhorn bind mount validation failed'; exit 1; }
  fi
  fi
fi

echo "==> [4/6] Installing k3s (Role: $ROLE)..."
mark_setup_started
if [ "$ROLE" = "server" ]; then
  if [[ -n "$SSD_UUID" && -z "$K3S_URL" ]]; then
    if sudo test -e /etc/systemd/system/k3s.service && ! mount_matches "$ETCD_DIR" "$SSD_UUID" "$ETCD_FSROOT"; then
      storage_fail "Existing K3s installation without the validated SSD etcd mount; separate migration required."
      exit 1
    fi
    prepare_etcd_ssd "$SSD_UUID"
  fi
  if sudo test -e /etc/systemd/system/k3s.service || sudo test -s /var/lib/rancher/k3s/server/db/etcd/member/snap/db || sudo test -e /var/lib/rancher/k3s/server/db/state.db; then
    echo "--> Existing K3s installation detected; skipping installer."
  else
    K3S_KUBECONFIG_MODE="600" sh "$K3S_INSTALLER" server --cluster-init
  fi

  if [[ -n "$SSD_UUID" && -z "$K3S_URL" ]]; then
    mount_matches "$ETCD_DIR" "$SSD_UUID" "$ETCD_FSROOT" || { storage_fail "etcd is not on the selected SSD"; exit 1; }
    sudo test -s "$ETCD_DIR/member/snap/db" || { storage_fail "etcd database not yet present on SSD"; exit 1; }
  fi

  echo "--> Waiting for k3s configuration file..."
  sudo test -f /etc/rancher/k3s/k3s.yaml || { storage_fail 'K3s kubeconfig is unavailable.'; exit 1; }
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

elif [ "$ROLE" = "agent" ]; then
  if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
    echo "ERROR: K3S_URL and K3S_TOKEN are required for agent role."
    exit 1
  fi
  K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh "$K3S_INSTALLER"
fi

echo "==> [5/6] Checking Helm..."
if [ "$INSTALL_LONGHORN" = "true" ] && [ "$ROLE" = server ]; then
  command -v helm >/dev/null 2>&1 || { storage_fail 'Missing prerequisite: helm'; exit 1; }
fi

echo "==> [6/6] Longhorn Deployment..."
if [ "$INSTALL_LONGHORN" = "true" ] && [ "$ROLE" = server ]; then

  echo "--> Waiting for Kubernetes API & Node status..."
  kubectl get nodes >/dev/null || { storage_fail 'Kubernetes API unavailable; install Longhorn separately after recovery.'; exit 1; }

  longhorn_namespace=$(kubectl get namespace longhorn-system --ignore-not-found -o name) || { storage_fail 'Cannot inspect Longhorn namespace.'; exit 1; }
  [[ -z "$longhorn_namespace" ]] || { storage_fail 'Existing Longhorn namespace detected; refusing to modify it.'; exit 1; }
  helm repo add longhorn https://charts.longhorn.io
  helm repo update longhorn
  helm install longhorn longhorn/longhorn \
    --namespace longhorn-system \
    --create-namespace \
    --version 1.12.1 \
    --set defaultSettings.defaultReplicaCount="$REPLICA_COUNT" \
    --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
    --wait

fi

sudo rmdir /var/lib/robrowser-k3s-setup-in-progress || { storage_fail 'Cannot remove setup marker; manual review required.'; exit 1; }
echo "==> Done on $(hostname)."