# Integration Test Matrix

## Goal

Validate the full MVP path:

`iOS Shortcuts -> Feishu bot -> OpenClaw -> Obsidian-Clipper / Obsidian-Analyzer`

The tests in this matrix focus on routing correctness, result visibility, and failure guidance.

## Test categories

### Case 1: Clip success

#### Input

```text
剪藏视频：<valid Douyin share text>
```

#### Expected behavior

- OpenClaw routes to `obsidian-clipper`
- clipping note is created in `Clippings/`
- attachment directory is created
- mobile reply says `剪藏成功`

#### Acceptance criteria

- `final_run_status = SUCCESS`
- `note_path` exists
- `support_bundle_path` exists

## Case 2: Analyze success for raw share text

### Input

```text
拆解视频：<valid Douyin share text>
```

### Expected behavior

- OpenClaw routes to `clip first -> analyze second`
- clipping note is created if missing
- breakdown note is created in `爆款拆解/`
- mobile reply says `拆解成功`

### Acceptance criteria

- clipping note exists
- breakdown note exists
- `final_run_status = SUCCESS` or explicit usable success state

## Case 3: Analyze existing clipping note

### Input

```text
拆解笔记：<absolute clipping note path>
```

### Expected behavior

- OpenClaw skips clipper
- analyzer runs directly
- breakdown note is created or updated

### Acceptance criteria

- analyzer debug directory exists
- breakdown note exists

## Case 4: Missing URL in share text

### Input

```text
拆解视频：<share text with no http/https URL>
```

### Expected behavior

- OpenClaw does not invent a link
- task stops with explicit failure guidance
- mobile reply explains the original short link is missing

### Acceptance criteria

- `final_run_status = FAILED`
- failure message clearly points to missing original short link

## Case 5: Expired Douyin auth

### Input

```text
拆解视频：<valid Douyin share text>
```

### Precondition

- local auth is expired or intentionally removed

### Expected behavior

- clipper detects auth issue
- user gets `需刷新登录态`
- refresh command is included

### Acceptance criteria

- `auth_action_required = refresh_douyin_auth`
- `auth_refresh_command` exists

## Case 6: Missing local config

### Input

```text
剪藏视频：<valid Douyin share text>
```

### Precondition

- required config fields are blank or invalid

### Expected behavior

- config validation runs before capture
- workflow stops
- user gets config file path and missing keys

### Acceptance criteria

- validation failure is explicit
- no false success is reported

## Case 7: Partial analyzer result

### Input

```text
拆解视频：<valid share text>
```

### Precondition

- analyzer returns partial output but not a hard failure

### Expected behavior

- user sees `部分完成`
- reply explains which stage completed and what remains incomplete

### Acceptance criteria

- partial status is not mislabeled as hard failure

## Required debug artifacts

For every test run, keep:

- `support-bundle/`
- result JSON
- summary text

For clip tests:

- clipper debug directory

For analyze tests:

- analyzer debug directory

## Minimum acceptance for Phase 6 completion

Phase 6 is complete when:

1. at least one real `剪藏视频` run succeeds
2. at least one real `拆解视频` run succeeds
3. auth-expired behavior is confirmed
4. config-missing behavior is confirmed
5. the returned mobile-facing messages match the Phase 5 contract
