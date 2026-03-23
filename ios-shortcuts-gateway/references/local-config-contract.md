# Local Config Contract

## Goal

Define the local configuration required by `ios-shortcuts-gateway`.

## Config file

Recommended location:

- `ios-shortcuts-gateway/references/local-config.json`

This file is local-machine specific and must not be committed with secrets.

## Required fields

### Server

- `server.host`
- `server.port`
- `server.bind_mode`

### Auth

- `auth.bearer_token`

### Routing

- `routing.clipper_script`
- `routing.analyzer_script`

### Vault

- `obsidian.vault_path`

## Optional fields

### Network

- `server.allowed_tailscale_cidr`

### Logging

- `logging.level`
- `logging.directory`
- `logging.redact_source_text`

### Runtime

- `runtime.python_command`
- `runtime.powershell_command`

## Field rules

### `server.host`

Recommended:

- a Tailscale IP
- or `127.0.0.1` for local-only debugging

### `server.bind_mode`

Allowed values:

- `tailscale_only`
- `localhost_only`

### `auth.bearer_token`

Rules:

- must be a long random string
- must not be empty
- must not be reused from unrelated apps

### `routing.clipper_script`

Should point to:

- `obsidian-clipper/scripts/run_clipper.ps1`

### `routing.analyzer_script`

Should point to:

- `obsidian-analyzer/scripts/run_analyzer.ps1`

## Non-goals of config

The config must not support:

- arbitrary shell templates
- arbitrary command fragments
- arbitrary script lists

The purpose of config is to bind fixed local paths, not to become a general task engine.
