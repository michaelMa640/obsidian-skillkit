# iOS Shortcuts Gateway

## Document Status

- Last Updated: `2026-04-05`

## Change Log

- `2026-04-05`
  - added document status metadata so gateway changes can be tracked directly in the README

## Purpose

`ios-shortcuts-gateway` is the local HTTP entry layer for iPhone-triggered short-video tasks over Tailscale.

It bridges:

- iPhone Shortcuts
- Tailscale private connectivity
- local HTTP requests
- `obsidian-clipper`
- `obsidian-analyzer`

This module is not a new clipping or analysis engine.

## Recommended topology

`iPhone Shortcut -> Tailscale -> local HTTP gateway -> Clipper / Analyzer -> Feishu callback`

## Allowed actions

- `clip`
- `analyze`

No other action is in scope for the current implementation.

## References

- [Module Boundary](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\module-boundary.md)
- [Request Schema](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\short-video-task.request.schema.json)
- [Response Schema](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\short-video-task.response.schema.json)
- [Security Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\security-contract.md)
- [Local Config Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\local-config-contract.md)
- [Feishu Notifier Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\feishu-notifier-contract.md)
- [Submit-Only User Guide](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\references\ios-shortcuts-submit-mode-user-guide.md)

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
   - `feishu.*` if you want async callback delivery
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

## Local smoke tests

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
  - `display_text`
- runs `clip` or `analyze` in the background by default

If the caller explicitly sets `wait_for_completion = true`, the gateway waits for the full workflow and returns the final result. This mode is suitable for local PowerShell smoke tests, not for iPhone shortcut UX.

### `GET /short-video/task/{request_id}`

- returns the current task state
- intended for debugging/operator lookup

Possible states:

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

## `status.json`

The async lifecycle is persisted through:

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
- `display_text`
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

## Feishu notifier

Terminal task states are finalized first and then passed through `feishu_notifier.py`.
Callback delivery never downgrades the underlying task outcome.

### Recommended mode

If your OpenClaw environment already has a working Feishu connection, prefer:

- `feishu.mode = openclaw_cli`

This uses:

```text
openclaw message send --channel feishu --target <open_id or chat_id> --message <text>
```

`webhook` remains available as a compatibility fallback.

## iPhone shortcut behavior

Recommended request body:

```json
{
  "action": "clip",
  "source_text": "<raw share text>",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```

or:

```json
{
  "action": "analyze",
  "source_text": "<raw share text>",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```

Recommended response handling:

- read `display_text`
- show the accepted message
- stop immediately
- wait for Feishu as the primary result channel

`GET /short-video/task/{request_id}` remains available, but only as a debug or operator endpoint.
