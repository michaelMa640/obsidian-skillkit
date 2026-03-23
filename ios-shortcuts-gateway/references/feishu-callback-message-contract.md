# Feishu Callback Message Contract

## Goal

Define the minimum payload and message sections for sending async task results back to Feishu after Gateway completion.

## Trigger points

Send a Feishu callback when task status becomes one of:

- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

Do not send a callback for:

- `ACCEPTED`
- `RUNNING`

## Required structured fields

- `request_id`
- `action`
- `status`
- `message_zh`
- `source_url`
- `normalized_url`
- `original_source_text`
- `clipper_note`
- `analyzer_note`
- `failed_step`
- `auth_action_required`
- `refresh_command`

## User-facing message sections

### Success

- result summary
- request id
- original video link
- clipping note path
- breakdown note path when applicable

### Partial

- result summary
- request id
- original video link
- note paths
- warning that the result is incomplete

### Failed

- failure summary
- request id
- failed step
- original video link
- debug hint

### Auth required

- login-state expired summary
- request id
- original video link
- refresh instruction

## Example content block

```text
拆解完成
request_id: 123456
状态: SUCCESS
原始链接: https://v.douyin.com/xxxxxxx/
规范化链接: https://www.douyin.com/video/1234567890
剪藏笔记: Clippings/2026-03-23 示例.md
爆款拆解: 爆款拆解/2026-03-23 示例.md
```

## Privacy rule

Do not include:

- cookies
- storage state paths
- raw stack traces
- full debug file contents

Debug references may point the user back to the local machine, but the callback itself should remain sanitized.
