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
    $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Config file not found: $Path" }
    Read-Utf8Text -Path $Path | ConvertFrom-Json
}

function ConvertFrom-JsonCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,
        [int]$Depth = 64
    )
    $convertParams = @{}
    $depthParam = (Get-Command ConvertFrom-Json).Parameters['Depth']
    if ($null -ne $depthParam) {
        $convertParams.Depth = $Depth
    }
    $Json | ConvertFrom-Json @convertParams
}

function Get-SafeFileName {
    param([string]$Value)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $sanitized = -join ($Value.ToCharArray() | ForEach-Object { if ($invalidChars -contains $_) { '_' } else { $_ } })
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
    $path = Join-Path $tempDir ([guid]::NewGuid().ToString('N'))
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
    if ($null -eq $subtitleFile) { return '' }
    Clean-SubtitleText -Text (Read-Utf8Text -Path $subtitleFile.FullName)
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
    if ($match.Success) { return [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value).Trim() }
    ''
}

function Get-HtmlTitle {
    param([string]$Html)
    $match = [regex]::Match($Html, '<title>(?<value>.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) { return [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value).Trim() }
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
function Resolve-AbsoluteUrl {
    param([string]$BaseUrl, [string]$Candidate)
    if (-not (Test-HasValue $Candidate)) { return '' }
    try { return [System.Uri]::new([System.Uri]$BaseUrl, $Candidate).AbsoluteUri } catch { return $Candidate }
}

function Get-RegexGroupValue {
    param([string]$Html, [string]$Pattern, [string]$GroupName = 'value')
    $match = [regex]::Match($Html, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) { return [System.Net.WebUtility]::HtmlDecode($match.Groups[$GroupName].Value).Trim() }
    ''
}

function Get-PodcastResourceHints {
    param([string]$Html, [string]$BaseUrl)
    $rss = Get-RegexGroupValue -Html $Html -Pattern '<link[^>]+type="application/rss\+xml"[^>]+href="(?<value>[^"]+)"'
    if (-not (Test-HasValue $rss)) { $rss = Get-RegexGroupValue -Html $Html -Pattern 'href="(?<value>[^"]+\.(xml|rss))(?:\?[^"]*)?"' }
    $transcript = Get-RegexGroupValue -Html $Html -Pattern 'href="(?<value>[^"]*(transcript|subtitle|captions)[^"]*)"'
    if (-not (Test-HasValue $transcript)) { $transcript = Get-RegexGroupValue -Html $Html -Pattern 'href="(?<value>[^"]+\.(vtt|srt|lrc|txt))(?:\?[^"]*)?"' }
    $enclosure = Get-RegexGroupValue -Html $Html -Pattern 'href="(?<value>[^"]+\.(mp3|m4a|aac|wav))(?:\?[^"]*)?"'
    if (-not (Test-HasValue $enclosure)) { $enclosure = Get-MetaContent -Html $Html -Key 'og:audio' }
    [pscustomobject]@{ rss_url = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate $rss; transcript_url = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate $transcript; enclosure_url = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate $enclosure }
}

function Get-TranscriptFromUrl {
    param([string]$TranscriptUrl)
    if (-not (Test-HasValue $TranscriptUrl)) { return '' }
    try {
        $response = Invoke-WebRequest -Uri $TranscriptUrl -UseBasicParsing
        if (-not (Test-HasValue $response.Content)) { return '' }
        return (Clean-SubtitleText -Text ([string]$response.Content))
    } catch { return '' }
}

function Get-PodcastShowNotes {
    param([string]$Html, [string]$Description, [string]$PlainText)
    $candidates = New-Object System.Collections.Generic.List[string]
    if (Test-HasValue $Description) { $candidates.Add($Description) }
    foreach ($pattern in @('<article[^>]*>(?<value>.*?)</article>', '<main[^>]*>(?<value>.*?)</main>', '<section[^>]+(?:show-notes|shownotes|notes|description)[^>]*>(?<value>.*?)</section>', '<div[^>]+(?:show-notes|shownotes|notes|description)[^>]*>(?<value>.*?)</div>')) {
        $match = [regex]::Match($Html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($match.Success) {
            $candidateText = Get-PlainTextFromHtml -Html $match.Groups['value'].Value
            if (Test-HasValue $candidateText) { $candidates.Add($candidateText) }
        }
    }
    if ($candidates.Count -eq 0 -and (Test-HasValue $PlainText)) { $candidates.Add($PlainText) }
    foreach ($candidate in $candidates) {
        $trimmed = Get-PreviewText -Text ($candidate.Trim()) -Length 2500
        if (Test-HasValue $trimmed) { return $trimmed }
    }
    ''
}

function Get-BestArticleText {
    param([string]$Html)
    $blocks = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @('<article[^>]*>(?<value>.*?)</article>', '<main[^>]*>(?<value>.*?)</main>', '<div[^>]+(?:content|article|post|entry|main|story|text|body)[^>]*>(?<value>.*?)</div>', '<section[^>]+(?:content|article|post|entry|main|story|text|body)[^>]*>(?<value>.*?)</section>')) {
        $matches = [regex]::Matches($Html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($match in $matches) {
            $text = Get-PlainTextFromHtml -Html $match.Groups['value'].Value
            if (Test-HasValue $text -and $text.Length -ge 200) { $blocks.Add($text) }
        }
    }
    if ($blocks.Count -gt 0) { return ($blocks | Select-Object -Unique | Sort-Object Length -Descending | Select-Object -First 1) }
    Get-PlainTextFromHtml -Html $Html
}

function New-CaptureObject {
    param([string]$Title,[string]$Author,[string]$PublishedAt,[string]$Summary,[string]$RawText,[string]$Transcript,[string[]]$Tags,[string[]]$Images,[string[]]$Videos,$Metadata)
    [pscustomobject]@{ title=$Title; author=$Author; published_at=$PublishedAt; summary=$Summary; raw_text=$RawText; transcript=$Transcript; tags=$Tags; images=$Images; videos=$Videos; metadata=$Metadata }
}

function New-ArticleFallbackCapture {
    param([string]$Url,[string]$TitleHint,[string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Article Clip - $(Get-HostLabel -Url $Url)" }
    $metadata = [ordered]@{ capture_level='fallback'; transcript_status='not_applicable'; media_downloaded=$false; analysis_ready=$true; extractor='web-article'; fallback_reason=$ErrorText }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Article clipping fell back to a minimal clipping because page extraction could not be completed in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped','article','fallback') -Images @() -Videos @() -Metadata $metadata
}

function New-SocialFallbackCapture {
    param([string]$Url,[string]$TitleHint,[string]$Platform,[string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Social Clip - $Platform" }
    $metadata = [ordered]@{ capture_level='fallback'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='playwright'; fallback_reason=$ErrorText }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Social clipping fell back to a minimal clipping because Playwright capture could not be completed in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped','social',$Platform,'fallback') -Images @() -Videos @($Url) -Metadata $metadata
}

function New-VideoMetadataFallbackCapture {
    param([string]$Url,[string]$TitleHint,[string]$Platform,[string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Video Clip - $Platform" }
    $metadata = [ordered]@{ capture_level='fallback'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='yt-dlp'; fallback_reason=$ErrorText }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Metadata capture fell back to a minimal clipping because yt-dlp could not fetch remote metadata in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped','video',$Platform,'fallback') -Images @() -Videos @($Url) -Metadata $metadata
}

function New-PodcastFallbackCapture {
    param([string]$Url,[string]$TitleHint,[string]$Platform,[string]$ErrorText)
    $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Podcast Clip - $Platform" }
    $metadata = [ordered]@{ capture_level='fallback'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='web-metadata'; fallback_reason=$ErrorText; rss_url=''; transcript_url=''; enclosure_url='' }
    New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Podcast clipping fell back to a minimal clipping because page metadata could not be fetched in the current environment.' -RawText ("Fallback reason:`n$ErrorText") -Transcript '' -Tags @('clipped','podcast',$Platform,'fallback') -Images @() -Videos @($Url) -Metadata $metadata
}

function Invoke-ArticleCapture {
    param([string]$Url,[string]$TitleHint,[switch]$DryRun)
    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Article Clip - $(Get-HostLabel -Url $Url)" }
        $metadata = [ordered]@{ capture_level='light'; transcript_status='not_applicable'; media_downloaded=$false; analysis_ready=$true; extractor='web-article'; dry_run=$true }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: article extraction route not executed.' -RawText '' -Transcript '' -Tags @('clipped','article') -Images @() -Videos @() -Metadata $metadata)
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $html = [string]$response.Content
        if (-not (Test-HasValue $html)) { throw 'Article page returned empty HTML content.' }
        $ogTitle = Get-MetaContent -Html $html -Key 'og:title'
        $ogDescription = Get-MetaContent -Html $html -Key 'og:description'
        if (-not (Test-HasValue $ogDescription)) { $ogDescription = Get-MetaContent -Html $html -Key 'description' -Attr 'name' }
        $ogImage = Get-MetaContent -Html $html -Key 'og:image'
        $author = Get-MetaContent -Html $html -Key 'author' -Attr 'name'
        if (-not (Test-HasValue $author)) { $author = Get-MetaContent -Html $html -Key 'article:author' }
        $publishedAt = Get-MetaContent -Html $html -Key 'article:published_time'
        if (-not (Test-HasValue $publishedAt)) { $publishedAt = Get-MetaContent -Html $html -Key 'og:published_time' }
        if (-not (Test-HasValue $publishedAt)) { $publishedAt = 'unknown' }
        $pageTitle = Get-HtmlTitle -Html $html
        $mainText = Get-BestArticleText -Html $html
        $rawText = Get-PreviewText -Text $mainText -Length 8000
        $title = if (Test-HasValue $TitleHint) { $TitleHint } elseif (Test-HasValue $ogTitle) { $ogTitle } elseif (Test-HasValue $pageTitle) { $pageTitle } else { "Article Clip - $(Get-HostLabel -Url $Url)" }
        if (-not (Test-HasValue $author)) { $author = 'unknown' }
        $summaryParts = New-Object System.Collections.Generic.List[string]
        if (Test-HasValue $ogDescription) { $summaryParts.Add($ogDescription) } else { $summaryParts.Add('Article text extracted from the page body.') }
        if (Test-HasValue $mainText) { $summaryParts.Add("Body preview: $(Get-PreviewText -Text $mainText -Length 180)") }
        $summary = ($summaryParts -join ' ').Trim()
        $images = @(); if (Test-HasValue $ogImage) { $images = @($ogImage) }
        $metadata = [ordered]@{ capture_level = if (Test-HasValue $mainText) { 'standard' } else { 'light' }; transcript_status='not_applicable'; media_downloaded=$false; analysis_ready=$true; extractor='web-article'; source_status_code=$response.StatusCode; source_status_description=$response.StatusDescription; main_text_length = if (Test-HasValue $mainText) { $mainText.Length } else { 0 } }
        return (New-CaptureObject -Title $title -Author $author -PublishedAt $publishedAt -Summary $summary -RawText $rawText -Transcript '' -Tags @('clipped','article') -Images $images -Videos @() -Metadata $metadata)
    } catch {
        return (New-ArticleFallbackCapture -Url $Url -TitleHint $TitleHint -ErrorText $_.Exception.Message)
    }
}

function Invoke-SocialCapture {
    param($Config,[string]$Url,[string]$TitleHint,[string]$Platform,[switch]$DryRun)
    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Social Clip - $Platform" }
        $metadata = [ordered]@{ capture_level='light'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='playwright'; dry_run=$true }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: Playwright social capture route not executed.' -RawText '' -Transcript '' -Tags @('clipped','social',$Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }
    $pythonCommand = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'command' -DefaultValue 'python'
    $scriptPath = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'script' -DefaultValue ''
    if (-not (Test-HasValue $scriptPath) -or $scriptPath -like '*REPLACE/WITH/YOUR*' -or $scriptPath -like '*REPLACE\WITH\YOUR*' -or -not (Test-Path $scriptPath)) { $scriptPath = Join-Path $PSScriptRoot 'capture_social_playwright.py' }
    $timeoutMs = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'timeout_ms' -DefaultValue '25000'
    $tempDir = New-LocalTempDirectory
    try {
        $outputJsonPath = Join-Path $tempDir 'social-capture.json'
        & $pythonCommand $scriptPath '--url' $Url '--platform' $Platform '--timeout-ms' $timeoutMs '--output-json' $outputJsonPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Playwright social capture failed with exit code $LASTEXITCODE." }
        if (-not (Test-Path $outputJsonPath)) { throw 'Playwright social capture did not write its JSON output file.' }
        $payload = Read-Utf8Text -Path $outputJsonPath
        if (-not (Test-HasValue $payload)) { throw 'Playwright social capture returned no output.' }
        $obj = ConvertFrom-JsonCompat -Json $payload -Depth 50
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { [string]$obj.title }
        if (-not (Test-HasValue $title)) { $title = "Social Clip - $Platform" }
        $tags = @($obj.tags | ForEach-Object { [string]$_ })
        $images = @($obj.images | ForEach-Object { [string]$_ })
        $videos = @($obj.videos | ForEach-Object { [string]$_ })
        return (New-CaptureObject -Title $title -Author ([string]$obj.author) -PublishedAt ([string]$obj.published_at) -Summary ([string]$obj.summary) -RawText ([string]$obj.raw_text) -Transcript ([string]$obj.transcript) -Tags $tags -Images $images -Videos $videos -Metadata $obj.metadata)
    } catch {
        return (New-SocialFallbackCapture -Url $Url -TitleHint $TitleHint -Platform $Platform -ErrorText $_.Exception.Message)
    } finally {
        Remove-LocalTempDirectory -Path $tempDir
    }
}
function Invoke-VideoMetadataCapture {
    param($Config,[string]$Url,[string]$TitleHint,[string]$Platform,[switch]$DryRun)
    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Video Clip - $Platform" }
        $metadata = [ordered]@{ capture_level='light'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='yt-dlp'; dry_run=$true }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: yt-dlp metadata route not executed.' -RawText '' -Transcript '' -Tags @('clipped','video',$Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }
    $ytDlpCommand = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'command' -DefaultValue 'yt-dlp'
    $subtitleLanguages = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'subtitle_languages' -DefaultValue 'all,-live_chat'
    $subtitleFormat = Get-RouteConfigValue -Config $Config -RouteName 'video_metadata' -PropertyName 'subtitle_format' -DefaultValue 'vtt/srt/best'
    $tempDir = New-LocalTempDirectory
    try {
        try {
            $metadataJson = & $ytDlpCommand '--dump-single-json' '--skip-download' '--no-warnings' '--no-playlist' $Url 2>&1
            if ($LASTEXITCODE -ne 0) { throw "yt-dlp metadata extraction failed with exit code $LASTEXITCODE. Output: $metadataJson" }
            $metadataText = ($metadataJson | Out-String).Trim(); if (-not (Test-HasValue $metadataText)) { throw 'yt-dlp returned no metadata output.' }
            $info = ConvertFrom-JsonCompat -Json $metadataText -Depth 100
            $baseTemplate = Join-Path $tempDir 'subtitle'
            $subtitleOutput = & $ytDlpCommand '--skip-download' '--write-subs' '--write-auto-subs' '--sub-langs' $subtitleLanguages '--sub-format' $subtitleFormat '--no-playlist' '--no-warnings' '-o' "$baseTemplate.%(ext)s" $Url 2>&1
            $subtitleExitCode = $LASTEXITCODE
            $transcript = if ($subtitleExitCode -eq 0) { Get-FirstSubtitleText -Directory $tempDir } else { '' }
            $publishedAt = 'unknown'; if (Test-HasValue $info.release_date) { $publishedAt = [string]$info.release_date } elseif (Test-HasValue $info.upload_date) { $publishedAt = [string]$info.upload_date }
            $description = if (Test-HasValue $info.description) { $info.description.Trim() } else { '' }
            $summaryParts = @('Metadata-first clipping via yt-dlp.'); if (Test-HasValue $info.uploader) { $summaryParts += "Uploader: $($info.uploader)." }; if (Test-HasValue $info.duration_string) { $summaryParts += "Duration: $($info.duration_string)." }; if (Test-HasValue $description) { $summaryParts += "Description preview: $(Get-PreviewText -Text $description -Length 180)" }
            $title = if (Test-HasValue $TitleHint) { $TitleHint } else { [string]$info.title }; if (-not (Test-HasValue $title)) { $title = "Video Clip - $Platform" }
            $author = if (Test-HasValue $info.uploader) { [string]$info.uploader } elseif (Test-HasValue $info.channel) { [string]$info.channel } else { 'unknown' }
            $images = @(); if (Test-HasValue $info.thumbnail) { $images = @([string]$info.thumbnail) }
            $videos = if (Test-HasValue $info.webpage_url) { @([string]$info.webpage_url) } else { @($Url) }
            $metadata = [ordered]@{ capture_level = if (Test-HasValue $transcript) { 'standard' } else { 'light' }; transcript_status = if (Test-HasValue $transcript) { 'available' } else { 'missing' }; media_downloaded=$false; analysis_ready=$true; extractor='yt-dlp'; duration=$info.duration; duration_string=$info.duration_string; uploader=$info.uploader; channel=$info.channel; extractor_key=$info.extractor_key; subtitle_command_exit_code=$subtitleExitCode; subtitle_command_output=($subtitleOutput | Out-String).Trim() }
            return (New-CaptureObject -Title $title -Author $author -PublishedAt $publishedAt -Summary (($summaryParts -join ' ').Trim()) -RawText $description -Transcript $transcript -Tags @('clipped','video',$Platform) -Images $images -Videos $videos -Metadata $metadata)
        } catch {
            return (New-VideoMetadataFallbackCapture -Url $Url -TitleHint $TitleHint -Platform $Platform -ErrorText $_.Exception.Message)
        }
    } finally {
        Remove-LocalTempDirectory -Path $tempDir
    }
}

function Invoke-PodcastCapture {
    param($Config,[string]$Url,[string]$TitleHint,[string]$Platform,[switch]$DryRun)
    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Podcast Clip - $Platform" }
        $metadata = [ordered]@{ capture_level='light'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='web-metadata'; dry_run=$true }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: podcast metadata route not executed.' -RawText '' -Transcript '' -Tags @('clipped','podcast',$Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $html = [string]$response.Content
        if (-not (Test-HasValue $html)) { throw 'Podcast page returned empty HTML content.' }
        $ogTitle = Get-MetaContent -Html $html -Key 'og:title'
        $ogDescription = Get-MetaContent -Html $html -Key 'og:description'
        if (-not (Test-HasValue $ogDescription)) { $ogDescription = Get-MetaContent -Html $html -Key 'description' -Attr 'name' }
        $ogImage = Get-MetaContent -Html $html -Key 'og:image'
        $pageTitle = Get-HtmlTitle -Html $html
        $plainText = Get-PlainTextFromHtml -Html $html
        $resourceHints = Get-PodcastResourceHints -Html $html -BaseUrl $Url
        $showNotes = Get-PodcastShowNotes -Html $html -Description $ogDescription -PlainText $plainText
        $transcript = Get-TranscriptFromUrl -TranscriptUrl $resourceHints.transcript_url
        $title = if (Test-HasValue $TitleHint) { $TitleHint } elseif (Test-HasValue $ogTitle) { $ogTitle } elseif (Test-HasValue $pageTitle) { $pageTitle } else { "Podcast Clip - $Platform" }
        $author = 'unknown'; if (Test-HasValue $pageTitle -and $pageTitle -match '^(?<episode>.*?)\s+-\s+(?<podcast>.*?)\s+\|') { $author = $Matches['podcast'] }
        $summaryParts = New-Object System.Collections.Generic.List[string]
        if (Test-HasValue $ogDescription) { $summaryParts.Add($ogDescription) } else { $summaryParts.Add('Podcast metadata captured from the episode page.') }
        if (Test-HasValue $resourceHints.rss_url) { $summaryParts.Add('RSS discovered.') }
        if (Test-HasValue $resourceHints.transcript_url) { $summaryParts.Add('Transcript hint discovered.') }
        if (Test-HasValue $resourceHints.enclosure_url) { $summaryParts.Add('Audio enclosure hint discovered.') }
        if (Test-HasValue $showNotes) { $summaryParts.Add('Show notes extracted from page content.') }
        $rawParts = New-Object System.Collections.Generic.List[string]
        if (Test-HasValue $ogDescription) { $rawParts.Add("Description:`n$ogDescription") }
        if (Test-HasValue $showNotes) { $rawParts.Add("Show Notes:`n$showNotes") } elseif (Test-HasValue $plainText) { $rawParts.Add("Page Text Preview:`n$(Get-PreviewText -Text $plainText -Length 1800)") }
        $images = @(); if (Test-HasValue $ogImage) { $images = @($ogImage) }
        $videos = @($Url); if (Test-HasValue $resourceHints.enclosure_url) { $videos += $resourceHints.enclosure_url }; $videos = @($videos | Select-Object -Unique)
        if (Test-HasValue $transcript) { $captureLevel = 'enhanced' } elseif (Test-HasValue $showNotes -or Test-HasValue $resourceHints.rss_url -or Test-HasValue $resourceHints.enclosure_url) { $captureLevel = 'standard' } else { $captureLevel = 'light' }
        $metadata = [ordered]@{ capture_level=$captureLevel; transcript_status = if (Test-HasValue $transcript) { 'available' } else { 'missing' }; media_downloaded=$false; analysis_ready=$true; extractor='web-metadata'; source_status_code=$response.StatusCode; source_status_description=$response.StatusDescription; rss_url=$resourceHints.rss_url; transcript_url=$resourceHints.transcript_url; enclosure_url=$resourceHints.enclosure_url; show_notes_extracted=[bool](Test-HasValue $showNotes) }
        return (New-CaptureObject -Title $title -Author $author -PublishedAt 'unknown' -Summary (($summaryParts -join ' ').Trim()) -RawText (($rawParts | Select-Object -Unique) -join "`n`n") -Transcript $transcript -Tags @('clipped','podcast',$Platform) -Images $images -Videos $videos -Metadata $metadata)
    } catch {
        return (New-PodcastFallbackCapture -Url $Url -TitleHint $TitleHint -Platform $Platform -ErrorText $_.Exception.Message)
    }
}

function Invoke-CaptureRoute {
    param($Config,$Detection,[string]$Url,[string]$TitleHint,[switch]$DryRun)
    switch ($Detection.route) {
        'article' { return Invoke-ArticleCapture -Url $Url -TitleHint $TitleHint -DryRun:$DryRun }
        'social' { return Invoke-SocialCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        'video_metadata' { return Invoke-VideoMetadataCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        'podcast' { return Invoke-PodcastCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        default { throw "Unsupported route: $($Detection.route)" }
    }
}

function Build-ClippingNote {
    param($Config,$Detection,$Capture,[string]$SourceUrl,[string]$CategoryHint)
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
    $metadataLines = @("- Capture Level: $($Capture.metadata.capture_level)", "- Transcript Status: $($Capture.metadata.transcript_status)", "- Media Downloaded: $($Capture.metadata.media_downloaded)", "- Analysis Ready: $($Capture.metadata.analysis_ready)")
    if ($Capture.metadata -is [System.Collections.IDictionary]) {
        foreach ($entry in $Capture.metadata.GetEnumerator()) {
            if ($entry.Key -in @('capture_level','transcript_status','media_downloaded','analysis_ready')) { continue }
            if ($null -eq $entry.Value) { continue }
            $value = if ($entry.Value -is [System.Array]) { ($entry.Value -join ', ') } else { [string]$entry.Value }
            if (Test-HasValue $value) { $metadataLines += "- $($entry.Key): $value" }
        }
    }
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
$($metadataLines -join "`n")
"@
    [pscustomobject]@{ title=$title; folder=$folder; file_name=$fileName; tags=$tags; note_body=$body }
}

function Write-NoteToVault {
    param($Config,$Note,[string]$VaultPath)
    $resolvedVaultPath = if (Test-HasValue $VaultPath) { $VaultPath } elseif (Test-HasValue $Config.obsidian.vault_path) { [string]$Config.obsidian.vault_path } else { '' }
    if (-not (Test-HasValue $resolvedVaultPath)) { throw 'No vault path provided. Supply -VaultPath or set obsidian.vault_path in config.' }
    $targetFolder = Join-Path $resolvedVaultPath $Note.folder
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    $targetPath = Join-Path $targetFolder $Note.file_name
    Write-Utf8Text -Path $targetPath -Content $Note.note_body
    $targetPath
}

if (-not (Test-HasValue $ConfigPath)) {
    if (Test-Path (Join-Path $PSScriptRoot '..\references\local-config.json')) { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.json' } else { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.example.json' }
}
$config = Get-Config -Path $ConfigPath
$detection = Get-Detection -Url $SourceUrl
$capture = Invoke-CaptureRoute -Config $config -Detection $detection -Url $SourceUrl -TitleHint $TitleHint -DryRun:$DryRun
$note = Build-ClippingNote -Config $config -Detection $detection -Capture $capture -SourceUrl $SourceUrl -CategoryHint $CategoryHint
$result = [ordered]@{ success=$true; dry_run=[bool]$DryRun; title=$note.title; folder=$note.folder; file_name=$note.file_name; route=$detection.route; platform=$detection.platform; content_type=$detection.content_type; tags=$note.tags; note_preview=$note.note_body; vault_path = if (Test-HasValue $VaultPath) { $VaultPath } else { $config.obsidian.vault_path } }
if (-not $DryRun -and $config.obsidian.mode -eq 'filesystem') { $result.note_path = Write-NoteToVault -Config $config -Note $note -VaultPath $VaultPath }
$json = $result | ConvertTo-Json -Depth 20
if (Test-HasValue $OutputJsonPath) { Write-Utf8Text -Path $OutputJsonPath -Content $json }
$json
