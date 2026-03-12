---
name: obsidian-archiver
description: Capture, analyze, classify, and archive user-provided multi-format content into an Obsidian vault by combining OpenClaw workflows with x-reader extraction. Use when Codex needs to ingest URLs, webpages, copied text, PDFs, images, local documents, transcripts, or other readable sources, turn them into structured notes, choose the best category folder automatically, and create a new Markdown article in the appropriate Obsidian location.
---

# Obsidian Archiver

## Overview

Use this skill to turn raw sources into durable Obsidian notes.

The goal is consistent intake:
- Extract normalized content and metadata through the local OpenClaw + x-reader workflow.
- Analyze the source for topic, type, intent, and long-term value.
- Choose the best destination folder in the target vault.
- Create one new Markdown note with a clean title, source metadata, summary, insights, and follow-up items.

If the vault structure is unclear, inspect the vault first and adapt to the folders that already exist instead of inventing a new taxonomy.

## Workflow

### 1. Identify the source

Accept any source that x-reader can help normalize, such as:
- URL or webpage
- Copied text or pasted transcript
- PDF or Office document
- Image that requires OCR
- Local file path
- Existing note that needs to be reorganized into a permanent article

Record the source form before extraction. Preserve the original URL or file path whenever available.

### 2. Use the local OpenClaw + x-reader entrypoint

Do not invent x-reader commands.

Instead:
- Search the current workspace or the user's provided repo/config for the actual OpenClaw or x-reader entrypoint.
- Prefer an existing script, task runner, MCP wrapper, or documented command over handwritten one-off extraction code.
- If multiple entrypoints exist, choose the one that already outputs clean text plus metadata.

Target output from extraction:
- canonical text
- title
- author or channel if available
- source URL or file path
- publish date if available
- content type
- any useful structured fields already returned by x-reader

If extraction is partial, continue with the best available content and clearly mark missing metadata as unknown.

### 3. Analyze before filing

Summarize the source into durable knowledge, not a raw dump.

Extract:
- what the source is
- what problem or question it addresses
- the main claims, arguments, or instructions
- useful facts, quotes, or examples worth preserving
- actions, decisions, or follow-ups for the user
- tags and aliases that will make the note easier to find later

Prefer concise synthesis. Avoid copying the full source unless the user explicitly wants a transcript archive.

### 4. Choose the destination folder

Inspect the vault structure and infer the best match from existing folders first.

Use these rules:
- If the vault already has clear category folders, file into the closest existing category.
- If multiple folders fit, prefer the one aligned with the source's long-term use, not its transport format.
- If no confident match exists, file into a capture or inbox-style folder rather than creating taxonomy drift.
- Create a new category folder only when the vault already uses that style and the source clearly belongs there.

Read [references/category-rules.md](references/category-rules.md) for default category heuristics and note structure.

### 5. Create the note

Use a new Markdown note. Keep the filename stable and readable.

Preferred filename pattern:
- `YYYY-MM-DD Title.md` for time-sensitive sources
- `Title.md` for evergreen references
- Sanitize characters that are unsafe for filenames

Preferred note shape:

```md
---
title: <final title>
source_type: <url|pdf|image|text|video|audio|file|other>
source_url: <url or empty>
source_path: <local path or empty>
author: <author/channel/site or unknown>
published: <YYYY-MM-DD or unknown>
captured: <YYYY-MM-DD>
tags:
  - <topic tag>
  - <type tag>
---

# <final title>

## Summary
<4-8 sentence synthesis>

## Key Points
- <point>
- <point>
- <point>

## Insights
- <why this matters>
- <how it connects to existing knowledge or work>

## Actions
- [ ] <optional follow-up>

## Source
- Original: <url or file path>
- Extraction: OpenClaw + x-reader
```

Adapt this template to the vault's established style if the vault already uses frontmatter fields, callouts, or specific sections.

### 6. Write into Obsidian safely

Prefer Obsidian-aware workflows when available:
- Use the official `obsidian` CLI for note creation or moves when it is configured.
- Otherwise write the Markdown file directly inside the vault.

Before writing:
- Ensure the destination folder exists.
- Check whether a note with the same source and near-identical title already exists.
- If a duplicate exists, update or merge only if the user asked for deduplication; otherwise create a clearly distinguished note.

## Classification guidance

Classify by meaning, not just by medium.

Examples:
- A PDF research paper belongs in `Research/` or `Papers/`, not necessarily `PDFs/`.
- A YouTube transcript about product strategy belongs in `Strategy/` or `Product/`.
- A tweet thread that teaches a reusable workflow may belong in `Notes/`, `Methods/`, or `Playbooks/`.
- A tool announcement belongs in `Tools/` if the vault tracks software references.

When the vault already uses PARA, Johnny.Decimal, MOCs, or another explicit system, follow that system instead of the defaults in the reference file.

## Quality bar

The archived note should be:
- findable later by title, tags, and source metadata
- useful without reopening the original source
- short enough to skim
- rich enough to support future writing or decision-making

Do not:
- dump raw extraction without synthesis unless explicitly requested
- create many new folders casually
- lose source attribution
- overwrite an existing note without checking for collisions
