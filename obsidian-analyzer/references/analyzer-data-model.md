# Analyzer Data Model

## Purpose

This document defines the minimum runtime payload for `obsidian-analyzer`.

`obsidian-analyzer` consumes already-clipped records from Obsidian.
It does not re-download the source.

## Accepted Inputs

The runnable entrypoint should accept either:

- `-NotePath`
- `-CaptureJsonPath`

When `-NotePath` is provided, the analyzer may also load sidecar files referenced by the clipping note frontmatter.

## Canonical Analyzer Payload

Minimum fields:

- `analysis_mode`
- `source_note_path`
- `capture_json_path`
- `source_url`
- `normalized_url`
- `title`
- `platform`
- `content_type`
- `capture_id`
- `source_item_id`
- `summary`
- `raw_text`
- `transcript`
- `top_comments`
- `comments_count`
- `metrics_like`
- `metrics_comment`
- `metrics_share`
- `metrics_collect`
- `video_path`
- `cover_path`
- `sidecar_path`
- `comments_path`
- `metadata_path`

Phase 3 adds normalized helper fields so later phases do not need to parse raw note files again:

- `route`
- `capture_key`
- `author`
- `published_at`
- `description`
- `note_body`
- `note_sections`
- `tags`
- `comments`
- `comments_capture_status`
- `comments_source`
- `metrics_source`
- `engagement`
- `source_files`
- `payload_warnings`

`comments` should be normalized into objects with stable keys such as:

- `author`
- `text`
- `display_text`
- `like_count`
- `reply_count`
- `created_at`
- `cid`

## Output Contract

The runtime should produce:

- a structured breakdown note for `analyze`
- a stable JSON result object
- a stable `analyzer-payload.json` artifact
- optional debug artifacts and `support-bundle/`

## Phase 1 Constraint

The first runnable version may generate a mock analysis result before a real LLM adapter is wired.
