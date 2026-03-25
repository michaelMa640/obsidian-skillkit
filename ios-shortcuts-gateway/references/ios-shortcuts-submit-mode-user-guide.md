# iOS Shortcuts Submit-Only User Guide

## Goal

Use an iPhone shortcut to submit a short-video task to the local Gateway and receive the final result later in Feishu.

## What this mode does

The iPhone shortcut does not wait for the full business result.

It only:

1. sends the task
2. receives `request_id`
3. shows a short accepted message from `display_text`

The computer then continues in the background and sends the final result to Feishu.

## Preconditions

- Windows computer is online
- Tailscale is connected on both devices
- Gateway is running
- `feishu.enabled = true`
- one of these is configured:
  - `feishu.mode = openclaw_cli` with valid `target`
  - or `feishu.mode = webhook` with valid `webhook_url`
- `obsidian-clipper` and `obsidian-analyzer` already work from PowerShell

## Gateway startup

Run on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\start_gateway.ps1" -UseConfigHost
```

## Shortcut request

### URL

```text
http://<tailscale-ip>:8787/short-video/task
```

### Method

```text
POST
```

### Headers

- `Authorization: Bearer <token>`

### JSON body for clip

```json
{
  "action": "clip",
  "source_text": "<raw share text>",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```

### JSON body for analyze

```json
{
  "action": "analyze",
  "source_text": "<raw share text>",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```

## What the shortcut should show

The shortcut should display:

- `display_text`

Typical accepted message:

- `任务已提交，正在后台执行。结果将稍后通过飞书返回。`
- `request_id: ...`

## What Feishu should show

The final Feishu message should contain:

- task status
- `request_id`
- `source_url`
- `normalized_url`
- `original_source_text`
- clipping note path when available
- breakdown note path when available
- refresh instruction when auth is required

## Failure handling

### `AUTH_REQUIRED`

Refresh Douyin auth on Windows:

```powershell
python ".\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

### Gateway accepted the task but Feishu did not return

Inspect:

- `.tmp/gateway/runs/<request_id>/status.json`
- `.tmp/gateway/runs/<request_id>/feishu-callback.json`

### Request was rejected

Check:

- bearer token
- Gateway startup mode
- Tailscale connectivity
