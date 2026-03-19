param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUrl,
    [string]$VaultPath,
    [string]$CategoryHint,
    [string]$TitleHint,
    [string]$ConfigPath,
    [string]$DetectionJsonPath,
    [string]$CaptureJsonPath,
    [string]$OutputJsonPath,
    [string]$DebugDirectory,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'source_input_helpers.ps1')

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

function Get-ResolvedVaultPath {
    param($Config, [string]$VaultPath)
    if (Test-HasValue $VaultPath) { return $VaultPath }
    if ($null -ne $Config.obsidian -and (Test-HasValue $Config.obsidian.vault_path)) { return [string]$Config.obsidian.vault_path }
    ''
}

function Get-DataValue {
    param($Data, [string]$Name)
    if ($null -eq $Data) { return $null }
    if ($Data -is [System.Collections.IDictionary]) {
        if ($Data.Contains($Name)) { return $Data[$Name] }
        return $null
    }
    $property = $Data.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $property.Value
}

function Get-StringValue {
    param($Data, [string]$Name, [string]$DefaultValue = '')
    $value = Get-DataValue -Data $Data -Name $Name
    if ($null -eq $value) { return $DefaultValue }
    if ($value -is [System.Array]) {
        $text = ($value | ForEach-Object { [string]$_ }) -join ', '
        if (Test-HasValue $text) { return $text }
        return $DefaultValue
    }
    $text = [string]$value
    if (Test-HasValue $text) { return $text }
    $DefaultValue
}

function Get-StringArrayValue {
    param($Data, [string]$Name)
    $value = Get-DataValue -Data $Data -Name $Name
    if ($null -eq $value) { return @() }
    if ($value -is [System.Array]) {
        return @($value | ForEach-Object { [string]$_ } | Where-Object { Test-HasValue $_ })
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        return @($value | ForEach-Object { [string]$_ } | Where-Object { Test-HasValue $_ })
    }
    if (Test-HasValue ([string]$value)) { return @([string]$value) }
    @()
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

function Get-ConfiguredPathValue {
    param($Object, [string]$PropertyName)
    if ($null -eq $Object) { return '' }
    $value = Get-StringValue -Data $Object -Name $PropertyName -DefaultValue ''
    if (-not (Test-HasValue $value)) { return '' }
    if ($value -like '*REPLACE/WITH/YOUR*' -or $value -like '*REPLACE\WITH\YOUR*') { return '' }
    $value
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

function New-Directory {
    param([string]$Path)
    if (-not (Test-HasValue $Path)) { return '' }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $Path
}

function Get-QueryParameterValue {
    param(
        [string]$Query,
        [string]$Name
    )
    if (-not (Test-HasValue $Query)) { return '' }
    $trimmed = $Query.TrimStart('?')
    foreach ($part in ($trimmed -split '&')) {
        if (-not (Test-HasValue $part)) { continue }
        $segments = $part -split '=', 2
        $key = [System.Uri]::UnescapeDataString($segments[0])
        if ($key -ne $Name) { continue }
        if ($segments.Count -lt 2) { return '' }
        return [System.Uri]::UnescapeDataString($segments[1])
    }
    ''
}

function Sanitize-Url {
    param([string]$Url)
    if (-not (Test-HasValue $Url)) { return $Url }
    try {
        $uri = [System.Uri]$Url
    } catch {
        return $Url
    }

    $urlHost = $uri.Host.ToLowerInvariant()
    $path = $uri.AbsolutePath
    if ($urlHost -eq 'www.douyin.com' -or $urlHost -eq 'v.douyin.com' -or $urlHost -eq 'douyin.com') {
        $vid = Get-QueryParameterValue -Query $uri.Query -Name 'vid'
        if (Test-HasValue $vid) {
            return "https://www.douyin.com/video/$vid"
        }
        if ($path -match '/video/([0-9]+)') {
            return "https://www.douyin.com/video/$($Matches[1])"
        }
    }

    $builder = [System.UriBuilder]::new($uri)
    $builder.Query = ''
    $builder.Fragment = ''
    $sanitized = $builder.Uri.AbsoluteUri
    if ($sanitized.EndsWith('/')) {
        return $sanitized.TrimEnd('/')
    }
    $sanitized
}

function Sanitize-PathValue {
    param([string]$Value)
    if (-not (Test-HasValue $Value)) { return $Value }

    $sanitized = $Value
    if (Test-HasValue $resolvedVaultPath) {
        $vaultFull = [System.IO.Path]::GetFullPath($resolvedVaultPath).TrimEnd('\', '/')
        $vaultFullForward = ($vaultFull -replace '\\', '/')
        $sanitized = $sanitized.Replace($vaultFull, '<vault-root>')
        $sanitized = $sanitized.Replace($vaultFullForward, '<vault-root>')
    }
    if (Test-HasValue $env:USERPROFILE) {
        $userProfileForward = ($env:USERPROFILE -replace '\\', '/')
        $sanitized = $sanitized.Replace($env:USERPROFILE, '%USERPROFILE%')
        $sanitized = $sanitized.Replace($userProfileForward, '%USERPROFILE%')
    }
    $sanitized
}

function Sanitize-Text {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return $Text }
    $sanitized = $Text
    if (Test-HasValue $SourceUrl) {
        $sanitized = $sanitized.Replace($SourceUrl, (Sanitize-Url -Url $SourceUrl))
    }
    $sanitized = Sanitize-PathValue -Value $sanitized
    $sanitized
}

function Get-SanitizedData {
    param(
        $Value,
        [string]$PropertyName = ''
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $name = $PropertyName.ToLowerInvariant()
        if ($name -like '*url*') { return (Sanitize-Url -Url $Value) }
        if ($name -like '*path*' -or $name -like '*directory*' -or $name -eq 'vault_path' -or $name -eq 'note_path') { return (Sanitize-PathValue -Value $Value) }
        return (Sanitize-Text -Text $Value)
    }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[$key] = Get-SanitizedData -Value $Value[$key] -PropertyName ([string]$key)
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(Get-SanitizedData -Value $item -PropertyName $PropertyName)
        }
        return $items
    }
    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in $properties) {
            $result[$property.Name] = Get-SanitizedData -Value $property.Value -PropertyName $property.Name
        }
        return $result
    }
    $Value
}

function Write-SanitizedJsonFile {
    param(
        [string]$Path,
        $Data,
        [int]$Depth = 100
    )
    if (-not (Test-HasValue $Path) -or $null -eq $Data) { return }
    $sanitized = Get-SanitizedData -Value $Data
    Write-Utf8Text -Path $Path -Content ($sanitized | ConvertTo-Json -Depth $Depth)
}

function Get-ArtifactDirectory {
    param(
        [string]$ExplicitDirectory,
        [string]$JsonPath
    )
    if (Test-HasValue $ExplicitDirectory) { return (New-Directory -Path $ExplicitDirectory) }
    if (Test-HasValue $JsonPath) {
        $parent = Split-Path -Parent $JsonPath
        if (Test-HasValue $parent) { return (New-Directory -Path $parent) }
    }
    ''
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
    param([string]$Title,[string]$Author,[string]$PublishedAt,[string]$Summary,[string]$RawText,[string]$Transcript,[string[]]$Tags,[string[]]$Images,[string[]]$Videos,$Metadata,$ExtraProperties)
    $capture = [ordered]@{ title=$Title; author=$Author; published_at=$PublishedAt; summary=$Summary; raw_text=$RawText; transcript=$Transcript; tags=$Tags; images=$Images; videos=$Videos; metadata=$Metadata }
    if ($null -ne $ExtraProperties) {
        if ($ExtraProperties -is [System.Collections.IDictionary]) {
            foreach ($entry in $ExtraProperties.GetEnumerator()) {
                $capture[$entry.Key] = $entry.Value
            }
        } else {
            foreach ($property in $ExtraProperties.PSObject.Properties) {
                $capture[$property.Name] = $property.Value
            }
        }
    }
    [pscustomobject]$capture
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
    param($Config,[string]$Url,[string]$TitleHint,[string]$Platform,[string]$ResolvedVaultPath,[switch]$DryRun)
    if ($DryRun) {
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { "Social Clip - $Platform" }
        $metadata = [ordered]@{ capture_level='light'; transcript_status='missing'; media_downloaded=$false; analysis_ready=$true; extractor='playwright'; dry_run=$true }
        return (New-CaptureObject -Title $title -Author 'unknown' -PublishedAt 'unknown' -Summary 'Dry run: Playwright social capture route not executed.' -RawText '' -Transcript '' -Tags @('clipped','social',$Platform) -Images @() -Videos @($Url) -Metadata $metadata)
    }
    $pythonCommand = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'command' -DefaultValue 'python'
    $scriptPath = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'script' -DefaultValue ''
    if (-not (Test-HasValue $scriptPath) -or $scriptPath -like '*REPLACE/WITH/YOUR*' -or $scriptPath -like '*REPLACE\WITH\YOUR*' -or -not (Test-Path $scriptPath)) { $scriptPath = Join-Path $PSScriptRoot 'capture_social_playwright.py' }
    $timeoutMs = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'timeout_ms' -DefaultValue '25000'
    $authConfig = $null
    if ($null -ne $Config.routes -and $null -ne $Config.routes.social) {
        $authConfig = Get-DataValue -Data $Config.routes.social -Name 'auth'
    }
    $storageStatePath = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'storage_state_path'
    $cookiesFile = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'cookies_file'
    $tempDir = New-LocalTempDirectory
    try {
        $outputJsonPath = Join-Path $tempDir 'social-capture.json'
        $captureArguments = @($scriptPath, '--url', $Url, '--platform', $Platform, '--timeout-ms', $timeoutMs, '--output-json', $outputJsonPath)
        if (Test-HasValue $storageStatePath) { $captureArguments += @('--storage-state', $storageStatePath) }
        if (Test-HasValue $cookiesFile) { $captureArguments += @('--cookies-file', $cookiesFile) }
        & $pythonCommand @captureArguments 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Playwright social capture failed with exit code $LASTEXITCODE." }
        if (-not (Test-Path $outputJsonPath)) { throw 'Playwright social capture did not write its JSON output file.' }
        $payload = Read-Utf8Text -Path $outputJsonPath
        if (-not (Test-HasValue $payload)) { throw 'Playwright social capture returned no output.' }
        $obj = ConvertFrom-JsonCompat -Json $payload -Depth 50
        if (Test-HasValue $ResolvedVaultPath) {
            $downloadScriptPath = Join-Path $PSScriptRoot 'download_social_media.ps1'
            if (Test-Path $downloadScriptPath) {
                $downloadCommand = Get-RouteConfigValue -Config $Config -RouteName 'social' -PropertyName 'download_command' -DefaultValue 'yt-dlp'
                $attachmentsRoot = if ($null -ne $Config.clipper -and (Test-HasValue $Config.clipper.attachments_root)) { [string]$Config.clipper.attachments_root } else { 'Attachments/ShortVideos' }
                $downloadOutputPath = Join-Path $tempDir 'social-download.json'
                $downloadParameters = @{
                    PayloadJsonPath = $outputJsonPath
                    VaultPath = $ResolvedVaultPath
                    Platform = $Platform
                    SourceUrl = $Url
                    AttachmentsRoot = $attachmentsRoot
                    YtDlpCommand = $downloadCommand
                    OutputJsonPath = $downloadOutputPath
                }
                if (Test-HasValue $cookiesFile) { $downloadParameters.CookiesFile = $cookiesFile }
                if (Test-HasValue $storageStatePath) { $downloadParameters.StorageStatePath = $storageStatePath }
                try {
                    & $downloadScriptPath @downloadParameters | Out-Null
                } catch {
                }
                if (Test-Path $downloadOutputPath) {
                    $downloadPayload = Read-Utf8Text -Path $downloadOutputPath
                    if (Test-HasValue $downloadPayload) {
                        $obj = ConvertFrom-JsonCompat -Json $downloadPayload -Depth 100
                    }
                }
            }
        }
        $title = if (Test-HasValue $TitleHint) { $TitleHint } else { [string]$obj.title }
        if (-not (Test-HasValue $title)) { $title = "Social Clip - $Platform" }
        $tags = @($obj.tags | ForEach-Object { [string]$_ })
        $images = @($obj.images | ForEach-Object { [string]$_ })
        $videos = @($obj.videos | ForEach-Object { [string]$_ })
        $extraProperties = [ordered]@{}
        foreach ($property in $obj.PSObject.Properties) {
            if ($property.Name -in @('title','author','published_at','summary','raw_text','transcript','tags','images','videos','metadata')) { continue }
            $extraProperties[$property.Name] = $property.Value
        }
        return (New-CaptureObject -Title $title -Author ([string]$obj.author) -PublishedAt ([string]$obj.published_at) -Summary ([string]$obj.summary) -RawText ([string]$obj.raw_text) -Transcript ([string]$obj.transcript) -Tags $tags -Images $images -Videos $videos -Metadata $obj.metadata -ExtraProperties $extraProperties)
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
    param($Config,$Detection,[string]$Url,[string]$TitleHint,[string]$ResolvedVaultPath,[switch]$DryRun)
    switch ($Detection.route) {
        'article' { return Invoke-ArticleCapture -Url $Url -TitleHint $TitleHint -DryRun:$DryRun }
        'social' { return Invoke-SocialCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -ResolvedVaultPath $ResolvedVaultPath -DryRun:$DryRun }
        'video_metadata' { return Invoke-VideoMetadataCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        'podcast' { return Invoke-PodcastCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -DryRun:$DryRun }
        default { throw "Unsupported route: $($Detection.route)" }
    }
}

function ConvertTo-YamlScalar {
    param($Value)
    if ($null -eq $Value) { return "''" }
    $text = [string]$Value
    $text = $text -replace "'", "''"
    return "'$text'"
}

function Invoke-NoteRenderer {
    param($Config,$Detection,$Capture,[string]$SourceUrl,[string]$CategoryHint,[string]$ResolvedVaultPath,[switch]$DryRun)

    $pythonCommand = 'python'
    $rendererScript = Join-Path $PSScriptRoot 'render_clipping_note.py'
    if (-not (Test-Path $rendererScript)) { throw "Note renderer not found: $rendererScript" }

    $tempDir = New-LocalTempDirectory
    try {
        $configJsonPath = Join-Path $tempDir 'renderer-config.json'
        $detectionJsonPath = Join-Path $tempDir 'renderer-detection.json'
        $captureJsonPath = Join-Path $tempDir 'renderer-capture.json'
        $outputJsonPath = Join-Path $tempDir 'renderer-output.json'

        Write-Utf8Text -Path $configJsonPath -Content ($Config | ConvertTo-Json -Depth 20)
        Write-Utf8Text -Path $detectionJsonPath -Content ($Detection | ConvertTo-Json -Depth 20)
        Write-Utf8Text -Path $captureJsonPath -Content ($Capture | ConvertTo-Json -Depth 40)

        $arguments = @(
            $rendererScript,
            '--config-json', $configJsonPath,
            '--detection-json', $detectionJsonPath,
            '--capture-json', $captureJsonPath,
            '--source-url', $SourceUrl,
            '--output-json', $outputJsonPath
        )
        if (Test-HasValue $CategoryHint) { $arguments += @('--category-hint', $CategoryHint) }
        if (Test-HasValue $ResolvedVaultPath) { $arguments += @('--vault-path', $ResolvedVaultPath) }
        if (-not $DryRun -and $null -ne $Config.obsidian -and $Config.obsidian.mode -eq 'filesystem') { $arguments += '--write-note' }
        if ($DryRun) { $arguments += '--dry-run' }

        $commandOutput = (& $pythonCommand @arguments 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "Note renderer failed: $commandOutput"
        }
        return (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $outputJsonPath) -Depth 64)
    } finally {
        Remove-LocalTempDirectory -Path $tempDir
    }
}

function Get-MarkdownDisplayTitle {
    param([string]$Title)
    if (-not (Test-HasValue $Title)) { return 'Untitled Clip' }
    if ($Title.StartsWith('#')) { return ('\' + $Title) }
    $Title
}

function Test-LooksLikeLoginPrompt {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    return ($lower.Contains('login'))
}

function Build-ClippingNote {
    param($Config,$Detection,$Capture,[string]$SourceUrl,[string]$CategoryHint)

    $captured = Get-Date -Format 'yyyy-MM-dd'
    $folder = if (Test-HasValue $CategoryHint) { $CategoryHint } elseif (Test-HasValue $Config.clipper.default_folder) { [string]$Config.clipper.default_folder } else { 'Clippings' }
    $title = [string]$Capture.title
    $displayTitle = Get-MarkdownDisplayTitle -Title $title
    $prefixDate = if ($Config.clipper.prefix_date -eq $true) { "$captured " } else { '' }
    $fileName = Get-SafeFileName "$prefixDate$title.md"
    $tags = @($Capture.tags | Where-Object { Test-HasValue $_ } | Select-Object -Unique)
    if ($tags.Count -eq 0) { $tags = @('clipped') }

    $imagesText = if (@($Capture.images).Count -gt 0) { (@($Capture.images) | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $videosText = if (@($Capture.videos).Count -gt 0) { (@($Capture.videos) | ForEach-Object { "- $_" }) -join "`n" } else { '- none' }
    $summaryText = if (Test-HasValue $Capture.summary) { [string]$Capture.summary } else { '(none)' }
    $rawText = if (Test-HasValue $Capture.raw_text) { [string]$Capture.raw_text } else { '(none)' }
    $transcript = if (Test-HasValue $Capture.transcript) { [string]$Capture.transcript } else { '(none)' }
    $metadata = Get-DataValue -Data $Capture -Name 'metadata'

    $captureLevel = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'capture_level' -DefaultValue 'light' } else { 'light' }
    $transcriptStatus = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'transcript_status' -DefaultValue 'missing' } else { 'missing' }
    $analysisReadyValue = Get-DataValue -Data $Capture -Name 'analysis_ready'
    if ($null -eq $analysisReadyValue -and $null -ne $metadata) { $analysisReadyValue = Get-DataValue -Data $metadata -Name 'analysis_ready' }
    $analysisReady = if ($null -eq $analysisReadyValue) { $true } else { [bool]$analysisReadyValue }

    $captureId = Get-StringValue -Data $Capture -Name 'capture_id' -DefaultValue ''
    if (-not (Test-HasValue $captureId) -and $null -ne $metadata) { $captureId = Get-StringValue -Data $metadata -Name 'capture_id' -DefaultValue '' }
    $captureKey = Get-StringValue -Data $Capture -Name 'capture_key' -DefaultValue ''
    if (-not (Test-HasValue $captureKey) -and $null -ne $metadata) { $captureKey = Get-StringValue -Data $metadata -Name 'capture_key' -DefaultValue '' }
    $normalizedUrl = Get-StringValue -Data $Capture -Name 'normalized_url' -DefaultValue ''
    if (-not (Test-HasValue $normalizedUrl) -and $null -ne $metadata) { $normalizedUrl = Get-StringValue -Data $metadata -Name 'normalized_url' -DefaultValue '' }
    $sourceItemId = Get-StringValue -Data $Capture -Name 'source_item_id' -DefaultValue ''
    if (-not (Test-HasValue $sourceItemId) -and $null -ne $metadata) { $sourceItemId = Get-StringValue -Data $metadata -Name 'source_item_id' -DefaultValue '' }

    $downloadStatus = Get-StringValue -Data $Capture -Name 'download_status' -DefaultValue ''
    if (-not (Test-HasValue $downloadStatus) -and $null -ne $metadata) { $downloadStatus = Get-StringValue -Data $metadata -Name 'download_status' -DefaultValue '' }
    $downloadMethod = Get-StringValue -Data $Capture -Name 'download_method' -DefaultValue ''
    if (-not (Test-HasValue $downloadMethod) -and $null -ne $metadata) { $downloadMethod = Get-StringValue -Data $metadata -Name 'download_method' -DefaultValue '' }
    $videoPath = Get-StringValue -Data $Capture -Name 'video_path' -DefaultValue ''
    if (-not (Test-HasValue $videoPath) -and $null -ne $metadata) { $videoPath = Get-StringValue -Data $metadata -Name 'video_path' -DefaultValue '' }
    $coverPath = Get-StringValue -Data $Capture -Name 'cover_path' -DefaultValue ''
    if (-not (Test-HasValue $coverPath) -and $null -ne $metadata) { $coverPath = Get-StringValue -Data $metadata -Name 'cover_path' -DefaultValue '' }
    $sidecarPath = Get-StringValue -Data $Capture -Name 'sidecar_path' -DefaultValue ''
    if (-not (Test-HasValue $sidecarPath) -and $null -ne $metadata) { $sidecarPath = Get-StringValue -Data $metadata -Name 'sidecar_path' -DefaultValue '' }
    $commentsPath = Get-StringValue -Data $Capture -Name 'comments_path' -DefaultValue ''
    if (-not (Test-HasValue $commentsPath) -and $null -ne $metadata) { $commentsPath = Get-StringValue -Data $metadata -Name 'comments_path' -DefaultValue '' }
    $metadataPath = Get-StringValue -Data $Capture -Name 'metadata_path' -DefaultValue ''
    if (-not (Test-HasValue $metadataPath) -and $null -ne $metadata) { $metadataPath = Get-StringValue -Data $metadata -Name 'metadata_path' -DefaultValue '' }

    $mediaDownloadedValue = Get-DataValue -Data $Capture -Name 'media_downloaded'
    if ($null -eq $mediaDownloadedValue -and $null -ne $metadata) { $mediaDownloadedValue = Get-DataValue -Data $metadata -Name 'media_downloaded' }
    $mediaDownloaded = if ($null -ne $mediaDownloadedValue) { [bool]$mediaDownloadedValue } else { $false }
    if (-not $mediaDownloaded -and (Test-HasValue $videoPath)) { $mediaDownloaded = $true }

    $rawTopComments = Get-StringArrayValue -Data $Capture -Name 'top_comments'
    if (@($rawTopComments).Count -eq 0) {
        $commentObjects = @(Get-DataValue -Data $Capture -Name 'comments')
        $rawTopComments = @(
            $commentObjects |
            ForEach-Object {
                $display = Get-StringValue -Data $_ -Name 'display_text' -DefaultValue ''
                if (-not (Test-HasValue $display)) {
                    $author = Get-StringValue -Data $_ -Name 'author' -DefaultValue ''
                    $text = Get-StringValue -Data $_ -Name 'text' -DefaultValue ''
                    if (Test-HasValue $author -and Test-HasValue $text) { $display = "${author}: $text" }
                    elseif (Test-HasValue $text) { $display = $text }
                }
                if (Test-HasValue $display) { $display }
            } |
            Where-Object { Test-HasValue $_ }
        )
    }
    $topComments = @($rawTopComments | Where-Object { -not (Test-LooksLikeLoginPrompt -Text ([string]$_)) })
    $topCommentsLoginPrompts = @($rawTopComments | Where-Object { Test-LooksLikeLoginPrompt -Text ([string]$_) })

    $commentsCountValue = Get-DataValue -Data $Capture -Name 'comments_count'
    if ($null -eq $commentsCountValue -and $null -ne $metadata) { $commentsCountValue = Get-DataValue -Data $metadata -Name 'comment_count_visible' }
    $commentsCountText = if ($null -ne $commentsCountValue -and (Test-HasValue ([string]$commentsCountValue))) { [string]$commentsCountValue } elseif (@($topComments).Count -gt 0) { [string]@($topComments).Count } else { '0' }
    $commentsCaptureStatus = Get-StringValue -Data $Capture -Name 'comments_capture_status' -DefaultValue ''
    if (-not (Test-HasValue $commentsCaptureStatus) -and $null -ne $metadata) { $commentsCaptureStatus = Get-StringValue -Data $metadata -Name 'comments_capture_status' -DefaultValue '' }
    if (-not (Test-HasValue $commentsCaptureStatus)) { $commentsCaptureStatus = if (@($topComments).Count -gt 0) { 'captured' } else { 'none' } }
    $commentsLoginRequiredValue = Get-DataValue -Data $Capture -Name 'comments_login_required'
    if ($null -eq $commentsLoginRequiredValue -and $null -ne $metadata) { $commentsLoginRequiredValue = Get-DataValue -Data $metadata -Name 'comments_login_required' }
    $commentsLoginRequired = ($commentsCaptureStatus -eq 'login_required')
    if ($commentsLoginRequiredValue -eq $true) { $commentsLoginRequired = $true }
    if (@($topCommentsLoginPrompts).Count -gt 0) { $commentsLoginRequired = $true }
    if ($commentsLoginRequired -and @($topComments).Count -eq 0) {
        $commentsCaptureStatus = 'login_required'
        $commentsCountText = '0'
    }

    $metricsLike = Get-StringValue -Data $Capture -Name 'metrics_like' -DefaultValue ''
    if (-not (Test-HasValue $metricsLike) -and $null -ne $metadata) { $metricsLike = Get-StringValue -Data $metadata -Name 'like_count' -DefaultValue '' }
    $metricsComment = Get-StringValue -Data $Capture -Name 'metrics_comment' -DefaultValue ''
    if (-not (Test-HasValue $metricsComment) -and $null -ne $metadata) { $metricsComment = Get-StringValue -Data $metadata -Name 'comment_count' -DefaultValue '' }
    $metricsShare = Get-StringValue -Data $Capture -Name 'metrics_share' -DefaultValue ''
    if (-not (Test-HasValue $metricsShare) -and $null -ne $metadata) { $metricsShare = Get-StringValue -Data $metadata -Name 'share_count' -DefaultValue '' }
    $metricsCollect = Get-StringValue -Data $Capture -Name 'metrics_collect' -DefaultValue ''
    if (-not (Test-HasValue $metricsCollect) -and $null -ne $metadata) { $metricsCollect = Get-StringValue -Data $metadata -Name 'collect_count' -DefaultValue '' }

    $analyzerStatus = Get-StringValue -Data $Capture -Name 'analyzer_status' -DefaultValue 'pending'
    $bitableSyncStatus = Get-StringValue -Data $Capture -Name 'bitable_sync_status' -DefaultValue 'pending'
    $isSocialShortVideo = ($Detection.route -eq 'social' -and $Detection.content_type -eq 'short_video')

    $topCommentsText = if (@($topComments).Count -gt 0) {
        (@($topComments) | ForEach-Object { "- $_" }) -join "`n"
    } elseif ($commentsLoginRequired) {
        '- Comments may require login.'
    } else {
        '- No visible comments captured.'
    }

    $engagementLines = @(
        "- Likes: $(if (Test-HasValue $metricsLike) { $metricsLike } else { 'missing' })",
        "- Platform Comments: $(if (Test-HasValue $metricsComment) { $metricsComment } else { 'missing' })",
        "- Captured Comments: $commentsCountText",
        "- Shares: $(if (Test-HasValue $metricsShare) { $metricsShare } else { 'missing' })",
        "- Collects: $(if (Test-HasValue $metricsCollect) { $metricsCollect } else { 'missing' })",
        "- Comment Capture: $commentsCaptureStatus"
    )

    $videoSectionLines = New-Object System.Collections.Generic.List[string]
    if (Test-HasValue $videoPath) {
        $videoSectionLines.Add("![[${videoPath}]]")
        $videoSectionLines.Add('')
        $videoSectionLines.Add("- Local Video: $videoPath")
        $videoSectionLines.Add("- Download Status: $(if (Test-HasValue $downloadStatus) { $downloadStatus } else { 'unknown' })")
        $videoSectionLines.Add("- Download Method: $(if (Test-HasValue $downloadMethod) { $downloadMethod } else { 'unknown' })")
    } else {
        $videoSectionLines.Add('- No local mp4 file stored yet.')
    }

    $attachmentLines = New-Object System.Collections.Generic.List[string]
    if (Test-HasValue $videoPath) { $attachmentLines.Add("- Local Video: $videoPath") }
    if (Test-HasValue $coverPath) { $attachmentLines.Add("- Cover Image: $coverPath") }
    if (Test-HasValue $sidecarPath) { $attachmentLines.Add("- Capture JSON: $sidecarPath") }
    if (Test-HasValue $commentsPath) { $attachmentLines.Add("- Comments JSON: $commentsPath") }
    if (Test-HasValue $metadataPath) { $attachmentLines.Add("- Metadata JSON: $metadataPath") }
    if ($attachmentLines.Count -eq 0) { $attachmentLines.Add('- none') }

    $statusLines = @(
        "- Download Status: $(if (Test-HasValue $downloadStatus) { $downloadStatus } else { 'unknown' })",
        "- Download Method: $(if (Test-HasValue $downloadMethod) { $downloadMethod } else { 'unknown' })",
        "- Media Stored: $(if ($mediaDownloaded) { 'yes' } else { 'no' })",
        "- Transcript Status: $transcriptStatus",
        "- Analyzer Status: $(if (Test-HasValue $analyzerStatus) { $analyzerStatus } else { 'pending' })",
        "- Bitable Sync: $(if (Test-HasValue $bitableSyncStatus) { $bitableSyncStatus } else { 'pending' })",
        "- Analysis Ready: $(if ($analysisReady) { 'yes' } else { 'no' })"
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('---')
    $lines.Add("title: $(ConvertTo-YamlScalar $title)")
    $lines.Add("source_url: $(ConvertTo-YamlScalar $SourceUrl)")
    $lines.Add("normalized_url: $(ConvertTo-YamlScalar $normalizedUrl)")
    $lines.Add("platform: $(ConvertTo-YamlScalar $Detection.platform)")
    $lines.Add("content_type: $(ConvertTo-YamlScalar $Detection.content_type)")
    $lines.Add("author: $(ConvertTo-YamlScalar $Capture.author)")
    $lines.Add("published_at: $(ConvertTo-YamlScalar $Capture.published_at)")
    $lines.Add("captured_at: $(ConvertTo-YamlScalar $captured)")
    $lines.Add("route: $(ConvertTo-YamlScalar $Detection.route)")
    $lines.Add("capture_id: $(ConvertTo-YamlScalar $captureId)")
    $lines.Add("capture_key: $(ConvertTo-YamlScalar $captureKey)")
    $lines.Add("source_item_id: $(ConvertTo-YamlScalar $sourceItemId)")
    $lines.Add("capture_level: $(ConvertTo-YamlScalar $captureLevel)")
    $lines.Add("transcript_status: $(ConvertTo-YamlScalar $transcriptStatus)")
    $lines.Add("media_downloaded: $($mediaDownloaded.ToString().ToLowerInvariant())")
    $lines.Add("analysis_ready: $($analysisReady.ToString().ToLowerInvariant())")
    $lines.Add("download_status: $(ConvertTo-YamlScalar $downloadStatus)")
    $lines.Add("download_method: $(ConvertTo-YamlScalar $downloadMethod)")
    $lines.Add("video_path: $(ConvertTo-YamlScalar $videoPath)")
    $lines.Add("sidecar_path: $(ConvertTo-YamlScalar $sidecarPath)")
    $lines.Add('tags:')
    foreach ($tag in $tags) {
        $lines.Add("  - $(ConvertTo-YamlScalar $tag)")
    }
    $lines.Add('status: clipped')
    $lines.Add('---')
    $lines.Add('')
    $lines.Add("# $displayTitle")
    $lines.Add('')
    $lines.Add('## Source')
    $lines.Add("- Link: $SourceUrl")
    $lines.Add("- Normalized URL: $(if (Test-HasValue $normalizedUrl) { $normalizedUrl } else { 'n/a' })")
    $lines.Add("- Platform: $($Detection.platform)")
    $lines.Add("- Content Type: $($Detection.content_type)")
    $lines.Add("- Route: $($Detection.route)")
    $lines.Add("- Capture ID: $(if (Test-HasValue $captureId) { $captureId } else { 'n/a' })")
    $lines.Add("- Source Item ID: $(if (Test-HasValue $sourceItemId) { $sourceItemId } else { 'n/a' })")
    $lines.Add('')
    if ($isSocialShortVideo) {
        $lines.Add('## Video')
        foreach ($line in $videoSectionLines) { $lines.Add($line) }
        $lines.Add('')
    }
    $lines.Add('## Summary')
    $lines.Add($summaryText)
    $lines.Add('')
    $lines.Add('## Raw Text')
    $lines.Add($rawText)
    $lines.Add('')
    if (Test-HasValue $transcript) {
        $lines.Add('## Transcript')
        $lines.Add($transcript)
        $lines.Add('')
    }
    $lines.Add('## Metrics')
    foreach ($line in $engagementLines) { $lines.Add($line) }
    $lines.Add('')
    $lines.Add('## Comments')
    foreach ($line in ($topCommentsText -split "`n")) { $lines.Add($line) }
    $lines.Add('')
    $lines.Add('## Attachments')
    foreach ($line in $attachmentLines) { $lines.Add($line) }
    if (-not $isSocialShortVideo) {
        $lines.Add('')
        $lines.Add('## Image URLs')
        foreach ($line in ($imagesText -split "`n")) { $lines.Add($line) }
        $lines.Add('')
        $lines.Add('## Video URLs')
        foreach ($line in ($videosText -split "`n")) { $lines.Add($line) }
    }
    $lines.Add('')
    $lines.Add('## Status')
    foreach ($line in $statusLines) { $lines.Add($line) }

    $body = $lines -join "`n"
    [pscustomobject]@{ title = $title; folder = $folder; file_name = $fileName; tags = $tags; note_body = $body }
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

function Get-RunSummaryLines {
    param($Result)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('=== Clipper Summary ===')
    $lines.Add("route    : $($Result.route)")
    $lines.Add("platform : $($Result.platform)")
    $lines.Add("title    : $($Result.title)")
    $lines.Add("capture  : $($Result.capture_id)")
    $lines.Add("download : $($Result.download_status) / $($Result.download_method)")
    $lines.Add("video    : $($Result.video_path)")
    if ($null -ne $Result.PSObject.Properties['note_path']) {
        $lines.Add("note     : $($Result.note_path)")
    }
    if ($null -ne $Result.PSObject.Properties['support_bundle_path']) {
        $lines.Add("share    : $($Result.support_bundle_path)")
    }
    if ($null -ne $Result.PSObject.Properties['errors'] -and @($Result.errors).Count -gt 0) {
        $lines.Add("error    : $((@($Result.errors) | Select-Object -First 1))")
    }
    return @($lines)
}

function Write-RunSummary {
    param($Result)
    $lines = Get-RunSummaryLines -Result $Result
    Write-Host ''
    Write-Host $lines[0] -ForegroundColor Cyan
    foreach ($line in @($lines | Select-Object -Skip 1)) {
        if ($line -like 'error    :*') {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
    Write-Host ''
}

if (-not (Test-HasValue $ConfigPath)) {
    if (Test-Path (Join-Path $PSScriptRoot '..\references\local-config.json')) { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.json' } else { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.example.json' }
}
$resolvedSourceInput = Resolve-SourceInput -InputText $SourceUrl
$rawSourceInput = $SourceUrl
$SourceUrl = $resolvedSourceInput.source_url
$config = Get-Config -Path $ConfigPath
$resolvedVaultPath = Get-ResolvedVaultPath -Config $config -VaultPath $VaultPath
if (-not $DryRun -and -not (Test-HasValue $resolvedVaultPath)) { throw 'No vault path provided. Supply -VaultPath or set obsidian.vault_path in config.' }
if (Test-HasValue $DetectionJsonPath) {
    if (-not (Test-Path $DetectionJsonPath)) { throw "Detection JSON not found: $DetectionJsonPath" }
    $detection = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $DetectionJsonPath) -Depth 64
} else {
    $detection = Get-Detection -Url $SourceUrl
}
if (Test-HasValue $CaptureJsonPath) {
    if (-not (Test-Path $CaptureJsonPath)) { throw "Capture JSON not found: $CaptureJsonPath" }
    $capture = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $CaptureJsonPath) -Depth 100
} else {
    $capture = Invoke-CaptureRoute -Config $config -Detection $detection -Url $SourceUrl -TitleHint $TitleHint -ResolvedVaultPath $resolvedVaultPath -DryRun:$DryRun
}
$note = Invoke-NoteRenderer -Config $config -Detection $detection -Capture $capture -SourceUrl $SourceUrl -CategoryHint $CategoryHint -ResolvedVaultPath $resolvedVaultPath -DryRun:$DryRun
$captureMetadata = Get-DataValue -Data $capture -Name 'metadata'
$captureIdForResult = Get-StringValue -Data $capture -Name 'capture_id' -DefaultValue ''
if (-not (Test-HasValue $captureIdForResult) -and $null -ne $captureMetadata) { $captureIdForResult = Get-StringValue -Data $captureMetadata -Name 'capture_id' -DefaultValue '' }
$downloadStatusForResult = Get-StringValue -Data $capture -Name 'download_status' -DefaultValue ''
if (-not (Test-HasValue $downloadStatusForResult) -and $null -ne $captureMetadata) { $downloadStatusForResult = Get-StringValue -Data $captureMetadata -Name 'download_status' -DefaultValue '' }
$downloadMethodForResult = Get-StringValue -Data $capture -Name 'download_method' -DefaultValue ''
if (-not (Test-HasValue $downloadMethodForResult) -and $null -ne $captureMetadata) { $downloadMethodForResult = Get-StringValue -Data $captureMetadata -Name 'download_method' -DefaultValue '' }
$videoPathForResult = Get-StringValue -Data $capture -Name 'video_path' -DefaultValue ''
if (-not (Test-HasValue $videoPathForResult) -and $null -ne $captureMetadata) { $videoPathForResult = Get-StringValue -Data $captureMetadata -Name 'video_path' -DefaultValue '' }
$sidecarPathForResult = Get-StringValue -Data $capture -Name 'sidecar_path' -DefaultValue ''
if (-not (Test-HasValue $sidecarPathForResult) -and $null -ne $captureMetadata) { $sidecarPathForResult = Get-StringValue -Data $captureMetadata -Name 'sidecar_path' -DefaultValue '' }
$result = [ordered]@{ success=$true; dry_run=[bool]$DryRun; title=$note.title; folder=$note.folder; file_name=$note.file_name; route=$detection.route; platform=$detection.platform; content_type=$detection.content_type; capture_id=$captureIdForResult; download_status=$downloadStatusForResult; download_method=$downloadMethodForResult; video_path=$videoPathForResult; sidecar_path=$sidecarPathForResult; tags=$note.tags; note_preview=$note.note_body; vault_path = $resolvedVaultPath; source_url = $SourceUrl; source_input_kind = $resolvedSourceInput.input_kind; source_url_extracted = [bool]$resolvedSourceInput.extraction_applied }
$captureErrors = Get-DataValue -Data $capture -Name 'errors'
if ($null -ne $captureErrors -and @($captureErrors).Count -gt 0) { $result.errors = @($captureErrors) }
$notePathFromRenderer = Get-StringValue -Data $note -Name 'note_path' -DefaultValue ''
if (Test-HasValue $notePathFromRenderer) { $result.note_path = $notePathFromRenderer }
$artifactDirectory = Get-ArtifactDirectory -ExplicitDirectory $DebugDirectory -JsonPath $OutputJsonPath
if (Test-HasValue $artifactDirectory) {
    $result.debug_directory = $artifactDirectory
    $result.support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
}

$resultObject = [pscustomobject]$result
$summaryLines = Get-RunSummaryLines -Result $resultObject
if (Test-HasValue $artifactDirectory) {
    $rawSummaryPath = Join-Path $artifactDirectory 'run-clipper-summary.txt'
    Write-Utf8Text -Path $rawSummaryPath -Content ($summaryLines -join "`r`n")

    $rawJsonPath = if (Test-HasValue $OutputJsonPath) { $OutputJsonPath } else { Join-Path $artifactDirectory 'run-clipper.json' }
    $json = $resultObject | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $rawJsonPath -Content $json

    $supportBundleDirectory = New-Directory -Path (Join-Path $artifactDirectory 'support-bundle')
    $sanitizedResult = Get-SanitizedData -Value $resultObject
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper.json') -Content (($sanitizedResult | ConvertTo-Json -Depth 20))
    $sanitizedSummaryLines = @((Get-RunSummaryLines -Result ([pscustomobject]$sanitizedResult)) | ForEach-Object { Sanitize-Text -Text ([string]$_) })
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper-summary.txt') -Content ($sanitizedSummaryLines -join "`r`n")
    $resultObject = [pscustomobject]$result
} else {
    $json = $resultObject | ConvertTo-Json -Depth 20
    if (Test-HasValue $OutputJsonPath) { Write-Utf8Text -Path $OutputJsonPath -Content $json }
}

Write-RunSummary -Result $resultObject
if (-not (Test-HasValue $json)) { $json = $resultObject | ConvertTo-Json -Depth 20 }
$json
