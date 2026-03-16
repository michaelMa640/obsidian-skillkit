# Platform Routing

## Default Routes

- `article`: normal article pages and blogs
- `social`: Xiaohongshu and Douyin short social content
- `video_metadata`: Bilibili and YouTube long video sources
- `podcast`: Xiaoyuzhou and podcast-style long audio sources

## Principles

- Prefer the lightest useful capture path
- Preserve source metadata for later analysis
- Do not download media files by default
- Prefer transcript/subtitles for long media sources

## Route Notes

### `article`
- Intended capture: title, author, publish date, cleaned main text
- Current status: built-in page fetch + main-text extraction with fallback clipping

### `social`
- Intended capture: visible caption, cover/media references, tags, engagement
- Current status: built-in Playwright page capture with Xiaohongshu / Douyin selectors, wait strategy, and fallback clipping

### `video_metadata`
- Tooling: `yt-dlp`
- Preferred assets: metadata, subtitles, description, thumbnail
- Fallback: minimal clipping with extractor error summary

### `podcast`
- Tooling: built-in page metadata capture in `run_clipper.ps1`
- Preferred assets: title, description, show notes, transcript link hints, RSS hints, audio enclosure hints
- Fallback: minimal clipping with network/error summary
- Analyzer intent: `learn`, not `analyze`
