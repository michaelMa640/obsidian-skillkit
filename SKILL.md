---
name: obsidian
description: Work with Obsidian vaults (plain Markdown notes) using the official Obsidian CLI on desktop. Use when Codex needs to search, read, create, append, prepend, move, rename, delete, or inspect links, tags, tasks, or backlinks in an Obsidian vault from the terminal.
homepage: https://help.obsidian.md
metadata: {"clawdbot":{"emoji":"💎","requires":{"bins":["obsidian"]}}}
---

# Obsidian

Obsidian vault = a normal folder on disk.

Vault structure (typical)
- Notes: `*.md` (plain text Markdown; edit with any editor)
- Config: `.obsidian/` (workspace + plugin settings; usually do not touch from scripts)
- Canvases: `*.canvas` (JSON)
- Attachments: whatever folder you chose in Obsidian settings (images, PDFs, etc.)

## Enable the official CLI

The official CLI command is `obsidian`.

Requirements
- Install Obsidian desktop with CLI support.
- Enable `Settings -> General -> Command line interface`.

Windows
- Put `Obsidian.com` in the same directory as `Obsidian.exe`.
- Make sure that directory is on `PATH`, or call `obsidian` from that install location.
- If you just enabled the CLI, restart the terminal before testing again.
- On Windows, `obsidian` should resolve to `Obsidian.com`, not `Obsidian.exe`.

Notes
- If `obsidian` is not found, the CLI is not enabled, not on `PATH`, or the terminal has not been restarted yet.
- Prefer the official CLI over third-party wrappers when both are available.
- Some terminals show startup log lines before command output.
- Some hosted or sandboxed terminals may fail to capture CLI stdout even when the command works in a normal local terminal.

## Choose the target vault

The CLI resolves the vault like this:
- If the current working directory is inside a vault, use that vault.
- Otherwise use the active vault in the Obsidian app.
- If needed, pass `vault="<vault name>"` explicitly.

Do not hardcode vault paths into scripts unless the user explicitly wants that.

## Quick start

Check that the CLI is available:
- `obsidian --help`
- `Get-Command obsidian`
- `where.exe obsidian`

Expected Windows result:
- `Get-Command obsidian` should show `Source ...\Obsidian.com`
- `where.exe obsidian` should list `Obsidian.com` before `Obsidian.exe`

Work against the current vault:
- `obsidian search query="meeting notes"`
- `obsidian read path="Projects/Plan.md"`
- `obsidian create path="Inbox/New note.md" content="# New note"`

Work against a specific vault by name:
- `obsidian search query="roadmap" vault="WorkVault"`
- `obsidian create path="Inbox/Todo.md" content="- [ ] Follow up" vault="WorkVault"`

Work against a known vault path by changing directory first:
- `cd "C:\path\to\vault"`
- `obsidian search query="welcome"`
- `obsidian read path="welcome.md"`

Validated on Windows:
- Running `obsidian search query="欢迎"` from inside a vault returned matching notes.
- `obsidian help` may only print startup logs in `cmd.exe` or PowerShell instead of a help screen.

## Common commands

Search
- `obsidian search query="query"` searches note names and content.
- `obsidian tags query="#tag"` inspects tags.
- `obsidian tasks path="Projects/Plan.md"` shows tasks in a note.

Read and inspect
- `obsidian read path="Folder/Note.md"`
- `obsidian links path="Folder/Note.md"`
- `obsidian backlinks path="Folder/Note.md"`

Create and edit
- `obsidian create path="Folder/New note.md" content="# Title"`
- `obsidian append path="Daily/2026-03-12.md" content="- Finished task"`
- `obsidian prepend path="Daily/2026-03-12.md" content="# Daily note"`

Move or rename
- `obsidian move path="old/path/note.md" to="new/path/note.md"`
- Prefer this over raw filesystem moves when you want Obsidian-aware refactors.

Delete
- `obsidian delete path="Folder/Old note.md"`

## Windows troubleshooting

If the user enabled the CLI but `obsidian` is still not found:
- Restart the terminal and try `Get-Command obsidian` again.
- Run `where.exe obsidian` to see whether the command is on `PATH`.
- Confirm `Obsidian.com` exists beside `Obsidian.exe`.
- If needed, call the executable by full path first, then fix `PATH` later.
- If the vault is known, `cd` into that vault before testing so the CLI resolves the correct workspace.
- If `where.exe obsidian` shows `Obsidian.exe` but not `Obsidian.com`, reinstall Obsidian or repair the CLI integration.
- If a command works in a normal terminal but not in an agent terminal, treat it as an output-capture issue.

## Working guidelines

- Prefer direct file edits for simple content changes; Obsidian will pick them up.
- Prefer `obsidian move` over `mv` or Explorer rename when link integrity matters.
- Keep note paths relative to the vault root.
- Avoid writing into hidden dot-folders unless the user explicitly asks for it.
- If a command depends on the active vault, state that assumption in the response.
