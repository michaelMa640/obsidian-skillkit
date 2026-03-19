param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HasValue {
    param($Value)
    $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Read-Utf8Text {
    param([string]$Path)
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function ConvertFrom-JsonCompat {
    param([Parameter(Mandatory = $true)][string]$Json, [int]$Depth = 64)
    $params = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('Depth')) { $params.Depth = $Depth }
    $Json | ConvertFrom-Json @params
}

function Resolve-ConfigPath {
    param([string]$RequestedPath)
    if (Test-HasValue $RequestedPath) { return $RequestedPath }
    $localConfig = Join-Path $PSScriptRoot '..\references\local-config.json'
    if (Test-Path $localConfig) { return $localConfig }
    Join-Path $PSScriptRoot '..\references\local-config.example.json'
}

function Is-PlaceholderValue {
    param([string]$Value)
    if (-not (Test-HasValue $Value)) { return $true }
    $text = [string]$Value
    return ($text -match 'REPLACE/WITH/YOUR' -or $text -match 'REPLACE\\WITH\\YOUR')
}

$resolvedConfigPath = Resolve-ConfigPath -RequestedPath $ConfigPath
if (-not (Test-Path $resolvedConfigPath)) {
    throw "Config not found: $resolvedConfigPath"
}

$config = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $resolvedConfigPath) -Depth 100
$missingRequired = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

$vaultPath = if ($null -ne $config.obsidian) { [string]$config.obsidian.vault_path } else { '' }
if (Is-PlaceholderValue $vaultPath) {
    $missingRequired.Add([pscustomobject]@{
        field = 'obsidian.vault_path'
        message = 'Set the Obsidian vault root path in references/local-config.json.'
    }) | Out-Null
}

$socialScript = ''
if ($null -ne $config.routes -and $null -ne $config.routes.social) {
    $socialScript = [string]$config.routes.social.script
}
if (Is-PlaceholderValue $socialScript) {
    $missingRequired.Add([pscustomobject]@{
        field = 'routes.social.script'
        message = 'Set the absolute path to capture_social_playwright.py.'
    }) | Out-Null
} elseif (-not (Test-Path $socialScript)) {
    $missingRequired.Add([pscustomobject]@{
        field = 'routes.social.script'
        message = "Configured script path does not exist: $socialScript"
    }) | Out-Null
}

$storageStatePath = ''
$cookiesFile = ''
if ($null -ne $config.routes -and $null -ne $config.routes.social -and $null -ne $config.routes.social.auth) {
    $storageStatePath = [string]$config.routes.social.auth.storage_state_path
    $cookiesFile = [string]$config.routes.social.auth.cookies_file
}

if (Is-PlaceholderValue $storageStatePath) {
    $warnings.Add('routes.social.auth.storage_state_path is not configured. Logged-in Playwright capture will not be available.') | Out-Null
} elseif (-not (Test-Path $storageStatePath)) {
    $warnings.Add("Configured storage_state_path does not exist: $storageStatePath") | Out-Null
}

if (Is-PlaceholderValue $cookiesFile) {
    $warnings.Add('routes.social.auth.cookies_file is not configured. yt-dlp may fail on Douyin when fresh cookies are required.') | Out-Null
} elseif (-not (Test-Path $cookiesFile)) {
    $warnings.Add("Configured cookies_file does not exist: $cookiesFile") | Out-Null
}

$result = [pscustomobject]@{
    success = ($missingRequired.Count -eq 0)
    config_path = $resolvedConfigPath
    missing_required = @($missingRequired.ToArray())
    warnings = @($warnings.ToArray())
    recommended_next_steps = @(
        'If auth warnings exist, refresh Douyin login state with scripts/bootstrap_social_auth.py --platform douyin.',
        'After config is valid, run scripts/run_clipper.ps1 or let OpenClaw call the skill normally.'
    )
}

$result | ConvertTo-Json -Depth 10
