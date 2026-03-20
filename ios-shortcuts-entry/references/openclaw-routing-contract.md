# OpenClaw Routing Contract

## Goal

Define deterministic routing behavior for iOS Shortcut requests that arrive through Feishu.

## Routing table

### Input starts with `剪藏视频：` or `剪藏：`

OpenClaw should:

1. treat the request as `clip`
2. call `obsidian-clipper`
3. stop after clipping succeeds or fails

### Input starts with `拆解视频：` or `分析视频：` or `爆款拆解：`

OpenClaw should:

1. treat the request as `analyze`
2. inspect whether the input is a clipping note path or raw share text
3. if it is raw share text or raw URL:
   - call `obsidian-clipper` first
   - then call `obsidian-analyzer`
4. if it is an existing clipping note path:
   - call `obsidian-analyzer` directly

## Handoff rules

- OpenClaw must use the exact structured output from `obsidian-clipper`.
- It must not guess note file names.
- It must not guess capture ids.
- It must not generate English or pinyin slugs.
- If `note_path` contains characters that are unsafe in shell handoff, pass `sidecar_path` and run analyzer with `-CaptureJsonPath`.

## Completion rules

### Clip task

Complete when:

- clipping note exists
- clipper result status is success or explicit failure

### Analyze task

Complete only when:

- clipping stage succeeded or an existing clipping note was resolved
- analyzer stage produced a breakdown note

If only clipping finished, the analyze task is incomplete.

## Retry rules

- Do not brute-force retries with guessed file paths.
- Do not enumerate vault files and choose one by name similarity.
- If the first analyzer handoff fails, return the real error plus debug paths.

## First-run validation

Before formal execution, OpenClaw should validate config when:

- the machine runs the flow for the first time
- the task fails before capture or analyze begins

Validation scripts:

- `obsidian-clipper/scripts/validate_local_config.ps1`
- `obsidian-analyzer/scripts/validate_local_config.ps1`

## User-visible error guidance

If config is missing:

- tell the user which config file to edit
- list the missing keys

If Douyin auth is expired:

- return `auth_action_required = refresh_douyin_auth`
- return `auth_refresh_command`
- tell the user to refresh local auth before retrying
