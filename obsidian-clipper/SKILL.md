---
name: obsidian-clipper
description: Primary clipping route for Douyin/Xiaohongshu social share links and share text. Use when OpenClaw should save a link into Clippings first, preserve source facts, and prepare analyzer-ready records. This skill should win over obsidian-archiver for xhslink, xiaohongshu, douyin, and copied social share text.
---

# Obsidian Clipper

## Use this skill when

- the user wants to clip, save, archive, or collect a link into Obsidian
- the user provides a raw URL or a full share-text block copied from Douyin / Xiaohongshu
- the link is from `xhslink.com`, `xiaohongshu.com`, `douyin.com`, `iesdouyin.com`, or another short-social share domain
- the content is a Xiaohongshu note, post, or share page even if it looks like an article instead of a short video
- the user wants a stored clipping note first, before any deeper analysis

## Do not use this skill when

- the user already has an Obsidian clipping note and only wants analysis
- the task is purely downstream analysis or knowledge distillation

## OpenClaw behavior rules

- User intent like `剪藏`, `保存链接`, `收录视频`, `保存到 Obsidian` should call this skill directly.
- Explicit entry prefixes like `剪藏视频：` or `剪藏：` should call this skill directly.
- If the input contains a Douyin / Xiaohongshu share link or copied share text, do not route to `obsidian-archiver`, `web_fetch`, or a direct `write` flow first.
- For `xhslink.com`, `xiaohongshu.com`, `douyin.com`, and copied app-share blocks, this skill must be treated as the default clipping entry even when the page looks like an article, note, or mixed media post.
- Do not classify Xiaohongshu note links as generic web articles just because the title or body reads like an article.
- Do not create a manual summary note when this skill should have been used. First run the clipper, then summarize or analyze from the returned clipping record if needed.
- If the user intent contains `拆解`, `分析`, `爆款拆解`, or `分析视频`, and the input is a raw URL or share text, do not stop after clipping.
- In that case, this skill is stage 1 of a two-stage workflow:
  - first create the clipping note
  - then hand the returned `note_path` or `sidecar_path` to `obsidian-analyzer`
- `拆解视频（链接）` must not end at clipping unless clipping itself failed.
- `拆解视频：<share text>` must not end at clipping unless clipping itself failed.
- OpenClaw must use the exact `note_path` and `sidecar_path` returned by this skill.
- Do not rewrite the clipping note name into a slug, English alias, pinyin alias, or capture-id file name.
- Do not manually rename the clipping note inside OpenClaw.
- If the returned `note_path` contains Chinese or emoji and passing it to the next shell step is unreliable, pass `sidecar_path` forward and let `obsidian-analyzer` run with `-CaptureJsonPath`.
- If the machine is running this skill for the first time, or the run fails before capture starts, run `scripts/validate_local_config.ps1` first.
- If `validate_local_config.ps1` reports missing required fields, stop and tell the user:
  - which file to edit
  - which fields are missing
  - what they should point to
- Do not continue until required config is fixed.
- If the run fails with a Douyin auth problem, especially `Fresh cookies are needed`, tell the user local auth must be refreshed.
- In that auth-expired case, tell the user to run:
  - `python "E:\Codex_project\obsidian-skillkit\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin`
- Always return these fields after a run:
  - `note_path`
  - `sidecar_path`
  - `debug_directory`
  - `support_bundle_path`
  - `final_run_status`
  - `failed_step` when failed
  - `auth_action_required` and `auth_refresh_command` when auth refresh is needed

## Current entrypoints

- `scripts/run_clipper.ps1`
- `scripts/validate_local_config.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`
- `scripts/bootstrap_social_auth.py`

## Responsibilities

- normalize incoming source input
- extract an embedded URL from share text
- detect route, platform, and content type
- capture the raw source record
- create a clipping note in Obsidian
- for short social video, download media during clipping when possible
- persist sidecar JSON and attachment references even if download partially fails

## Output contract

Each run should create or update a clipping record that includes:

- `capture_id`
- `capture_key`
- `source_url`
- `normalized_url`
- `platform`
- `content_type`
- `title`
- `author`
- `published_at`
- `comments` / `top_comments` when available
- engagement hints when available
- `download_status`
- `download_method`
- `video_path`
- `sidecar_path`

## Debug and support contract

Every non-trivial run should keep a debug directory and a shareable support bundle.

The main fields OpenClaw should surface back to the user are:

- `note_path`
- `sidecar_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `final_message_en`
- `final_message_zh`

When auth expires, the result should also include:

- `auth_action_required = refresh_douyin_auth`
- `auth_failure_reason`
- `auth_refresh_command`
- `auth_guidance_en`
- `auth_guidance_zh`

If the user needs help, ask them to upload `support-bundle/` first.
