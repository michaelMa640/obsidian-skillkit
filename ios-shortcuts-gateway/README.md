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
- [Feishu Notifier Contract](references/feishu-notifier-contract.md)
- [local-config.example.json](references/local-config.example.json)
- [Phase 6 Integration Test Plan](references/integration-test-plan.md)
- [Submit-Only User Guide](references/ios-shortcuts-submit-mode-user-guide.md)

## Entrypoints

- `app.py`
- `feishu_notifier.py`

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
   - optional `feishu.*` if you want callback delivery to Feishu
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
- `feishu-callback.json` after terminal-state callback handling
- `clipper-result.json`
- `analyzer-result.json` when applicable
- `clipper-stdout.log`
- `clipper-stderr.log`
- `analyzer-stdout.log`
- `analyzer-stderr.log`

under:

- `.tmp/gateway/runs/<request_id>/`

### `status.json`

The async lifecycle is now persisted through:

- `ACCEPTED`
- `RUNNING`
- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

Each `status.json` keeps:

- `request_id`
- `action`
- `status`
- `message_zh`
- `created_at`
- `updated_at`
- `source_url`
- `normalized_url`
- `original_source_text`
- optional note paths and failure fields
- optional callback fields:
  - `callback_attempted_at`
  - `callback_sent`
  - `callback_error`

## Feishu notifier module

Phase 4 adds an isolated notifier module:

- `feishu_notifier.py`

Current scope:

- validates Feishu notifier config
- validates terminal callback payloads
- renders a standard Feishu text message
- sends the webhook request through a dedicated helper

From Phase 5 onward, terminal task states are finalized first and then passed through this notifier helper. Callback delivery does not downgrade the task outcome if Feishu delivery fails.

### Recommended Feishu mode

If your OpenClaw environment already has a working Feishu connection, prefer:

- `feishu.mode = openclaw_cli`

This uses:

```text
openclaw message send --channel feishu --target <open_id or chat_id> --message <text>
```

`webhook` remains available as a compatibility fallback.

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
5. stop the shortcut immediately
6. wait for the Feishu callback as the primary result channel

### Recommended shortcut pattern

- request 1:
  - submit task
- response:
  - show `request_id`
  - show `message_zh`
  - tell the user that the final result will return in Feishu

### Polling rule

`GET /short-video/task/{request_id}` remains available, but only as a debug or operator endpoint.

It is not the recommended primary UX for the iPhone shortcut.

The detailed checklist is in:

- [Phase 6 Integration Test Plan](references/integration-test-plan.md)
