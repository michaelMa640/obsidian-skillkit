# Feishu Notifier Contract

## Goal

Define the configuration and runtime contract for sending final async task results to Feishu.

## Delivery model

The notifier is a one-way sender:

- input: structured callback payload
- output: Feishu bot message delivery

It does not decide task state.  
It only formats and sends the final result.

## Minimum configuration

Recommended config path:

- `ios-shortcuts-gateway/references/local-config.json`

Required fields:

- `feishu.enabled`
- `feishu.mode`

Optional fields:

- `feishu.target`
- `feishu.openclaw_command`
- `feishu.webhook_url`
- `feishu.timeout_seconds`
- `feishu.message_prefix`

## Rules

- if `feishu.enabled = false`, sending is skipped
- if `feishu.mode = openclaw_cli`, `target` must be non-empty
- if `feishu.mode = webhook`, `webhook_url` must be non-empty
- the notifier must only send terminal states:
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`

## Delivery modes

### `openclaw_cli`

Recommended default.

Uses:

```text
openclaw message send --channel feishu --target <target> --message <text>
```

### `webhook`

Compatibility fallback.

Uses a Feishu custom bot webhook.

## Input contract

The notifier input must match:

- `feishu-callback.payload.schema.json`

## Output format

The first implementation may use Feishu text messages only.

The message must include:

- result summary
- `request_id`
- `status`
- original source link
- normalized link when available
- original shared text when available
- clipper note path when available
- analyzer note path when available
- refresh instruction when required

## Error handling

- notifier failure must not erase task completion status
- send failure should be logged
- send failure can be retried later, but retry policy is out of scope for this phase
