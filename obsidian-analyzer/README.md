# Obsidian Analyzer

`obsidian-analyzer` is the second stage of the workflow.
It reads an existing clipping note plus sidecar files from Obsidian and writes a structured analysis note back into the vault.

## Scope

- Input: a clipping note from `Clippings/` and its sidecars such as `capture.json`
- Output: a knowledge note written to `爆款拆解/` for `analyze` mode
- Current priority: `analyze` for Douyin / Xiaohongshu short video content

It does not:

- capture content from the web
- download source media
- replace `obsidian-clipper`

## Main entrypoint

Run with only a note path after `references/local-config.json` is configured:

```powershell
powershell -ExecutionPolicy Bypass -File "E:\Codex_project\obsidian-skillkit\obsidian-analyzer\scripts\run_analyzer.ps1" `
  -NotePath "E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\michael内容库\Clippings\example.md"
```

Optional overrides:

- `-VaultPath`
- `-DebugDirectory`
- `-ConfigPath`
- `-DryRun`

## Configuration

1. Copy `references/local-config.example.json` to `references/local-config.json`
2. Set `obsidian.vault_path`
3. Set `analyzer.default_analyze_folder` if your vault uses a different folder name
4. Configure the model provider in `llm`
5. Put the API key in either:
   - `llm.api_key` in `local-config.json`
   - or the environment variable named by `llm.api_key_env`

Key local settings:

- `obsidian.vault_path`
- `analyzer.default_learn_folder`
- `analyzer.default_analyze_folder`
- `analyzer.output_language`
- `analyzer.default_debug_directory`
- `llm.provider`
- `llm.model`
- `llm.api_key`
- `llm.api_key_env`

## Current pipeline

- `scripts/build_analyzer_payload.py`
  reads the clipping note and sidecars and produces `analyzer-payload.json`
- `scripts/invoke_analyzer_llm.py`
  calls the configured model provider for `analyze` mode
- `scripts/render_breakdown_note.py`
  renders the final note into the vault
- `scripts/run_analyzer.ps1`
  orchestrates the full run and writes debug artifacts

If no real provider is configured, the pipeline falls back to deterministic mock output instead of crashing the full run.

## Debug and support

Every run creates a debug directory.
By default it is rooted at `analyzer.default_debug_directory`, and each run gets its own timestamped subfolder.

Typical artifacts:

- `analyzer-payload.json`
- `analysis-input.json`
- `llm-request.json`
- `llm-response.json`
- `run-analyzer.json`
- `run-analyzer-summary.txt`
- `support-bundle/`

`support-bundle/` is the shareable package for issue reporting.
It contains sanitized copies of the main debug artifacts so another machine can be diagnosed without exposing the local vault path.

When asking for help, upload either:

- `support-bundle/`
- or the full debug directory if more detail is needed

## Output behavior

- `analyze` mode writes to `爆款拆解/` by default
- output language defaults to `zh-CN`
- the final note includes:
  - source links
  - capture JSON link
  - local video link
  - embedded local video when available

## Related files

- `SKILL.md`
- `references/local-config.example.json`
- `references/analyzer-data-model.md`
- `references/analyzer-record.schema.json`
- `references/analyze-output.schema.json`
- `references/output-note-contract.md`
- `references/prompts/analyze.md`
- `scripts/run_analyzer.ps1`
- `scripts/build_analyzer_payload.py`
- `scripts/invoke_analyzer_llm.py`
- `scripts/render_breakdown_note.py`
