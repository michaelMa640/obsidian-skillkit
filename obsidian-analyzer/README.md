# Obsidian Analyzer

## Document Status

- Last Updated: `2026-04-08`

## Change Log

- `2026-04-08`
  - reviewed the analyzer README against the current two-stage workflow and kept the document aligned with the verified clipper -> analyzer handoff
- `2026-04-05`
  - added document status metadata so future analyzer behavior changes can be tracked in-place

`obsidian-analyzer` is the second stage of the workflow.
It reads an existing clipping note plus sidecar files from Obsidian and writes a structured breakdown note back into the vault.

## Scope

- Input:
  - a clipping note from `Clippings/`
  - or a `capture.json` path that belongs to an existing clipping
- Output:
  - a breakdown note written to `爆款拆解/`
- Current priority:
  - `analyze` mode for Douyin / Xiaohongshu short video content

It does not:

- capture content from the web
- download source media
- replace `obsidian-clipper`

## Main entrypoint

### Note-path mode

```powershell
powershell -ExecutionPolicy Bypass -File "E:\Codex_project\obsidian-skillkit\obsidian-analyzer\scripts\run_analyzer.ps1" `
  -NotePath "E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\michael内容库\Clippings\example.md"
```

### Capture-json mode

```powershell
powershell -ExecutionPolicy Bypass -File "E:\Codex_project\obsidian-skillkit\obsidian-analyzer\scripts\run_analyzer.ps1" `
  -CaptureJsonPath "E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\michael内容库\Attachments\ShortVideos\douyin\example\capture.json"
```

When running from `-CaptureJsonPath`, Analyzer now resolves the matching clipping note from the vault and uses it as the source note.

Optional overrides:

- `-VaultPath`
- `-DebugDirectory`
- `-ConfigPath`
- `-DryRun`

## Configuration

1. Copy `references/local-config.example.json` to `references/local-config.json`
2. Set `obsidian.vault_path`
3. Set `analyzer.default_analyze_folder` if your vault uses a different folder name
4. Configure the model provider under `llm`
5. Put the API key in:
   - `llm.api_key`
   - or the environment variable named by `llm.api_key_env`

Key local settings:

- `obsidian.vault_path`
- `analyzer.default_analyze_folder`
- `analyzer.output_language`
- `analyzer.default_debug_directory`
- `llm.provider`
- `llm.model`
- `llm.api_key`
- `llm.api_key_env`

## Current pipeline

- `scripts/build_analyzer_payload.py`
  - loads clipping/frontmatter/sidecars
  - resolves the source clipping note when only `capture.json` is provided
- `scripts/invoke_analyzer_llm.py`
  - calls the configured provider
  - normalizes defaults
- `scripts/render_breakdown_note.py`
  - renders the final breakdown note into the vault
- `scripts/run_analyzer.ps1`
  - orchestrates the full run
  - writes debug artifacts
  - marks the clipping note as analyzed on successful runs

If no real provider is configured, the run falls back to deterministic mock output instead of crashing.

## Output behavior

- `analyze` mode writes to `爆款拆解/` by default
- output language defaults to `zh-CN`
- breakdown title now follows the clipping note title
- breakdown file date uses the actual analysis run date
- source links point back to the resolved clipping note
- the final note includes:
  - clipping note link
  - capture JSON link
  - local video link
  - embedded local video when available

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

Preferred share target for issue reporting:

- `support-bundle/`

Use the full debug directory only when the support bundle is not enough.

## Related files

- `SKILL.md`
- `references/local-config.example.json`
- `references/analyzer-data-model.md`
- `references/output-note-contract.md`
- `references/prompts/analyze.md`
- `scripts/run_analyzer.ps1`
- `scripts/build_analyzer_payload.py`
- `scripts/invoke_analyzer_llm.py`
- `scripts/render_breakdown_note.py`
