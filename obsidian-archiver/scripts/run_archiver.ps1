param(
    [string]$SourceUrl,
    [string]$SourcePath,
    [string]$RawText,
    [string]$VaultPath,
    [string]$CategoryHint,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\references\local-config.example.json'),
    [string]$OutputJsonPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Config {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    return Get-Content -Raw $Path | ConvertFrom-Json -Depth 20
}

function Test-HasValue {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value)
}

function Get-Slug {
    param([string]$Value)

    if (-not (Test-HasValue $Value)) {
        return 'untitled'
    }

    $slug = $Value.ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9\s-]', '')
    $slug = [regex]::Replace($slug, '\s+', '-')
    $slug = [regex]::Replace($slug, '-+', '-')
    return $slug.Trim('-')
}

function Get-SafeFileName {
    param([string]$Value)

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $sanitized = -join ($Value.ToCharArray() | ForEach-Object {
        if ($invalidChars -contains $_) { '_' } else { $_ }
    })

    return $sanitized.Trim()
}

function Get-ArchiveTitle {
    param($Extraction, $Payload)

    if (Test-HasValue $Extraction.title) { return $Extraction.title }
    if (Test-HasValue $Payload.source_url) { return $Payload.source_url }
    if (Test-HasValue $Payload.source_path) { return [System.IO.Path]::GetFileNameWithoutExtension($Payload.source_path) }
    if (Test-HasValue $Payload.raw_text) { return 'Captured Text' }
    return 'Untitled Capture'
}

function Invoke-XReader {
    param($Config, $Payload, [switch]$DryRun)

    if ($DryRun -or $Config.x_reader.mode -eq 'mock') {
        return [pscustomobject]@{
            title = if (Test-HasValue $Payload.source_url) { "Captured from $($Payload.source_url)" } elseif (Test-HasValue $Payload.source_path) { [System.IO.Path]::GetFileNameWithoutExtension($Payload.source_path) } else { 'Captured Text' }
            source_type = if (Test-HasValue $Payload.source_url) { 'url' } elseif (Test-HasValue $Payload.source_path) { 'file' } else { 'text' }
            author = 'unknown'
            published = 'unknown'
            normalized_text = if (Test-HasValue $Payload.raw_text) { $Payload.raw_text } else { 'Dry run: no extraction executed.' }
            tags = @()
            metadata = [pscustomobject]@{ dry_run = $true }
        }
    }

    if ($Config.x_reader.mode -ne 'command') {
        throw "Unsupported x_reader.mode: $($Config.x_reader.mode)"
    }

    $command = $Config.x_reader.command
    if (-not (Test-HasValue $command)) {
        throw 'x_reader.command is required when mode=command'
    }

    $args = @()
    if ($null -ne $Config.x_reader.args) {
        $args = @($Config.x_reader.args)
    }

    $payloadJson = $Payload | ConvertTo-Json -Depth 20 -Compress
    $tempInputPath = [System.IO.Path]::GetTempFileName()
    $tempOutputPath = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText($tempInputPath, $payloadJson, [System.Text.UTF8Encoding]::new($false))

        $expandedArgs = foreach ($arg in $args) {
            $arg.Replace('{input_json}', $tempInputPath).Replace('{output_json}', $tempOutputPath)
        }

        $stdout = & $command @expandedArgs 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "x-reader command failed with exit code $exitCode. Output: $stdout"
        }

        if (Test-Path $tempOutputPath) {
            $outputText = Get-Content -Raw $tempOutputPath
            if (Test-HasValue $outputText) {
                try {
                    return $outputText | ConvertFrom-Json -Depth 20
                }
                catch {
                    return [pscustomobject]@{
                        title = $null
                        source_type = $null
                        author = $null
                        published = $null
                        normalized_text = $outputText
                        tags = @()
                        metadata = [pscustomobject]@{ parser = 'raw-output-file' }
                    }
                }
            }
        }

        $stdoutText = ($stdout | Out-String).Trim()
        if (Test-HasValue $stdoutText) {
            try {
                return $stdoutText | ConvertFrom-Json -Depth 20
            }
            catch {
                return [pscustomobject]@{
                    title = $null
                    source_type = $null
                    author = $null
                    published = $null
                    normalized_text = $stdoutText
                    tags = @()
                    metadata = [pscustomobject]@{ parser = 'raw-stdout' }
                }
            }
        }

        throw 'x-reader produced no usable output.'
    }
    finally {
        foreach ($path in @($tempInputPath, $tempOutputPath)) {
            if (Test-Path $path) {
                Remove-Item $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Build-Note {
    param($Config, $Payload, $Extraction)

    $title = Get-ArchiveTitle -Extraction $Extraction -Payload $Payload
    $captured = Get-Date -Format 'yyyy-MM-dd'
    $sourceType = if (Test-HasValue $Extraction.source_type) { $Extraction.source_type } elseif (Test-HasValue $Payload.source_url) { 'url' } elseif (Test-HasValue $Payload.source_path) { 'file' } else { 'text' }
    $author = if (Test-HasValue $Extraction.author) { $Extraction.author } else { 'unknown' }
    $published = if (Test-HasValue $Extraction.published) { $Extraction.published } else { 'unknown' }

    $tags = @()
    if ($null -ne $Extraction.tags) {
        $tags += @($Extraction.tags)
    }
    if (Test-HasValue $CategoryHint) {
        $tags += $CategoryHint
    }
    $tags = @($tags | Where-Object { Test-HasValue $_ } | Select-Object -Unique)
    if ($tags.Count -eq 0) {
        $tags = @($Config.archiver.default_tag)
    }

    $summary = if (Test-HasValue $Extraction.summary) { $Extraction.summary } else { 'Summary not provided by extractor. Review and refine if needed.' }
    $keyPoints = @()
    if ($null -ne $Extraction.key_points) {
        $keyPoints = @($Extraction.key_points)
    }
    if ($keyPoints.Count -eq 0) {
        $keyPoints = @('Review extracted content.', 'Confirm classification folder.', 'Refine summary and tags if needed.')
    }

    $sourceLine = if (Test-HasValue $Payload.source_url) { $Payload.source_url } elseif (Test-HasValue $Payload.source_path) { $Payload.source_path } else { 'inline-text' }

    $frontmatterTags = ($tags | ForEach-Object { "  - $_" }) -join "`n"
    $keyPointLines = ($keyPoints | ForEach-Object { "- $_" }) -join "`n"

    $noteBody = @"
---
title: $title
source_type: $sourceType
source_url: $($Payload.source_url)
source_path: $($Payload.source_path)
author: $author
published: $published
captured: $captured
tags:
$frontmatterTags
---

# $title

## Summary
$summary

## Key Points
$keyPointLines

## Source
- Original: $sourceLine
- Processed by: x-reader
- Archived via: obsidian-archiver
"@

    $folder = if (Test-HasValue $CategoryHint) { $CategoryHint } elseif (Test-HasValue $Config.archiver.default_folder) { $Config.archiver.default_folder } else { 'Inbox' }
    $prefixDate = if ($Config.archiver.prefix_date -eq $true) { "$captured " } else { '' }
    $fileName = Get-SafeFileName "$prefixDate$title.md"

    return [pscustomobject]@{
        title = $title
        folder = $folder
        file_name = $fileName
        tags = $tags
        note_body = $noteBody
        extraction = $Extraction
    }
}

function Write-NoteToVault {
    param($Config, $Note, [string]$VaultPath)

    $resolvedVaultPath = if (Test-HasValue $VaultPath) { $VaultPath } elseif (Test-HasValue $Config.obsidian.vault_path) { $Config.obsidian.vault_path } else { '' }
    if (-not (Test-HasValue $resolvedVaultPath)) {
        throw 'No vault path provided. Supply -VaultPath or set obsidian.vault_path in config.'
    }

    $targetFolder = Join-Path $resolvedVaultPath $Note.folder
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

    $targetPath = Join-Path $targetFolder $Note.file_name
    [System.IO.File]::WriteAllText($targetPath, $Note.note_body, [System.Text.UTF8Encoding]::new($false))
    return $targetPath
}

$providedSources = @($SourceUrl, $SourcePath, $RawText) | Where-Object { Test-HasValue $_ }
if ($providedSources.Count -eq 0) {
    throw 'Provide at least one source: -SourceUrl, -SourcePath, or -RawText'
}

$config = Get-Config -Path $ConfigPath
$payload = [pscustomobject]@{
    source_url = $SourceUrl
    source_path = $SourcePath
    raw_text = $RawText
    category_hint = $CategoryHint
    requested_at = (Get-Date).ToString('s')
    requested_vault = $VaultPath
}

$extraction = Invoke-XReader -Config $config -Payload $payload -DryRun:$DryRun
$note = Build-Note -Config $config -Payload $payload -Extraction $extraction

$result = [ordered]@{
    success = $true
    dry_run = [bool]$DryRun
    title = $note.title
    folder = $note.folder
    file_name = $note.file_name
    tags = $note.tags
    x_reader_mode = $config.x_reader.mode
    vault_path = if (Test-HasValue $VaultPath) { $VaultPath } else { $config.obsidian.vault_path }
    note_preview = $note.note_body
}

if (-not $DryRun -and $config.obsidian.mode -eq 'filesystem') {
    $result.note_path = Write-NoteToVault -Config $config -Note $note -VaultPath $VaultPath
}

$json = $result | ConvertTo-Json -Depth 20
if (Test-HasValue $OutputJsonPath) {
    [System.IO.File]::WriteAllText($OutputJsonPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$json
