param(
    [ValidateSet("health", "clip", "analyze")]
    [string]$Action = "health",
    [string]$ConfigPath = "",
    [string]$SourceText = "",
    [string]$GatewayUrl = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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
$token = [string]$config.auth.bearer_token

if ([string]::IsNullOrWhiteSpace($GatewayUrl)) {
    $GatewayUrl = "http://{0}:{1}" -f $config.server.host, $config.server.port
}

$headers = @{
    Authorization = "Bearer $token"
}

if ($Action -eq "health") {
    $response = Invoke-RestMethod -Uri "$GatewayUrl/health" -Method Get
    [Console]::WriteLine(($response | ConvertTo-Json -Depth 10))
    return
}

if ([string]::IsNullOrWhiteSpace($SourceText)) {
    throw "SourceText is required when Action is clip or analyze."
}

$body = @{
    action = $Action
    source_text = $SourceText
    client = "powershell_smoke_test"
    wait_for_completion = $true
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod -Uri "$GatewayUrl/share/task" -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
[Console]::WriteLine(($response | ConvertTo-Json -Depth 10))
