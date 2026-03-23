# iOS Shortcuts Gateway

## Purpose

`ios-shortcuts-gateway` is a local entry-layer module for remote iPhone-triggered tasks over a Tailscale private network.

It bridges:

- iOS Shortcuts
- Tailscale private connectivity
- local HTTP requests
- `obsidian-clipper`
- `obsidian-analyzer`

This module is not a new clipping or analysis engine.

## Recommended topology

`iPhone Shortcuts -> Tailscale -> local HTTP gateway -> Clipper / Analyzer`

## Responsibilities

- authenticate incoming requests
- validate request payloads
- allow only approved actions
- call fixed internal workflows
- return mobile-safe structured results

## Allowed actions

- `clip`
- `analyze`

No other action is in scope for the MVP.

## References

- [Module Boundary](references/module-boundary.md)
- [Request Schema](references/short-video-task.request.schema.json)
- [Response Schema](references/short-video-task.response.schema.json)
- [Security Contract](references/security-contract.md)
- [Local Config Contract](references/local-config-contract.md)
- [local-config.example.json](references/local-config.example.json)
- [Phase 6 Integration Test Plan](references/integration-test-plan.md)

## Entrypoint

- `app.py`

## Setup

1. Copy:
   - `references/local-config.example.json`
   - to `references/local-config.json`
2. Fill in local values:
   - `server.host`
   - `server.port`
   - `auth.bearer_token`
   - `routing.clipper_script`
   - `routing.analyzer_script`
   - `obsidian.vault_path`
3. Install dependencies:

```powershell
python -m pip install -r .\ios-shortcuts-gateway\requirements.txt
```

## Local startup

Local smoke test mode:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\start_gateway.ps1"
```

Tailscale bind mode:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\start_gateway.ps1" -UseConfigHost
```

## Local smoke test

Health:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" -Action health
```

Clip:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" `
  -Action clip `
  -SourceText "3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ..."
```

Analyze:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" `
  -Action analyze `
  -SourceText "3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ..."
```

## Runtime behavior

### `POST /short-video/task`

- validates the request
- creates `.tmp/gateway/runs/<request_id>/`
- returns immediately with:
  - `status = ACCEPTED`
  - `request_id`
- runs `clip` or `analyze` in the background by default

If the caller explicitly sets `wait_for_completion = true`, the gateway waits for the full workflow and returns the final result. This is suitable for local PowerShell smoke tests, but not recommended for iPhone shortcuts.

### `GET /short-video/task/{request_id}`

- returns the current task state
- possible states:
  - `ACCEPTED`
  - `RUNNING`
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`

## Request-local artifacts

Each request creates:

- `request.json`
- `status.json`
- `clipper-result.json`
- `analyzer-result.json` when applicable
- `clipper-stdout.log`
- `clipper-stderr.log`
- `analyzer-stdout.log`
- `analyzer-stderr.log`

under:

- `.tmp/gateway/runs/<request_id>/`

## iPhone / Tailscale phase

When the local smoke test passes:

1. set `server.host` to the Windows Tailscale IP
2. restart the gateway with `-UseConfigHost`
3. configure the iPhone shortcut to:
   - `POST http://<tailscale-ip>:<port>/short-video/task`
   - send header `Authorization: Bearer <token>`
   - send JSON body with:
     - `action`
     - `source_text`
     - `client`
     - `wait_for_completion = false`
4. read `request_id` from the accepted response
5. poll:
   - `GET http://<tailscale-ip>:<port>/short-video/task/<request_id>`
   - until the result becomes `SUCCESS`, `PARTIAL`, `FAILED`, or `AUTH_REQUIRED`

### Recommended shortcut pattern

- request 1:
  - submit task
- wait:
  - 3 to 5 seconds
- request 2:
  - check task status
- if still `ACCEPTED` or `RUNNING`
  - wait again and retry

The detailed checklist is in:

- [Phase 6 Integration Test Plan](references/integration-test-plan.md)
