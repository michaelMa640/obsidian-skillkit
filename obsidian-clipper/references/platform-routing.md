# Platform Routing

## Default Routes

- `article`: normal article pages and blogs
- `social`: Xiaohongshu and Douyin short social content
- `video_metadata`: Bilibili and YouTube long video sources
- `podcast`: Xiaoyuzhou and podcast-style long audio sources

## Principles

- Prefer the lightest useful capture path for the source type
- Preserve source metadata for later analysis
- Short social video is asset-first in Phase 1: clip and download in `obsidian-clipper`
- Long media remains metadata-first unless the workflow explicitly requires binary download
- Do not block note creation when media download fails; write a partial record instead

## Route Notes

### `article`
- Intended capture: title, author, publish date, cleaned main text
- Current status: built-in page fetch + main-text extraction with fallback clipping

### `social`
- Intended capture: visible caption, top comments, engagement, media references, downloaded video, and analyzer-ready metadata
- Current implementation: built-in Playwright page capture with Xiaohongshu / Douyin selectors, wait strategy, and fallback clipping
- Phase 1 target: `obsidian-clipper` owns video download, attachment placement, and sidecar record creation before analyzer handoff

### `video_metadata`
- Tooling: `yt-dlp`
- Preferred assets: metadata, subtitles, description, thumbnail
- Fallback: minimal clipping with extractor error summary

### `podcast`
- Tooling: built-in page metadata capture in `run_clipper.ps1`
- Preferred assets: title, description, show notes, transcript link hints, RSS hints, audio enclosure hints
- Phase 1 capture result: stable `capture_id`, page + RSS merged metadata, Obsidian note, and podcast sidecars under `Attachments/Podcasts/{platform}/{capture_id}/`
- Fallback: minimal clipping with network/error summary
- Analyzer intent: `learn`, not `analyze`
