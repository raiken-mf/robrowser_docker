#!/usr/bin/env bash
# Shared storage safety checks; this file does not change the host when sourced.

storage_fail() { echo "ERROR: $*" >&2; return 1; }

mount_state() {
  local target=$1 mounts
  mounts=$(findmnt -rn -o TARGET) || { storage_fail 'Cannot inspect mount table.'; return 2; }
  [[ -n "$mounts" ]] || { storage_fail 'Mount table is empty.'; return 2; }
  if grep -Fxq -- "$target" <<<"$mounts"; then
    printf '%s\n' mounted
  else
    printf '%s\n' absent
  fi
}

mount_matches() {
  local target=$1 uuid=$2 root=$3 actual_uuid actual_root
  actual_uuid=$(findmnt -rn -M "$target" -o UUID) || return 1
  actual_root=$(findmnt -rn -M "$target" -o FSROOT) || return 1
  [[ "$actual_uuid" == "$uuid" && "$actual_root" == "$root" ]]
}

reject_nested_mounts() {
  local mounts target path
  mounts=$(findmnt -rn -o TARGET) || { storage_fail 'Cannot inspect mount table.'; return 1; }
  [[ -n "$mounts" ]] || { storage_fail 'Mount table is empty.'; return 1; }
  while IFS= read -r target; do
    for path in "$@"; do
      case "$target" in
        "$path"|"$path"/*) storage_fail "Existing mount requires manual review: $target"; return 1 ;;
      esac
    done
  done <<<"$mounts"
}

validate_storage_device() {
  local device=$1 mountpoint=$2 root_device root_tree storage_tree root_disks storage_disks disk uuid matches mounted_source mounted_type mounts target
  [[ "$device" == /dev/* ]] && test -b "$device" || { storage_fail 'Storage must be a block device under /dev.'; return 1; }
  device=$(readlink -f "$device") || { storage_fail 'Cannot resolve storage device.'; return 1; }
  [[ $(lsblk -dn -o TYPE "$device") == part ]] || { storage_fail 'Select a prepared partition, not a whole disk.'; return 1; }
  root_device=$(findmnt -rn -M / -o SOURCE) || { storage_fail 'Cannot identify root filesystem.'; return 1; }
  root_device=${root_device%%\[*}
  [[ "$root_device" == /dev/* ]] && test -b "$root_device" || { storage_fail 'Root filesystem is not backed by an identifiable block device.'; return 1; }
  root_tree=$(lsblk -s -nrpo NAME,TYPE "$root_device") || { storage_fail 'Cannot inspect root device hierarchy.'; return 1; }
  storage_tree=$(lsblk -s -nrpo NAME,TYPE "$device") || { storage_fail 'Cannot inspect storage device hierarchy.'; return 1; }
  root_disks=$(awk '$2 == "disk" {print $1}' <<<"$root_tree")
  storage_disks=$(awk '$2 == "disk" {print $1}' <<<"$storage_tree")
  [[ -n "$root_disks" && -n "$storage_disks" ]] || { storage_fail 'Cannot identify physical root and storage disks.'; return 1; }
  while IFS= read -r disk; do
    if grep -Fxq -- "$disk" <<<"$root_disks"; then
      storage_fail 'Storage shares a physical disk with the root filesystem.'; return 1
    fi
  done <<<"$storage_disks"
  uuid=$(sudo blkid -s UUID -o value "$device") || { storage_fail 'Cannot determine storage UUID.'; return 1; }
  [[ "$uuid" =~ ^[a-zA-Z0-9-]+$ && $(sudo blkid -s TYPE -o value "$device") == ext4 ]] || { storage_fail 'Storage must have an ext4 filesystem and UUID.'; return 1; }
  matches=$(sudo blkid -c /dev/null -t "UUID=$uuid" -o device) || { storage_fail 'Cannot verify storage UUID uniqueness.'; return 1; }
  [[ "$matches" == "$device" ]] || { storage_fail 'Storage UUID is ambiguous or resolves to another device.'; return 1; }
  mounted_source=$(findmnt -rn -M "$mountpoint" -o SOURCE) || { storage_fail 'Prepared storage must already be mounted.'; return 1; }
  mounted_source=${mounted_source%%\[*}
  mounted_source=$(readlink -f "$mounted_source") || { storage_fail 'Cannot resolve mounted storage.'; return 1; }
  mounted_type=$(findmnt -rn -M "$mountpoint" -o FSTYPE) || { storage_fail 'Cannot inspect mounted filesystem.'; return 1; }
  [[ "$mounted_source" == "$device" && "$mounted_type" == ext4 ]] && mount_matches "$mountpoint" "$uuid" / || { storage_fail 'Mounted storage does not match the selected ext4 filesystem.'; return 1; }
  mounts=$(findmnt -rn -S "$device" -o TARGET) || { storage_fail 'Cannot inspect storage mounts.'; return 1; }
  [[ -n "$mounts" ]] || { storage_fail 'Storage mount list is empty.'; return 1; }
  while IFS= read -r target; do
    case "$target" in
      "$mountpoint"|"${ETCD_DIR:-/var/lib/rancher/k3s/server/db/etcd}"|/var/lib/longhorn) ;;
      *) storage_fail 'Storage is mounted at an unexpected location.'; return 1 ;;
    esac
  done <<<"$mounts"
  printf '%s\n' "$uuid"
}

write_if_missing_or_equal() {
  local target=$1 content=$2
  if sudo test -e "$target"; then
    diff -q <(printf '%s\n' "$content") <(sudo cat "$target") >/dev/null || storage_fail "Conflicting configuration: $target"
  else
    printf '%s\n' "$content" | sudo tee "$target" >/dev/null
  fi
}

ensure_fstab_entry() {
  local target=$1 line=$2 existing fstab_file="${FSTAB_FILE:-/etc/fstab}"
  [[ -r "$fstab_file" ]] || { storage_fail "Cannot read $fstab_file"; return 1; }
  existing=$(awk -v target="$target" '$1 !~ /^#/ && $2 == target {print}' "$fstab_file")
  if [[ -n "$existing" ]]; then
    [[ "$existing" == "$line" ]] || storage_fail "Conflicting or duplicate fstab entry for $target"
  else
    printf '%s\n' "$line" | sudo tee -a "$fstab_file" >/dev/null
  fi
}

prepare_etcd_ssd() {
  local uuid=$1 source="${ETCD_SSD_DIR:-$MOUNTPOINT/k3s-etcd-data}" target="$ETCD_DIR" ssd_unit etcd_unit srcroot state
  [[ "$MOUNTPOINT" =~ ^/[a-zA-Z0-9_./-]+$ && "$target" =~ ^/[a-zA-Z0-9_./-]+$ && "$uuid" =~ ^[a-zA-Z0-9-]+$ ]] || storage_fail 'Unsafe path or UUID' || return 1
  [[ "$source" == "$MOUNTPOINT/"* && "$source" =~ ^/[a-zA-Z0-9_./-]+$ && "$source" != *..* && "$source" != *//* ]] || storage_fail "Unsafe SSD etcd source path" || return 1
  mount_matches "$MOUNTPOINT" "$uuid" / || storage_fail "SSD missing or wrong at $MOUNTPOINT" || return 1
  ssd_unit=$(systemd-escape -p --suffix=mount "$MOUNTPOINT")
  etcd_unit=$(systemd-escape -p --suffix=mount "$target")
  srcroot="/${source#"$MOUNTPOINT"/}"
  state=$(mount_state "$target") || return 1
  if [[ "$state" == mounted ]]; then
    mount_matches "$target" "$uuid" "$srcroot" || storage_fail "Wrong existing etcd mount at $target" || return 1
  elif sudo test -d "$target" && [[ -n "$(sudo find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    storage_fail "Existing etcd data at $target: stop and use a separately planned, backed-up migration; automatic migration is disabled." || return 1
  elif sudo test -d "$source" && [[ -n "$(sudo find "$source" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    storage_fail "Existing SSD etcd data at $source without the active bind mount; manual recovery required." || return 1
  fi
  sudo mkdir -p "$source" "$target" /etc/systemd/system/k3s.service.d
  sudo chmod 700 "$source"
  local mount_config dropin
  mount_config="[Unit]
Description=K3s embedded etcd data on SSD
Requires=$ssd_unit
After=$ssd_unit
Before=k3s.service

[Mount]
What=$source
Where=$target
Type=none
Options=bind"
  dropin="[Unit]
Requires=$ssd_unit $etcd_unit
After=$ssd_unit $etcd_unit
BindsTo=$etcd_unit

[Service]
ExecStartPre=/usr/bin/findmnt --mountpoint $MOUNTPOINT --source UUID=$uuid --noheadings
ExecStartPre=/usr/bin/mountpoint -q $target
ExecStartPre=/bin/sh -c 'uuid=\$\$(findmnt -n -o UUID --mountpoint $target) && root=\$\$(findmnt -n -o FSROOT --mountpoint $target) && test \"\$\$uuid\" = $uuid && test \"\$\$root\" = $srcroot'"
  write_if_missing_or_equal "/etc/systemd/system/$etcd_unit" "$mount_config" || return 1
  write_if_missing_or_equal /etc/systemd/system/k3s.service.d/etcd-ssd.conf "$dropin" || return 1
  sudo systemctl daemon-reload
  state=$(mount_state "$target") || return 1
  if [[ "$state" == absent ]]; then sudo systemctl start "$etcd_unit"; fi
  mount_matches "$target" "$uuid" "$srcroot" || storage_fail 'etcd bind mount validation failed'
}

check_etcd_ssd_guard() {
  local mountpoint="${MOUNTPOINT:-/mnt/longhorn}"
  local etcd_dir="${ETCD_DIR:-/var/lib/rancher/k3s/server/db/etcd}"
  local etcd_ssd_dir="${ETCD_SSD_DIR:-$mountpoint/k3s-etcd-data}"
  local srcroot="/${etcd_ssd_dir#"$mountpoint"/}"
  local fstab_file="${FSTAB_FILE:-/etc/fstab}"
  local uuid etcd_unit ssd_unit enabled_state restart_policy expected_mount expected_dropin
  uuid=$(findmnt -rn -M "$mountpoint" -o UUID) || { storage_fail "SSD not mounted at $mountpoint"; return 1; }
  mount_matches "$mountpoint" "$uuid" / || { storage_fail "SSD root mount mismatch at $mountpoint"; return 1; }
  mount_matches "$etcd_dir" "$uuid" "$srcroot" || { storage_fail "etcd bind mount mismatch at $etcd_dir (expected UUID=$uuid FSROOT=$srcroot)"; return 1; }
  etcd_unit=$(systemd-escape -p --suffix=mount "$etcd_dir")
  ssd_unit=$(systemd-escape -p --suffix=mount "$mountpoint")
  sudo test -e "/etc/systemd/system/$etcd_unit" || { storage_fail "Missing systemd mount unit /etc/systemd/system/$etcd_unit"; return 1; }
  sudo test -e /etc/systemd/system/k3s.service.d/etcd-ssd.conf || { storage_fail 'Missing systemd start guard /etc/systemd/system/k3s.service.d/etcd-ssd.conf'; return 1; }
  expected_mount="[Unit]
Description=K3s embedded etcd data on SSD
Requires=$ssd_unit
After=$ssd_unit
Before=k3s.service

[Mount]
What=$etcd_ssd_dir
Where=$etcd_dir
Type=none
Options=bind"
  expected_dropin="[Unit]
Requires=$ssd_unit $etcd_unit
After=$ssd_unit $etcd_unit
BindsTo=$etcd_unit

[Service]
ExecStartPre=/usr/bin/findmnt --mountpoint $mountpoint --source UUID=$uuid --noheadings
ExecStartPre=/usr/bin/mountpoint -q $etcd_dir
ExecStartPre=/bin/sh -c 'uuid=\$\$(findmnt -n -o UUID --mountpoint $etcd_dir) && root=\$\$(findmnt -n -o FSROOT --mountpoint $etcd_dir) && test \"\$\$uuid\" = $uuid && test \"\$\$root\" = $srcroot'"
  diff -q <(printf '%s\n' "$expected_mount") <(sudo cat "/etc/systemd/system/$etcd_unit") >/dev/null || { storage_fail 'Conflicting etcd mount unit.'; return 1; }
  diff -q <(printf '%s\n' "$expected_dropin") <(sudo cat /etc/systemd/system/k3s.service.d/etcd-ssd.conf) >/dev/null || { storage_fail 'Conflicting etcd start guard.'; return 1; }
  [[ -r "$fstab_file" ]] || { storage_fail "Cannot read $fstab_file"; return 1; }
  awk -v mp="$mountpoint" -v uuid="$uuid" '$1 !~ /^#/ && $2 == mp {count++; if ($1 != "UUID=" uuid || $3 != "ext4" || $4 !~ /(^|,)nofail(,|$)/) bad=1} END {exit (count != 1 || bad)}' "$fstab_file" || {
    storage_fail "$fstab_file has a missing, duplicate or conflicting SSD entry"
    return 1
  }
  if [[ "${INSTALL_LONGHORN:-true}" == true ]]; then
    awk -v mp="$mountpoint" '$1 !~ /^#/ && $2 == "/var/lib/longhorn" {count++; if ($1 != mp "/data" || $3 != "none" || $4 !~ /(^|,)bind(,|$)/ || $4 !~ /(^|,)nofail(,|$)/ || index("," $4 ",", ",x-systemd.requires-mounts-for=" mp ",") == 0) bad=1} END {exit (count != 1 || bad)}' "$fstab_file" || {
      storage_fail "$fstab_file has a missing, duplicate or conflicting Longhorn entry"
      return 1
    }
    mount_matches /var/lib/longhorn "$uuid" /data || { storage_fail 'Longhorn bind mount mismatch'; return 1; }
  fi
  enabled_state=$(systemctl is-enabled k3s.service 2>/dev/null || true)
  [[ "$enabled_state" == enabled ]] || { storage_fail "k3s.service autostart is '$enabled_state' (expected enabled)"; return 1; }
  restart_policy=$(systemctl show k3s.service -p Restart --value 2>/dev/null || true)
  [[ "$restart_policy" == always ]] || { storage_fail "k3s.service Restart policy is '$restart_policy' (expected always)"; return 1; }
  echo "SSD/etcd guard: OK (UUID=$uuid, mount=$etcd_dir, k3s=enabled/Restart=always)"
}

check_sd_capacity_and_io() {
  local root_mount="${ROOT_MOUNT:-/}"
  local max_use="${MAX_ROOT_USE_PERCENT:-80}"
  local max_inodes="${MAX_INODE_USE_PERCENT:-50}"
  local disk_name="${ROOT_DISK_NAME:-mmcblk0}"
  local sample_sec="${IO_SAMPLE_SECONDS:-1}"
  local max_r_iops="${MAX_SD_READ_IOPS:-500}"
  local max_util="${MAX_SD_UTIL_PERCENT:-70}"
  local diskstats_file="${PROC_DISKSTATS:-/proc/diskstats}"
  local stat_file="${PROC_STAT:-/proc/stat}"
  local use_pct inode_pct avail_kb
  read -r use_pct avail_kb < <(df -Pk "$root_mount" | awk 'NR==2 {gsub(/%/,"",$5); print $5, $4}')
  inode_pct=$(df -Pi "$root_mount" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  [[ -n "$use_pct" && -n "$inode_pct" ]] || { storage_fail "Unable to read df metrics for $root_mount"; return 1; }
  (( use_pct <= max_use )) || { storage_fail "Root filesystem usage ${use_pct}% exceeds ${max_use}% threshold"; return 1; }
  (( inode_pct <= max_inodes )) || { storage_fail "Root filesystem inode usage ${inode_pct}% exceeds ${max_inodes}% threshold (possible snapshot/extraction leak)"; return 1; }
  if [[ -r "$diskstats_file" && -r "$stat_file" ]] && awk -v d="$disk_name" '$3 == d {found=1} END {exit !found}' "$diskstats_file"; then
    local r1 w1 ticks1 cpu1 r2 w2 ticks2 cpu2
    read -r r1 w1 ticks1 < <(awk -v d="$disk_name" '$3 == d {print $4, $8, $13; exit}' "$diskstats_file")
    cpu1=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $6; exit}' "$stat_file")
    if (( sample_sec > 0 )); then
      sleep "$sample_sec"
    fi
    if [[ -n "${PROC_DISKSTATS_AFTER:-}" && -r "${PROC_DISKSTATS_AFTER}" ]]; then
      read -r r2 w2 ticks2 < <(awk -v d="$disk_name" '$3 == d {print $4, $8, $13; exit}' "$PROC_DISKSTATS_AFTER")
    else
      read -r r2 w2 ticks2 < <(awk -v d="$disk_name" '$3 == d {print $4, $8, $13; exit}' "$diskstats_file")
    fi
    if [[ -n "${PROC_STAT_AFTER:-}" && -r "${PROC_STAT_AFTER}" ]]; then
      cpu2=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $6; exit}' "$PROC_STAT_AFTER")
    else
      cpu2=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $6; exit}' "$stat_file")
    fi
    local divisor=$(( sample_sec > 0 ? sample_sec : 1 ))
    local read_iops=$(( (r2 - r1) / divisor ))
    local write_iops=$(( (w2 - w1) / divisor ))
    local util_pct=$(( (ticks2 - ticks1) / (divisor * 10) ))
    (( util_pct > 100 )) && util_pct=100
    local tot1=${cpu1% *} iow1=${cpu1#* } tot2=${cpu2% *} iow2=${cpu2#* }
    local dtot=$(( tot2 - tot1 ))
    local iowait_pct=0
    if (( dtot > 0 )); then
      iowait_pct=$(( (iow2 - iow1) * 100 / dtot ))
    fi
    echo "SD I/O & capacity: disk=$disk_name used=${use_pct}% (avail=$((avail_kb / 1024))MiB) inodes=${inode_pct}% read_iops=${read_iops} write_iops=${write_iops} util=${util_pct}% iowait=${iowait_pct}%"
    (( read_iops <= max_r_iops )) || { storage_fail "SD read IOPS (${read_iops}/s) exceeds ${max_r_iops}/s threshold (possible containerd DiskUsage thrashing)"; return 1; }
    (( util_pct <= max_util )) || { storage_fail "SD utilization (${util_pct}%) exceeds ${max_util}% threshold"; return 1; }
  else
    echo "SD capacity: used=${use_pct}% (avail=$((avail_kb / 1024))MiB) inodes=${inode_pct}%"
  fi
}

check_containerd_snapshots_and_leases() {
  local max_extract="${MAX_EXTRACT_SNAPSHOTS:-3}"
  local max_temp_leases="${MAX_TEMP_LEASES:-20}"
  local max_gc_errors="${MAX_JOURNAL_GC_ERRORS:-3}"
  local snaps_out leases_out total_snaps active_snaps committed_snaps extract_snaps total_leases temp_leases gc_errors
  snaps_out=$(sudo k3s ctr snapshots ls 2>/dev/null) || { storage_fail 'Unable to query k3s containerd snapshots'; return 1; }
  read -r total_snaps active_snaps committed_snaps extract_snaps < <(
    awk 'NR>1 && NF>=3 {
      total++
      if ($1 ~ /^extract-/) extract++
      if ($3 == "Active") active++
      if ($3 == "Committed") committed++
    } END {printf "%d %d %d %d\n", total+0, active+0, committed+0, extract+0}' <<<"$snaps_out"
  )
  leases_out=$(sudo k3s ctr leases ls 2>/dev/null) || { storage_fail 'Unable to query k3s containerd leases'; return 1; }
  read -r total_leases temp_leases < <(
    awk 'NR>1 && NF>=1 {
      total++
      if ($0 ~ /containerd\.io\/gc\.expire|content_unpack|mediatype/) temp++
    } END {printf "%d %d\n", total+0, temp+0}' <<<"$leases_out"
  )
  echo "Containerd state: snapshots=${total_snaps} (active=${active_snaps}, committed=${committed_snaps}, extract=${extract_snaps}) leases=${total_leases} (temp_gc=${temp_leases})"
  (( extract_snaps <= max_extract )) || {
    storage_fail "Containerd has ${extract_snaps} active extract-* snapshots (threshold ${max_extract}); aborted image extraction loop suspected"
    return 1
  }
  (( temp_leases <= max_temp_leases )) || {
    storage_fail "Containerd has ${temp_leases} temporary GC leases (threshold ${max_temp_leases}); stale leases may block snapshot garbage collection"
    return 1
  }
  if command -v journalctl >/dev/null 2>&1; then
    gc_errors=$(sudo journalctl -u k3s --since "-15min" --no-pager -q 2>/dev/null | grep -Ec 'PullImage.*context deadline exceeded|cleanupDirectories.*failed|failed to reserve sandbox name' || true)
    (( gc_errors < max_gc_errors )) || {
      storage_fail "Detected ${gc_errors} recent K3s image extraction/GC timeout errors in journalctl (last 15m)"
      return 1
    }
  fi
}

check_kubelet_image_gc() {
  local node_name="${NODE_NAME:-$(hostname)}"
  local configz_json parsed high low min_age serialize
  configz_json=$(sudo k3s kubectl get --raw "/api/v1/nodes/${node_name}/proxy/configz" 2>/dev/null) || {
    storage_fail "Unable to query Kubelet configz for node ${node_name}"
    return 1
  }
  parsed=$(python3 -c '
import json, sys
cfg = json.load(sys.stdin).get("kubeletconfig", {})
high = int(cfg.get("imageGCHighThresholdPercent", 0))
low = int(cfg.get("imageGCLowThresholdPercent", 0))
min_age = str(cfg.get("imageMinimumGCAge", "unknown"))
ser = str(bool(cfg.get("serializeImagePulls", False))).lower()
print(f"{high} {low} {min_age} {ser}")
' <<<"$configz_json") || { storage_fail 'Failed to parse Kubelet configz JSON'; return 1; }
  read -r high low min_age serialize <<<"$parsed"
  (( low > 0 && low < high && high <= 90 )) || {
    storage_fail "Invalid Kubelet ImageGC thresholds: low=${low}% high=${high}%"
    return 1
  }
  echo "Kubelet ImageGC: high=${high}% low=${low}% minAge=${min_age} serializeImagePulls=${serialize}"
  if [[ "$serialize" == false ]]; then
    echo "NOTE: Kubelet serializeImagePulls=false; pull or roll out large images sequentially on SD storage."
  fi
}

check_k3s_storage_health() {
  check_etcd_ssd_guard || return 1
  check_sd_capacity_and_io || return 1
  check_containerd_snapshots_and_leases || return 1
  check_kubelet_image_gc || return 1
  echo "OK: K3s SSD etcd guards, SD capacity/inodes/I/O, containerd snapshots/leases, and Kubelet ImageGC verified (read-only)."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:---check}" in
    --check) check_k3s_storage_health ;;
    *) storage_fail "Usage: bash scripts/sh/k8s/k8s-setup-storage.sh [--check] (read-only diagnostics only)" || exit 2 ;;
  esac
fi