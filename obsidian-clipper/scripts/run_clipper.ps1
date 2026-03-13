param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUrl,

    [string]$VaultPath,
    [string]$CategoryHint,
    [string]$TitleHint,
    [string]$ConfigPath,
    [string]$OutputJsonPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Utf8Text {
    param([string]$Path)
    [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Text {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Test-HasValue {
    param($Value)
    return $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }
    Read-Utf8Text -Path $Path | ConvertFrom-Json
}

function Get-SafeFileName {
    param([string]$Value)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $sanitized = -join ($Value.ToCharArray() | ForEach-Object {
        if ($invalidChars -contains $_) { '_' } else { $_ }
    })
    $sanitized.Trim()
}

function Get-Detection {
    param([string]$Url)
    $detectScript = Join-Path $PSScriptRoot 'detect_platform.ps1'
    (& $detectScript -SourceUrl $Url | ConvertFrom-Json)
}

function Get-HostLabel {
    param([string]$Url)
    ([System.Uri]$Url).Host.ToLowerInvariant()
}

function New-LocalTempDirectory {
    $tempDir = Join-Path $PSScriptRoot '..\.tmp'
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $dirName = [guid]::NewGuid().ToString('N')
    $path = Join-Path $tempDir $dirName
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $path
}

function Remove-LocalTempDirectory {
    param([string]$Path)
    if (Test-HasValue $Path -and (Test-Path $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Clean-SubtitleText {
    param([string]$Text)
    $cleaned = $Text -replace '\uFEFF', ''
    $cleaned = $cleaned -replace '(?m)^WEBVTT.*$', ''
    $cleaned = $cleaned -replace '(?m)^Kind:.*$', ''
    $cleaned = $cleaned -replace '(?m)^Language:.*$', ''
    $cleaned = $cleaned -replace '(?m)^\d+$', ''
    $cleaned = $cleaned -replace '(?m)^\d{2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}\.\d{3}.*$', ''
    $cleaned = $cleaned -replace '(?m)^\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}\.\d{3}.*$', ''
    $cleaned = $cleaned -replace '<[^>]+>', ''
    $cleaned = $cleaned -replace '&nbsp;', ' '
    $cleaned = $cleaned -replace '(?m)^\s+$', ''
    $cleaned = $cleaned -replace '(\r?\n){3,}', "`n`n"
    $cleaned.Trim()
}

function Get-FirstSubtitleText {
    param([string]$Directory)
    $subtitleFile = Get-ChildItem -LiteralPath $Directory -Recurse -File -Include *.vtt, *.srt, *.ass, *.lrc -ErrorAction SilentlyContinue |
        Sort-Object Extension, Name |
        Select-Object -First 1
    if ($null -eq $subtitleFile) {
        return ''
    }
    $raw = Read-Utf8Text -Path $subtitleFile.FullName
    Clean-SubtitleText -Text $raw
}

function Get-RouteConfigValue {
    param($Config, [string]$RouteName, [string]$PropertyName, [string]$DefaultValue = '')
    if ($null -eq $Config.routes) { return $DefaultValue }
    $route = $Config.routes.$RouteName
    if ($null -eq $route) { return $DefaultValue }
    $property = $route.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $DefaultValue }
    $value = [string]$property.Value
    if (Test-HasValue $value) { return $value }
    $DefaultValue
}

function Get-MetaContent {
    param([string]$Html, [string]$Key, [string]$Attr = 'property')
    $pattern = '<meta\s+' + $Attr + '="' + [regex]::Escape($Key) + '"[^>]*content="(?<value>[^"]+)"'
    $match = [regex]::Match($Html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value).Trim()
    }
    ''
}

function Get-HtmlTitle {
    param([string]$Html)
    $match = [regex]::Match($Html, '<title>(?<value>.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value).Trim()
    }
    ''
}

function Get-PlainTextFromHtml {
    param([string]$Html)
    $text = $Html -replace '(?is)<script[^>]*>.*?</script>', ' '
    $text = $text -replace '(?is)<style[^>]*>.*?</style>', ' '
    $text = $text -replace '(?i)<br\s*/?>', "`n"
    $text = $text -replace '(?i)</p>', "`n"
    $text = $text -replace '(?is)<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace '[ \t]{2,}', ' '
    $text = $text -replace '(\r?\n){3,}', "`n`n"
    $text.Trim()
}

function Get-PreviewText {
    param([string]$Text, [int]$Length = 1200)
    if (-not (Test-HasValue $Text)) { return '' }
    if ($Text.Length -le $Length) { return $Text }
    $Text.Substring(0, $Length) + '...'
}

function New-CaptureObject {
    param(
        [string]$Title,
        [string]$Author,
        [string]$PublishedAt,
        [string]$Summary,
        [string]$RawText,
        [string]$Transcript,
        [string[]]$Tags,
        [string[]]$Images,
        [string[]]$Videos,
        $Metadata
    )

    [pscustomobject]@{
        title = $Title
        author = $Author
        published_at = $PublishedAt
        summary = $Summary
        raw_text = $RawText
        transcript = $Transcript
        tags = $Tags
        images = $Images
        videos = $Videos
        metadata = $Metadata
    }
}

function New-VideoMetadataFallbackCapture {
    param([string]$Url, [string]$TitleHint, [string]$Platform, [string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Video Clip - $Platform" }
    $metadata = [ordered]@{
        capture_level = 'fallback'
        transcript_status = 'missing'
        media_downloaded = $false
        analysis_ready = $true
        extractor = 'yt-dlp'
        fallback_reason = $ErrorText
    }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Metadata capture fell back to a minimal clipping because yt-dlp could not fetch remote metadata in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped', 'video', $Platform, 'fallback') -Images @() -Videos @($Url) -Metadata $metadata
}

function New-PodcastFallbackCapture {
    param([string]$Url, [string]$TitleHint, [string]$Platform, [string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Podcast Clip - $Platform" }
    $metadata = [ordered]@{
        capture_level = 'fallback'
        transcript_status = 'missing'
        media_downloaded = $false
        analysis_ready = $true
        extractor = 'web-metadata'
        fallback_reason = $ErrorText
    }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Podcast clipping fell back to a minimal clipping because page metadata could not be fetched in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped', 'podcast', $Platform, 'fallback') -Images @() -Videos @($Url) -Metadata $metadata
}

function Invoke-ArticleCapture {
    param([string]$Url, [string]$TitleHint)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Article Clip - $(Get-HostLabel -Url $Url)" }
    $metadata = [ordered]@{
        capture_level = 'light'
        transcript_status = 'not_applicable'
        media_downloaded = $false
        analysis_ready = $true
    }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Light clipping only. Full article extraction is not wired into the first runnable version yet.' -RawText 'Placeholder article capture. Next step: connect browser + article extraction tooling.' -Transcript '' -Tags @('clipped', 'article') -Images @() -Videos @() -Metadata $metadata
}

function Invoke-SocialCapture {
    param([string]$Url, [string]$TitleHint, [string]$Platform)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Social Clip - $Platform" }
    $metadata = [ordered]@{
        capture_level = 'light'
        transcript_status = 'missing'
        media_downloaded = $false
        analysis_ready = $true
    }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Light social clipping only. Browser capture integration is planned for the next step.' -RawText 'Placeholder social capture. Intended future fields: visible caption, tags, cover, and engagement data.' -Transcript '' -Tags @('clipped', 'social', $Platform) -Images @() -Videos @($Url) -Metadata $metadata
}

function Invoke-VideoMetadataCapture {
    param($Config, [string]$Url, [string]$TitleHint, [string]$Platform, [switch]$DryRun)

    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Video Clip - $Platform" }
        $metadata = [ordered]@{
            capture_level = 'light'
            transcript_status = 'missing'
            media_downloaded = $false
            analysis_ready = $true
            extractor = 'yt-dlp'
            dry_run = $true
        }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: yt-dlp metadata route not executed.' -RawText '' -Transcript '' -Tags @('clipped', 'video', $Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }

    $ytDlpCommand = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'command' -DefaultValue 'yt-dlp'
    $subtitleLanguages = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'subtitle_languages' -DefaultValue 'all,-live_chat'
    $subtitleFormat = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'subtitle_format' -DefaultValue 'vtt/srt/best'

    $tempDir = New-LocalTempDirectory
    try {
        try {
            $metadataArgs = @('--dump-single-json', '--skip-download', '--no-warnings', '--no-playlist', $Url)
            $metadataJson = & $ytDlpCommand @metadataArgs 2>&1
            $metadataExitCode = $LASTEXITCODE
            if ($metadataExitCode -ne 0) {
                throw "yt-dlp metadata extraction failed with exit code $metadataExitCode. Output: $metadataJson"
            }
            $metadataText = ($metadataJson | Out-String).Trim()
            if (-not (Test-HasValue $metadataText)) {
                throw 'yt-dlp returned no metadata output.'
            }
            $info = $metadataText | ConvertFrom-Json -Depth 100

            $baseTemplate = Join-Path $tempDir 'subtitle'
            $subtitleArgs = @('--skip-download', '--write-subs', '--write-auto-subs', '--sub-langs', $subtitleLanguages, '--sub-format', $subtitleFormat, '--no-playlist', '--no-warnings', '-o', "$baseTemplate.%(ext)s", $Url)
            $subtitleOutput = & $ytDlpCommand @subtitleArgs 2>&1
            $subtitleExitCode = $LASTEXITCODE
            $transcript = ''
            if ($subtitleExitCode -eq 0) {
                $transcript = Get-FirstSubtitleText -Directory $tempDir
            }

            $publishedAt = 'unknown'
            if (Test-HasValue $info.release_date) { $publishedAt = [string]$info.release_date }
            elseif (Test-HasValue $info.upload_date) { $publishedAt = [string]$info.upload_date }

            $description = if (Test-HasValue $info.description) { $info.description.Trim() } else { '' }
            $summaryParts = @('Metadata-first clipping via yt-dlp.')
            if (Test-HasValue $info.uploader) { $summaryParts += "Uploader: $($info.uploader)." }
            if (Test-HasValue $info.duration_string) { $summaryParts += "Duration: $($info.duration_string)." }
            if (Test-HasValue $info.view_count) { $summaryParts += "Views: $($info.view_count)." }
            if (Test-HasValue $info.like_count) { $summaryParts += "Likes: $($info.like_count)." }
            if (Test-HasValue $description) {
                $summaryParts += "Description preview: $(Get-PreviewText -Text $description -Length 180)"
            }
            $summary = ($summaryParts -join ' ').Trim()

            $title = if (Test-HasValue $TitleHint) { $TitleHint } else { [string]$info.title }
            if (-not (Test-HasValue $title)) { $title = "Video Clip - $Platform" }
            $author = if (Test-HasValue $info.uploader) { [string]$info.uploader } elseif (Test-HasValue $info.channel) { [string]$info.channel } else { 'unknown' }

            $tags = New-Object System.Collections.Generic.List[string]
            foreach ($tag in @('clipped', 'video', $Platform)) { if (Test-HasValue $tag) { $tags.Add([string]$tag) } }
            if ($null -ne $info.categories) {
                foreach ($category in @($info.categories)) { if (Test-HasValue $category) { $tags.Add([string]$category) } }
            }
            if ($null -ne $info.tags) {
                foreach ($tag in @($info.tags | Select-Object -First 8)) { if (Test-HasValue $tag) { $tags.Add([string]$tag) } }
            }
            $tagList = @($tags | Select-Object -Unique)

            $images = @()
            if (Test-HasValue $info.thumbnail) { $images = @([string]$info.thumbnail) }
            $videos = if (Test-HasValue $info.webpage_url) { @([string]$info.webpage_url) } else { @($Url) }
            $metadata = [ordered]@{
                capture_level = if (Test-HasValue $transcript) { 'standard' } else { 'light' }
                transcript_status = if (Test-HasValue $transcript) { 'available' } else { 'missing' }
                media_downloaded = $false
                analysis_ready = $true
                extractor = 'yt-dlp'
                duration = $info.duration
                duration_string = $info.duration_string
                uploader = $info.uploader
                channel = $info.channel
                extractor_key = $info.extractor_key
                subtitle_command_exit_code = $subtitleExitCode
                subtitle_command_output = ($subtitleOutput | Out-String).Trim()
            }
            return (New-CaptureObject -Title $title -Author $author -PublishedAt $publishedAt -Summary $summary -RawText $description -Transcript $transcript -Tags $tagList -Images $images -Videos $videos -Metadata $metadata)
        }
        catch {
            return (New-VideoMetadataFallbackCapture -Url $Url -TitleHint $TitleHint -Platform $Platform -ErrorText $_.Exception.Message)
        }
    }
    finally {
        Remove-LocalTempDirectory -Path $tempDir
    }
}

function Invoke-PodcastCapture {
    param($Config, [string]$Url, [string]$TitleHint, [string]$Platform, [switch]$DryRun)

    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Podcast Clip - $Platform" }
        $metadata = [ordered]@{
            capture_level = 'light'
            transcript_status = 'missing'
            media_downloaded = $false
            analysis_ready = $true
            extractor = 'web-metadata'
            dry_run = $true
        }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: podcast metadata route not executed.' -RawText '' -Transcript '' -Tags @('clipped', 'podcast', $Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $html = [string]$response.Content
        if (-not (Test-HasValue $html)) {
            throw 'Podcast page returned empty HTML content.'
        }

        $ogTitle = Get-MetaContent -Html $html -Key 'og:title'
        $ogDescription = Get-MetaContent -Html $html -Key 'og:description'
        $ogImage = Get-MetaContent -Html $html -Key 'og:image'
        $pageTitle = Get-HtmlTitle -Html $html
        $plainText = Get-PlainTextFromHtml -Html $html

        $title = if (Test-HasValue $TitleHint) { $TitleHint } elseif (Test-HasValue $ogTitle) { $ogTitle } elseif (Test-HasValue $pageTitle) { $pageTitle } else { "Podcast Clip - $Platform" }
        $author = 'unknown'
        if (Test-HasValue $pageTitle -and $pageTitle -match '^(?<episode>.*?)\s+-\s+(?<podcast>.*?)\s+\|') {
            $author = $Matches['podcast']
        }

        $summary = if (Test-HasValue $ogDescription) { $ogDescription } else { 'Podcast metadata captured from the episode page.' }
        $rawParts = @()
        if (Test-HasValue $ogDescription) { $rawParts += $ogDescription }
        if (Test-HasValue $plainText) { $rawParts += (Get-PreviewText -Text $plainText -Length 1200) }
        $rawText = ($rawParts | Where-Object { Test-HasValue $_ } | Select-Object -Unique) -join "`n`n"

        $images = @()
        if (Test-HasValue $ogImage) { $images = @($ogImage) }
        $metadata = [ordered]@{
            capture_level = 'standard'
            transcript_status = 'missing'
            media_downloaded = $false
            analysis_ready = $true
            extractor = 'web-metadata'
            source_status_code = $response.StatusCode
            source_status_description = $response.StatusDescription
        }
        return (New-CaptureObject -Title $title -Author $author -PublishedAt 'unknown' -Summary $summary -RawText $rawText -Transcript '' -Tags @('clipped', 'podcast', $Platform) -Images $images -Videos @($Url) -Metadata $metadata)
    }
    catch {
        return (New-PodcastFallbackCapture -Url $Url -TitleHint $TitleHint -Platform $Platform -ErrorText $_.Exception.Message)
    }
}

function Invoke-CaptureRoute {
    param($Config, $Detection, [string]$Url, [string]$TitleHint, [switch]$DryRun)
    switch ($Detection.route) {
        'article' { return Invoke-ArticleCapture -Url $Url -TitleHint $TitleHint }
        'social' { return Invoke-SocialCapture -Url $Url -TitleHint $TitleHint -Platform $Detection.platform }
        'video_metadata' { return Invoke-VideoMetadataCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        'podcast' { return Invoke-PodcastCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        default { throw "Unsupported route: $($Detection.route)" }
    }
}

function Build-ClippingNote {
    param($Config, $Detection, $Capture, [string]$SourceUrl, [string]$CategoryHint)

    $captured = Get-Date -Format 'yyyy-MM-dd'
    $folder = if (Test-HasValue $CategoryHint) { $CategoryHint } elseif (Test-HasValue $Config.clipper.default_folder) { [string]$Config.clipper.default_folder } else { 'Clippings' }
    $title = [string]$Capture.title
    $prefixDate = if ($Config.clipper.prefix_date -eq $true) { "$captured " } else { '' }
    $fileName = Get-SafeFileName "$prefixDate$title.md"
    $tags = @($Capture.tags | Where-Object { Test-HasValue $_ } | Select-Object -Unique)
    if ($tags.Count -eq 0) { $tags = @('clipped') }
    $frontmatterTags = ($tags | ForEach-Object { "  - $_" }) -join "`n"
    $images = if (@($Capture.images).Count -gt 0) { (@($Capture.images) | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $videos = if (@($Capture.videos).Count -gt 0) { (@($Capture.videos) | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $rawText = if (Test-HasValue $Capture.raw_text) { [string]$Capture.raw_text } else { '(none)' }
    $transcript = if (Test-HasValue $Capture.transcript) { [string]$Capture.transcript } else { '(none)' }

    $metadataLines = @(
        "- Capture Level: $($Capture.metadata.capture_level)",
        "- Transcript Status: $($Capture.metadata.transcript_status)",
        "- Media Downloaded: $($Capture.metadata.media_downloaded)",
        "- Analysis Ready: $($Capture.metadata.analysis_ready)"
    )
    if ($Capture.metadata -is [System.Collections.IDictionary]) {
        foreach ($entry in $Capture.metadata.GetEnumerator()) {
            if ($entry.Key -in @('capture_level', 'transcript_status', 'media_downloaded', 'analysis_ready')) { continue }
            if ($null -eq $entry.Value) { continue }
            $value = if ($entry.Value -is [System.Array]) { ($entry.Value -join ', ') } else { [string]$entry.Value }
            if (Test-HasValue $value) {
                $metadataLines += "- $($entry.Key): $value"
            }
        }
    }
    $metadataBlock = $metadataLines -join "`n"

    $body = @"
---
title: $title
source_url: $SourceUrl
platform: $($Detection.platform)
content_type: $($Detection.content_type)
author: $($Capture.author)
published_at: $($Capture.published_at)
captured_at: $captured
route: $($Detection.route)
capture_level: $($Capture.metadata.capture_level)
transcript_status: $($Capture.metadata.transcript_status)
media_downloaded: $($Capture.metadata.media_downloaded.ToString().ToLowerInvariant())
analysis_ready: $($Capture.metadata.analysis_ready.ToString().ToLowerInvariant())
tags:
$frontmatterTags
status: clipped
---

# $title

## Source
- URL: $SourceUrl
- Platform: $($Detection.platform)
- Content Type: $($Detection.content_type)
- Route: $($Detection.route)

## Summary of Raw Content
$($Capture.summary)

## Raw Text / Transcript
### Raw Text
$rawText

### Transcript
$transcript

## Images
$images

## Videos
$videos

## Metadata
$metadataBlock
"@

    [pscustomobject]@{
        title = $title
        folder = $folder
        file_name = $fileName
        tags = $tags
        note_body = $body
    }
}

function Write-NoteToVault {
    param($Config, $Note, [string]$VaultPath)
    $resolvedVaultPath = if (Test-HasValue $VaultPath) { $VaultPath } elseif (Test-HasValue $Config.obsidian.vault_path) { [string]$Config.obsidian.vault_path } else { '' }
    if (-not (Test-HasValue $resolvedVaultPath)) {
        throw 'No vault path provided. Supply -VaultPath or set obsidian.vault_path in config.'
    }
    $targetFolder = Join-Path $resolvedVaultPath $Note.folder
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    $targetPath = Join-Path $targetFolder $Note.file_name
    Write-Utf8Text -Path $targetPath -Content $Note.note_body
    $targetPath
}

if (-not (Test-HasValue $ConfigPath)) {
    if (Test-Path (Join-Path $PSScriptRoot '..\references\local-config.json')) {
        $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.json'
    } else {
        $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.example.json'
    }
}

$config = Get-Config -Path $ConfigPath
$detection = Get-Detection -Url $SourceUrl
$capture = Invoke-CaptureRoute -Config $config -Detection $detection -Url $SourceUrl -TitleHint $TitleHint -DryRun:$DryRun
$note = Build-ClippingNote -Config $config -Detection $detection -Capture $capture -SourceUrl $SourceUrl -CategoryHint $CategoryHint

$result = [ordered]@{
    success = $true
    dry_run = [bool]$DryRun
    title = $note.title
    folder = $note.folder
    file_name = $note.file_name
    route = $detection.route
    platform = $detection.platform
    content_type = $detection.content_type
    tags = $note.tags
    note_preview = $note.note_body
    vault_path = if (Test-HasValue $VaultPath) { $VaultPath } else { $config.obsidian.vault_path }
}

if (-not $DryRun -and $config.obsidian.mode -eq 'filesystem') {
    $result.note_path = Write-NoteToVault -Config $config -Note $note -VaultPath $VaultPath
}

$json = $result | ConvertTo-Json -Depth 20
if (Test-HasValue $OutputJsonPath) {
    Write-Utf8Text -Path $OutputJsonPath -Content $json
}

$json
