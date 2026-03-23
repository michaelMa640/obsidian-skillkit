param(
    [string]$ConfigPath = "",
    [switch]$UseConfigHost
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleDir = Split-Path -Parent $scriptDir
$referencesDir = Join-Path $moduleDir "references"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $referencesDir "local-config.json"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Gateway config not found: $ConfigPath"
}

$pythonCommand = "python"
$configJson = @"
import json
from pathlib import Path
path = Path(r'''$ConfigPath''')
config = json.loads(path.read_text(encoding='utf-8'))
print(json.dumps(config, ensure_ascii=False))
"@

$configRaw = $configJson | & $pythonCommand -
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($configRaw)) {
    throw "Failed to parse gateway config via Python: $ConfigPath"
}

$config = $configRaw | ConvertFrom-Json
$serverHost = "127.0.0.1"
if ($UseConfigHost) {
    $serverHost = [string]$config.server.host
}
$port = [int]$config.server.port

if ($config.runtime.python_command) {
    $pythonCommand = [string]$config.runtime.python_command
}

Write-Host ""
Write-Host "=== Gateway Startup ==="
Write-Host "config   : $ConfigPath"
Write-Host "host     : $serverHost"
Write-Host "port     : $port"
Write-Host "mode     : $($config.server.bind_mode)"
Write-Host "vault    : $($config.obsidian.vault_path)"
Write-Host ""

& $pythonCommand -m uvicorn app:app --host $serverHost --port $port --app-dir $moduleDir
