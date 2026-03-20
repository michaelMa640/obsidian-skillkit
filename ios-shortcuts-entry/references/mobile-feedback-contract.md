# Mobile Feedback Contract

## Goal

Define how Feishu and OpenClaw should present short-video task results back to mobile users.

The output should be:

- concise
- Chinese-first
- actionable
- explicit about success or failure

## Principles

- Lead with status, not raw paths
- Keep the first screen short enough for mobile reading
- Only include debug guidance when needed
- Use structured fields from skill outputs instead of inferred wording

## Required result categories

### 1. Clip success

Conditions:

- `final_run_status = SUCCESS`
- task intent = clip

Suggested mobile reply:

```text
剪藏成功
已写入 Obsidian 剪藏库。
如需排查问题，可在需要时提供 support-bundle。
```

Suggested details:

- 标题
- `note_path`

### 2. Analyze success

Conditions:

- clipping completed
- analyzer completed
- breakdown note exists

Suggested mobile reply:

```text
拆解成功
已完成剪藏并生成爆款拆解。
```

Suggested details:

- 剪藏笔记路径
- 拆解笔记路径

### 3. Partial success

Conditions:

- one stage completed
- a later stage returned `partial`
- or analyzer produced partial output that is still usable

Suggested mobile reply:

```text
部分完成
任务已执行，但结果不完整，请根据下方提示决定是否重试。
```

Suggested details:

- completed stage
- incomplete stage
- `final_message_zh`

### 4. Config missing

Conditions:

- validation failed before capture/analyze start

Suggested mobile reply:

```text
配置未完成
请先修改本机配置后再重试。
```

Required details:

- config file path
- missing keys

### 5. Auth expired

Conditions:

- `auth_action_required = refresh_douyin_auth`
- or error indicates fresh cookies are needed

Suggested mobile reply:

```text
抖音登录态已失效
请先刷新本机登录态，再重新执行。
```

Required details:

- refresh command
- debug path if available

### 6. Hard failure

Conditions:

- `final_run_status = FAILED`

Suggested mobile reply:

```text
执行失败
请查看失败步骤，并上传 support-bundle 以便排查。
```

Required details:

- `failed_step`
- `final_message_zh`
- `support_bundle_path`

## Required fields for mobile rendering

For every run, OpenClaw should try to produce:

- `final_run_status`
- `final_message_zh`
- `failed_step` when failed
- `debug_directory`
- `support_bundle_path`

For clip runs:

- `note_path`

For analyze runs:

- `clipper_note_path` when available
- `analyzer_note_path` when available

For auth-expired runs:

- `auth_action_required`
- `auth_refresh_command`
- `auth_guidance_zh`

## Recommended Chinese response structure

### Success

```text
结果：成功
说明：<final_message_zh>
剪藏笔记：<clipper note path if available>
拆解笔记：<analyzer note path if available>
```

### Failure

```text
结果：失败
步骤：<failed_step>
说明：<final_message_zh>
调试目录：<debug_directory>
支持包：<support_bundle_path>
如需排查，请优先上传 support-bundle。
```

### Auth expired

```text
结果：需刷新登录态
说明：<auth_guidance_zh>
命令：<auth_refresh_command>
```

## Path display guidance

For mobile-first display:

- paths may be shown in a shortened label form in the first message
- full paths should still remain available when needed

Example:

- `剪藏笔记：Clippings/...`
- `拆解笔记：爆款拆解/...`

## Support guidance

When the task fails, the first debug request should always be:

- `support-bundle/`

Only if that is insufficient should the user be asked for:

- the full `debug_directory`
