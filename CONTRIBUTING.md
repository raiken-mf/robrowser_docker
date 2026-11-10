# Contributing

Keep changes focused, preserve local configuration and client assets, and explain
the problem, behavior change and validation in the pull request. A human reviewer
is responsible for AI-assisted changes; disclose that assistance and distinguish
observed results from assumptions.

## Local checks

Run from the repository root. Python 3 with PyYAML, Bash, Docker with Compose, `kubectl`,
`envsubst` and a C compiler are needed for the checks that use them. Docker image
builds and upstream-layout checks require network access. Never use production
credentials or a live cluster for these tests.

Install the YAML test dependency in a Python environment with
`python3 -m pip install 'PyYAML==6.0.2'`.

```bash
python3 scripts/py/check-script-layout.py
python3 scripts/py/check-dockerfile-configs.py
python3 scripts/py/check-compose-contract.py
python3 scripts/py/check-k8s-bootstrap.py
python3 scripts/py/check-k8s-all.py
python3 scripts/py/check-xerj-monitor.py
bash scripts/sh/ci/check-platform-config.sh
kubectl kustomize deploy/k8s/overlays/flux >/dev/null
bash scripts/sh/ci/check-upstream-layout.sh
git diff --check
```

Follow the repository architecture in [AGENTS.md](AGENTS.md#repository-architecture).
For a new image, keep its Dockerfile and exclusive helpers together, choose an
appropriate build context, pin dependencies, and add applicable AMD64/ARM64 CI
builds and security checks. After structural changes, test affected callers,
build contexts, Compose and Kustomize rendering, Flux migration paths and docs.

For image and integration changes, build the pinned local images and run the
applicable isolated checks in [development](docs/development.md). The Compose
smoke test reads the synthetic `.env-tmpl` by default; `COMPOSE_TEST_ENV_FILE`
selects an explicit alternative.
The Compose smoke test uses an empty client fixture unless `CLIENT_TEST_ROOT` is
explicitly set; its temporary directory must be accessible to the Docker daemon.
Case-conflict fixtures require a case-sensitive filesystem. These checks do not
prove a real cluster installation or game login.

After building `rathena:ci`, run `bash images/rathena/tests/check-entrypoint.sh`
to check database failure handling and runtime configuration validation.

For documentation changes, run the strict MkDocs build described in
[development](docs/development.md#documentation-checks). Do not commit generated
site files. Report unavailable tools, skipped checks and failures explicitly.

## Review and merge

- Add or update focused regression tests for changed behavior where practical;
  document any coverage gap and update affected documentation.
- Review the effective diff, security implications, compatibility and recovery
  paths. For stateful or GitOps changes, explain upgrade and rollback behavior.
- Require applicable CI checks to pass before merge, including the existing PR
  image-security gate when applicable. CI is scope-sensitive: a green docs-only
  run does not establish image or cluster behavior. Repository branch protection
  and required-check settings must be verified separately by maintainers.
- Include **Tested**, **Not tested**, and **Failed** sections with commands,
  results and reasons. Do not claim a test passed when it was skipped or failed.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

See [best practices](docs/best-practices.md) for the external references and
the human-reviewed update process.