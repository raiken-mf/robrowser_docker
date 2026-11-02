# roBrowser Docker and Kubernetes stack

Ragnarok Online with separate `robrowser` frontend, `remote` client-file service,
wsProxy, rAthena and MariaDB. Docker Compose and Kubernetes/FluxCD are supported;
Hercules is available through the Compose overlay.

| Service | Role | Internal port | External setting |
| --- | --- | --- | --- |
| robrowser | Node.js/Vite + pinned roBrowserLegacy | 3000 | PORT_FRONTEND |
| remote | Apache/PHP 8.4, RemoteClient, ROEnglishRE, GRF/BGM/AI | 8080 | PORT_HTTP |
| wsproxy | WebSocket bridge to the game services | 5999 | PORT_WSPROXY |
| ragnarok-login / char / map | rAthena game services | 6900 / 6121 / 5121 | Internal cluster services |

## Choose the correct procedure

- **New cluster:** [K3s, Longhorn and Flux bootstrap](docs/cluster-installation.md).
  Infrastructure scripts live in the separate `custom-scripts` repository.
- **New Ragnarok stack on an existing cluster:** [Fresh-install runbook](docs/fresh-install-runbook.md).
  `k8s-all.sh --check` is read-only; `--apply` needs installation approval and
  requires existing Flux reconcilers to be paused. It never deletes a namespace.
- **Existing GitOps cluster:** [Operations and recovery](docs/operations.md).
  Use reviewed Git changes. Do not rerun cluster setup or the fresh installer.
- **Local Docker:** [Compose deployment and configuration](docs/deployment.md).

## Verified Pi baseline

On 2026-11-02 the operator confirmed K3s/Longhorn working, both Flux
Kustomizations active and Ready at application revision `109430d1`, and all
seven Ragnarok pods Running/ready. Browser login succeeded after PRs #87–#90.
This is a dated validation record, not a permanent revision or pod-name target.
Remaining graphics, Lua, GRF-content and client errors are separate follow-up
work; they are not addressed by this documentation update.

## Local configuration and client assets

Prepare `.env` from `.env-tmpl` only when no local configuration exists:

```bash
test -f .env || cp .env-tmpl .env
```

Edit it locally; never commit it or credentials. `client/resources/DATA.INI`
(case-sensitive) must reference the available GRFs. Keep AI, BGM, data and System
files in their corresponding `client/` folders. Existing local files and
`repository_override` payloads must be preserved across checkouts.

The reviewed Pi settings are HOST=pi, PORT_HTTP=30080, PORT_FRONTEND=30000 and
PORT_WSPROXY=30599. [.env and port semantics](docs/deployment.md#configuration-sources)
explains Compose fallbacks, Kubernetes NodePorts and internal listener ports.
Flux reads committed manifests, **not** the machine's `.env`.

For local Compose, from the repository root:

```bash
./start.sh rathena detached
# Alternative: ./start.sh hercules detached
```

## Further documentation

[GitOps and releases](docs/gitops.md) · [Image revisions](docs/image-revisions.md) ·
[Security](docs/security.md) · [Development](docs/development.md) ·
[Validation](docs/validation.md) · [Frontend module regression](docs/frontend-api-module.md)

See [LICENSE](LICENSE) for the project license.
