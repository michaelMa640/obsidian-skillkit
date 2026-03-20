# OpenClaw Short-Video Integration

## Goal

Use two skills to complete the short-video workflow:

- `obsidian-clipper`
- `obsidian-analyzer`

Supported user intents:

- `剪藏（链接）`
- `拆解视频（链接）`
- `剪藏视频：<share text>`
- `拆解视频：<share text>`

## Entry modules

Current entry layers may coexist:

- Feishu bot entry
- iOS Shortcuts entry

For iOS mobile usage, the current recommended route is:

`iOS Shortcuts -> Feishu bot -> OpenClaw -> skills`

See also:

- `ios-shortcuts-entry/README.md`
- `ios-shortcuts-entry/references/feishu-message-contract.md`
- `ios-shortcuts-entry/references/openclaw-routing-contract.md`

## Intent mapping

### 1. Clip only

Examples:

- 帮我剪藏这个视频
- 请帮我保存这个抖音链接到 Obsidian
- 帮我收录这个短视频

OpenClaw should:

- call only `obsidian-clipper`

Shortcut-style prefixes that should map here:

- `剪藏视频：`
- `剪藏：`

### 2. Analyze video

Examples:

- 帮我拆解这个视频
- 分析这个抖音短视频
- 拆解视频：https://...

OpenClaw should:

- if the input is already a clipping note or explicit `note_path`, call `obsidian-analyzer`
- if the input is a raw URL or share text, call `obsidian-clipper` first
- then call `obsidian-analyzer`

Shortcut-style prefixes that should map here:

- `拆解视频：`
- `分析视频：`
- `爆款拆解：`

Workflow:

1. clip first
2. analyze second

The task is complete only when:

1. the clipping note exists
2. analyzer has run
3. a breakdown note exists in `爆款拆解/`

If only step 1 completed, the workflow is not complete.

## Handoff rules that OpenClaw must follow

- After `obsidian-clipper` succeeds, OpenClaw must read the structured result JSON and use the returned `note_path`.
- OpenClaw must not reconstruct a clipping file name from:
  - title
  - hashtags
  - platform
  - capture id
  - guessed English slug or pinyin slug
- OpenClaw must never invent names like `2026-03-20-douyin-yashua.md`.
- If the returned `note_path` includes Chinese or emoji and shell argument passing is unreliable, OpenClaw must switch to the returned `sidecar_path` and invoke analyzer with `-CaptureJsonPath`.
- OpenClaw must not use wildcard matching, manual renaming, or repeated file-system guessing to locate the clipping note.
- If the first analyzer handoff fails, OpenClaw should stop and return the real failure plus `support-bundle/`, not brute-force multiple retries.

## First-run config checks

Before formal execution, or whenever the workflow fails before capture/analyze starts, OpenClaw should run local config validation.

### Clipper config check

Script:

- `obsidian-clipper/scripts/validate_local_config.ps1`

Required fields:

- `obsidian.vault_path`
- `routes.social.script`
- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

Config file:

- `obsidian-clipper/references/local-config.json`

If required fields are missing, OpenClaw should:

- stop the workflow
- tell the user which file to edit
- list the missing fields

### Analyzer config check

Script:

- `obsidian-analyzer/scripts/validate_local_config.ps1`

Required fields:

- `obsidian.vault_path`
- `analyzer.default_analyze_folder`
- `llm.provider`
- `llm.model`
- `llm.api_key` or environment variable

Config file:

- `obsidian-analyzer/references/local-config.json`

## Douyin auth handling

OpenClaw does not log in to Douyin itself. It reuses locally generated auth state.

Refresh command:

```powershell
python "E:\Codex_project\obsidian-skillkit\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

Generated files:

- `obsidian-clipper/.local-auth/douyin-storage-state.json`
- `obsidian-clipper/.local-auth/douyin-cookies.txt`

Configured in:

- `obsidian-clipper/references/local-config.json`

Required fields:

- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

## Handling expired cookies

If the result contains:

- `auth_action_required = refresh_douyin_auth`

or the error contains:

- `Fresh cookies are needed`

OpenClaw should tell the user:

- local Douyin auth is expired or missing
- they need to refresh local auth
- the refresh command is:

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

If auth refresh is required, also return:

- `auth_action_required`
- `auth_refresh_command`
- `auth_guidance_zh`

### Analyzer

- `note_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `failed_step`
- `final_message_zh`

## Debug handoff

On error, OpenClaw should first ask the user to upload:

- `support-bundle/`

If that is not enough, then ask for:

- the whole `debug_directory`

## Recommended natural-language prompts

### Clip

```text
请使用 Obsidian-Clipper 帮我剪藏这个抖音短视频到 Obsidian：https://v.douyin.com/xxxxxxx/
```

### Analyze video

```text
请帮我拆解这个抖音短视频。如果它还没有被剪藏，请先使用 Obsidian-Clipper 剪藏，再使用 Obsidian-Analyzer 生成爆款拆解：https://v.douyin.com/xxxxxxx/
```

### Share-text style input

```text
拆解视频：3.25 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```
