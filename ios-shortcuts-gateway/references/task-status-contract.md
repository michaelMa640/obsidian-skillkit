# Task Status Contract

## Goal

Define the persistent status model for every async Gateway request.

## Storage location

Each request must have a dedicated directory:

- `.tmp/gateway/runs/<request_id>/`

The current task state is stored in:

- `status.json`

## Required fields

- `request_id`
- `action`
- `status`
- `message_zh`
- `created_at`
- `updated_at`

## Optional fields

- `failed_step`
- `source_url`
- `normalized_url`
- `original_source_text`
- `clipper_note`
- `analyzer_note`
- `auth_action_required`
- `refresh_command`
- `debug_hint`
- `callback_attempted_at`
- `callback_sent`
- `callback_error`

## Allowed statuses

- `ACCEPTED`
- `RUNNING`
- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

## State transitions

Allowed path:

- `ACCEPTED -> RUNNING`
- `RUNNING -> SUCCESS`
- `RUNNING -> PARTIAL`
- `RUNNING -> FAILED`
- `RUNNING -> AUTH_REQUIRED`

`ACCEPTED` is written immediately after request validation.  
`RUNNING` is written when background execution begins.  
Terminal states are:

- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

## Terminal-state rule

Once a task reaches a terminal state:

- `status.json` must not be downgraded
- task status must remain terminal even if callback delivery fails

## Callback recording rule

If a terminal-state callback is attempted, `status.json` should record:

- `callback_attempted_at`
- `callback_sent`
- `callback_error`

The callback result must not overwrite the underlying task outcome.

## Source-link preservation rule

If available, `status.json` must retain:

- `source_url`
- `normalized_url`
- `original_source_text`

This is required for the Feishu callback stage.
