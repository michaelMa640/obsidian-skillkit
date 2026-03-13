---
name: obsidian-clipper
description: Quickly clip a URL into an Obsidian vault as a reusable raw-content note. Use when OpenClaw should save a link into Clippings first, without waiting for deep AI analysis.
---

# Obsidian Clipper

## Overview

Use this skill when the user wants to save a link into Obsidian quickly.

This skill is the first stage of the new workflow:
- OpenClaw receives a clipping request
- `obsidian-clipper` identifies the source type
- the skill routes the request to the appropriate capture path
- the skill writes a clipping note into `Clippings/`
- later, `obsidian-analyzer` can read that clipping and turn it into formal knowledge

This skill does not do deep knowledge extraction by default.
Its job is fast capture, stable metadata, and analyzer-ready note structure.

## Current runnable entrypoint

Current first runnable scripts:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

This first implementation already supports:
- URL input
- route detection
- clipping note generation
- filesystem write into an Obsidian vault

It does not yet execute the full external capture stack for every route.
Treat current route handlers as a minimal executable skeleton that the next implementation steps will deepen.

## Responsibilities

`obsidian-clipper` is responsible for:
- normalizing the incoming request
- detecting platform and content type
- choosing the correct capture route
- preserving the source URL and core metadata
- saving a clipping note into Obsidian

`obsidian-clipper` is not responsible for:
- long-form AI summarization by default
- deep content analysis
- viral-content breakdown
- full media downloading unless explicitly requested

## Core routing model

Use the route that matches the source:
- article pages: browser plus article extraction
- Xiaohongshu and Douyin: browser page capture
- Bilibili and YouTube: metadata plus subtitles first, currently implemented through `yt-dlp`, with fallback clipping when extraction fails
- Xiaoyuzhou and podcasts: transcript/show-notes first

Default rule:
- save the lightest useful representation first
- do not block clipping on heavy media processing

## Output expectations

Each successful run should create one clipping note that includes:
- source URL
- platform
- content type
- title
- author or channel if known
- publish date if known
- captured date
- raw text, transcript, or visible page text
- image or video references where available
- metadata block for later reuse

The note should be suitable for later processing by `obsidian-analyzer`.

## Video and podcast rules

For video:
- default to link-first and transcript-first
- do not download the video file by default

For podcasts such as Xiaoyuzhou:
- treat them as knowledge sources, not social short content
- prefer transcript, show notes, episode metadata, and source link
- do not route them into viral-breakdown analysis

## Obsidian handoff

Prefer using the existing Obsidian skill or direct vault file creation depending on the local deployment.

Write clipping notes into a clipping-oriented folder such as:
- `Clippings/`

Keep the note structure stable so downstream analysis can rely on it.