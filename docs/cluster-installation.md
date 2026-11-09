# Fresh K3s, Longhorn and Flux cluster

This procedure is for a **new cluster**, not an existing installation. For an existing
cluster use the [fresh stack runbook](fresh-install-runbook.md) or
[normal operations](operations.md). The final documentation cleanup executes
none of the installation/bootstrap commands below.

## Infrastructure source and prerequisites

The infrastructure scripts are in the separate
[custom-scripts repository](https://github.com/raiken-mf/custom-scripts), under
sh/setup-k8s.sh and sh/setup-k8s-flux.sh. Their local source was inspected at
commit `7220a191bd06b0ece8b5e42a1f3a04f56751d838`; it was not changed. Reinspect
later versions rather than assuming this description remains exact.
These helpers include Raspberry Pi-specific setup and are optional; other Linux
hosts can provision compatible Kubernetes, Longhorn and Flux independently.

Prepare the host OS/network, a deliberately selected storage device, console/admin
access, and a kubeconfig/context identifying the intended cluster. Preserve any
existing data. The application additionally needs Git, kubectl, Python 3, bash,
envsubst, tar and local client resources; local development/tests need Docker.

## K3s and Longhorn: setup-k8s.sh

The inspected script:

- Adds Raspberry Pi memory-cgroup boot parameters when missing; a reboot may be required.
- Defaults ROLE=server, INSTALL_LONGHORN=true, MOUNTPOINT=/mnt/longhorn and
  REPLICA_COUNT=1. K3S_URL/K3S_TOKEN are required for an agent/join operation.
- Installs iSCSI/NFS/storage prerequisites. If STORAGE_DEVICE is unset, it can
  auto-detect a non-root disk. After an explicit formatting prompt it can
  repartition/format it, change fstab and configure Longhorn/bind mounts.
  Declining formatting still uses/configures the existing partition and mounts.
- Installs K3s via the upstream installer (no fixed K3s version in this script),
  copies the server kubeconfig to the real user's ~/.kube/config with mode 0600,
  and may persist KUBECONFIG in .bashrc. The installer invocation uses
  K3S_KUBECONFIG_MODE=644 for the system file; protect kubeconfig access accordingly.
- Installs Helm when needed and installs/upgrades the Longhorn chart at 1.12.1
  with defaultReplicaCount and /var/lib/longhorn data path. It marks local-path
  non-default; verify the actual Longhorn StorageClass/default/replica settings.
  A chart default does not necessarily rewrite an existing StorageClass.

Example interface, **only after explicit new-cluster/storage approval**:

```bash
# Run from the separately reviewed custom-scripts checkout.
bash sh/setup-k8s.sh
```

Do not run this to repair a healthy cluster, PVC or application. Check the device
and prompt yourself; do not automate a yes response. No new infrastructure
installation was re-executed as part of the final documentation verification.

## Verify the intended context and storage

On the target host, the setup script normally provides ~/.kube/config. Application scripts
otherwise default to the K3s system path; explicitly select the correct file:

```bash
export KUBECONFIG="$HOME/.kube/config"
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storageclass
kubectl -n longhorn-system get pods
```

For remote administration use an authorized kubeconfig with the correct reachable
server address, not an unreviewed copy pointing at localhost. Do not print tokens
or kubeconfig contents into logs/chat.

## Flux bootstrap: setup-k8s-flux.sh

The inspected wrapper checks API access, obtains GITHUB_TOKEN by a hidden prompt
if absent, installs the Flux CLI if missing, runs `flux check --pre`, then calls
`flux bootstrap github` with:

- owner GITHUB_USER (default raiken-mf), repository positional argument/default
  robrowser_docker;
- GITHUB_BRANCH (default main) and CLUSTER_PATH (use the path explicitly reviewed
  in the installation branch; the first migration phase retains clusters/pi-cluster);
- the extra image-reflector/image-automation controllers and --personal;
- KUBECONFIG from the caller, otherwise ~/.kube/config with a system-file fallback.

It writes bootstrap resources/commits and starts reconciliation. It does **not**
create application Secrets from `.env`, populate client data, install the MariaDB
operator, or automatically suspend either Kustomization.

### Gate a genuinely fresh cluster before application reconciliation

Current main describes an **active** ragnarok-stack (suspend:false). Bootstrapping
it onto an empty cluster can start the stack before private prerequisites exist.
Do not use the normal active main as though it were a paused installation plan.

For a new cluster, first prepare an operator-reviewed installation branch with
the same deploy/clusters/default path in its parent manifest and an explicit
ragnarok-stack suspend:true. This path change is installation-specific and must
not be merged into main as part of the first migration phase.
Set the child Kustomization's HOST patch to the new installation's browser-reachable
hostname or IP; the existing value belongs only to the original installation.
Keep the running cluster on its existing main; do not merge a global pause as
part of documentation maintenance. Bootstrap that reviewed branch, for example:

```bash
# Interface example: INSTALL_BRANCH must already exist and hold the child paused.
: "${INSTALL_BRANCH:?Set the existing reviewed installation branch first}"
GITHUB_BRANCH="$INSTALL_BRANCH" CLUSTER_PATH=deploy/clusters/default \
  bash sh/setup-k8s-flux.sh robrowser_docker
```

This branch-based fresh-cluster gate is derived from the inspected interfaces;
it was **not re-executed/claimed as a new verified install** during this cleanup.
Never use a nonexistent placeholder branch. Verify the child is suspended before
pausing the parent for manual application bootstrap. Any suspend/resume commands
are installation actions requiring their own approval, not normal health checks.

## Complete prerequisites before the application

Longhorn alone is insufficient. The application requires a ready MariaDB operator,
webhook and k8s.mariadb.com CRDs; K3s/Longhorn setup does not supply them. The
existing [k8s-mariadb.sh](https://github.com/raiken-mf/robrowser_docker/blob/main/scripts/sh/k8s/k8s-mariadb.sh) can install/upgrade that operator
but ALSO creates application resources/secrets, so it is not a harmless check.
Have the operator provision the required infrastructure in an approved stage.
In the verified example installation it was already available before k8s-all.sh.

Continue with [fresh Ragnarok installation](fresh-install-runbook.md), keeping
both application reconcilers paused until their controlled activation. Future
moves from a staging branch to main must be reviewed in both the GitRepository
spec and bootstrap files; do not repeat bootstrap against the running cluster.
