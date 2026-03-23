# Phase 6 Integration Test Plan

## Goal

Validate the gateway end-to-end in two stages:

1. local Windows smoke test
2. remote iPhone over Tailscale

This phase is complete only when both stages have been exercised.

## Preconditions

- `references/local-config.json` exists
- `server.host` is set to the target Tailscale IP for remote testing
- `auth.bearer_token` is set
- `routing.clipper_script` points to a working `run_clipper.ps1`
- `routing.analyzer_script` points to a working `run_analyzer.ps1`
- `obsidian.vault_path` points to the real vault root
- `python`, `fastapi`, and `uvicorn` are installed
- `Clipper` and `Analyzer` already run successfully from PowerShell
- Tailscale is installed and both devices are in the same tailnet

## Stage A: Local smoke test

### Start the gateway locally

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\start_gateway.ps1"
```

### Check health

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" -Action health
```

Expected result:

- returns `status = ok`

### Smoke test clip

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" `
  -Action clip `
  -SourceText "3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ..."
```

Expected result:

- response contains `status = SUCCESS` or `AUTH_REQUIRED`
- request-local files exist under `.tmp/gateway/runs/<request_id>/`

### Smoke test analyze

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\test_gateway.ps1" `
  -Action analyze `
  -SourceText "3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ..."
```

Expected result:

- response contains `status = SUCCESS`, `PARTIAL`, or `AUTH_REQUIRED`
- if successful, both `clipper-result.json` and `analyzer-result.json` exist

## Stage B: Tailscale remote test

### Start the gateway on the Tailscale IP

```powershell
powershell -ExecutionPolicy Bypass -File ".\ios-shortcuts-gateway\scripts\start_gateway.ps1" -UseConfigHost
```

The `server.host` field in `references/local-config.json` must already be set to the Windows machine Tailscale IP.

### Verify the iPhone can reach the service

Use Safari on the iPhone:

```text
http://<tailscale-ip>:8787/health
```

Expected result:

- a small JSON document is returned

### Configure iOS Shortcuts

The shortcut should:

1. collect the raw shared text
2. ask the user to choose `剪藏` or `拆解`
3. send a POST request to `http://<tailscale-ip>:8787/short-video/task`
4. send header `Authorization: Bearer <token>`
5. send JSON body:

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

6. read `request_id` from the accepted response
7. poll `GET http://<tailscale-ip>:8787/short-video/task/<request_id>`
8. stop polling only when the result changes to:
   - `SUCCESS`
   - `PARTIAL`
   - `FAILED`
   - `AUTH_REQUIRED`

### Expected remote outcomes

- first response should be `ACCEPTED`
- follow-up status should become `RUNNING` and then a terminal state
- `clip` creates a new note under `Clippings/`
- `analyze` creates a new note under `Clippings/` and a new note under `爆款拆解/`
- gateway request artifacts are stored under `.tmp/gateway/runs/<request_id>/`

## Failure handling

### `401 Unauthorized`

- token mismatch
- check the bearer token configured in the iPhone shortcut and `local-config.json`

### `AUTH_REQUIRED`

- Douyin login state needs refresh
- run:

```powershell
python ".\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

### `FAILED`

- inspect `.tmp/gateway/runs/<request_id>/`
- then inspect the nested `clipper-debug/` or `analyzer-debug/`

## Acceptance criteria

- one successful local `clip` request
- one successful local `analyze` request
- one successful remote iPhone `clip` request over Tailscale
- one successful remote iPhone `analyze` request over Tailscale
- one confirmed `AUTH_REQUIRED` or config-failure path
- no sensitive auth content returned to the mobile client
