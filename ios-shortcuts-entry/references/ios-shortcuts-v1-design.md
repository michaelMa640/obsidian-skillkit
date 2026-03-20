# iOS Shortcuts 1.0 Design

## Goal

Define two concrete iOS Shortcuts for the MVP:

- `剪藏视频`
- `拆解视频`

These shortcuts should:

- accept short-video share text from the iOS share sheet
- format the text using the Feishu message contract
- send the formatted text to the Feishu bot
- provide simple local feedback to the user

## Shared design principles

- Prefer the share sheet input over clipboard input
- Do not rewrite or summarize the incoming share text
- Only prepend the standard command prefix
- Show a simple success message after the request is sent
- If no text is available, stop locally and tell the user the input is empty

## Shortcut A: `剪藏视频`

### Intent

Send a short-video clipping request into the system.

### Input

- primary: share sheet text
- fallback: clipboard text

### Output message sent to Feishu

```text
剪藏视频：<raw share text>
```

### Suggested iOS Shortcuts action flow

1. `接收来自共享表单的内容`
2. `如果 共享输入 不为空`
   - use shared input
3. `否则`
   - `获取剪贴板`
4. `如果 文本为空`
   - `显示结果：未检测到可发送的分享文本`
   - stop
5. `文本` = `剪藏视频：` + 原始文本
6. `通过飞书发送消息`
7. `显示结果：已提交剪藏任务`

### Local feedback text

Success:

```text
已提交剪藏任务，请稍后在飞书或 Obsidian 中查看结果。
```

Failure:

```text
未检测到可发送的分享文本，请从分享面板重新触发。
```

## Shortcut B: `拆解视频`

### Intent

Send a short-video analysis request into the system.

### Input

- primary: share sheet text
- fallback: clipboard text

### Output message sent to Feishu

```text
拆解视频：<raw share text>
```

### Suggested iOS Shortcuts action flow

1. `接收来自共享表单的内容`
2. `如果 共享输入 不为空`
   - use shared input
3. `否则`
   - `获取剪贴板`
4. `如果 文本为空`
   - `显示结果：未检测到可发送的分享文本`
   - stop
5. `文本` = `拆解视频：` + 原始文本
6. `通过飞书发送消息`
7. `显示结果：已提交拆解任务`

### Local feedback text

Success:

```text
已提交拆解任务，系统会先剪藏再生成爆款拆解。
```

Failure:

```text
未检测到可发送的分享文本，请从分享面板重新触发。
```

## Optional Shortcut C: `拆解笔记`

This is not required for the first mobile MVP, but it is useful later.

### Output message sent to Feishu

```text
拆解笔记：<absolute note path>
```

## Feishu send step

Phase 4 does not force one exact Feishu delivery mechanism.

Either of these can be used:

- open Feishu and prefill a message to a target bot/chat
- call a Feishu incoming webhook if your bot supports it

The only hard requirement is that the final message content matches the standardized contract.

## Validation rules

The shortcut should validate only:

1. there is non-empty text input
2. the message prefix is correct

It should not attempt to:

- extract URLs itself
- normalize Douyin short links
- guess whether the content is already clipped

Those belong to OpenClaw and the skills.

## Completion criteria for Phase 4

Phase 4 is complete when:

- the two shortcut definitions are documented
- the message templates exactly match the Phase 3 contract
- the shortcuts are simple enough to build manually in iOS Shortcuts without additional backend changes
