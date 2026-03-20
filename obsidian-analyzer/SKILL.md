---
name: obsidian-analyzer
description: Read an existing clipping note from Obsidian and turn it into a structured analysis note. Use after clipping is already complete.
---

# Obsidian Analyzer

## Use this skill when

- the source has already been clipped into Obsidian
- the user wants to analyze, break down, summarize, or structurally extract knowledge from stored content
- the output should be written back into the vault as a reusable analysis note

## Do not use this skill when

- the user only provided a raw URL or share text and the source has not been clipped yet
- the task requires media download or source capture
- the task belongs to `obsidian-clipper`

## OpenClaw behavior rules

- For requests like `拆解视频`, `分析视频`, `爆款拆解`, or `分析这条短视频`:
  - if the input is an existing clipping note or explicit `note_path`, call this skill directly
  - if the input is a raw URL or share text, first call `obsidian-clipper`, then call `obsidian-analyzer`
- Treat `拆解视频（链接）` as `clip first -> analyze second` by default.
- If OpenClaw only matched `obsidian-clipper` first, it must continue into this skill after clipping succeeds.
- The workflow is not complete until the breakdown note is generated or the analyzer stage fails explicitly.
- OpenClaw must trust only the structured outputs returned by `obsidian-clipper`.
- Use the returned `note_path` exactly as-is. Do not reconstruct the clipping file name from:
  - title
  - hashtags
  - platform
  - capture id
  - English slug / pinyin slug
- Do not manually rename clipping notes inside OpenClaw.
- Do not use wildcard matching, directory listing, time-sorted guessing, or generated names such as `2026-03-20-douyin-yashua.md` to locate the clipping note.
- If the returned `note_path` contains Chinese, emoji, or other characters that shell argument passing may mishandle, switch to the returned `sidecar_path` and call `run_analyzer.ps1` with `-CaptureJsonPath`.
- `sidecar_path` is the only supported fallback handoff path when `note_path` cannot be passed safely.
- After one successful clipping run, OpenClaw must not brute-force multiple analyzer retries with guessed paths or guessed capture ids. If the first analyzer handoff fails, stop and surface the real failure.
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
