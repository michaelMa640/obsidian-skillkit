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
