# Vite iframe HTML-proxy regression

The pinned upstream `applications/api/api.js` creates a FRAME URL as
`api.html?` + `Math.random()` + `location.hash`. On a cold Vite server, requesting
that cache-busted page transformed the inline module into
`api.html?html-proxy&index=0.js`. That module request returned HTTP 500:
`No matching HTML proxy module found`. Warming the unqueried HTML first can hide
the problem, which is why the old root/API-script HTTP smoke checks missed it.

## Project-owned override

`images/robrowser/repository_override/applications/api/api.html` changes only the
inline module into `<script type="module" src="./api-bootstrap.js"></script>`.
The neighboring `api-bootstrap.js` contains the exact extracted upstream logic.
Its relative dynamic import still resolves to `../../src/main.js` because the
external module stays in the same directory as the HTML page.

Parent/opener source filtering, the one-shot configuration listener, ROConfig
assignment before the import, the ready reply after successful import and the
error handler are preserved. The import map, styles/preloader and HTML remain.
The random query, Firefox/hash behavior and upstream api.js are unchanged.
No upstream repository, package dependency, source revision, runtime security,
port setting or Kubernetes resource is changed.

These two files are intentionally versioned exceptions to the local override
ignore rules. Other custom override payloads remain ignored. A source-pin update
must recheck this extraction: `check-upstream-layout.sh` runs
`check-api-override.py` against the actual fetched upstream HTML and rejects a
stale override instead of silently masking an upstream bootstrap change.

## Regression checks

After building the normal pinned frontend image:

```bash
python3 images/robrowser/tests/check-api-module.py robrowser:ci
```

The test starts/removes its own container on an ephemeral loopback host port.
It first requests query-bearing iframe HTML without warming the unqueried page,
fetches every module URL returned by Vite, and verifies JavaScript/HTTP 200 for
several query/hash/no-query variants. It also requests the real transformed
`/src/main.js` entry. The same test fails against the pre-fix image with the
original HTTP 500 proxy error.

`check-api-handshake.cjs` then executes the real api.js and the Vite-served
external bootstrap using Node VM modules. It checks random iframe URLs, config
polling/ready cleanup, rejected foreign-window messages, parent and opener
initialization, one-shot setup, delayed import readiness and import failure.
Only engine execution is stubbed here: the real engine URL is independently
requested through Vite. This is not a full graphical browser/gameplay test.
The regression is required in PR/main CI and needs no added npm dependencies.

## Verification and current deployment

Local ARM64 tests reproduced the old 500 response and passed after extraction.
CI includes the HTTP/module and handshake checks. The fix merged in PR #88;
its published ARM64-capable frontend release was selected through PR #89.
After the completed Kubernetes/GitOps adoption the operator confirmed successful
browser login. Both Flux Kustomizations are now active/Ready; the former paused
installation state is no longer an operating instruction.

These tests do not close separate graphics, Lua, GRF-content or gameplay issues.
See [validation coverage](validation.md) and [normal operations](operations.md).
