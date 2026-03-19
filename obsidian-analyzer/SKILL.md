---
name: obsidian-analyzer
description: Read an existing clipping note from Obsidian and turn it into a structured analysis note. Use after clipping is already complete.
---

# Obsidian Analyzer

## Use this skill when

- the source has already been clipped into Obsidian
- the user wants to analyze,拆解, summarize, or structurally break down stored content
- the output should be written back into the vault as a reusable analysis note

## Do not use this skill when

- the user only provided a raw URL or share text and the source has not been clipped yet
- the task requires media download or source capture
- the task belongs to `obsidian-clipper`

## OpenClaw behavior rules

- User intent like `拆解视频`, `分析视频`, `分析这条短视频` needs two different behaviors:
  - if the input is an existing clipping note or explicit `note_path`, call this skill directly
  - if the input is a raw URL or share text, first call `obsidian-clipper`, then call `obsidian-analyzer` with the returned `note_path`
- Treat `拆解视频（链接）` as `clip first -> analyze second` by default.
- If the machine is running this skill for the first time, or the run fails before payload build, run `scripts/validate_local_config.ps1` first.
- If required config is missing, stop and tell the user exactly which file and fields must be updated.
- Always return these fields after a run:
  - `note_path`
  - `debug_directory`
  - `support_bundle_path`
  - `final_run_status`
  - `failed_step` when failed

## Entry points

- `scripts/run_analyzer.ps1`
- `scripts/validate_local_config.ps1`

## Key implementation files

- `scripts/build_analyzer_payload.py`
- `scripts/invoke_analyzer_llm.py`
- `scripts/render_breakdown_note.py`
- `references/prompts/analyze.md`
- `references/analyze-output.schema.json`
- `references/local-config.example.json`

## Responsibilities

- read a clipping note
- resolve sidecars such as `capture.json`
- build a normalized analyzer payload
- invoke the configured LLM provider or fall back to mock output
- render the final analysis note into the Obsidian vault
- produce debug artifacts and a shareable `support-bundle`

## Debug and support contract

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
