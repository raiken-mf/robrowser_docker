# Fresh K3s, Longhorn and Flux cluster

This procedure is for an approved new installation. Do not use it to repair or
migrate an existing cluster. Back up existing data and verify the target host,
device and Kubernetes context before any change. These scripts have not been
validated on real hardware or a live cluster.

The complete new-installation path and mount-query failures are covered by
isolated mocks. Device, mount and systemd behavior still require hardware
integration tests. Do not run these scripts on a real host before hardware
validation and explicit approval.

## K3s and storage

Prepare Linux, systemd, memory cgroups, sudo, storage utilities, open-iscsi,
NFS utilities, cryptsetup, pigz, Helm and kubectl. Start iscsid separately.
Obtain a reviewed K3s installer and its SHA-256 from a trusted source; the
installer itself may download K3s artifacts. Review and pin its version and
artifact verification before execution. The script does not download the
installer or install host packages. It does not copy or overwrite a user
kubeconfig; the K3s system kubeconfig is created with mode 0600.

For a new server, prepare an ext4 partition on a separate SSD and mount it at
`/mnt/longhorn` before running the script. Select the partition, not the disk:

```bash
K3S_INSTALLER=/path/to/reviewed-install.sh \
K3S_INSTALLER_SHA256=REPLACE_WITH_TRUSTED_SHA256 \
STORAGE_DEVICE=/dev/REPLACE_WITH_SELECTED_DEVICE \
  sudo --preserve-env=K3S_INSTALLER,K3S_INSTALLER_SHA256,STORAGE_DEVICE bash scripts/sh/k8s/k8s-setup.sh
```

`INITIALIZE_STORAGE=true` is rejected. The setup never partitions or formats
storage. Existing unmounted
etcd or Longhorn data requires a separately planned, backed-up migration.
For an agent, set `ROLE=agent`, `K3S_URL` and `K3S_TOKEN` securely; do not put
tokens in shell history. Existing K3s installations are checked without running
the installer or changing mounts, kubeconfig or Longhorn. Some inconsistent or
partial states are rejected; this is not a recovery tool.
An interrupted setup leaves `/var/lib/robrowser-k3s-setup-in-progress`; inspect
the host and recover manually before removing it. Joining an existing server is
not supported by this setup script; the rejection is covered by an isolated
regression check and there is no server-join installer path.

The server installs Longhorn chart 1.12.1 only when its namespace is absent.
It does not change the default StorageClass. Verify Longhorn readiness, data
path, replica count and StorageClass before proceeding. The storage diagnostic
is read-only and requires access to the K3s API and system diagnostics:

```bash
bash scripts/sh/k8s/k8s-setup-storage.sh --check
```

## Flux

Install a compatible Flux CLI and kubectl separately and select an authorized
kubeconfig. Existing Flux is checked without bootstrap or reconciliation:

```bash
bash scripts/sh/k8s/k8s-setup-flux.sh --check
```

For a genuinely new cluster, first prepare a reviewed installation branch with
`ragnarok-stack` suspended and the installation-specific HOST configured. The
current main branch has an active child and is not an installation hold. Then:

```bash
GITHUB_BRANCH=REVIEWED_INSTALL_BRANCH bash scripts/sh/k8s/k8s-setup-flux.sh
```

The script requires the exact confirmation `BOOTSTRAP` and a GitHub token via
environment or hidden prompt. Bootstrap changes the cluster and can commit and
push to GitHub. It creates a write-enabled SSH deploy key for image automation;
the private key is stored in a Kubernetes Secret. Defaults are owner `raiken-mf`, repository `robrowser_docker`,
branch `main`, path `deploy/clusters/default`, and both image controllers.
Existing Flux drift or incomplete resources cause an error, not an automatic
repair. Never print tokens, kubeconfigs or credential-bearing URLs.

## Ragnarok GitOps

After K3s, storage, Longhorn and Flux are ready, provision the MariaDB operator
and follow the [fresh stack runbook](fresh-install-runbook.md). Keep the
application reconcilers paused until the controlled activation described in
[GitOps](gitops.md#controlled-first-activation).
