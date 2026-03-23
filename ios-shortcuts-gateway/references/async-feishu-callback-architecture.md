# Async Task and Feishu Callback Architecture

## Goal

Move the iPhone-triggered workflow from synchronous waiting to asynchronous execution:

`iPhone Shortcuts -> Gateway -> immediate ACCEPTED -> background task -> Clipper / Analyzer -> Feishu callback`

## Why

The current synchronous pattern is not suitable for mobile clients because:

- `clip` can take tens of seconds
- `analyze` can take even longer
- iOS Shortcuts frequently times out on long-running HTTP requests

The gateway should therefore acknowledge receipt quickly and finish the heavy work in the background.

## Target flow

1. iPhone sends `POST /short-video/task`
2. Gateway validates the request
3. Gateway writes a request-local status file
4. Gateway returns:
   - `status = ACCEPTED`
   - `request_id`
5. Background worker executes:
   - `run_clipper.ps1`
   - optionally `run_analyzer.ps1`
6. Gateway persists final status
7. Gateway sends a Feishu callback message to the user

## Required callback content

Every final Feishu callback must include:

- `request_id`
- requested action: `clip` or `analyze`
- final status: `SUCCESS`, `PARTIAL`, `FAILED`, or `AUTH_REQUIRED`
- short Chinese result summary
- source link for the submitted video
- original shared text when available
- clipping note path when available
- breakdown note path when available
- login-refresh instruction when required

## Link fields to preserve

The callback must preserve enough source information for later reuse.

At minimum it should return:

- `source_url`
- `normalized_url`
- `original_source_text`

If more than one is available, all should be included.

## Task lifecycle states

- `ACCEPTED`
- `RUNNING`
- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

## Gateway responsibilities

- accept and validate the task
- assign `request_id`
- persist request and status files
- execute fixed local workflows in the background
- emit Feishu callback on completion

## Feishu responsibilities

- serve as the user-facing async notification channel
- receive final task results from the Gateway
- display links, statuses, and remediation guidance

## Non-goals

- no synchronous mobile waiting for final business results
- no direct mobile polling as the primary UX
- no arbitrary message routing or multi-user auth in the MVP
