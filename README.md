# roBrowser Docker and Kubernetes stack

Ragnarok Online with separate `robrowser` frontend, `remote` client-file service,
wsProxy, rAthena and MariaDB. Docker Compose and Kubernetes/FluxCD are supported;
Hercules is available through the Compose overlay.
Supported Linux hosts include servers, virtual machines and Raspberry Pis; the
four published rAthena stack images target `linux/amd64` and `linux/arm64`.
Hercules is Compose-only and is not covered by that image publishing workflow.

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

## Example installation

On 2026-11-02 the operator confirmed a Raspberry Pi installation with K3s/Longhorn working, both Flux
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

Edit it locally; replace template credentials before deployment and never commit
it or credentials. `client/resources/DATA.INI`
(case-sensitive) must reference the available GRFs. Keep AI, BGM, data and System
files in their corresponding `client/` folders. Existing local files and
`repository_override` payloads must be preserved across checkouts.

Set `HOST` to an address reachable from the browser; the template defaults to
`127.0.0.1` for local access. [.env and port semantics](docs/deployment.md#configuration-sources)
explains Compose fallbacks, Kubernetes NodePorts and internal listener ports.
Flux reads committed manifests, **not** the machine's `.env`; configure the
installation-specific Flux Kustomization for your host before reconciliation.
The shared Kubernetes base retains the existing host until the separately reviewed
second stage of the [Flux migration](docs/gitops.md) is complete.

For local Compose, from the repository root:

```bash
./scripts/sh/compose/start-compose.sh rathena detached
# Alternative: ./scripts/sh/compose/start-compose.sh hercules detached
```

## Projects and references

- [roBrowserLegacy](https://github.com/MrAntares/roBrowserLegacy), the browser client; this stack builds the [project fork](https://github.com/raiken-mf/roBrowserLegacy).
- [RemoteClient PHP fork](https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP), the client-file service.
- [rAthena](https://github.com/rathena/rathena) and [Hercules](https://github.com/HerculesWS/Hercules), the game servers; this stack builds the [rAthena fork](https://github.com/raiken-mf/rathena) or [Hercules fork](https://github.com/raiken-mf/Hercules).
- [ROEnglishRE](https://github.com/llchrisll/ROenglishRE), the translation project; this stack builds the [project fork](https://github.com/raiken-mf/ROenglishRE).
- [XERJ](https://github.com/xerj-org/xerj), an external reference for development and security practices, not a runtime dependency.

The exact source revisions used for builds are recorded in [build/dependencies.env](build/dependencies.env).

## Further documentation

[GitOps and releases](docs/gitops.md) · [Image revisions](docs/image-revisions.md) ·
[Security](docs/security.md) · [Development](docs/development.md) ·
[Validation](docs/validation.md) · [Frontend module regression](docs/frontend-api-module.md)

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution checks and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

See [LICENSE](LICENSE) for the project license.
