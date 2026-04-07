# Obsidian Skillkit

## Document Status

- Last Updated: `2026-04-07`

## Change Log

- 2026-04-07
  - rendering now embeds local social videos based on ideo_path instead of only short_video, fixing Xiaohongshu notes that were detected as social_post
- 2026-04-07
  - hardened OpenClaw routing guidance so Feishu 剪藏 + xhslink / xiaohongshu / douyin requests should go to obsidian-clipper instead of generic web archiving
- `2026-04-07`
  - documented the Step 7 readiness decision for whether Xiaohongshu can remove the fallback backend today
- `2026-04-07`
  - documented the Step 6 fallback-backend behavior for Xiaohongshu media download
- `2026-04-07`
  - documented the Step 5 generic media resolution pipeline and backend fallback fields
  - updated the Xiaohongshu download order to extractor-first with backend fallback
- `2026-04-05`
  - rewrote the root overview to match the current Feishu / OpenClaw workflow
  - documented the Xiaohongshu short-link fix, blocked-access detection, and local video embedding status
  - documented the optional `XHS-Downloader` role and the split between development repo and OpenClaw runtime copy

This repository is the local workspace for the Obsidian-based short-video workflow used by OpenClaw, Feishu, and the optional iPhone gateway.

## Current Status

Verified on `2026-04-07`:

- `obsidian-clipper/` can capture Douyin and Xiaohongshu share text into `Clippings/`
- Xiaohongshu share text now preserves the full `xhslink.com/o/<id>` short link instead of truncating to `/o`
- Xiaohongshu notes now:
  - keep platform-specific auth separate from Douyin
  - detect `website-login/error` and `300012` as blocked access instead of pretending the clip succeeded
  - embed the downloaded local `.mp4` after `## 原始文案`
  - clean malformed interaction labels such as `赞` so they render as `未获取`
- `obsidian-analyzer/` can read an existing clipping plus sidecars and write structured notes into `爆款拆解/`
- `ios-shortcuts-gateway/` still supports the remote iPhone path, but Feishu -> OpenClaw is the main day-to-day entry

Important Xiaohongshu nuance:

- content capture does not require `XHS-Downloader`
- local video landing currently benefits from the optional `XHS-Downloader` adapter
- if that API is not running, the clipping note is still created, but the Xiaohongshu video file may not land locally
- current clip runs also record generic `resolved_media_*` and `media_backend_*` fields so media resolution and media download can evolve independently
- `XHS-Downloader` now acts as a fallback backend behind the built-in Xiaohongshu extractor path
- current engineering verdict: keep the fallback backend for now, because the current validation sample is not yet enough to justify hard removal

## Main Modules

- `obsidian-clipper/`
  - raw capture into `Clippings/`
  - sidecars and media under `Attachments/ShortVideos/...`
- `obsidian-analyzer/`
  - structured analysis output into `爆款拆解/`
- `ios-shortcuts-gateway/`
  - optional local HTTP gateway for iPhone Shortcut submission
- `obsidian/`
  - direct Obsidian vault operations through the official CLI
- `tools/`
  - local helper tools, including the bundled `XHS-Downloader` launcher

## Runtime Paths

There are usually two relevant copies of the clipper code on a machine:

1. Development repo:
   - `E:\Codex_project\obsidian-skillkit\obsidian-clipper`
2. OpenClaw runtime copy:
   - `C:\Users\<user>\.openclaw\workspace\skills\obsidian-clipper`

If Feishu / OpenClaw behavior does not match the repo, check whether the runtime copy has been synced.

## Recommended Flow

### Feishu / OpenClaw

1. OpenClaw receives `剪藏视频：<share text or url>` or `拆解视频：<share text or url>`
2. `obsidian-clipper` creates a clipping note in `Clippings/`
3. `obsidian-analyzer` optionally reads that clipping and writes a breakdown note into `爆款拆解/`

### iPhone Shortcut

1. iPhone Shortcut sends a request to `ios-shortcuts-gateway`
2. Gateway returns immediately with `ACCEPTED`
3. Gateway runs `obsidian-clipper` or `obsidian-clipper -> obsidian-analyzer`
4. Final status goes back to Feishu asynchronously

## Xiaohongshu Video Download

Current download order for Xiaohongshu short video:

1. extractor-provided resolved media candidates
2. optional `XHS-Downloader` backend fallback
3. `yt-dlp` fallback

The local helper scripts in `tools/` start and stop the bundled API:

- `tools/start_xhs_downloader.cmd`
- `tools/start_xhs_downloader.ps1`
- `tools/stop_xhs_downloader.ps1`

Default adapter endpoint:

- `http://127.0.0.1:5556/xhs/detail`

## Debugging

Preferred artifacts for troubleshooting:

- `support-bundle/`
- `run-clipper.json`
- `capture.json`
- `download-social.json`

For social validation runs:

- `obsidian-clipper/.tmp/social-download-validation/<timestamp>/`

## Main Docs

- [Clipper README](E:\Codex_project\obsidian-skillkit\obsidian-clipper\README.md)
- [Analyzer README](E:\Codex_project\obsidian-skillkit\obsidian-analyzer\README.md)
- [OpenClaw Short-Video Integration](E:\Codex_project\obsidian-skillkit\openclaw-short-video-integration.md)
- [iOS Shortcuts Gateway README](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\README.md)


