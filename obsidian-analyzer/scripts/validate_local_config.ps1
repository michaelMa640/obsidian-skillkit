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

$defaultAnalyzeFolder = ''
if ($null -ne $config.analyzer) {
    $defaultAnalyzeFolder = [string]$config.analyzer.default_analyze_folder
}
if (-not (Test-HasValue $defaultAnalyzeFolder)) {
    $missingRequired.Add([pscustomobject]@{
        field = 'analyzer.default_analyze_folder'
        message = 'Set the output folder for short-video analysis notes.'
    }) | Out-Null
}

$provider = if ($null -ne $config.llm) { [string]$config.llm.provider } else { '' }
$model = if ($null -ne $config.llm) { [string]$config.llm.model } else { '' }
if (-not (Test-HasValue $provider)) {
    $missingRequired.Add([pscustomobject]@{
        field = 'llm.provider'
        message = 'Set the LLM provider in references/local-config.json.'
    }) | Out-Null
}
if (-not (Test-HasValue $model)) {
    $missingRequired.Add([pscustomobject]@{
        field = 'llm.model'
        message = 'Set the LLM model name in references/local-config.json.'
    }) | Out-Null
}

$apiKey = if ($null -ne $config.llm) { [string]$config.llm.api_key } else { '' }
$apiKeyEnv = if ($null -ne $config.llm -and (Test-HasValue ([string]$config.llm.api_key_env))) { [string]$config.llm.api_key_env } else { 'DASHSCOPE_API_KEY' }
$apiKeyFromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv)
if (-not (Test-HasValue $apiKey) -and -not (Test-HasValue $apiKeyFromEnv)) {
    $missingRequired.Add([pscustomobject]@{
        field = 'llm.api_key or environment variable'
        message = "Set llm.api_key or populate the environment variable $apiKeyEnv."
    }) | Out-Null
}

$result = [pscustomobject]@{
    success = ($missingRequired.Count -eq 0)
    config_path = $resolvedConfigPath
    missing_required = @($missingRequired.ToArray())
    warnings = @($warnings.ToArray())
    recommended_next_steps = @(
        'If the user provided a raw URL instead of a clipping note, run obsidian-clipper first and then run obsidian-analyzer on the resulting note_path.',
        'After config is valid, run scripts/run_analyzer.ps1 or let OpenClaw call the skill normally.'
    )
}

$result | ConvertTo-Json -Depth 10
