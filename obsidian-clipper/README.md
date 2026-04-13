# Obsidian Clipper

## Document Status

- Last Updated: `2026-04-13`

## Change Log

- `2026-04-13`
  - documented the first-run podcast runtime profile flow
  - documented that a new machine should complete the first podcast setup from a local entry before iOS Shortcut is used
- `2026-04-08`
  - reviewed the README against the current verified runtime behavior
  - fixed the landed-video rendering note so it now correctly refers to `video_path`
- `2026-04-07`
  - documented that local social videos are embedded whenever a social clipping has a local `video_path`, even if the detected `content_type` is `social_post`
- `2026-04-07`
  - documented the OpenClaw routing hardening for Feishu clipping requests so Xiaohongshu and Douyin share links should not fall through to `obsidian-archiver` or `web_fetch`
- `2026-04-07`
  - documented the Step 7 removal-readiness assessment for the Xiaohongshu fallback backend
- `2026-04-07`
  - documented the Step 6 fallback-backend behavior for Xiaohongshu
  - clarified that `XHS-Downloader` now runs only when resolved media candidates are missing or fail
- `2026-04-07`
  - documented the Step 5 media pipeline split between media resolution and media download
  - documented the new generic `resolved_media_*` and `media_backend_*` fields
  - updated the Xiaohongshu download order to extractor-first with backend fallback
- `2026-04-05`
  - rewrote the README around the currently verified clipper behavior
  - documented the Xiaohongshu adapter, auth split, blocked-access detection, and note rendering changes
  - documented the current download order and the optional `XHS-Downloader` dependency

`obsidian-clipper` is the first-stage capture skill in the Obsidian workflow.

Its job is to turn a URL or share text into a stable clipping note plus reusable sidecar data, without forcing a full AI analysis step.

## What It Does

- accepts a direct URL or raw app share text
- detects platform and route
- captures structured content into an Obsidian vault
- writes sidecars and landed media into `Attachments/ShortVideos/...`
- preserves a downstream-safe record for `obsidian-analyzer`

## Verified Scope

Current working routes:

- article
- social short video
- `video_metadata`
- podcast

Current verified social platforms:

- Douyin
- Xiaohongshu

## Current Xiaohongshu Behavior

As of `2026-04-07`, Xiaohongshu support includes:

- full short-link extraction from pasted share text such as `https://xhslink.com/o/<id>`
- per-platform auth files instead of reusing Douyin cookies
- blocked-access detection for `website-login/error` and `300012`
- extractor-first media resolution with optional backend fallback through `XHS-Downloader`
- generic media metadata fields such as `resolved_media_*` and `media_backend_*`
- note rendering that embeds the local `.mp4` after `## 原始文案`
- interaction-metric cleanup so malformed labels such as `赞` become `未获取`

Important:

- note creation does not depend on media download
- if Xiaohongshu media download fails, the note can still be saved successfully
- `CategoryHint` folder override is disabled by default, so clip notes should stay in `Clippings/`
- `XHS-Downloader` is now treated as a fallback backend, not the primary Xiaohongshu path
- current engineering verdict: do not remove the fallback backend yet, because the validation set is still too small and too synthetic
- Feishu clipping requests for `xhslink`, `xiaohongshu`, `douyin`, and copied social share text should now route to `obsidian-clipper` first instead of generic web archiving

## Download Strategy

Current Xiaohongshu download order:

1. extractor-provided resolved media candidates
2. optional `XHS-Downloader` backend fallback
3. `yt-dlp` fallback

Current fallback-backend semantics:

- backend is attempted only after the resolved-media stage does not produce a landed video
- runs now record `media_backend_trigger_reason` so it is visible why fallback backend was used

Current Douyin download order:

1. Playwright candidate media refs
2. `yt-dlp`

## What A Good Run Looks Like

For a healthy Xiaohongshu clipping run, you should expect:

- `route = social`
- `platform = xiaohongshu`
- a clipping note in `Clippings/`
- a local `video_path` when media landing succeeds
- `capture.json`, `comments.json`, and `metadata.json` under `Attachments/ShortVideos/...`
- direct embedded local video in the note whenever `video_path` exists

If you instead get a note that says `Processed by: web_fetch`, that note did not come from `obsidian-clipper`.

## Key Scripts

- `scripts/run_clipper.ps1`
  - main PowerShell entrypoint
- `scripts/detect_platform.ps1`
  - platform and route detection
- `scripts/capture_social_playwright.py`
  - social-page capture, metadata extraction, comment capture, block detection
- `scripts/download_social_media.ps1`
  - media download orchestration and attachment landing
- `scripts/xiaohongshu_downloader_adapter.py`
  - adapter that talks to the local `XHS-Downloader` API and normalizes results back into clipper fields
- `scripts/bootstrap_social_auth.py`
  - one-time auth bootstrap helper for platform-specific storage state and cookie export
- `scripts/podcast_asr_fallback.py`
  - optional podcast transcript fallback entrypoint for local audio attachments

## Storage Model

Recommended local layout:

- `Clippings/`
- `Attachments/ShortVideos/{platform}/{capture_id}/`
- `爆款拆解/`

Typical landed files for a social video:

- `capture.json`
- `comments.json`
- `metadata.json`
- `video-*.mp4`
- optional backend payload files such as `xhs-downloader-response.json`

## Local Config

Template:

- `references/local-config.example.json`

Important config points:

- `clipper.allow_category_hint_folder_override`
  - default `false`
- `routes.social.auth.douyin.*`
- `routes.social.auth.xiaohongshu.*`
- `routes.social.xiaohongshu_adapter.server_url`
  - default `http://127.0.0.1:5556/xhs/detail`
- `routes.podcast.download_audio`
- `routes.podcast.runtime_profile`
  - recommended `prompt` on a new machine
- `routes.podcast.asr.*`
  - optional transcript fallback configuration for Phase 3
- `routes.podcast.diarization.*`
  - optional speaker diarization configuration for Step 6

### Podcast runtime profile

Podcast runtime now supports a first-run device selection flow.

Recommended setup on a new machine:

1. keep `routes.podcast.runtime_profile = "prompt"`
2. start the first podcast task from a local entry that can show terminal interaction
3. choose the detected runtime profile
4. let `run_clipper.ps1` write the selected values back into `local-config.json`

The selected profile updates these fields:

- `routes.podcast.runtime_profile`
- `routes.podcast.asr.device`
- `routes.podcast.asr.compute_type`
- `routes.podcast.diarization.device`

Why this matters:

- ASR and diarization may not share the same hardware capability on the same machine
- some machines support GPU ASR but only CPU diarization
- first-run selection avoids forcing users to hand-edit device flags before their first successful podcast run

Important:

- if the machine has never handled podcast clipping before, do the first run from Feishu/OpenClaw or local terminal
- do not use iPhone Shortcut as the first podcast entry, because it cannot reliably present the CPU/GPU selection step
- after the local machine has written the selected runtime profile into `local-config.json`, iPhone Shortcut can use that machine normally
- on Windows, GPU ASR also requires CUDA runtime DLLs to be available inside the active Python environment; installing `faster-whisper` alone is not enough

Validate config with:

```powershell
pwsh .\scripts\validate_local_config.ps1
```

## Auth Bootstrap

Generate dedicated login-state files per platform:

```powershell
python ".\scripts\bootstrap_social_auth.py" --platform douyin
```

```powershell
python ".\scripts\bootstrap_social_auth.py" --platform xiaohongshu
```

## Optional Xiaohongshu Downloader

The bundled helper lives at the repo root:

- `tools/start_xhs_downloader.cmd`
- `tools/start_xhs_downloader.ps1`
- `tools/stop_xhs_downloader.ps1`

What this means in practice:

- if the API is running, Xiaohongshu video landing is more reliable
- if the API is not running, clipper still captures content and falls back gracefully

## Validation And Debugging

Primary validation command:

```powershell
pwsh .\scripts\dev_validate_social_download.ps1
```

Useful outputs:

- `.tmp/social-download-validation/<timestamp>/`
- `support-bundle/`
- `run-clipper.json`
- `capture-social.json`
- `download-social.json`

Preferred files to share first:

- `support-bundle/validation-report.json`
- `support-bundle/run-clipper.log`
- `support-bundle/download-social.json`

## Current Limitations

- Xiaohongshu DOM structure is still not fully stable across all layouts
- some interaction metrics may still be missing even when content capture succeeds
- `XHS-Downloader` is a third-party dependency and currently runs as a separate local API process
- remote object storage sync is not wired yet
- Feishu Bitable upsert is still outside the core clipper path

## Practical Rule Of Thumb

- if you need the note, clipper alone is enough
- if you need the Xiaohongshu video file to land locally, keep `XHS-Downloader` running
- if Feishu behavior does not match this repo, verify the OpenClaw runtime copy under `C:\Users\<user>\.openclaw\workspace\skills\obsidian-clipper`


