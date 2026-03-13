---
name: obsidian-archiver
description: Legacy one-step x-reader based archival workflow for Obsidian. Use mainly for compatibility or migration support, not as the primary path for new two-stage development.
---

# Obsidian Archiver (Legacy)

## Status

This skill is now a legacy compatibility path.

Prefer the newer architecture for ongoing development:
- `obsidian-clipper` for first-stage clipping
- `obsidian-analyzer` for second-stage analysis

Use `obsidian-archiver` mainly when:
- you still need the older x-reader based workflow
- you are migrating an existing OpenClaw deployment
- you need to compare old and new behavior during transition

## Legacy workflow

Old intended runtime chain:
- OpenClaw receives a command
- `obsidian-archiver` calls x-reader
- x-reader extracts content and metadata
- `obsidian-archiver` builds a Markdown note
- the note is written into Obsidian

## Why this is legacy now

The repository has moved to a two-stage model:
- first clip content quickly into `Clippings/`
- then analyze clipped notes into formal knowledge

That newer model is more reliable, faster for users, and better aligned with Obsidian as a content database.

## Current responsibilities

If this legacy skill is still used, it should:
- accept a source URL or other input
- call x-reader through the local wrapper
- normalize the result into one note
- write the note into Obsidian

It should not be the base for new feature expansion unless the user explicitly chooses to keep the legacy path.