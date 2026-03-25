# Integration Test Matrix

## Goal

Validate the older Feishu-forwarding MVP path:

`iOS Shortcuts -> Feishu bot -> OpenClaw -> Obsidian-Clipper / Obsidian-Analyzer`

Note:

- this document is now for the Feishu-forwarding path only
- the current primary mobile path is documented under `ios-shortcuts-gateway/`

## Test categories

### Case 1: Clip success

Input:

```text
剪藏视频：<valid Douyin share text>
```

Expected behavior:

- OpenClaw routes to `obsidian-clipper`
- clipping note is created in `Clippings/`
- attachment directory is created

Acceptance:

- `final_run_status = SUCCESS`
- `note_path` exists
- `support_bundle_path` exists

### Case 2: Analyze success for raw share text

Input:

```text
拆解视频：<valid Douyin share text>
```

Expected behavior:

- OpenClaw routes to `clip first -> analyze second`
- clipping note is created if missing
- breakdown note is created in `爆款拆解/`

Acceptance:

- clipping note exists
- breakdown note exists
- `final_run_status = SUCCESS` or another explicit usable success state

### Case 3: Analyze existing clipping note

Input:

```text
拆解笔记：<absolute clipping note path>
```

Expected behavior:

- OpenClaw skips clipper
- analyzer runs directly
- breakdown note is created or updated

### Case 4: Missing URL in share text

Input:

```text
拆解视频：<share text with no http/https URL>
```

Expected behavior:

- OpenClaw does not invent a link
- task stops with explicit failure guidance

### Case 5: Expired Douyin auth

Expected behavior:

- clipper detects auth issue
- user gets refresh guidance

### Case 6: Missing local config

Expected behavior:

- config validation runs before capture
- workflow stops with explicit config guidance

### Case 7: Partial analyzer result

Expected behavior:

- partial state is shown as partial, not mislabeled as hard failure
