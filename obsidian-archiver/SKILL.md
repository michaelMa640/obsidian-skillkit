---
name: obsidian-archiver
description: Orchestrate content capture and archival into Obsidian when OpenClaw receives a command from any connected IM tool and needs to route the task through x-reader for extraction and metadata normalization, then use Obsidian note operations to create a classified Markdown note in the correct vault folder. Use when Codex is acting as the workflow layer between OpenClaw, x-reader, and Obsidian.
---

# Obsidian Archiver

## Overview

Use this skill as an orchestration layer, not as a standalone extractor.

The intended runtime chain is:
- User sends a command from any IM tool already connected to OpenClaw.
- Local OpenClaw receives the command.
- OpenClaw invokes this skill.
- This skill calls the local x-reader entrypoint to extract text and metadata.
- This skill organizes the content into an Obsidian-ready note.
- This skill uses the local Obsidian workflow to write the note into the vault.

This skill should not vendor x-reader source code into the skill folder. Treat x-reader as an external dependency that must already be installed or otherwise reachable from the local OpenClaw environment.

## System role

Responsibilities of each layer:
- IM tool: user-facing command entry
- OpenClaw: command routing, tool invocation, environment ownership
- `obsidian-archiver`: workflow logic, note synthesis, classification, handoff between tools
- x-reader: source reading, OCR, parsing, metadata extraction
- Obsidian integration: note creation, append, move, and vault-aware storage

Keep these responsibilities separate. Do not duplicate x-reader extraction logic inside this skill unless the user explicitly asks to replace x-reader.

## Preconditions

Before using this skill, confirm:
- OpenClaw is already connected to at least one IM tool and can receive local commands.
- x-reader is already deployed locally and has a known callable entrypoint.
- The target Obsidian vault is reachable from the same local environment.
- The Obsidian write path is already solved, either through the official `obsidian` CLI or direct file creation inside the vault.

If any dependency is missing, stop and report the missing layer instead of inventing one.

## Workflow

### 1. Accept the OpenClaw task

The input normally comes from OpenClaw, not directly from the end user.

Expected incoming task payload may include:
- raw user instruction from the connected IM tool
- source URL, file path, pasted text, or attachment reference
- target vault hint
- optional preferred category or tag hint

If OpenClaw provides only partial input, continue with best effort and mark unknown fields explicitly.

### 2. Resolve the local x-reader entrypoint

Do not guess a command.

Find the real local integration point first:
- existing OpenClaw tool wrapper
- shell command
- Python entry script
- MCP server action
- HTTP endpoint on localhost

Prefer the integration that already returns structured metadata.

Expected x-reader output should include as much of the following as possible:
- normalized text
- title
- source type
- source URL or file path
- author, site, or channel
- publish date
- extracted metadata fields

### 3. Normalize the content for archival

Convert the x-reader output into an archive-ready representation.

Always preserve:
- original source reference
- capture date
- content type
- extracted title or fallback title
- summary
- key points
- tags

Prefer synthesis over raw dumps. Only preserve the full original text when the user explicitly wants transcript-style archival.

### 4. Classify the destination

Inspect the target vault structure before choosing a folder.

Rules:
- Prefer an existing folder over creating a new one.
- Classify by meaning, not by file format.
- If the vault has a known taxonomy such as PARA or another explicit layout, follow it.
- If confidence is low, use a safe intake folder such as `Inbox/`, `Capture/`, or `Sources/`.

Use [references/category-rules.md](references/category-rules.md) for default heuristics.

### 5. Build the note payload

Prepare one Markdown note that Obsidian can store directly.

Preferred structure:

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
- <how it connects to user context>

## Actions
- [ ] <optional follow-up>

## Source
- Original: <url or file path>
- Processed by: x-reader
- Archived via: obsidian-archiver
```

Adapt to the vault's existing note conventions if they already exist.

### 6. Handoff to Obsidian storage

Prefer reuse over reinvention.

Storage options, in order:
- Use the existing `obsidian` skill workflow if that is how the local system already writes notes.
- Use the official `obsidian` CLI if it is configured.
- Fall back to direct file creation only when the environment already expects that behavior.

Before writing:
- ensure the target folder exists
- check for obvious duplicates by title and source
- avoid overwriting an existing note silently

### 7. Report the result back through OpenClaw

Return a concise result that OpenClaw can forward back to the originating IM tool.

Include:
- whether extraction succeeded
- which folder the note was written to
- final note title
- source reference
- any missing metadata or fallback behavior used

## Deployment model

This skill is deployed separately from x-reader.

Recommended model:
- Deploy OpenClaw in the local environment.
- Connect at least one IM tool to OpenClaw.
- Deploy x-reader in the same environment or another reachable local endpoint.
- Deploy this skill as the orchestration skill.
- Keep the existing `obsidian` skill available for vault operations.

Do not copy the full x-reader repository into this skill folder unless the user explicitly wants a vendored, pinned fork.

## Quality bar

A successful run should produce:
- one useful, findable Obsidian note
- preserved source attribution
- consistent metadata
- a folder choice that matches the vault's real structure
- a clear status message back to OpenClaw

Do not:
- hardcode non-existent x-reader commands
- bypass OpenClaw when the workflow is meant to be OpenClaw-driven
- mix extractor implementation details into this skill unnecessarily
- create many new categories without evidence from the vault
