# Feishu Message Contract

## Goal

Define a stable text contract for messages sent from iOS Shortcuts into the Feishu bot, so OpenClaw can route the task without relying on free-form interpretation alone.

## Supported command prefixes

### Clip only

Preferred prefixes:

- `剪藏视频：`
- `剪藏：`

Examples:

```text
剪藏视频：3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```

### Analyze video

Preferred prefixes:

- `拆解视频：`
- `分析视频：`
- `爆款拆解：`

Examples:

```text
拆解视频：3.53 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```

## Standard message templates

The Feishu bot should receive a single plain-text payload.

No markdown structure is required for MVP.

### Template A: clip only

```text
剪藏视频：<raw share text>
```

### Template B: analyze video

```text
拆解视频：<raw share text>
```

### Template C: analyze an existing clipping note

```text
拆解笔记：<absolute note path>
```

This third template is optional for the shortcut MVP, but it is useful for later manual debugging or Feishu-only operations.

## Field semantics

### Prefix

The prefix determines user intent and should appear before any share text.

Allowed values for MVP:

- `剪藏视频：`
- `拆解视频：`
- `拆解笔记：`

### Payload

For `剪藏视频：` and `拆解视频：`

- the payload should be the untouched raw share text copied from the app
- the embedded short URL must remain present

For `拆解笔记：`

- the payload should be an explicit clipping note path
- OpenClaw may skip clipper and call analyzer directly

## Message body rules

- The original share text should be passed through as completely as possible.
- Do not summarize the share text before sending to Feishu.
- Do not remove the embedded `http://` or `https://` URL.
- Do not convert the message into a guessed title or slug.

## Recommended shortcut payload shape

The shortcut should send a single message containing:

1. an explicit command prefix
2. the raw share text

Recommended format:

```text
拆解视频：<raw share text>
```

or

```text
剪藏视频：<raw share text>
```

Recommended analyze-note format:

```text
拆解笔记：E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\michael内容库\Clippings\2026-03-20 示例.md
```

## Shortcut-side validation rules

Before sending to Feishu, the shortcut should ideally:

1. confirm that input text is not empty
2. prefer the shared text from the share sheet
3. fall back to clipboard only when the share sheet did not provide text

The shortcut does not need to validate the URL deeply.

It should only avoid sending an empty payload.

## Feishu-side interpretation rules

OpenClaw should parse the message in this order:

1. detect the explicit prefix
2. strip the prefix from the remaining payload
3. route based on prefix, not on vague natural-language inference
4. only if no standard prefix exists, fall back to broader intent interpretation

This ensures that shortcut-originated requests are deterministic.

## Failure-handling expectation

If the share text does not contain an actual URL:

- OpenClaw should not invent a link
- OpenClaw should tell the user the original short link is missing

## Result fields expected back from OpenClaw

Feishu should relay these fields when available:

### Clip result

- `final_run_status`
- `note_path`
- `debug_directory`
- `support_bundle_path`
- `final_message_zh`

### Analyze result

- `final_run_status`
- `clipper_note_path`
- `analyzer_note_path`
- `debug_directory`
- `support_bundle_path`
- `final_message_zh`

### Auth-expired case

- `auth_action_required`
- `auth_refresh_command`
- `auth_guidance_zh`

## Mobile feedback rendering

Feishu should render mobile-facing results using the contract defined in:

- `mobile-feedback-contract.md`

That contract defines:

- Chinese-first result summaries
- success / partial / failure wording
- auth-expired wording
- when to ask for `support-bundle/`
