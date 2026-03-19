# Real Download Validation

This is a disposable Phase 3 validation flow for short-social download.

## Purpose

Use this when you want to test a real Douyin or Xiaohongshu URL and keep a debug bundle that is easy to share and easy to delete later.

## Default Behavior

- The validator writes into `obsidian-clipper/.tmp/social-download-validation/<timestamp>/`
- It creates a disposable validation vault inside that folder by default
- It stores logs, JSON payloads, and a markdown report in the same folder
- If you want to test against your real vault, pass `-VaultPath`
- When `-VaultPath` is provided, debug logs still stay in `.tmp`, but notes and attachments are written into your real vault

## Auth Setup

If Douyin comments or `yt-dlp` need login state, bootstrap local auth first:

```powershell
python ".\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

By default this writes two local-only files under `obsidian-clipper/.local-auth/`:

- `douyin-storage-state.json`
- `douyin-cookies.txt`

Then copy `references/local-config.example.json` to `references/local-config.json` and set:

- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

## Command

```powershell
powershell -ExecutionPolicy Bypass -File ".\obsidian-clipper\scripts\dev_validate_social_download.ps1" `
  -SourceUrl "https://www.douyin.com/video/REPLACE_ME"
```

Optional real-vault run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\obsidian-clipper\scripts\dev_validate_social_download.ps1" `
  -SourceUrl "https://www.douyin.com/video/REPLACE_ME" `
  -VaultPath "E:\Your\ObsidianVault"
```

## What It Produces

- `detect-platform.json`
- `capture-social.json`
- `download-social.json`
- `run-clipper.json`
- `validation-report.json`
- `validation-report.md`
- `validation-vault-tree.txt`
- tool logs such as `tool-python.log`, `tool-yt-dlp.log`, `tool-ffprobe.log`
- step logs such as `detect-platform.log`, `capture-social.log`, `download-social.log`, `run-clipper.log`

## Privacy Defaults

The validation bundle is intended to be shareable for troubleshooting.

Saved debug artifacts are sanitized before the run completes:
- real vault roots are masked as `<vault-root>`
- auth file paths are masked as `<auth-storage-state>` and `<auth-cookies-file>`
- source URLs are normalized or stripped of extra query noise before being written into final debug artifacts
- local auth files themselves are never copied into the debug bundle

Do not share:
- anything under `obsidian-clipper/.local-auth/`
- `references/local-config.json`
- raw browser exports that contain cookie values

## Success Criteria

- detection route is `social`
- `capture-social.json` contains a non-empty `capture_id`
- `capture-social.json` shows whether `auth_applied` is true and which `auth_mode` was used
- `download-social.json` shows `download_status = success`
- `download-social.json` shows which `yt_dlp_auth_mode` was used
- `download-social.json` has a non-empty `video_path` or valid sidecar paths
- `run-clipper.json` includes a `note_path`
- validation vault contains:
  - `Clippings/`
  - `Attachments/ShortVideos/{platform}/{capture_id}/`

## What To Share For Debugging

If validation fails, the minimum useful bundle is:

- `validation-report.json`
- `detect-platform.log`
- `capture-social.log`
- `download-social.log`
- `run-clipper.log`
- `capture-social.json` if auth or comments look wrong
- `download-social.json` if it exists

## Cleanup

Delete the generated timestamp folder under:

- `obsidian-clipper/.tmp/social-download-validation/`

That removes the disposable vault, logs, and reports together.
