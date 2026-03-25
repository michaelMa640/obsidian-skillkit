# Obsidian Skillkit

## Overview

This repository is the local skill and gateway workspace for the Obsidian-based short-video workflow.

Current primary modules:

- `obsidian-clipper/`
  - captures raw records into `Clippings/`
  - downloads media and writes sidecars under `Attachments/ShortVideos/...`
- `obsidian-analyzer/`
  - reads an existing clipping plus sidecars
  - writes structured analysis notes into `爆款拆解/`
- `ios-shortcuts-gateway/`
  - receives remote iPhone shortcut requests over local HTTP + Tailscale
  - runs `clip` or `analyze` asynchronously
  - returns an immediate accepted response and sends final status back through Feishu via OpenClaw CLI or webhook
- `obsidian/`
  - direct Obsidian vault operations through the official CLI

Legacy reference module:

- `obsidian-archiver/`
  - older one-step archive flow retained only for compatibility/reference

## Recommended architecture

### Local / OpenClaw workflow

1. OpenClaw receives a URL or share text
2. `obsidian-clipper` writes a clipping note into `Clippings/`
3. `obsidian-analyzer` reads that clipping and writes a breakdown note into `爆款拆解/`

### iPhone workflow

1. iPhone Shortcut sends `clip` or `analyze` to `ios-shortcuts-gateway`
2. Gateway returns immediately with `ACCEPTED` and `request_id`
3. Gateway runs `obsidian-clipper` or `obsidian-clipper -> obsidian-analyzer` in the background
4. Final status is sent back to Feishu

## Repository layout

- `README.md`
- `openclaw-short-video-integration.md`
- `obsidian/SKILL.md`
- `obsidian-clipper/SKILL.md`
- `obsidian-analyzer/SKILL.md`
- `ios-shortcuts-gateway/README.md`
- `*/references/`
- `*/scripts/`

## Runtime notes

### Clipper

- accepts either a clean URL or raw share text
- clipping file names are cleaned for Obsidian-safe note names
- frontmatter keeps the original full title

### Analyzer

- can run from `-NotePath` or `-CaptureJsonPath`
- when only `capture.json` is provided, it now resolves the matching clipping note from the vault
- breakdown note title follows the clipping note title
- breakdown note file date uses the actual analysis run date
- breakdown note source link points back to the resolved clipping note

### Gateway

- `POST /short-video/task`
  - default behavior is asynchronous
  - returns `ACCEPTED`
- `GET /short-video/task/{request_id}`
  - debug/operator status lookup
- Feishu callback
  - recommended mode is `openclaw_cli`
  - `webhook` is still supported as a fallback

## Debug policy

Each runtime module keeps local debug artifacts and a shareable support bundle.

Preferred share target for troubleshooting:

- `support-bundle/`

Use raw local debug files only when the support bundle is not enough.

## Main docs

- [OpenClaw Short-Video Integration](E:\Codex_project\obsidian-skillkit\openclaw-short-video-integration.md)
- [Clipper README](E:\Codex_project\obsidian-skillkit\obsidian-clipper\README.md)
- [Analyzer README](E:\Codex_project\obsidian-skillkit\obsidian-analyzer\README.md)
- [iOS Shortcuts Gateway README](E:\Codex_project\obsidian-skillkit\ios-shortcuts-gateway\README.md)
