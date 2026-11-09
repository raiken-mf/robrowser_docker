# roBrowser stack documentation

The stack has a Node.js/Vite frontend (`robrowser`) and an independent Apache/PHP
RemoteClient (`remote`). MariaDB, rAthena login/character/map and wsProxy provide
the game services. See the [repository README](https://github.com/raiken-mf/robrowser_docker/blob/main/README.md) for architecture
and local client-file layout.

## Installation versus operation

| Situation | Procedure |
| --- | --- |
| New cluster, no K3s or Longhorn | [Cluster installation](cluster-installation.md) |
| Cluster exists, Ragnarok stack is new | [Fresh Ragnarok installation](fresh-install-runbook.md) |
| Stack already runs under Flux | [Operations and rollback](operations.md) |
| Local Docker/rAthena or Hercules | [Deployment and configuration](deployment.md) |

Do not use infrastructure setup, namespace resets or `k8s-all.sh --apply` for
routine GitOps updates. `k8s-all.sh --check` is a **bootstrap** check and rejects
active Flux reconcilers; use the read-only checks in the operations guide on an
already active cluster.

## Current validation record

As confirmed by the operator on 2026-11-02: K3s and Longhorn work; `flux-system`
and `ragnarok-stack` are active/Ready, last confirmed application revision
`109430d1`; seven Ragnarok pods are Running and ready, and browser login works.
PRs #87, #88, #89 and #90 are merged. Historical instructions to keep this
namespace deleted or Flux permanently suspended no longer describe operation.

[Validation coverage](validation.md) distinguishes executed checks from future
installation examples. Graphical/Lua/GRF-content issues remain separate work.

## Reference

- [GitOps lifecycle and release approval](gitops.md)
- [Image tags, digests and source revisions](image-revisions.md)
- [Upstream updates](upstream-updates.md)
- [Security and private configuration](security.md)
- [Development and offline tests](development.md)
- [Vite iframe regression](frontend-api-module.md)
