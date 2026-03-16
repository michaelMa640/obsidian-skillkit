---
name: obsidian-clipper
description: Quickly clip a URL into an Obsidian vault as a reusable raw-content note. Use when OpenClaw should save a link into Clippings first, preserve source facts, and prepare analyzer-ready records.
---

# Obsidian Clipper

## Overview

Use this skill when the user wants to save a source into Obsidian quickly as a stable raw record.

This skill is the first stage of the new workflow:
- OpenClaw receives a clipping request
- `obsidian-clipper` identifies the source type
- the skill routes the request to the appropriate capture path
- the skill writes a clipping note into `Clippings/`
- later, `obsidian-analyzer` reads that stored record and turns it into formal knowledge

This skill does not do deep knowledge extraction by default.
Its job is fast capture, stable metadata, stable IDs, and analyzer-ready record structure.

## Current runnable entrypoint

Current runnable scripts:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`

This implementation already supports:
- URL input
- route detection
- clipping note generation
- filesystem write into an Obsidian vault
- `video_metadata` via real `yt-dlp` metadata/subtitle capture with fallback clipping
- `social` via built-in Playwright page capture plus downloader handoff, with structured comments, engagement hints, candidate video references, attachment landing, and sidecar JSON output
- `podcast` via built-in page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction with fallback clipping

It still does not execute the full ideal external stack for every route.
Treat the current route handlers as a runnable baseline whose short-social path is now downloader-aware, while auth reuse, Bitable sync, and object-storage sync are still pending.

## Responsibilities

`obsidian-clipper` is responsible for:
- normalizing the incoming request
- detecting platform and content type
- choosing the correct capture route
- preserving the source URL and core metadata
- generating deterministic capture identifiers for stable storage
- creating analyzer-ready raw records for later processing
- saving a clipping note into Obsidian

For short social video sources such as Xiaohongshu and Douyin, the architectural contract is now asset-first:
- the clipper stage owns the raw source record
- the clipper stage owns the media download step and attachment landing
- the analyzer stage should consume stored assets instead of re-fetching the source URL

`obsidian-clipper` is not responsible for:
- long-form AI summarization by default
- deep content analysis
- viral-content breakdown
- final knowledge distillation into `Breakdowns/` or `Insights/`

## Core routing model

Use the route that matches the source:
- article pages: built-in page fetch plus main-text extraction, with fallback clipping on fetch failure
- Xiaohongshu and Douyin: built-in Playwright page capture with platform-specific selectors, structured social metadata, downloader handoff, local attachment landing, and fallback clipping
- Bilibili and YouTube: metadata plus subtitles first, currently implemented through `yt-dlp`, with fallback clipping when extraction fails
- Xiaoyuzhou and podcasts: page metadata, RSS hints, transcript hints, and show-notes-style text first, with fallback clipping when the source page cannot be reached

Default rules:
- save the lightest useful representation for the source type
- for short social video, download binary media during clipping when the source is reachable and persist sidecars even if the download fails
- do not block clipping-note creation when media download fails; write a partial record instead
- for long media, stay metadata-first unless the workflow explicitly requires binary download

## Output expectations

Each successful run should create one clipping record that includes:
- `capture_id`
- `capture_key`
- source URL
- normalized URL where available
- platform
- content type
- title
- author or channel if known
- publish date if known
- captured date
- raw text, transcript, or visible page text
- comments or top comments where available
- engagement hints where available
- image or video references where available
- download-state metadata for later reuse

The resulting record should be suitable for later processing by `obsidian-analyzer`.

## Video and podcast rules

For short social video:
- default contract is record-first and asset-ready
- the clipper should preserve title, author, description, visible comments, engagement hints, and candidate video references
- downloader integration belongs to the clipper stage, not the analyzer stage

For Bilibili and YouTube long video:
- default to metadata-first and transcript-first
- do not force binary video download unless the workflow explicitly requires it

For podcasts such as Xiaoyuzhou:
- treat them as knowledge sources, not social short content
- prefer transcript, show notes, RSS hints, episode metadata, and source link
- do not route them into viral-breakdown analysis

## Obsidian handoff

Prefer using the existing Obsidian skill or direct vault file creation depending on the local deployment.

Write clipping notes into a clipping-oriented folder such as:
- `Clippings/`

Keep the note structure stable so downstream analysis can rely on it.
Use a stable attachment pattern such as:
- `Attachments/ShortVideos/{platform}/{capture_id}/`