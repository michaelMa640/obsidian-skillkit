---
name: obsidian-analyzer
description: Read an existing clipping note from Obsidian and turn it into a structured analysis note. Use after clipping is already complete.
---

# Obsidian Analyzer

## Use this skill when

- the source has already been clipped into Obsidian
- the task is to analyze, summarize, or structurally break down that stored content
- the output should be written back into the vault as a reusable note

## Do not use this skill when

- the user needs web capture or media download
- the source URL has not been clipped yet
- the task belongs to `obsidian-clipper`

## Current priority

Current runnable priority is `analyze` mode for short-video content, especially Douyin and Xiaohongshu.

## Responsibilities

- read a clipping note
- resolve sidecars such as `capture.json`
- build a normalized analyzer payload
- invoke a configured LLM provider or fall back to mock output
- render the final note into the Obsidian vault
- produce debug artifacts and a shareable `support-bundle`

## Entry point

- `scripts/run_analyzer.ps1`

## Key implementation files

- `scripts/build_analyzer_payload.py`
- `scripts/invoke_analyzer_llm.py`
- `scripts/render_breakdown_note.py`
- `references/prompts/analyze.md`
- `references/analyze-output.schema.json`
- `references/local-config.example.json`

## Debug expectations

Every run should produce a timestamped debug directory containing at least:

- `analyzer-payload.json`
- `analysis-input.json`
- `run-analyzer.json`
- `run-analyzer-summary.txt`
- `support-bundle/`

When a real provider is used, the run may also include:

- `llm-request.json`
- `llm-response.json`

When helping users debug, prefer asking for `support-bundle/` first.
