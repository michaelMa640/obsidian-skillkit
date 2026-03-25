# OpenClaw Short-Video Integration

## Goal

Use the short-video workflow with:

- `obsidian-clipper`
- `obsidian-analyzer`
- optionally `ios-shortcuts-gateway` for iPhone remote submission

## Supported intents

- `剪藏视频：<share text or url>`
- `拆解视频：<share text or url>`
- direct clipping note analysis from `note_path`

## Current entry layers

- Feishu bot -> OpenClaw -> skills
- iPhone Shortcut -> `ios-shortcuts-gateway` -> skills

The iPhone path is no longer “shortcut -> Feishu bot -> OpenClaw” as the primary route.
The current recommended mobile route is:

`iPhone Shortcut -> Tailscale -> ios-shortcuts-gateway -> Clipper / Analyzer`

Final result delivery for the iPhone route goes back to Feishu asynchronously.

## Intent mapping

### Clip only

Input examples:

- `剪藏视频：https://v.douyin.com/...`
- `剪藏视频：6.43 复制打开抖音，看看…… https://v.douyin.com/...`

Expected behavior:

- call only `obsidian-clipper`

### Analyze video

Input examples:

- `拆解视频：https://v.douyin.com/...`
- `拆解视频：6.43 复制打开抖音，看看…… https://v.douyin.com/...`

Expected behavior:

- if the input is raw share text or URL:
  1. run `obsidian-clipper`
  2. run `obsidian-analyzer`
- if the input is already a clipping note path:
  - run `obsidian-analyzer` directly

Completion rule:

- the job is complete only after the breakdown note exists in `爆款拆解/`

## Handoff rules

- always use the structured result returned by `obsidian-clipper`
- never reconstruct clipping filenames manually
- if shell argument passing is unreliable for a clipping note with Chinese or emoji:
  - use `sidecar_path`
  - call analyzer with `-CaptureJsonPath`
- analyzer now resolves the matching clipping note from the vault when running from `-CaptureJsonPath`

## Config checks

Before formal execution, validate local config if capture/analyze cannot start.

### Clipper config

Script:

- `obsidian-clipper/scripts/validate_local_config.ps1`

Required:

- `obsidian.vault_path`
- `routes.social.script`
- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

### Analyzer config

Script:

- `obsidian-analyzer/scripts/validate_local_config.ps1`

Required:

- `obsidian.vault_path`
- `analyzer.default_analyze_folder`
- `llm.provider`
- `llm.model`
- `llm.api_key` or configured env fallback

## Douyin auth handling

OpenClaw and Gateway do not log in to Douyin directly.
They reuse locally generated auth files.

Refresh command:

```powershell
python "E:\Codex_project\obsidian-skillkit\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

## Fields to return to the user

### Clipper

- `note_path`
- `sidecar_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `failed_step`
- `final_message_zh`

### Analyzer

- `note_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `failed_step`
- `final_message_zh`

### Gateway accepted response

- `status = ACCEPTED`
- `request_id`
- `message_zh`
- `display_text`

## Debug handoff

Ask for these in this order:

1. `support-bundle/`
2. if needed, the full `debug_directory`

## Recommended examples

### Feishu / OpenClaw

```text
剪藏视频：6.43 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```

```text
拆解视频：6.43 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```

### iPhone shortcut -> Gateway

```json
{
  "action": "clip",
  "source_text": "6.43 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```

```json
{
  "action": "analyze",
  "source_text": "6.43 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...",
  "client": "ios_shortcuts",
  "wait_for_completion": false
}
```
