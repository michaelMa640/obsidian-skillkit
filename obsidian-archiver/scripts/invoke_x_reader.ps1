param(
    [Parameter(Mandatory = $true)]
    [string]$InputJson,

    [Parameter(Mandatory = $true)]
    [string]$OutputJson,

    [string]$XReaderRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($XReaderRoot)) {
    $XReaderRoot = Join-Path $PSScriptRoot '..\..\.x-reader-site'
}

function Test-HasValue {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value)
}

if (-not (Test-Path $InputJson)) {
    throw "Input JSON not found: $InputJson"
}

if (-not (Test-Path $XReaderRoot)) {
    throw "x-reader package root not found: $XReaderRoot"
}

$payload = Get-Content -Raw $InputJson | ConvertFrom-Json
if (-not (Test-HasValue $payload.source_url)) {
    throw 'x-reader wrapper currently supports SourceUrl inputs only.'
}

$workDir = Join-Path $PSScriptRoot '..\.x-reader-runtime'
$inboxPath = Join-Path $workDir 'unified_inbox.json'
$outputDir = Join-Path $workDir 'output'
$stdoutPath = Join-Path $workDir 'x-reader.stdout.log'
$stderrPath = Join-Path $workDir 'x-reader.stderr.log'

New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$env:INBOX_FILE = $inboxPath
$env:OUTPUT_DIR = $outputDir
$env:PYTHONPATH = $XReaderRoot
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'

$process = Start-Process -FilePath python -ArgumentList @('-m', 'x_reader.cli', $payload.source_url) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
if ($process.ExitCode -ne 0) {
    $stderr = if (Test-Path $stderrPath) { Get-Content -Raw $stderrPath } else { '' }
    throw "x-reader failed with exit code $($process.ExitCode). $stderr"
}

if (-not (Test-Path $inboxPath)) {
    throw "x-reader did not create inbox output: $inboxPath"
}

$inbox = Get-Content -Raw $inboxPath | ConvertFrom-Json
$item = @($inbox)[-1]
if ($null -eq $item) {
    throw 'x-reader inbox was empty after execution.'
}

$author = if (Test-HasValue $item.source_name) { $item.source_name } else { 'unknown' }
$tags = @()
if ($null -ne $item.tags) {
    $tags = @($item.tags | Where-Object { Test-HasValue $_ })
}

$summary = if (Test-HasValue $item.content) {
    $normalized = ($item.content -replace "`r`n", "`n").Trim()
    if ($normalized.Length -gt 280) { $normalized.Substring(0, 280) + '...' } else { $normalized }
} else {
    'Summary not provided by x-reader.'
}

$keyPoints = @()
if (Test-HasValue $item.content) {
    $keyPoints = @(
        ($item.content -split "`r?`n" | Where-Object { Test-HasValue $_ } | Select-Object -First 3)
    )
}

$result = [ordered]@{
    title = $item.title
    source_type = $item.source_type
    author = $author
    published = if (Test-HasValue $item.fetched_at) { $item.fetched_at } else { 'unknown' }
    normalized_text = $item.content
    tags = $tags
    summary = $summary
    key_points = if ($keyPoints.Count -gt 0) { $keyPoints } else { @('Review extracted content in x-reader runtime inbox.') }
    metadata = [ordered]@{
        url = $item.url
        fetched_at = $item.fetched_at
        media_type = $item.media_type
        priority = $item.priority
        category = $item.category
        extra = $item.extra
        inbox_path = $inboxPath
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
    }
}

[System.IO.File]::WriteAllText($OutputJson, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
