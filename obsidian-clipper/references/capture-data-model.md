# Capture Data Model

## Purpose

This document defines the Phase 1 capture contract for short social video sources.

The goal of Phase 1 is to make `obsidian-clipper` the system of record for raw capture:

- normalize the request
- identify the source
- download the video when the source is short social video
- persist the raw record
- hand off a stable, analyzer-ready record to downstream stages

`obsidian-analyzer` should consume this stored record and should not re-download the source asset.

## Storage Decision

Phase 1 standard:

- Obsidian is the primary store for raw capture notes
- the attachment folder or object storage is the primary store for binary assets
- Feishu Bitable is an index and workflow surface, not the sole source of truth

For local-first deployments, use:

- `Clippings/` for Markdown capture notes
- `Attachments/ShortVideos/{platform}/{capture_id}/` for media assets and sidecar data

## Record Layers

Each captured short video should produce three related artifacts:

1. a clipping note in Obsidian
2. a sidecar JSON record for automation-friendly reads
3. a media asset directory for downloaded files

## Capture ID Rule

`capture_id` must be deterministic so the same source resolves to the same record key.

Use this order:

1. resolve redirects and normalize the URL
2. extract a platform-native item ID when available
3. build `capture_key`:
   - preferred: `{platform}:{source_item_id}`
   - fallback: `{platform}:{normalized_url}`
4. compute `sha256(capture_key)`
5. set `capture_id` to `{platform}_{hash16}`

Where:

- `platform` is lower-case, such as `douyin` or `xiaohongshu`
- `hash16` is the first 16 lower-case hex characters of the SHA-256 digest

Examples:

- `douyin_7e3a4b4c1a2d9f10`
- `xiaohongshu_5d2b88f96e673a41`

## Required Logical Fields

Every short-video capture should be able to represent these fields, even when some are empty:

- `capture_id`
- `capture_key`
- `source_url`
- `normalized_url`
- `platform`
- `content_type`
- `source_item_id`
- `title`
- `author`
- `published_at`
- `captured_at`
- `status`
- `download_status`
- `download_method`
- `media_downloaded`
- `video_path`
- `video_storage_url`
- `cover_path`
- `video_duration_seconds`
- `video_width`
- `video_height`
- `video_size_bytes`
- `video_sha256`
- `comments_count`
- `metrics_like`
- `metrics_comment`
- `metrics_share`
- `analyzer_status`
- `bitable_sync_status`

## Clipping Frontmatter Contract

Recommended frontmatter shape:

```yaml
title: ""
capture_id: ""
capture_key: ""
source_url: ""
normalized_url: ""
platform: douyin
content_type: short_video
source_item_id: ""
author: ""
published_at: ""
captured_at: ""
route: social
status: clipped
download_status: success
download_method: yt-dlp
media_downloaded: true
video_path: Attachments/ShortVideos/douyin/douyin_xxx/video.mp4
video_storage_url: ""
cover_path: Attachments/ShortVideos/douyin/douyin_xxx/cover.jpg
video_duration_seconds: 0
video_width: 0
video_height: 0
video_size_bytes: 0
video_sha256: ""
comments_count: 0
metrics_like: ""
metrics_comment: ""
metrics_share: ""
analyzer_status: pending
bitable_sync_status: pending
tags:
  - clipped
  - social
  - douyin
```

## Sidecar JSON Contract

The sidecar JSON should mirror the frontmatter and carry richer structured data.

Recommended file name:

- `capture.json`

Recommended location:

- `Attachments/ShortVideos/{platform}/{capture_id}/capture.json`

The sidecar should additionally support:

- `summary`
- `description`
- `raw_text`
- `top_comments`
- `comments`
- `engagement`
- `images`
- `videos`
- `errors`
- `fallbacks`
- `capture_version`

## State Rules

Recommended status values:

- `status`: `clipped`, `clip_failed_partial`
- `download_status`: `success`, `failed`, `partial`, `skipped`
- `analyzer_status`: `pending`, `running`, `done`, `failed`, `skipped`
- `bitable_sync_status`: `pending`, `done`, `failed`, `skipped`

## Obsidian Note Requirement

The clipping note should stay readable for a human and structured for a machine.

At minimum, the note body should include:

- source details
- raw description or visible text
- top comments
- video and cover references
- machine metadata summary
- error or fallback summary when capture was incomplete

## Analyzer Handoff Rule

The analyzer should read:

- the clipping note
- the sidecar JSON
- the downloaded video path or storage URL

It should not be responsible for retrieving the source URL again when the clipper already produced a stored asset.
