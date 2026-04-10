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

function Initialize-Utf8ProcessEncoding {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $script:OutputEncoding = $utf8NoBom
    $env:PYTHONIOENCODING = 'utf-8'
}

Initialize-Utf8ProcessEncoding

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

function Resolve-ConfigDirectoryPath {
    param([string]$ConfiguredPath, [string]$BasePath)
    if (-not (Test-HasValue $ConfiguredPath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) { return $ConfiguredPath }
    Join-Path $BasePath $ConfiguredPath
}

function Get-DefaultDebugDirectory {
    param($Config, [string]$RequestedDebugDirectory)
    if (Test-HasValue $RequestedDebugDirectory) { return $RequestedDebugDirectory }
    $configured = ''
    if ($null -ne $Config.clipper -and $null -ne $Config.clipper.PSObject.Properties['default_debug_directory'] -and (Test-HasValue ([string]$Config.clipper.default_debug_directory))) {
        $configured = [string]$Config.clipper.default_debug_directory
    }
    $clipperRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if (Test-HasValue $configured) {
        $base = Resolve-ConfigDirectoryPath -ConfiguredPath $configured -BasePath $clipperRoot
    } else {
        $base = Join-Path $clipperRoot '.tmp\run-clipper'
    }
    Join-Path $base (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Zh {
    param([string]$Escaped)
    [regex]::Unescape($Escaped)
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

function Get-BoolValueFromData {
    param($Data, [string]$Name, [bool]$DefaultValue = $false)
    $value = Get-DataValue -Data $Data -Name $Name
    if ($null -eq $value) { return $DefaultValue }
    if ($value -is [bool]) { return [bool]$value }
    $text = [string]$value
    if (-not (Test-HasValue $text)) { return $DefaultValue }
    switch ($text.Trim().ToLowerInvariant()) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'on' { return $true }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        'off' { return $false }
        default { return $DefaultValue }
    }
}

function Set-ObjectField {
    param($Object, [string]$Name, $Value)
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return $Object
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $Object
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

function Add-UniqueStringToArray {
    param([string[]]$Items, [string]$Value, [switch]$Prepend)
    $existing = @($Items | Where-Object { Test-HasValue $_ } | ForEach-Object { [string]$_ })
    if (-not (Test-HasValue $Value)) { return $existing }
    $filtered = @($existing | Where-Object { $_ -ne $Value })
    if ($Prepend) { return @($Value) + $filtered }
    return $filtered + @($Value)
}

function Invoke-XiaohongshuExtractor {
    param($Config,[string]$SourceUrl,[string]$NormalizedUrl,[string]$PythonCommand,[string]$CookiesFile,[string]$StorageStatePath,[string]$TempDir)
    $socialRouteConfig = Get-DataValue -Data $Config.routes -Name 'social'
    $adapterConfig = if ($null -ne $socialRouteConfig) { Get-DataValue -Data $socialRouteConfig -Name 'xiaohongshu_adapter' } else { $null }
    $extractorCommand = if ($null -ne $adapterConfig) { Get-ConfiguredPathValue -Object $adapterConfig -PropertyName 'command' } else { '' }
    $extractorServerUrl = if ($null -ne $adapterConfig) { Get-StringValue -Data $adapterConfig -Name 'server_url' -DefaultValue 'http://127.0.0.1:5556/xhs/detail' } else { 'http://127.0.0.1:5556/xhs/detail' }
    $extractorTimeoutValue = if ($null -ne $adapterConfig) { Get-StringValue -Data $adapterConfig -Name 'timeout_ms' -DefaultValue '30000' } else { '30000' }
    $extractorScript = Join-Path $PSScriptRoot 'xiaohongshu_extract.py'
    if (-not (Test-HasValue $extractorCommand)) { $extractorCommand = $PythonCommand }
    if (-not (Test-Path $extractorScript)) { return $null }
    $extractorOutputPath = Join-Path $TempDir 'xiaohongshu-extract.json'
    $backendPayloadPath = Join-Path $TempDir 'xiaohongshu-extract-backend.json'
    $extractArguments = @($extractorScript, '--source-url', $SourceUrl, '--server-url', $extractorServerUrl, '--timeout-ms', $extractorTimeoutValue, '--output-json', $extractorOutputPath, '--backend-payload-path', $backendPayloadPath)
    if (Test-HasValue $NormalizedUrl) { $extractArguments += @('--normalized-url', $NormalizedUrl) }
    if (Test-HasValue $CookiesFile) { $extractArguments += @('--cookies-file', $CookiesFile) }
    if (Test-HasValue $StorageStatePath) { $extractArguments += @('--storage-state-path', $StorageStatePath) }
    & $extractorCommand @extractArguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $null }
    if (-not (Test-Path $extractorOutputPath)) { return $null }
    $payload = Read-Utf8Text -Path $extractorOutputPath
    if (-not (Test-HasValue $payload)) { return $null }
    ConvertFrom-JsonCompat -Json $payload -Depth 50
}

function Merge-XiaohongshuExtractorResult {
    param($CaptureObject, $ExtractorResult)
    if ($null -eq $CaptureObject -or $null -eq $ExtractorResult) { return $CaptureObject }
    $metadata = Get-DataValue -Data $CaptureObject -Name 'metadata'
    if ($null -eq $metadata) {
        $metadata = [ordered]@{}
        Set-ObjectField -Object $CaptureObject -Name 'metadata' -Value $metadata | Out-Null
    }

    $extractorSucceeded = [bool](Get-DataValue -Data $ExtractorResult -Name 'success')
    $extractorTitle = Get-StringValue -Data $ExtractorResult -Name 'title' -DefaultValue ''
    $extractorAuthor = Get-StringValue -Data $ExtractorResult -Name 'author' -DefaultValue ''
    $extractorDescription = Get-StringValue -Data $ExtractorResult -Name 'description' -DefaultValue ''
    $extractorPublishedAt = Get-StringValue -Data $ExtractorResult -Name 'published_at' -DefaultValue ''
    $canonicalVideoUrl = Get-StringValue -Data $ExtractorResult -Name 'canonical_video_url' -DefaultValue ''
    $coverUrl = Get-StringValue -Data $ExtractorResult -Name 'cover_url' -DefaultValue ''
    $mediaCandidates = Get-StringArrayValue -Data $ExtractorResult -Name 'media_candidates'
    $metrics = Get-DataValue -Data $ExtractorResult -Name 'metrics'

    if ($extractorSucceeded) {
        if (Test-HasValue $extractorTitle) { Set-ObjectField -Object $CaptureObject -Name 'title' -Value $extractorTitle | Out-Null }
        if (Test-HasValue $extractorAuthor) { Set-ObjectField -Object $CaptureObject -Name 'author' -Value $extractorAuthor | Out-Null }
        if (Test-HasValue $extractorPublishedAt) { Set-ObjectField -Object $CaptureObject -Name 'published_at' -Value $extractorPublishedAt | Out-Null }
        if (Test-HasValue $extractorDescription -and -not (Test-HasValue (Get-StringValue -Data $CaptureObject -Name 'description' -DefaultValue ''))) {
            Set-ObjectField -Object $CaptureObject -Name 'description' -Value $extractorDescription | Out-Null
        }

        if ($null -ne $metrics) {
            $likeCount = Get-StringValue -Data $metrics -Name 'like_count' -DefaultValue ''
            $commentCount = Get-StringValue -Data $metrics -Name 'comment_count' -DefaultValue ''
            $collectCount = Get-StringValue -Data $metrics -Name 'collect_count' -DefaultValue ''
            $shareCount = Get-StringValue -Data $metrics -Name 'share_count' -DefaultValue ''
            if (Test-HasValue $likeCount) {
                Set-ObjectField -Object $CaptureObject -Name 'metrics_like' -Value $likeCount | Out-Null
                Set-ObjectField -Object $metadata -Name 'like_count' -Value $likeCount | Out-Null
            }
            if (Test-HasValue $commentCount) {
                Set-ObjectField -Object $CaptureObject -Name 'metrics_comment' -Value $commentCount | Out-Null
                Set-ObjectField -Object $metadata -Name 'comment_count' -Value $commentCount | Out-Null
                Set-ObjectField -Object $metadata -Name 'platform_comment_count' -Value $commentCount | Out-Null
            }
            if (Test-HasValue $collectCount) {
                Set-ObjectField -Object $CaptureObject -Name 'metrics_collect' -Value $collectCount | Out-Null
                Set-ObjectField -Object $metadata -Name 'collect_count' -Value $collectCount | Out-Null
            }
            if (Test-HasValue $shareCount) {
                Set-ObjectField -Object $CaptureObject -Name 'metrics_share' -Value $shareCount | Out-Null
                Set-ObjectField -Object $metadata -Name 'share_count' -Value $shareCount | Out-Null
            }
        }

        if (Test-HasValue $canonicalVideoUrl) {
            Set-ObjectField -Object $CaptureObject -Name 'canonical_video_url' -Value $canonicalVideoUrl | Out-Null
            $candidateVideoRefs = Get-StringArrayValue -Data $CaptureObject -Name 'candidate_video_refs'
            $candidateVideoRefs = Add-UniqueStringToArray -Items $candidateVideoRefs -Value $canonicalVideoUrl -Prepend
            Set-ObjectField -Object $CaptureObject -Name 'candidate_video_refs' -Value $candidateVideoRefs | Out-Null
        }
        foreach ($candidate in $mediaCandidates) {
            $candidateVideoRefs = Get-StringArrayValue -Data $CaptureObject -Name 'candidate_video_refs'
            $candidateVideoRefs = Add-UniqueStringToArray -Items $candidateVideoRefs -Value $candidate
            Set-ObjectField -Object $CaptureObject -Name 'candidate_video_refs' -Value $candidateVideoRefs | Out-Null
        }
        if (Test-HasValue $coverUrl) {
            Set-ObjectField -Object $CaptureObject -Name 'cover_url' -Value $coverUrl | Out-Null
            $images = Get-StringArrayValue -Data $CaptureObject -Name 'images'
            $images = Add-UniqueStringToArray -Items $images -Value $coverUrl -Prepend
            Set-ObjectField -Object $CaptureObject -Name 'images' -Value $images | Out-Null
        }
        Set-ObjectField -Object $metadata -Name 'metrics_source' -Value 'xiaohongshu_extractor' | Out-Null
    }

    Set-ObjectField -Object $CaptureObject -Name 'xiaohongshu_extractor_success' -Value $extractorSucceeded | Out-Null
    Set-ObjectField -Object $CaptureObject -Name 'xiaohongshu_extractor_error_code' -Value (Get-StringValue -Data $ExtractorResult -Name 'error_code' -DefaultValue '') | Out-Null
    Set-ObjectField -Object $CaptureObject -Name 'xiaohongshu_extractor_error_message' -Value (Get-StringValue -Data $ExtractorResult -Name 'error_message' -DefaultValue '') | Out-Null
    Set-ObjectField -Object $CaptureObject -Name 'xiaohongshu_extractor_backend' -Value (Get-StringValue -Data $ExtractorResult -Name 'backend' -DefaultValue '') | Out-Null
    Set-ObjectField -Object $CaptureObject -Name 'xiaohongshu_extractor_backend_payload_path' -Value (Get-StringValue -Data $ExtractorResult -Name 'backend_payload_path' -DefaultValue '') | Out-Null
    Set-ObjectField -Object $metadata -Name 'xiaohongshu_extractor_success' -Value $extractorSucceeded | Out-Null
    Set-ObjectField -Object $metadata -Name 'xiaohongshu_extractor_error_code' -Value (Get-StringValue -Data $ExtractorResult -Name 'error_code' -DefaultValue '') | Out-Null
    return $CaptureObject
}

function New-XiaohongshuCaptureFromExtractor {
    param([string]$SourceUrl, $ExtractorResult)
    if ($null -eq $ExtractorResult) { return $null }

    $title = Get-StringValue -Data $ExtractorResult -Name 'title' -DefaultValue 'Social Clip - xiaohongshu'
    $author = Get-StringValue -Data $ExtractorResult -Name 'author' -DefaultValue 'unknown'
    $publishedAt = Get-StringValue -Data $ExtractorResult -Name 'published_at' -DefaultValue 'unknown'
    $description = Get-StringValue -Data $ExtractorResult -Name 'description' -DefaultValue ''
    $normalizedUrl = Get-StringValue -Data $ExtractorResult -Name 'normalized_url' -DefaultValue $SourceUrl
    $sourceItemId = Get-StringValue -Data $ExtractorResult -Name 'source_item_id' -DefaultValue ''
    $captureKey = Get-StringValue -Data $ExtractorResult -Name 'capture_key' -DefaultValue ''
    $captureId = Get-StringValue -Data $ExtractorResult -Name 'capture_id' -DefaultValue ''
    $canonicalVideoUrl = Get-StringValue -Data $ExtractorResult -Name 'canonical_video_url' -DefaultValue ''
    $coverUrl = Get-StringValue -Data $ExtractorResult -Name 'cover_url' -DefaultValue ''
    $metrics = Get-DataValue -Data $ExtractorResult -Name 'metrics'
    $likeCount = if ($null -ne $metrics) { Get-StringValue -Data $metrics -Name 'like_count' -DefaultValue '' } else { '' }
    $commentCount = if ($null -ne $metrics) { Get-StringValue -Data $metrics -Name 'comment_count' -DefaultValue '' } else { '' }
    $collectCount = if ($null -ne $metrics) { Get-StringValue -Data $metrics -Name 'collect_count' -DefaultValue '' } else { '' }
    $shareCount = if ($null -ne $metrics) { Get-StringValue -Data $metrics -Name 'share_count' -DefaultValue '' } else { '' }
    $mediaCandidates = Get-StringArrayValue -Data $ExtractorResult -Name 'media_candidates'

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if (Test-HasValue $description) { $summaryParts.Add((Get-PreviewText -Text $description -Length 240)) }
    $metricParts = New-Object System.Collections.Generic.List[string]
    if (Test-HasValue $likeCount) { $metricParts.Add("likes $likeCount") | Out-Null }
    if (Test-HasValue $commentCount) { $metricParts.Add("comments $commentCount") | Out-Null }
    if (Test-HasValue $collectCount) { $metricParts.Add("collects $collectCount") | Out-Null }
    if (Test-HasValue $shareCount) { $metricParts.Add("shares $shareCount") | Out-Null }
    if ($metricParts.Count -gt 0) { $summaryParts.Add("Metrics: $(($metricParts -join ', ')).") | Out-Null }
    $summaryParts.Add('Captured via xiaohongshu-extractor / xiaohongshu.') | Out-Null
    $summary = (($summaryParts | Where-Object { Test-HasValue $_ }) -join ' ').Trim()

    $tags = @('clipped', 'social', 'xiaohongshu')
    $images = @()
    if (Test-HasValue $coverUrl) { $images += $coverUrl }
    $videos = @()
    if (Test-HasValue $canonicalVideoUrl) { $videos += $canonicalVideoUrl } else { $videos += $SourceUrl }

    $metadata = [ordered]@{
        capture_level = if (Test-HasValue $description) { 'standard' } else { 'light' }
        transcript_status = 'missing'
        media_downloaded = $false
        analysis_ready = $true
        extractor = 'xiaohongshu-extractor'
        route = 'social'
        platform = 'xiaohongshu'
        content_type = 'social_post'
        source_url = $SourceUrl
        normalized_url = $normalizedUrl
        source_item_id = $sourceItemId
        capture_key = $captureKey
        capture_id = $captureId
        metrics_source = 'xiaohongshu_extractor'
        comments_source = 'none'
        comments_capture_status = 'none'
        comment_count_visible = 0
        like_count = $likeCount
        comment_count = $commentCount
        collect_count = $collectCount
        share_count = $shareCount
    }

    $extraProperties = [ordered]@{
        source_url = $SourceUrl
        normalized_url = $normalizedUrl
        platform = 'xiaohongshu'
        content_type = 'social_post'
        route = 'social'
        source_item_id = $sourceItemId
        capture_key = $captureKey
        capture_id = $captureId
        description = $description
        canonical_video_url = $canonicalVideoUrl
        cover_url = $coverUrl
        candidate_video_refs = @($mediaCandidates)
        comments = @()
        top_comments = @()
        comments_count = 0
        comments_capture_status = 'none'
        metrics_like = $likeCount
        metrics_comment = $commentCount
        metrics_collect = $collectCount
        metrics_share = $shareCount
        auth_applied = $false
        auth_mode = 'extractor'
        status = 'clipped'
        download_status = 'skipped'
        download_method = 'none'
        media_downloaded = $false
        analyzer_status = 'pending'
        bitable_sync_status = 'pending'
    }

    return (New-CaptureObject -Title $title -Author $author -PublishedAt $publishedAt -Summary $summary -RawText $description -Transcript '' -Tags $tags -Images $images -Videos $videos -Metadata $metadata -ExtraProperties $extraProperties)
}

function Merge-XiaohongshuSupplementalCapture {
    param($BaseCapture, $SupplementalCapture)
    if ($null -eq $BaseCapture) { return $SupplementalCapture }
    if ($null -eq $SupplementalCapture) { return $BaseCapture }

    $baseMetadata = Get-DataValue -Data $BaseCapture -Name 'metadata'
    if ($null -eq $baseMetadata) {
        $baseMetadata = [ordered]@{}
        Set-ObjectField -Object $BaseCapture -Name 'metadata' -Value $baseMetadata | Out-Null
    }

    foreach ($field in @('normalized_url', 'final_url', 'published_at', 'source_item_id', 'capture_key', 'capture_id', 'cover_url')) {
        $baseValue = Get-StringValue -Data $BaseCapture -Name $field -DefaultValue ''
        $supplementalValue = Get-StringValue -Data $SupplementalCapture -Name $field -DefaultValue ''
        if (-not (Test-HasValue $baseValue) -and (Test-HasValue $supplementalValue)) {
            Set-ObjectField -Object $BaseCapture -Name $field -Value $supplementalValue | Out-Null
        }
    }

    $baseRawText = Get-StringValue -Data $BaseCapture -Name 'raw_text' -DefaultValue ''
    $supplementalRawText = Get-StringValue -Data $SupplementalCapture -Name 'raw_text' -DefaultValue ''
    if ((-not (Test-HasValue $baseRawText) -or $supplementalRawText.Length -gt $baseRawText.Length) -and (Test-HasValue $supplementalRawText)) {
        Set-ObjectField -Object $BaseCapture -Name 'raw_text' -Value $supplementalRawText | Out-Null
    }

    $baseSummary = Get-StringValue -Data $BaseCapture -Name 'summary' -DefaultValue ''
    $supplementalSummary = Get-StringValue -Data $SupplementalCapture -Name 'summary' -DefaultValue ''
    if ((-not (Test-HasValue $baseSummary) -or $supplementalSummary.Length -gt $baseSummary.Length) -and (Test-HasValue $supplementalSummary)) {
        Set-ObjectField -Object $BaseCapture -Name 'summary' -Value $supplementalSummary | Out-Null
    }

    $baseDescription = Get-StringValue -Data $BaseCapture -Name 'description' -DefaultValue ''
    $supplementalDescription = Get-StringValue -Data $SupplementalCapture -Name 'description' -DefaultValue ''
    if (-not (Test-HasValue $baseDescription) -and (Test-HasValue $supplementalDescription)) {
        Set-ObjectField -Object $BaseCapture -Name 'description' -Value $supplementalDescription | Out-Null
    }

    foreach ($field in @('tags', 'images', 'videos', 'candidate_video_refs', 'top_comments')) {
        $mergedValues = Get-StringArrayValue -Data $BaseCapture -Name $field
        foreach ($value in (Get-StringArrayValue -Data $SupplementalCapture -Name $field)) {
            $mergedValues = Add-UniqueStringToArray -Items $mergedValues -Value $value
        }
        Set-ObjectField -Object $BaseCapture -Name $field -Value $mergedValues | Out-Null
    }

    $supplementalComments = Get-DataValue -Data $SupplementalCapture -Name 'comments'
    if ($null -ne $supplementalComments -and @($supplementalComments).Count -gt 0) {
        Set-ObjectField -Object $BaseCapture -Name 'comments' -Value $supplementalComments | Out-Null
    }

    $commentsCount = Get-DataValue -Data $SupplementalCapture -Name 'comments_count'
    if ($null -ne $commentsCount) {
        Set-ObjectField -Object $BaseCapture -Name 'comments_count' -Value $commentsCount | Out-Null
        Set-ObjectField -Object $baseMetadata -Name 'comment_count_visible' -Value $commentsCount | Out-Null
    }

    $commentsCaptureStatus = Get-StringValue -Data $SupplementalCapture -Name 'comments_capture_status' -DefaultValue ''
    if (Test-HasValue $commentsCaptureStatus) {
        Set-ObjectField -Object $BaseCapture -Name 'comments_capture_status' -Value $commentsCaptureStatus | Out-Null
        Set-ObjectField -Object $baseMetadata -Name 'comments_capture_status' -Value $commentsCaptureStatus | Out-Null
        Set-ObjectField -Object $baseMetadata -Name 'comments_source' -Value 'playwright' | Out-Null
    }

    foreach ($field in @('auth_applied', 'auth_mode', 'auth_cookie_count', 'auth_session_state', 'auth_session_likely_valid', 'comments_login_required')) {
        $value = Get-DataValue -Data $SupplementalCapture -Name $field
        if ($null -ne $value) {
            Set-ObjectField -Object $BaseCapture -Name $field -Value $value | Out-Null
            Set-ObjectField -Object $baseMetadata -Name $field -Value $value | Out-Null
        }
    }

    Set-ObjectField -Object $baseMetadata -Name 'playwright_supplement_applied' -Value $true | Out-Null
    return $BaseCapture
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
    $cleaned = $cleaned.TrimStart([char]0xFEFF, [char]0x200B, [char]0x00EF, [char]0x00BB, [char]0x00BF)
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

function Get-SocialPlatformAuthConfig {
    param($Config, [string]$Platform)
    if ($null -eq $Config.routes -or $null -eq $Config.routes.social) { return $null }
    $authConfig = Get-DataValue -Data $Config.routes.social -Name 'auth'
    if ($null -eq $authConfig) { return $null }

    $platformConfig = Get-DataValue -Data $authConfig -Name $Platform
    if ($null -ne $platformConfig) { return $platformConfig }

    $defaultConfig = Get-DataValue -Data $authConfig -Name 'default'
    if ($null -ne $defaultConfig) { return $defaultConfig }

    $legacyStorageState = Get-DataValue -Data $authConfig -Name 'storage_state_path'
    $legacyCookiesFile = Get-DataValue -Data $authConfig -Name 'cookies_file'
    if ($null -ne $legacyStorageState -or $null -ne $legacyCookiesFile) { return $authConfig }

    $null
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
    $Url = Get-CanonicalShareUrl -Url $Url
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
        $modalId = Get-QueryParameterValue -Query $uri.Query -Name 'modal_id'
        if (Test-HasValue $modalId) {
            return "https://www.douyin.com/video/$modalId"
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
        [string]$JsonPath,
        [string]$DefaultDirectory
    )
    if (Test-HasValue $ExplicitDirectory) { return (New-Directory -Path $ExplicitDirectory) }
    if (Test-HasValue $JsonPath) {
        $parent = Split-Path -Parent $JsonPath
        if (Test-HasValue $parent) { return (New-Directory -Path $parent) }
    }
    if (Test-HasValue $DefaultDirectory) { return (New-Directory -Path $DefaultDirectory) }
    ''
}
function Resolve-AbsoluteUrl {
    param([string]$BaseUrl, [string]$Candidate)
    if (-not (Test-HasValue $Candidate)) { return '' }
    try { return [System.Uri]::new([System.Uri]$BaseUrl, $Candidate).AbsoluteUri } catch { return $Candidate }
}

function Get-NormalizedContentUrl {
    param([string]$Url)
    if (-not (Test-HasValue $Url)) { return '' }
    try {
        $builder = [System.UriBuilder]::new([System.Uri]$Url)
        $builder.Query = ''
        $builder.Fragment = ''
        $normalized = $builder.Uri.AbsoluteUri
        if ($normalized.EndsWith('/')) { return $normalized.TrimEnd('/') }
        return $normalized
    } catch {
        return $Url
    }
}

function Get-Sha256Hex {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
        return (-join ($hash | ForEach-Object { $_.ToString('x2') }))
    } finally {
        $sha256.Dispose()
    }
}

function Get-XiaoyuzhouEpisodeIdFromUrl {
    param([string]$Url)
    if (-not (Test-HasValue $Url)) { return '' }
    try {
        $uri = [System.Uri]$Url
        $episodeMatch = [regex]::Match($uri.AbsolutePath, '/episode/(?<id>[A-Za-z0-9]+)')
        if ($episodeMatch.Success) { return $episodeMatch.Groups['id'].Value }
        foreach ($queryKey in @('eid', 'episodeId', 'episode_id', 'id')) {
            $queryValue = Get-QueryParameterValue -Query $uri.Query -Name $queryKey
            if (Test-HasValue $queryValue) { return $queryValue }
        }
    } catch {
    }
    ''
}

function New-PodcastIdentity {
    param(
        [string]$Url,
        [string]$Platform = 'podcast',
        [string]$SourceItemId = ''
    )
    $normalizedUrl = Get-NormalizedContentUrl -Url $Url
    $resolvedSourceItemId = if (Test-HasValue $SourceItemId) { $SourceItemId } elseif ($Platform -eq 'xiaoyuzhou') { Get-XiaoyuzhouEpisodeIdFromUrl -Url $normalizedUrl } else { '' }
    $captureKey = if (Test-HasValue $resolvedSourceItemId) { "${Platform}:$resolvedSourceItemId" } else { "${Platform}:$normalizedUrl" }
    $captureHash = Get-Sha256Hex -Text $captureKey
    [pscustomobject]@{
        normalized_url = $normalizedUrl
        source_item_id = $resolvedSourceItemId
        capture_key = $captureKey
        capture_id = if (Test-HasValue $captureHash) { "${Platform}_$($captureHash.Substring(0, 16))" } else { '' }
    }
}

function Get-ComparableTitle {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return '' }
    $normalized = [System.Net.WebUtility]::HtmlDecode([string]$Text)
    $normalized = $normalized -replace '\s+', ' '
    $normalized = $normalized -replace '\s+\|\s+.*$', ''
    $normalized = $normalized -replace '\s+-\s+.*$', ''
    $normalized.Trim().ToLowerInvariant()
}

function Get-XmlChildText {
    param($Node, [string]$LocalName)
    if ($null -eq $Node) { return '' }
    $selected = $Node.SelectSingleNode("./*[local-name()='$LocalName']")
    if ($null -ne $selected -and (Test-HasValue $selected.InnerText)) {
        return [System.Net.WebUtility]::HtmlDecode($selected.InnerText).Trim()
    }
    ''
}

function Get-XmlChildAttribute {
    param($Node, [string]$LocalName, [string]$AttributeName)
    if ($null -eq $Node) { return '' }
    $selected = $Node.SelectSingleNode("./*[local-name()='$LocalName']")
    if ($null -ne $selected -and $null -ne $selected.Attributes) {
        $attribute = $selected.Attributes[$AttributeName]
        if ($null -ne $attribute -and (Test-HasValue $attribute.Value)) { return $attribute.Value.Trim() }
    }
    ''
}

function Convert-PodcastDurationToSeconds {
    param([string]$DurationText)
    if (-not (Test-HasValue $DurationText)) { return 0 }
    $trimmed = $DurationText.Trim()
    if ($trimmed -match '^\d+$') { return [int]$trimmed }
    $parts = @($trimmed -split ':')
    if ($parts.Count -eq 2) {
        return ([int]$parts[0] * 60) + [int]$parts[1]
    }
    if ($parts.Count -eq 3) {
        return ([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2]
    }
    0
}

function Get-PodcastTranscriptUrlFromRssNode {
    param($Node, [string]$BaseUrl)
    if ($null -eq $Node) { return '' }
    $transcriptNodes = $Node.SelectNodes("./*[local-name()='transcript']")
    foreach ($transcriptNode in @($transcriptNodes)) {
        if ($null -eq $transcriptNode) { continue }
        if ($null -ne $transcriptNode.Attributes) {
            foreach ($attributeName in @('url', 'href')) {
                $attribute = $transcriptNode.Attributes[$attributeName]
                if ($null -ne $attribute -and (Test-HasValue $attribute.Value)) {
                    return (Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate $attribute.Value)
                }
            }
        }
        if (Test-HasValue $transcriptNode.InnerText) {
            return (Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate $transcriptNode.InnerText.Trim())
        }
    }
    ''
}

function Find-PodcastRssItem {
    param(
        $XmlDocument,
        [string]$BaseUrl,
        [string]$SourceItemId,
        [string]$NormalizedEpisodeUrl,
        [string[]]$TitleCandidates
    )
    if ($null -eq $XmlDocument) { return $null }
    $items = $XmlDocument.SelectNodes("//*[local-name()='item']")
    $cleanTitleCandidates = @($TitleCandidates | Where-Object { Test-HasValue $_ } | ForEach-Object { Get-ComparableTitle -Text $_ } | Where-Object { Test-HasValue $_ })
    foreach ($item in @($items)) {
        $itemLink = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Candidate (Get-XmlChildText -Node $item -LocalName 'link')
        $itemGuid = Get-XmlChildText -Node $item -LocalName 'guid'
        $itemTitle = Get-XmlChildText -Node $item -LocalName 'title'
        $comparableItemTitle = Get-ComparableTitle -Text $itemTitle

        if (Test-HasValue $SourceItemId) {
            foreach ($candidate in @($itemLink, $itemGuid)) {
                if ((Test-HasValue $candidate) -and ($candidate -match [regex]::Escape($SourceItemId))) {
                    return [pscustomobject]@{ item = $item; match_strategy = 'source_item_id' }
                }
            }
        }

        if (Test-HasValue $NormalizedEpisodeUrl) {
            foreach ($candidate in @($itemLink, $itemGuid)) {
                if ((Test-HasValue $candidate) -and ((Get-NormalizedContentUrl -Url $candidate) -eq $NormalizedEpisodeUrl)) {
                    return [pscustomobject]@{ item = $item; match_strategy = 'normalized_url' }
                }
            }
        }

        foreach ($titleCandidate in $cleanTitleCandidates) {
            if ((Test-HasValue $titleCandidate) -and (Test-HasValue $comparableItemTitle)) {
                if ($titleCandidate -eq $comparableItemTitle -or $titleCandidate.Contains($comparableItemTitle) -or $comparableItemTitle.Contains($titleCandidate)) {
                    return [pscustomobject]@{ item = $item; match_strategy = 'title' }
                }
            }
        }
    }
    $null
}

function Get-PodcastRssMetadata {
    param(
        [string]$RssUrl,
        [string]$NormalizedEpisodeUrl,
        [string]$SourceItemId,
        [string[]]$TitleCandidates
    )
    if (-not (Test-HasValue $RssUrl)) { return $null }
    try {
        $response = Invoke-WebRequest -Uri $RssUrl -UseBasicParsing
        $rssContent = [string]$response.Content
        if (-not (Test-HasValue $rssContent)) { throw 'RSS feed returned empty content.' }
        $rssContent = $rssContent.TrimStart([char]0xFEFF, [char]0x200B, [char]0x00EF, [char]0x00BB, [char]0x00BF)
        $xml = New-Object System.Xml.XmlDocument
        $xml.LoadXml($rssContent)
        $channel = $xml.SelectSingleNode("//*[local-name()='channel']")
        $match = Find-PodcastRssItem -XmlDocument $xml -BaseUrl $RssUrl -SourceItemId $SourceItemId -NormalizedEpisodeUrl $NormalizedEpisodeUrl -TitleCandidates $TitleCandidates
        $item = if ($null -ne $match) { $match.item } else { $null }
        $itemTitle = if ($null -ne $item) { Get-XmlChildText -Node $item -LocalName 'title' } else { '' }
        $itemLink = if ($null -ne $item) { Resolve-AbsoluteUrl -BaseUrl $RssUrl -Candidate (Get-XmlChildText -Node $item -LocalName 'link') } else { '' }
        $description = if ($null -ne $item) { Get-XmlChildText -Node $item -LocalName 'description' } else { '' }
        $durationText = if ($null -ne $item) { Get-XmlChildText -Node $item -LocalName 'duration' } else { '' }
        $channelImage = if ($null -ne $channel) { Get-XmlChildText -Node ($channel.SelectSingleNode("./*[local-name()='image']")) -LocalName 'url' } else { '' }
        $itunesImage = if ($null -ne $channel) { Get-XmlChildAttribute -Node $channel -LocalName 'image' -AttributeName 'href' } else { '' }
        [pscustomobject]@{
            rss_url = $RssUrl
            fetch_error = ''
            item_found = ($null -ne $item)
            match_strategy = if ($null -ne $match) { [string]$match.match_strategy } else { '' }
            podcast_title = if ($null -ne $channel) { Get-XmlChildText -Node $channel -LocalName 'title' } else { '' }
            podcast_author = if ($null -ne $channel) { Get-XmlChildText -Node $channel -LocalName 'author' } else { '' }
            podcast_image = if (Test-HasValue $itunesImage) { $itunesImage } else { $channelImage }
            episode_title = $itemTitle
            episode_link = $itemLink
            episode_guid = if ($null -ne $item) { Get-XmlChildText -Node $item -LocalName 'guid' } else { '' }
            published_at = if ($null -ne $item) { Get-XmlChildText -Node $item -LocalName 'pubDate' } else { '' }
            description = $description
            duration_text = $durationText
            duration_seconds = Convert-PodcastDurationToSeconds -DurationText $durationText
            enclosure_url = if ($null -ne $item) { Resolve-AbsoluteUrl -BaseUrl $RssUrl -Candidate (Get-XmlChildAttribute -Node $item -LocalName 'enclosure' -AttributeName 'url') } else { '' }
            transcript_url = if ($null -ne $item) { Get-PodcastTranscriptUrlFromRssNode -Node $item -BaseUrl $RssUrl } else { '' }
        }
    } catch {
        [pscustomobject]@{
            rss_url = $RssUrl
            fetch_error = $_.Exception.Message
            item_found = $false
            match_strategy = ''
            podcast_title = ''
            podcast_author = ''
            podcast_image = ''
            episode_title = ''
            episode_link = ''
            episode_guid = ''
            published_at = ''
            description = ''
            duration_text = ''
            duration_seconds = 0
            enclosure_url = ''
            transcript_url = ''
        }
    }
}

function Get-VaultRelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )
    if (-not (Test-HasValue $BasePath) -or -not (Test-HasValue $TargetPath)) { return '' }
    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')) + '\')
    $targetUri = [System.Uri]([System.IO.Path]::GetFullPath($TargetPath))
    [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/')
}

function Resolve-PathFromVault {
    param(
        [string]$VaultPath,
        [string]$RelativeOrAbsolutePath
    )
    if (-not (Test-HasValue $RelativeOrAbsolutePath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($RelativeOrAbsolutePath)) { return $RelativeOrAbsolutePath }
    if (-not (Test-HasValue $VaultPath)) { return $RelativeOrAbsolutePath }
    $parts = ($RelativeOrAbsolutePath -replace '\\', '/') -split '/'
    Join-Path $VaultPath ($parts -join '\')
}

function Get-UrlFileExtension {
    param(
        [string]$Url,
        [string]$DefaultExtension = '.mp3'
    )
    if (-not (Test-HasValue $Url)) { return $DefaultExtension }
    try {
        $path = ([System.Uri]$Url).AbsolutePath
        $extension = [System.IO.Path]::GetExtension($path)
        if (Test-HasValue $extension) { return $extension.ToLowerInvariant() }
    } catch {
    }
    $DefaultExtension
}

function Download-PodcastAudio {
    param(
        [string]$AudioUrl,
        [string]$TargetDirectory,
        [int]$TimeoutSec = 60
    )
    if (-not (Test-HasValue $AudioUrl) -or -not (Test-HasValue $TargetDirectory)) {
        return [pscustomobject]@{ success = $false; status = 'skipped'; file_path = ''; error = '' }
    }

    $extension = Get-UrlFileExtension -Url $AudioUrl -DefaultExtension '.mp3'
    $targetPath = Join-Path $TargetDirectory ("episode$extension")
    try {
        Invoke-WebRequest -Uri $AudioUrl -OutFile $targetPath -UseBasicParsing -TimeoutSec $TimeoutSec
        if (-not (Test-Path $targetPath)) {
            throw 'Audio download completed without a landed file.'
        }
        return [pscustomobject]@{
            success = $true
            status = 'success'
            file_path = $targetPath
            error = ''
        }
    } catch {
        if (Test-Path $targetPath) {
            Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{
            success = $false
            status = 'failed'
            file_path = ''
            error = $_.Exception.Message
        }
    }
}

function Invoke-PodcastAsrFallback {
    param(
        $Config,
        [string]$AudioPath,
        [string]$AssetDirectory
    )

    $result = [ordered]@{
        enabled = $false
        attempted = $false
        success = $false
        status = 'disabled'
        provider = ''
        model = ''
        language = ''
        normalization = 'none'
        transcript = ''
        transcript_raw = ''
        segments = @()
        error = ''
    }

    $podcastRoute = if ($null -ne $Config.routes) { Get-DataValue -Data $Config.routes -Name 'podcast' } else { $null }
    $asrConfig = if ($null -ne $podcastRoute) { Get-DataValue -Data $podcastRoute -Name 'asr' } else { $null }
    if ($null -eq $asrConfig) { return [pscustomobject]$result }

    $enabled = Get-BoolValueFromData -Data $asrConfig -Name 'enabled' -DefaultValue $false
    $result.enabled = $enabled
    $provider = Get-StringValue -Data $asrConfig -Name 'provider' -DefaultValue 'faster-whisper'
    $model = Get-StringValue -Data $asrConfig -Name 'model' -DefaultValue 'base'
    $language = Get-StringValue -Data $asrConfig -Name 'language' -DefaultValue 'zh'
    $result.provider = $provider
    $result.model = $model
    $result.language = $language
    if (-not $enabled) { return [pscustomobject]$result }

    if (-not (Test-HasValue $AudioPath) -or -not (Test-Path $AudioPath)) {
        $result.status = 'missing_audio'
        $result.error = 'ASR fallback could not start because no local audio file was available.'
        return [pscustomobject]$result
    }

    $command = Get-ConfiguredPathValue -Object $asrConfig -PropertyName 'command'
    if (-not (Test-HasValue $command)) { $command = 'python' }
    $scriptPath = Get-ConfiguredPathValue -Object $asrConfig -PropertyName 'script'
    if (($command -match 'python(?:\.exe)?$') -and -not (Test-HasValue $scriptPath)) {
        $result.status = 'not_configured'
        $result.error = 'Podcast ASR is enabled, but routes.podcast.asr.script is not configured.'
        return [pscustomobject]$result
    }

    $timeoutSec = 600
    $timeoutValue = Get-StringValue -Data $asrConfig -Name 'timeout_sec' -DefaultValue '600'
    if (Test-HasValue $timeoutValue) { $timeoutSec = [int]$timeoutValue }
    $device = Get-StringValue -Data $asrConfig -Name 'device' -DefaultValue 'auto'
    $computeType = Get-StringValue -Data $asrConfig -Name 'compute_type' -DefaultValue 'auto'
    $beamSize = Get-StringValue -Data $asrConfig -Name 'beam_size' -DefaultValue '5'
    $vadFilter = Get-BoolValueFromData -Data $asrConfig -Name 'vad_filter' -DefaultValue $true
    $normalizeScript = Get-StringValue -Data $asrConfig -Name 'normalize_script' -DefaultValue 'simplified'
    $mockTranscriptPath = Get-ConfiguredPathValue -Object $asrConfig -PropertyName 'mock_transcript_path'

    $outputJsonPath = Join-Path $AssetDirectory 'asr-output.json'
    $arguments = @()
    if (Test-HasValue $scriptPath) { $arguments += @($scriptPath) }
    $arguments += @('--audio-path', $AudioPath, '--output-json', $outputJsonPath, '--provider', $provider, '--model', $model, '--language', $language, '--device', $device, '--compute-type', $computeType, '--beam-size', $beamSize, '--vad-filter', $(if ($vadFilter) { 'true' } else { 'false' }), '--normalize-script', $normalizeScript)
    if (Test-HasValue $mockTranscriptPath) { $arguments += @('--mock-transcript-path', $mockTranscriptPath) }

    try {
        $result.attempted = $true
        $commandOutput = & $command @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $payload = $null
        if (Test-Path $outputJsonPath) {
            try {
                $payload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $outputJsonPath) -Depth 50
            } catch {
                $payload = $null
            }
        }

        if ($null -ne $payload) {
            $result.provider = Get-StringValue -Data $payload -Name 'provider' -DefaultValue $provider
            $result.model = Get-StringValue -Data $payload -Name 'model' -DefaultValue $model
            $result.language = Get-StringValue -Data $payload -Name 'language' -DefaultValue $language
            $result.normalization = Get-StringValue -Data $payload -Name 'normalization' -DefaultValue 'none'
            $result.transcript_raw = Get-StringValue -Data $payload -Name 'transcript_raw' -DefaultValue ''
            $result.transcript = Get-StringValue -Data $payload -Name 'transcript' -DefaultValue ''
            $segments = Get-DataValue -Data $payload -Name 'segments'
            if ($null -ne $segments) { $result.segments = @($segments) }
            $result.error = Get-StringValue -Data $payload -Name 'error' -DefaultValue ''
        }

        if ($exitCode -eq 0 -and (Test-HasValue $result.transcript)) {
            $result.success = $true
            $result.status = 'success'
            return [pscustomobject]$result
        }

        $result.status = 'failed'
        if (-not (Test-HasValue $result.error)) {
            $trimmedOutput = ($commandOutput | Out-String).Trim()
            if (Test-HasValue $trimmedOutput) {
                $result.error = $trimmedOutput
            } else {
                $result.error = "ASR command exited with code $exitCode."
            }
        }
        [pscustomobject]$result
    } catch {
        $result.status = 'failed'
        $result.error = $_.Exception.Message
        [pscustomobject]$result
    }
}

function Invoke-PodcastSpeakerDiarization {
    param(
        $Config,
        [string]$AudioPath,
        [string]$SegmentsJsonPath,
        [string]$AssetDirectory,
        [string]$ManualSpeakersPath
    )

    $result = [ordered]@{
        enabled = $false
        attempted = $false
        success = $false
        status = 'disabled'
        provider = ''
        model = ''
        segments = @()
        speaker_map = @()
        speaker_transcript = ''
        error = ''
    }

    $podcastRoute = if ($null -ne $Config.routes) { Get-DataValue -Data $Config.routes -Name 'podcast' } else { $null }
    $diarizationConfig = if ($null -ne $podcastRoute) { Get-DataValue -Data $podcastRoute -Name 'diarization' } else { $null }
    if ($null -eq $diarizationConfig) { return [pscustomobject]$result }

    $enabled = Get-BoolValueFromData -Data $diarizationConfig -Name 'enabled' -DefaultValue $false
    $result.enabled = $enabled
    $provider = Get-StringValue -Data $diarizationConfig -Name 'provider' -DefaultValue 'pyannote'
    $model = Get-StringValue -Data $diarizationConfig -Name 'model' -DefaultValue ''
    $result.provider = $provider
    $result.model = $model
    if (-not $enabled) { return [pscustomobject]$result }

    if (-not (Test-HasValue $AudioPath) -or -not (Test-Path $AudioPath)) {
        $result.status = 'missing_audio'
        $result.error = 'Speaker diarization could not start because no local audio file was available.'
        return [pscustomobject]$result
    }
    if (-not (Test-HasValue $SegmentsJsonPath) -or -not (Test-Path $SegmentsJsonPath)) {
        $result.status = 'missing_segments'
        $result.error = 'Speaker diarization could not start because transcript segments were not available.'
        return [pscustomobject]$result
    }

    $command = Get-ConfiguredPathValue -Object $diarizationConfig -PropertyName 'command'
    if (-not (Test-HasValue $command)) { $command = 'python' }
    $scriptPath = Get-ConfiguredPathValue -Object $diarizationConfig -PropertyName 'script'
    if (($command -match 'python(?:\.exe)?$') -and -not (Test-HasValue $scriptPath)) {
        $result.status = 'not_configured'
        $result.error = 'Podcast diarization is enabled, but routes.podcast.diarization.script is not configured.'
        return [pscustomobject]$result
    }

    $device = Get-StringValue -Data $diarizationConfig -Name 'device' -DefaultValue 'cpu'
    $hfTokenEnv = Get-StringValue -Data $diarizationConfig -Name 'hf_token_env' -DefaultValue 'HF_TOKEN'
    $mockDiarizationPath = Get-ConfiguredPathValue -Object $diarizationConfig -PropertyName 'mock_diarization_path'
    $minOverlapRatio = Get-StringValue -Data $diarizationConfig -Name 'min_overlap_ratio' -DefaultValue '0.35'
    $outputJsonPath = Join-Path $AssetDirectory 'speaker-diarization-output.json'
    $arguments = @()
    if (Test-HasValue $scriptPath) { $arguments += @($scriptPath) }
    $arguments += @(
        '--audio-path', $AudioPath,
        '--segments-json', $SegmentsJsonPath,
        '--output-json', $outputJsonPath,
        '--provider', $provider,
        '--device', $device,
        '--hf-token-env', $hfTokenEnv,
        '--min-overlap-ratio', $minOverlapRatio
    )
    if (Test-HasValue $model) { $arguments += @('--model', $model) }
    if (Test-HasValue $mockDiarizationPath) { $arguments += @('--mock-diarization-path', $mockDiarizationPath) }
    if (Test-HasValue $ManualSpeakersPath) { $arguments += @('--manual-speakers-path', $ManualSpeakersPath) }

    try {
        $result.attempted = $true
        $commandOutput = & $command @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $payload = $null
        if (Test-Path $outputJsonPath) {
            try {
                $payload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $outputJsonPath) -Depth 100
            } catch {
                $payload = $null
            }
        }

        if ($null -ne $payload) {
            $result.provider = Get-StringValue -Data $payload -Name 'provider' -DefaultValue $provider
            $result.model = Get-StringValue -Data $payload -Name 'model' -DefaultValue $model
            $result.status = Get-StringValue -Data $payload -Name 'status' -DefaultValue 'failed'
            $result.error = Get-StringValue -Data $payload -Name 'error' -DefaultValue ''
            $segments = Get-DataValue -Data $payload -Name 'segments'
            if ($null -ne $segments) { $result.segments = @($segments) }
            $speakerMap = Get-DataValue -Data $payload -Name 'speaker_map'
            if ($null -ne $speakerMap) { $result.speaker_map = @($speakerMap) }
            $result.speaker_transcript = Get-StringValue -Data $payload -Name 'speaker_transcript' -DefaultValue ''
        }

        if ($exitCode -eq 0 -and @($result.speaker_map).Count -gt 0) {
            $result.success = $true
            if (-not (Test-HasValue $result.status)) { $result.status = 'success' }
            return [pscustomobject]$result
        }

        if (-not (Test-HasValue $result.status)) { $result.status = 'failed' }
        if (-not (Test-HasValue $result.error)) {
            $trimmedOutput = ($commandOutput | Out-String).Trim()
            if (Test-HasValue $trimmedOutput) {
                $result.error = $trimmedOutput
            } else {
                $result.error = "Speaker diarization command exited with code $exitCode."
            }
        }
        return [pscustomobject]$result
    } catch {
        $result.status = 'failed'
        $result.error = $_.Exception.Message
        return [pscustomobject]$result
    }
}

function Save-PodcastArtifacts {
    param(
        $Config,
        $Capture,
        [string]$ResolvedVaultPath
    )
    if (-not (Test-HasValue $ResolvedVaultPath) -or $null -eq $Capture) { return $Capture }
    $captureId = Get-StringValue -Data $Capture -Name 'capture_id' -DefaultValue ''
    $metadata = Get-DataValue -Data $Capture -Name 'metadata'
    if (-not (Test-HasValue $captureId) -and $null -ne $metadata) { $captureId = Get-StringValue -Data $metadata -Name 'capture_id' -DefaultValue '' }
    if (-not (Test-HasValue $captureId)) { return $Capture }

    $attachmentsRoot = if ($null -ne $Config.clipper -and $null -ne $Config.clipper.PSObject.Properties['podcast_attachments_root'] -and (Test-HasValue ([string]$Config.clipper.podcast_attachments_root))) {
        [string]$Config.clipper.podcast_attachments_root
    } else {
        'Attachments/Podcasts'
    }
    $platform = Get-StringValue -Data $Capture -Name 'podcast_platform' -DefaultValue ''
    if (-not (Test-HasValue $platform)) { $platform = Get-StringValue -Data $Capture -Name 'platform' -DefaultValue 'podcast' }

    $assetDirectory = Join-Path (Join-Path (Join-Path $ResolvedVaultPath $attachmentsRoot) $platform) $captureId
    New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null

    $audioUrl = Get-StringValue -Data $Capture -Name 'enclosure_url' -DefaultValue ''
    if (-not (Test-HasValue $audioUrl) -and $null -ne $metadata) { $audioUrl = Get-StringValue -Data $metadata -Name 'enclosure_url' -DefaultValue '' }
    $podcastRoute = if ($null -ne $Config.routes) { Get-DataValue -Data $Config.routes -Name 'podcast' } else { $null }
    $downloadAudio = $true
    if ($null -ne $podcastRoute) {
        $downloadAudio = Get-BoolValueFromData -Data $podcastRoute -Name 'download_audio' -DefaultValue $true
    }
    $downloadTimeoutSec = 60
    if ($null -ne $podcastRoute -and $null -ne $podcastRoute.PSObject.Properties['download_timeout_sec'] -and (Test-HasValue ([string]$podcastRoute.download_timeout_sec))) {
        $downloadTimeoutSec = [int]$podcastRoute.download_timeout_sec
    }
    $audioDownloadStatus = if ($downloadAudio -and (Test-HasValue $audioUrl)) { 'pending' } elseif (Test-HasValue $audioUrl) { 'skipped' } else { 'missing' }
    $audioPath = ''
    $audioLocalPath = ''
    if ($downloadAudio -and (Test-HasValue $audioUrl)) {
        $audioDownloadResult = Download-PodcastAudio -AudioUrl $audioUrl -TargetDirectory $assetDirectory -TimeoutSec $downloadTimeoutSec
        $audioDownloadStatus = [string]$audioDownloadResult.status
        if ($audioDownloadResult.success) {
            $audioLocalPath = [string]$audioDownloadResult.file_path
            $audioPath = Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $audioDownloadResult.file_path
        } elseif ($null -ne $metadata) {
            Set-ObjectField -Object $metadata -Name 'audio_download_error' -Value ([string]$audioDownloadResult.error) | Out-Null
        }
    }

    $capturePath = Join-Path $assetDirectory 'capture.json'
    $metadataPath = Join-Path $assetDirectory 'metadata.json'

    $transcript = Get-StringValue -Data $Capture -Name 'transcript' -DefaultValue ''
    $transcriptStatus = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'transcript_status' -DefaultValue $(if (Test-HasValue $transcript) { 'available' } else { 'missing' }) } else { if (Test-HasValue $transcript) { 'available' } else { 'missing' } }
    $transcriptSource = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'transcript_source' -DefaultValue $(if (Test-HasValue $transcript) { 'remote' } else { 'missing' }) } else { if (Test-HasValue $transcript) { 'remote' } else { 'missing' } }
    $asrStatus = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'asr_status' -DefaultValue $(if (Test-HasValue $transcript) { 'not_needed' } else { 'not_attempted' }) } else { if (Test-HasValue $transcript) { 'not_needed' } else { 'not_attempted' } }
    $asrProvider = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'asr_provider' -DefaultValue '' } else { '' }
    $asrModel = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'asr_model' -DefaultValue '' } else { '' }
    $asrNormalization = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'asr_normalization' -DefaultValue 'none' } else { 'none' }
    $asrError = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'asr_error' -DefaultValue '' } else { '' }
    $transcriptRaw = ''
    $transcriptSegments = @()
    if (-not (Test-HasValue $audioLocalPath) -and (Test-HasValue $audioPath)) {
        $audioCandidatePath = Join-Path $ResolvedVaultPath ($audioPath -replace '/', '\')
        if (Test-Path $audioCandidatePath) { $audioLocalPath = $audioCandidatePath }
    }
    if (-not (Test-HasValue $transcript)) {
        $asrResult = Invoke-PodcastAsrFallback -Config $Config -AudioPath $audioLocalPath -AssetDirectory $assetDirectory
        $asrStatus = [string]$asrResult.status
        $asrProvider = [string]$asrResult.provider
        $asrModel = [string]$asrResult.model
        $asrNormalization = [string]$asrResult.normalization
        $asrError = [string]$asrResult.error
        if ($asrResult.success -and (Test-HasValue $asrResult.transcript)) {
            $transcript = [string]$asrResult.transcript
            $transcriptRaw = [string]$asrResult.transcript_raw
            $transcriptSegments = @($asrResult.segments)
            $transcriptStatus = 'available_asr'
            $transcriptSource = 'asr_fallback'
            if ($null -ne $metadata) {
                $currentCaptureLevel = Get-StringValue -Data $metadata -Name 'capture_level' -DefaultValue 'light'
                if ($currentCaptureLevel -ne 'enhanced') {
                    Set-ObjectField -Object $metadata -Name 'capture_level' -Value 'enhanced' | Out-Null
                }
            }
        } elseif ($transcriptSource -eq 'remote') {
            $transcriptSource = 'missing'
        }
    }
    $transcriptRawPath = ''
    $transcriptPath = ''
    $transcriptSegmentsPath = ''
    if (Test-HasValue $transcriptRaw) {
        $transcriptRawPath = Join-Path $assetDirectory 'transcript.raw.txt'
        Write-Utf8Text -Path $transcriptRawPath -Content $transcriptRaw
    }
    if (Test-HasValue $transcript) {
        $transcriptPath = Join-Path $assetDirectory 'transcript.txt'
        Write-Utf8Text -Path $transcriptPath -Content $transcript
    }
    if (@($transcriptSegments).Count -gt 0) {
        $transcriptSegmentsPath = Join-Path $assetDirectory 'transcript.segments.json'
        Write-Utf8Text -Path $transcriptSegmentsPath -Content ((@($transcriptSegments) | ConvertTo-Json -Depth 20))
    }

    $diarizationStatus = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'diarization_status' -DefaultValue 'not_attempted' } else { 'not_attempted' }
    $diarizationProvider = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'diarization_provider' -DefaultValue '' } else { '' }
    $diarizationModel = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'diarization_model' -DefaultValue '' } else { '' }
    $diarizationError = if ($null -ne $metadata) { Get-StringValue -Data $metadata -Name 'diarization_error' -DefaultValue '' } else { '' }
    $speakerMap = @()
    $speakerAnnotatedTranscript = ''
    $speakersPath = Join-Path $assetDirectory 'speakers.json'
    $speakerAnnotatedTranscriptPath = ''

    if ((Test-HasValue $audioLocalPath) -and (Test-HasValue $transcriptSegmentsPath)) {
        $diarizationResult = Invoke-PodcastSpeakerDiarization -Config $Config -AudioPath $audioLocalPath -SegmentsJsonPath $transcriptSegmentsPath -AssetDirectory $assetDirectory -ManualSpeakersPath $speakersPath
        $diarizationStatus = [string]$diarizationResult.status
        $diarizationProvider = [string]$diarizationResult.provider
        $diarizationModel = [string]$diarizationResult.model
        $diarizationError = [string]$diarizationResult.error
        if ($diarizationResult.success -and @($diarizationResult.segments).Count -gt 0) {
            $transcriptSegments = @($diarizationResult.segments)
            $speakerMap = @($diarizationResult.speaker_map)
            $speakerAnnotatedTranscript = [string]$diarizationResult.speaker_transcript
            Write-Utf8Text -Path $transcriptSegmentsPath -Content ((@($transcriptSegments) | ConvertTo-Json -Depth 20))
            if (Test-HasValue $speakerAnnotatedTranscript) {
                $speakerAnnotatedTranscriptPath = Join-Path $assetDirectory 'transcript.speakers.txt'
                Write-Utf8Text -Path $speakerAnnotatedTranscriptPath -Content $speakerAnnotatedTranscript
            }
        }
    }

    $speakerManifest = [ordered]@{
        version = 'speaker-map-v1'
        diarization_status = $diarizationStatus
        diarization_provider = $diarizationProvider
        diarization_model = $diarizationModel
        generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        speaker_count = @($speakerMap).Count
        speaker_map = @($speakerMap)
    }
    Write-Utf8Text -Path $speakersPath -Content (($speakerManifest | ConvertTo-Json -Depth 20))

    $relativeCapturePath = Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $capturePath
    $relativeMetadataPath = Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $metadataPath
    $relativeTranscriptRawPath = if (Test-HasValue $transcriptRawPath) { Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $transcriptRawPath } else { '' }
    $relativeTranscriptPath = if (Test-HasValue $transcriptPath) { Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $transcriptPath } else { '' }
    $relativeTranscriptSegmentsPath = if (Test-HasValue $transcriptSegmentsPath) { Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $transcriptSegmentsPath } else { '' }
    $relativeSpeakersPath = if (Test-HasValue $speakersPath) { Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $speakersPath } else { '' }
    $relativeSpeakerAnnotatedTranscriptPath = if (Test-HasValue $speakerAnnotatedTranscriptPath) { Get-VaultRelativePath -BasePath $ResolvedVaultPath -TargetPath $speakerAnnotatedTranscriptPath } else { '' }

    Set-ObjectField -Object $Capture -Name 'sidecar_path' -Value $relativeCapturePath | Out-Null
    Set-ObjectField -Object $Capture -Name 'metadata_path' -Value $relativeMetadataPath | Out-Null
    Set-ObjectField -Object $Capture -Name 'audio_path' -Value $audioPath | Out-Null
    Set-ObjectField -Object $Capture -Name 'audio_download_status' -Value $audioDownloadStatus | Out-Null
    Set-ObjectField -Object $Capture -Name 'transcript' -Value $transcript | Out-Null
    Set-ObjectField -Object $Capture -Name 'transcript_status' -Value $transcriptStatus | Out-Null
    Set-ObjectField -Object $Capture -Name 'transcript_source' -Value $transcriptSource | Out-Null
    Set-ObjectField -Object $Capture -Name 'asr_status' -Value $asrStatus | Out-Null
    Set-ObjectField -Object $Capture -Name 'asr_provider' -Value $asrProvider | Out-Null
    Set-ObjectField -Object $Capture -Name 'asr_model' -Value $asrModel | Out-Null
    Set-ObjectField -Object $Capture -Name 'asr_normalization' -Value $asrNormalization | Out-Null
    Set-ObjectField -Object $Capture -Name 'asr_error' -Value $asrError | Out-Null
    Set-ObjectField -Object $Capture -Name 'diarization_status' -Value $diarizationStatus | Out-Null
    Set-ObjectField -Object $Capture -Name 'diarization_provider' -Value $diarizationProvider | Out-Null
    Set-ObjectField -Object $Capture -Name 'diarization_model' -Value $diarizationModel | Out-Null
    Set-ObjectField -Object $Capture -Name 'diarization_error' -Value $diarizationError | Out-Null
    Set-ObjectField -Object $Capture -Name 'speaker_count' -Value @($speakerMap).Count | Out-Null
    if (@($speakerMap).Count -gt 0) { Set-ObjectField -Object $Capture -Name 'speaker_map' -Value @($speakerMap) | Out-Null }
    if (Test-HasValue $transcriptRaw) { Set-ObjectField -Object $Capture -Name 'transcript_raw' -Value $transcriptRaw | Out-Null }
    if (@($transcriptSegments).Count -gt 0) { Set-ObjectField -Object $Capture -Name 'transcript_segments' -Value @($transcriptSegments) | Out-Null }
    if (Test-HasValue $relativeTranscriptRawPath) { Set-ObjectField -Object $Capture -Name 'transcript_raw_path' -Value $relativeTranscriptRawPath | Out-Null }
    if (Test-HasValue $relativeTranscriptPath) { Set-ObjectField -Object $Capture -Name 'transcript_path' -Value $relativeTranscriptPath | Out-Null }
    if (Test-HasValue $relativeTranscriptSegmentsPath) { Set-ObjectField -Object $Capture -Name 'transcript_segments_path' -Value $relativeTranscriptSegmentsPath | Out-Null }
    if (Test-HasValue $relativeSpeakersPath) { Set-ObjectField -Object $Capture -Name 'speakers_path' -Value $relativeSpeakersPath | Out-Null }
    if (Test-HasValue $relativeSpeakerAnnotatedTranscriptPath) { Set-ObjectField -Object $Capture -Name 'speaker_annotated_transcript_path' -Value $relativeSpeakerAnnotatedTranscriptPath | Out-Null }
    if ($null -ne $metadata) {
        Set-ObjectField -Object $metadata -Name 'sidecar_path' -Value $relativeCapturePath | Out-Null
        Set-ObjectField -Object $metadata -Name 'metadata_path' -Value $relativeMetadataPath | Out-Null
        Set-ObjectField -Object $metadata -Name 'audio_path' -Value $audioPath | Out-Null
        Set-ObjectField -Object $metadata -Name 'audio_download_status' -Value $audioDownloadStatus | Out-Null
        Set-ObjectField -Object $metadata -Name 'transcript_status' -Value $transcriptStatus | Out-Null
        Set-ObjectField -Object $metadata -Name 'transcript_source' -Value $transcriptSource | Out-Null
        Set-ObjectField -Object $metadata -Name 'asr_status' -Value $asrStatus | Out-Null
        Set-ObjectField -Object $metadata -Name 'asr_provider' -Value $asrProvider | Out-Null
        Set-ObjectField -Object $metadata -Name 'asr_model' -Value $asrModel | Out-Null
        Set-ObjectField -Object $metadata -Name 'asr_normalization' -Value $asrNormalization | Out-Null
        Set-ObjectField -Object $metadata -Name 'asr_error' -Value $asrError | Out-Null
        Set-ObjectField -Object $metadata -Name 'diarization_status' -Value $diarizationStatus | Out-Null
        Set-ObjectField -Object $metadata -Name 'diarization_provider' -Value $diarizationProvider | Out-Null
        Set-ObjectField -Object $metadata -Name 'diarization_model' -Value $diarizationModel | Out-Null
        Set-ObjectField -Object $metadata -Name 'diarization_error' -Value $diarizationError | Out-Null
        Set-ObjectField -Object $metadata -Name 'speaker_count' -Value @($speakerMap).Count | Out-Null
        if (@($speakerMap).Count -gt 0) { Set-ObjectField -Object $metadata -Name 'speaker_map' -Value @($speakerMap) | Out-Null }
        if (Test-HasValue $transcriptRaw) { Set-ObjectField -Object $metadata -Name 'transcript_raw_path' -Value $relativeTranscriptRawPath | Out-Null }
        if (Test-HasValue $relativeTranscriptPath) { Set-ObjectField -Object $metadata -Name 'transcript_path' -Value $relativeTranscriptPath | Out-Null }
        if (Test-HasValue $relativeTranscriptSegmentsPath) { Set-ObjectField -Object $metadata -Name 'transcript_segments_path' -Value $relativeTranscriptSegmentsPath | Out-Null }
        if (Test-HasValue $relativeSpeakersPath) { Set-ObjectField -Object $metadata -Name 'speakers_path' -Value $relativeSpeakersPath | Out-Null }
        if (Test-HasValue $relativeSpeakerAnnotatedTranscriptPath) { Set-ObjectField -Object $metadata -Name 'speaker_annotated_transcript_path' -Value $relativeSpeakerAnnotatedTranscriptPath | Out-Null }
    }

    Write-Utf8Text -Path $capturePath -Content ($Capture | ConvertTo-Json -Depth 100)
    if ($null -ne $metadata) {
        Write-Utf8Text -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 100)
    }
    return $Capture
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
    $authConfig = Get-SocialPlatformAuthConfig -Config $Config -Platform $Platform
    $storageStatePath = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'storage_state_path'
    $cookiesFile = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'cookies_file'
    $tempDir = New-LocalTempDirectory
    try {
        $outputJsonPath = Join-Path $tempDir 'social-capture.json'
        $obj = $null
        $extractorResult = $null
        $extractorSucceeded = $false
        if ($Platform -eq 'xiaohongshu') {
            $extractorResult = Invoke-XiaohongshuExtractor -Config $Config -SourceUrl $Url -NormalizedUrl '' -PythonCommand $pythonCommand -CookiesFile $cookiesFile -StorageStatePath $storageStatePath -TempDir $tempDir
            $extractorSucceeded = ($null -ne $extractorResult) -and [bool](Get-DataValue -Data $extractorResult -Name 'success')
            if ($extractorSucceeded) {
                $obj = New-XiaohongshuCaptureFromExtractor -SourceUrl $Url -ExtractorResult $extractorResult
                $obj = Merge-XiaohongshuExtractorResult -CaptureObject $obj -ExtractorResult $extractorResult
            }
        }

        $playwrightError = ''
        try {
            $captureArguments = @($scriptPath, '--url', $Url, '--platform', $Platform, '--timeout-ms', $timeoutMs, '--output-json', $outputJsonPath)
            if (Test-HasValue $storageStatePath) { $captureArguments += @('--storage-state', $storageStatePath) }
            if (Test-HasValue $cookiesFile) { $captureArguments += @('--cookies-file', $cookiesFile) }
            & $pythonCommand @captureArguments 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Playwright social capture failed with exit code $LASTEXITCODE." }
            if (-not (Test-Path $outputJsonPath)) { throw 'Playwright social capture did not write its JSON output file.' }
            $payload = Read-Utf8Text -Path $outputJsonPath
            if (-not (Test-HasValue $payload)) { throw 'Playwright social capture returned no output.' }
            $playwrightObject = ConvertFrom-JsonCompat -Json $payload -Depth 50

            if ($Platform -eq 'xiaohongshu' -and $extractorSucceeded -and $null -ne $obj) {
                $obj = Merge-XiaohongshuSupplementalCapture -BaseCapture $obj -SupplementalCapture $playwrightObject
                $obj = Merge-XiaohongshuExtractorResult -CaptureObject $obj -ExtractorResult $extractorResult
            } else {
                $obj = $playwrightObject
                if ($Platform -eq 'xiaohongshu' -and $null -ne $extractorResult) {
                    $obj = Merge-XiaohongshuExtractorResult -CaptureObject $obj -ExtractorResult $extractorResult
                }
            }
        } catch {
            $playwrightError = $_.Exception.Message
            if (-not $extractorSucceeded -or $null -eq $obj) { throw }
            $metadata = Get-DataValue -Data $obj -Name 'metadata'
            if ($null -eq $metadata) {
                $metadata = [ordered]@{}
                Set-ObjectField -Object $obj -Name 'metadata' -Value $metadata | Out-Null
            }
            Set-ObjectField -Object $metadata -Name 'playwright_supplement_status' -Value 'failed' | Out-Null
            Set-ObjectField -Object $metadata -Name 'playwright_supplement_error' -Value $playwrightError | Out-Null
            Set-ObjectField -Object $metadata -Name 'comments_source' -Value 'none' | Out-Null
            Set-ObjectField -Object $obj -Name 'playwright_supplement_status' -Value 'failed' | Out-Null
            Set-ObjectField -Object $obj -Name 'playwright_supplement_error' -Value $playwrightError | Out-Null
        }

        if ($null -eq $obj) { throw 'Social capture returned no result.' }
        Write-Utf8Text -Path $outputJsonPath -Content ($obj | ConvertTo-Json -Depth 100)
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
                if ($Platform -eq 'xiaohongshu') {
                    $socialRouteConfig = Get-DataValue -Data $Config.routes -Name 'social'
                    $adapterConfig = if ($null -ne $socialRouteConfig) { Get-DataValue -Data $socialRouteConfig -Name 'xiaohongshu_adapter' } else { $null }
                    $adapterCommand = if ($null -ne $adapterConfig) { Get-ConfiguredPathValue -Object $adapterConfig -PropertyName 'command' } else { '' }
                    $adapterScript = if ($null -ne $adapterConfig) { Get-ConfiguredPathValue -Object $adapterConfig -PropertyName 'script' } else { '' }
                    $adapterServerUrl = if ($null -ne $adapterConfig) { Get-StringValue -Data $adapterConfig -Name 'server_url' -DefaultValue 'http://127.0.0.1:5556/xhs/detail' } else { 'http://127.0.0.1:5556/xhs/detail' }
                    $adapterTimeoutValue = if ($null -ne $adapterConfig) { Get-StringValue -Data $adapterConfig -Name 'timeout_ms' -DefaultValue '30000' } else { '30000' }
                    $adapterSaveBackendPayload = $true
                    if ($null -ne $adapterConfig) {
                        $savePayloadRaw = Get-DataValue -Data $adapterConfig -Name 'save_backend_payload'
                        if ($null -ne $savePayloadRaw) { $adapterSaveBackendPayload = [bool]$savePayloadRaw }
                    }
                    if (-not (Test-HasValue $adapterCommand)) { $adapterCommand = $pythonCommand }
                    if (-not (Test-HasValue $adapterScript) -or $adapterScript -like '*REPLACE/WITH/YOUR*' -or $adapterScript -like '*REPLACE\WITH\YOUR*' -or -not (Test-Path $adapterScript)) {
                        $adapterScript = Join-Path $PSScriptRoot 'xiaohongshu_downloader_adapter.py'
                    }
                    $downloadParameters.XiaohongshuAdapterCommand = $adapterCommand
                    $downloadParameters.XiaohongshuAdapterScriptPath = $adapterScript
                    $downloadParameters.XiaohongshuAdapterServerUrl = $adapterServerUrl
                    $downloadParameters.XiaohongshuAdapterTimeoutMs = [int]$adapterTimeoutValue
                    $downloadParameters.XiaohongshuAdapterSaveBackendPayload = [bool]$adapterSaveBackendPayload
                }
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
    param($Config,[string]$Url,[string]$TitleHint,[string]$Platform,[string]$ResolvedVaultPath,[switch]$DryRun)
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
        $canonicalUrl = Get-RegexGroupValue -Html $html -Pattern '<link[^>]+rel="canonical"[^>]+href="(?<value>[^"]+)"'
        if (-not (Test-HasValue $canonicalUrl)) { $canonicalUrl = Get-MetaContent -Html $html -Key 'og:url' }
        $canonicalUrl = Resolve-AbsoluteUrl -BaseUrl $Url -Candidate $canonicalUrl
        $pageTitle = Get-HtmlTitle -Html $html
        $plainText = Get-PlainTextFromHtml -Html $html
        $identity = New-PodcastIdentity -Url $(if (Test-HasValue $canonicalUrl) { $canonicalUrl } else { $Url }) -Platform $Platform
        $resourceHints = Get-PodcastResourceHints -Html $html -BaseUrl $Url
        $rssMetadata = Get-PodcastRssMetadata -RssUrl $resourceHints.rss_url -NormalizedEpisodeUrl $identity.normalized_url -SourceItemId $identity.source_item_id -TitleCandidates @($TitleHint, $ogTitle, $pageTitle)
        $showNotes = Get-PodcastShowNotes -Html $html -Description $ogDescription -PlainText $plainText
        $effectiveTranscriptUrl = if (Test-HasValue $resourceHints.transcript_url) { $resourceHints.transcript_url } elseif ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.transcript_url)) { [string]$rssMetadata.transcript_url } else { '' }
        $effectiveEnclosureUrl = if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.enclosure_url)) { [string]$rssMetadata.enclosure_url } elseif (Test-HasValue $resourceHints.enclosure_url) { $resourceHints.enclosure_url } else { '' }
        $transcript = Get-TranscriptFromUrl -TranscriptUrl $effectiveTranscriptUrl
        $title = if (Test-HasValue $TitleHint) { $TitleHint } elseif ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.episode_title)) { [string]$rssMetadata.episode_title } elseif (Test-HasValue $ogTitle) { $ogTitle } elseif (Test-HasValue $pageTitle) { $pageTitle } else { "Podcast Clip - $Platform" }
        $author = 'unknown'
        if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.podcast_author)) {
            $author = [string]$rssMetadata.podcast_author
        } elseif ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.podcast_title)) {
            $author = [string]$rssMetadata.podcast_title
        } elseif (Test-HasValue $pageTitle) {
            $pageTitleMatch = [regex]::Match($pageTitle, '^(?<episode>.*?)\s+-\s+(?<podcast>.*?)\s+\|')
            if ($pageTitleMatch.Success) { $author = $pageTitleMatch.Groups['podcast'].Value }
        }
        $publishedAt = if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.published_at)) { [string]$rssMetadata.published_at } else { 'unknown' }
        $episodeDescription = if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.description)) { [string]$rssMetadata.description } else { '' }
        $podcastTitle = if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.podcast_title)) { [string]$rssMetadata.podcast_title } else { $author }
        $podcastImage = if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.podcast_image)) { [string]$rssMetadata.podcast_image } else { '' }
        $summaryParts = New-Object System.Collections.Generic.List[string]
        if (Test-HasValue $ogDescription) { $summaryParts.Add($ogDescription) } else { $summaryParts.Add('Podcast metadata captured from the episode page.') }
        if ($null -ne $rssMetadata -and [bool]$rssMetadata.item_found) { $summaryParts.Add("RSS item matched via $($rssMetadata.match_strategy).") }
        if (Test-HasValue $resourceHints.rss_url) { $summaryParts.Add('RSS discovered.') }
        if (Test-HasValue $effectiveTranscriptUrl) { $summaryParts.Add('Transcript hint discovered.') }
        if (Test-HasValue $effectiveEnclosureUrl) { $summaryParts.Add('Audio enclosure hint discovered.') }
        if (Test-HasValue $showNotes) { $summaryParts.Add('Show notes extracted from page content.') }
        $rawParts = New-Object System.Collections.Generic.List[string]
        if (Test-HasValue $ogDescription) { $rawParts.Add("Description:`n$ogDescription") }
        if (Test-HasValue $episodeDescription) { $rawParts.Add("Episode Description:`n$episodeDescription") }
        if (Test-HasValue $showNotes) { $rawParts.Add("Show Notes:`n$showNotes") } elseif (Test-HasValue $plainText) { $rawParts.Add("Page Text Preview:`n$(Get-PreviewText -Text $plainText -Length 1800)") }
        $images = @($ogImage, $podcastImage | Where-Object { Test-HasValue $_ } | Select-Object -Unique)
        $videos = @($Url)
        if (Test-HasValue $effectiveEnclosureUrl) { $videos += $effectiveEnclosureUrl }
        if ($null -ne $rssMetadata -and (Test-HasValue $rssMetadata.episode_link)) { $videos += [string]$rssMetadata.episode_link }
        $videos = @($videos | Where-Object { Test-HasValue $_ } | Select-Object -Unique)
        if (Test-HasValue $transcript) {
            $captureLevel = 'enhanced'
        } elseif (Test-HasValue $showNotes -or Test-HasValue $resourceHints.rss_url -or ($null -ne $rssMetadata -and [bool]$rssMetadata.item_found) -or Test-HasValue $effectiveEnclosureUrl) {
            $captureLevel = 'standard'
        } else {
            $captureLevel = 'light'
        }
        $metadata = [ordered]@{
            capture_level = $captureLevel
            transcript_status = if (Test-HasValue $transcript) { 'available' } else { 'missing' }
            transcript_source = if (Test-HasValue $transcript) { 'remote' } else { 'missing' }
            media_downloaded = $false
            analysis_ready = $true
            extractor = if ($null -ne $rssMetadata -and [bool]$rssMetadata.item_found) { 'web-metadata+rss' } else { 'web-metadata' }
            source_status_code = $response.StatusCode
            source_status_description = $response.StatusDescription
            rss_url = $resourceHints.rss_url
            transcript_url = $effectiveTranscriptUrl
            enclosure_url = $effectiveEnclosureUrl
            show_notes_extracted = [bool](Test-HasValue $showNotes)
            normalized_url = $identity.normalized_url
            source_item_id = $identity.source_item_id
            capture_key = $identity.capture_key
            capture_id = $identity.capture_id
            source_strategy = if ($null -ne $rssMetadata -and [bool]$rssMetadata.item_found) { 'page+rss' } else { 'page_only' }
            rss_item_found = if ($null -ne $rssMetadata) { [bool]$rssMetadata.item_found } else { $false }
            rss_match_strategy = if ($null -ne $rssMetadata) { [string]$rssMetadata.match_strategy } else { '' }
            rss_fetch_error = if ($null -ne $rssMetadata) { [string]$rssMetadata.fetch_error } else { '' }
            podcast_title = $podcastTitle
            podcast_author = $author
            duration_seconds = if ($null -ne $rssMetadata) { [int]$rssMetadata.duration_seconds } else { 0 }
        }
        $extraProperties = [ordered]@{
            source_url = $Url
            normalized_url = $identity.normalized_url
            platform = $Platform
            podcast_platform = $Platform
            content_type = 'podcast'
            route = 'podcast'
            episode_url = $identity.normalized_url
            episode_id = $identity.source_item_id
            source_item_id = $identity.source_item_id
            capture_key = $identity.capture_key
            capture_id = $identity.capture_id
            podcast_title = $podcastTitle
            podcast_author = $author
            rss_url = $resourceHints.rss_url
            transcript_url = $effectiveTranscriptUrl
            enclosure_url = $effectiveEnclosureUrl
            source_strategy = $metadata.source_strategy
            duration_seconds = $metadata.duration_seconds
            description = if (Test-HasValue $ogDescription) { $ogDescription } else { $episodeDescription }
            audio_path = ''
            audio_download_status = 'skipped'
            transcript_source = $metadata.transcript_source
            asr_status = if (Test-HasValue $transcript) { 'not_needed' } else { 'not_attempted' }
            asr_provider = ''
            asr_model = ''
            asr_error = ''
            status = 'clipped'
            download_status = 'skipped'
            download_method = 'none'
            media_downloaded = $false
            analyzer_status = 'pending'
            bitable_sync_status = 'pending'
        }
        $capture = New-CaptureObject -Title $title -Author $author -PublishedAt $publishedAt -Summary (($summaryParts -join ' ').Trim()) -RawText (($rawParts | Select-Object -Unique) -join "`n`n") -Transcript $transcript -Tags @('clipped','podcast',$Platform) -Images $images -Videos $videos -Metadata $metadata -ExtraProperties $extraProperties
        $capture = Save-PodcastArtifacts -Config $Config -Capture $capture -ResolvedVaultPath $ResolvedVaultPath
        return $capture
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
        'podcast' { return Invoke-PodcastCapture -Config $Config -Url $Url -TitleHint $TitleHint -Platform $Detection.platform -ResolvedVaultPath $ResolvedVaultPath -DryRun:$DryRun }
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
        $vaultPathFile = Join-Path $tempDir 'renderer-vault-path.txt'

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
        if (Test-HasValue $ResolvedVaultPath) {
            Write-Utf8Text -Path $vaultPathFile -Content $ResolvedVaultPath
            $arguments += @('--vault-path-file', $vaultPathFile)
        }
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

function Test-ShouldAutoRunKnowledgeSummary {
    param(
        $Detection,
        $Capture,
        [string]$ResolvedVaultPath,
        [string]$NotePath,
        [switch]$DryRun
    )
    if ([bool]$DryRun) { return $false }
    if (-not (Test-HasValue $ResolvedVaultPath)) { return $false }
    if (-not (Test-HasValue $NotePath)) { return $false }
    $contentType = if ($null -ne $Detection) { [string]$Detection.content_type } else { '' }
    if (-not (Test-HasValue $contentType)) { $contentType = Get-StringValue -Data $Capture -Name 'content_type' -DefaultValue '' }
    if ($contentType -eq 'short_video') { return $false }
    $metadata = Get-DataValue -Data $Capture -Name 'metadata'
    $analysisReadyValue = Get-DataValue -Data $Capture -Name 'analysis_ready'
    if ($null -eq $analysisReadyValue -and $null -ne $metadata) { $analysisReadyValue = Get-DataValue -Data $metadata -Name 'analysis_ready' }
    if ($null -eq $analysisReadyValue) { return $true }
    [bool]$analysisReadyValue
}

function Set-CaptureAnalyzerStatus {
    param(
        $Capture,
        [string]$AnalyzerStatus
    )
    if ($null -eq $Capture) { return $Capture }
    Set-ObjectField -Object $Capture -Name 'analyzer_status' -Value $AnalyzerStatus | Out-Null
    $metadata = Get-DataValue -Data $Capture -Name 'metadata'
    if ($null -ne $metadata) {
        Set-ObjectField -Object $metadata -Name 'analyzer_status' -Value $AnalyzerStatus | Out-Null
    }
    $Capture
}

function Write-CaptureStateFiles {
    param(
        $Capture,
        [string]$ResolvedVaultPath,
        [string]$CaptureJsonInputPath
    )
    if ($null -eq $Capture) { return }
    $sidecarPath = ''
    if (Test-HasValue $CaptureJsonInputPath) {
        $sidecarPath = Resolve-PathFromVault -VaultPath $ResolvedVaultPath -RelativeOrAbsolutePath $CaptureJsonInputPath
    }
    if (-not (Test-HasValue $sidecarPath)) {
        $sidecarPath = Resolve-PathFromVault -VaultPath $ResolvedVaultPath -RelativeOrAbsolutePath (Get-StringValue -Data $Capture -Name 'sidecar_path' -DefaultValue '')
    }
    if (Test-HasValue $sidecarPath) {
        $sidecarDirectory = Split-Path -Parent $sidecarPath
        if (Test-HasValue $sidecarDirectory) { New-Item -ItemType Directory -Path $sidecarDirectory -Force | Out-Null }
        Write-Utf8Text -Path $sidecarPath -Content ($Capture | ConvertTo-Json -Depth 100)
    }

    $metadata = Get-DataValue -Data $Capture -Name 'metadata'
    if ($null -eq $metadata) { return }
    $metadataPath = Get-StringValue -Data $Capture -Name 'metadata_path' -DefaultValue ''
    if (-not (Test-HasValue $metadataPath)) { $metadataPath = Get-StringValue -Data $metadata -Name 'metadata_path' -DefaultValue '' }
    $metadataPath = Resolve-PathFromVault -VaultPath $ResolvedVaultPath -RelativeOrAbsolutePath $metadataPath
    if (Test-HasValue $metadataPath) {
        $metadataDirectory = Split-Path -Parent $metadataPath
        if (Test-HasValue $metadataDirectory) { New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null }
        Write-Utf8Text -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 100)
    }
}

function Invoke-KnowledgeAnalyzerFromClipper {
    param(
        [string]$NotePath,
        [string]$ResolvedVaultPath,
        [string]$ArtifactDirectory
    )
    $result = [ordered]@{
        attempted = $false
        success = $false
        analyzer_status = 'skipped'
        output_json_path = ''
        analysis_input_path = ''
        knowledge_note_path = ''
        debug_directory = ''
        error_message = ''
    }
    if (-not (Test-HasValue $NotePath) -or -not (Test-HasValue $ResolvedVaultPath)) {
        return [pscustomobject]$result
    }

    $analyzerScriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\obsidian-analyzer\scripts\run_analyzer.ps1'))
    if (-not (Test-Path $analyzerScriptPath)) {
        $result.error_message = "Analyzer script not found: $analyzerScriptPath"
        return [pscustomobject]$result
    }

    $result.attempted = $true
    $result.output_json_path = Join-Path $ArtifactDirectory 'knowledge-analyzer-run.json'
    $result.debug_directory = Join-Path $ArtifactDirectory 'knowledge-analyzer'

    try {
        $null = & $analyzerScriptPath -NotePath $NotePath -VaultPath $ResolvedVaultPath -Mode knowledge -OutputJsonPath $result.output_json_path -DebugDirectory $result.debug_directory 2>&1 | Out-String
        $analyzerRun = $null
        if (Test-Path $result.output_json_path) {
            $analyzerRun = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $result.output_json_path) -Depth 100
        }
        if ($null -eq $analyzerRun) {
            $result.error_message = 'Analyzer did not produce an output JSON file.'
            return [pscustomobject]$result
        }
        $result.analysis_input_path = Get-StringValue -Data $analyzerRun -Name 'analysis_input_path' -DefaultValue ''
        $result.knowledge_note_path = Get-StringValue -Data $analyzerRun -Name 'note_path' -DefaultValue ''
        $result.analyzer_status = Get-StringValue -Data $analyzerRun -Name 'analysis_status' -DefaultValue ''
        if ($analyzerRun.success -and ((Get-StringValue -Data $analyzerRun -Name 'final_run_status' -DefaultValue '') -eq 'SUCCESS')) {
            $result.success = $true
            if (-not (Test-HasValue $result.analyzer_status)) { $result.analyzer_status = 'done' }
        } else {
            $result.success = $false
            $result.error_message = Get-StringValue -Data $analyzerRun -Name 'final_message_zh' -DefaultValue (Get-StringValue -Data $analyzerRun -Name 'final_message_en' -DefaultValue 'Knowledge analyzer failed.')
            if (-not (Test-HasValue $result.analyzer_status)) { $result.analyzer_status = 'failed' }
        }
        return [pscustomobject]$result
    } catch {
        $result.error_message = $_.Exception.Message
        return [pscustomobject]$result
    }
}

function Invoke-KnowledgeSummaryUpdater {
    param(
        [string]$NotePath,
        [string]$ResolvedVaultPath,
        [string]$ArtifactDirectory,
        [string]$AnalyzerStatus,
        [string]$AnalysisJsonPath,
        [string]$KnowledgeNotePath
    )
    $result = [ordered]@{
        success = $false
        note_path = $NotePath
        analyzer_status = $AnalyzerStatus
        knowledge_section_written = $false
        output_json_path = ''
        error_message = ''
    }
    if (-not (Test-HasValue $NotePath) -or -not (Test-Path $NotePath)) {
        $result.error_message = "Clipping note not found: $NotePath"
        return [pscustomobject]$result
    }

    $updaterScriptPath = Join-Path $PSScriptRoot 'update_clipping_note_with_knowledge.py'
    if (-not (Test-Path $updaterScriptPath)) {
        $result.error_message = "Knowledge summary updater not found: $updaterScriptPath"
        return [pscustomobject]$result
    }

    $result.output_json_path = Join-Path $ArtifactDirectory 'knowledge-summary-update.json'
    try {
        $args = @(
            $updaterScriptPath,
            '--note-path', $NotePath,
            '--vault-path', $ResolvedVaultPath,
            '--analyzer-status', $AnalyzerStatus,
            '--output-json', $result.output_json_path
        )
        if (Test-HasValue $AnalysisJsonPath) { $args += @('--analysis-json', $AnalysisJsonPath) }
        if (Test-HasValue $KnowledgeNotePath) { $args += @('--knowledge-note-path', $KnowledgeNotePath) }
        $null = & python @args 2>&1 | Out-String
        if (-not (Test-Path $result.output_json_path)) {
            $result.error_message = 'Knowledge summary updater did not produce an output JSON file.'
            return [pscustomobject]$result
        }
        $updaterResult = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $result.output_json_path) -Depth 100
        $result.success = [bool]$updaterResult.success
        $result.note_path = Get-StringValue -Data $updaterResult -Name 'note_path' -DefaultValue $NotePath
        $result.knowledge_section_written = [bool](Get-DataValue -Data $updaterResult -Name 'knowledge_section_written')
        if (-not $result.success) {
            $result.error_message = Get-StringValue -Data $updaterResult -Name 'error_message' -DefaultValue 'Knowledge summary updater failed.'
        }
        return [pscustomobject]$result
    } catch {
        $result.error_message = $_.Exception.Message
        return [pscustomobject]$result
    }
}

function Get-MarkdownDisplayTitle {
    param([string]$Title)
    if (-not (Test-HasValue $Title)) { return 'Untitled Clip' }
    if ($Title.StartsWith('#')) { return ('\' + $Title) }
    $Title
}

function Get-CleanNoteTitle {
    param([string]$Title)

    if (-not (Test-HasValue $Title)) { return 'Untitled Clip' }

    $cleaned = [string]$Title
    $cleaned = [regex]::Replace($cleaned, 'https?://\S+', ' ', 'IgnoreCase')
    $cleaned = [regex]::Replace($cleaned, '@\S+', ' ')
    $cleaned = [regex]::Replace($cleaned, '#\S+', ' ')
    $cleaned = [regex]::Replace($cleaned, '\s+', ' ').Trim()
    $cleaned = [regex]::Replace($cleaned, '^[\s,.;:!?@\-_/]+', '')
    $cleaned = [regex]::Replace($cleaned, '[\s,.;:!?@\-_/]+$', '')
    $cleaned = [regex]::Replace($cleaned, '\s+', ' ').Trim()

    if (-not (Test-HasValue $cleaned)) { return 'Untitled Clip' }
    return $cleaned
}

function Test-LooksLikeLoginPrompt {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    return ($lower.Contains('login'))
}

function Use-CategoryHintAsFolder {
    param($Config)
    if ($null -eq $Config -or $null -eq $Config.clipper) { return $false }
    $rawValue = Get-DataValue -Data $Config.clipper -Name 'allow_category_hint_folder_override'
    if ($null -eq $rawValue) { return $false }
    return [bool]$rawValue
}

function Build-ClippingNote {
    param($Config,$Detection,$Capture,[string]$SourceUrl,[string]$CategoryHint)

    $captured = Get-Date -Format 'yyyy-MM-dd'
    $useCategoryHintFolder = (Use-CategoryHintAsFolder -Config $Config)
    $folder = if ($useCategoryHintFolder -and (Test-HasValue $CategoryHint)) { $CategoryHint } elseif (Test-HasValue $Config.clipper.default_folder) { [string]$Config.clipper.default_folder } else { 'Clippings' }
    $title = [string]$Capture.title
    $noteTitle = Get-CleanNoteTitle -Title $title
    $displayTitle = Get-MarkdownDisplayTitle -Title $noteTitle
    $prefixDate = if ($Config.clipper.prefix_date -eq $true) { "$captured " } else { '' }
    $fileName = Get-SafeFileName "$prefixDate$noteTitle.md"
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
    $captureStatus = Get-StringValue -Data $Capture -Name 'status' -DefaultValue 'clipped'
    $lines.Add("status: $captureStatus")
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

function Add-RunFinalStatusFields {
    param($Result)
    $downloadStatus = Get-StringValue -Data $Result -Name 'download_status' -DefaultValue ''
    $failedStep = Get-StringValue -Data $Result -Name 'failed_step' -DefaultValue ''
    $authActionRequired = Get-StringValue -Data $Result -Name 'auth_action_required' -DefaultValue ''
    $authRefreshCommand = Get-StringValue -Data $Result -Name 'auth_refresh_command' -DefaultValue ''
    $authGuidanceEn = Get-StringValue -Data $Result -Name 'auth_guidance_en' -DefaultValue ''
    $authGuidanceZh = Get-StringValue -Data $Result -Name 'auth_guidance_zh' -DefaultValue ''
    $errors = @()
    $resultErrors = Get-DataValue -Data $Result -Name 'errors'
    if ($null -ne $resultErrors) { $errors = @($resultErrors) }
    $platform = Get-StringValue -Data $Result -Name 'platform' -DefaultValue ''
    $captureLevel = Get-StringValue -Data $Result -Name 'capture_level' -DefaultValue ''
    $fallbackReason = Get-StringValue -Data $Result -Name 'fallback_reason' -DefaultValue ''
    $knowledgeSummaryStatus = Get-StringValue -Data $Result -Name 'knowledge_summary_status' -DefaultValue ''
    $knowledgeSummaryError = Get-StringValue -Data $Result -Name 'knowledge_summary_error' -DefaultValue ''

    if (-not [bool]$Result.success) {
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'FAILED' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u5931\u8d25') | Out-Null
        if (-not (Test-HasValue $failedStep)) { Set-ObjectField -Object $Result -Name 'failed_step' -Value 'unknown' | Out-Null }
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value (Get-StringValue -Data $Result -Name 'error_message' -DefaultValue 'The clipper run failed.') | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value (Get-StringValue -Data $Result -Name 'error_message_zh' -DefaultValue (Zh '\u672c\u6b21 Clipper \u8fd0\u884c\u5931\u8d25\u3002')) | Out-Null
        return $Result
    }

    if ([bool]$Result.dry_run) {
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'SUCCESS' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u6210\u529f') | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value 'Dry run completed successfully.' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value (Zh 'DryRun \u5df2\u6210\u529f\u5b8c\u6210\u3002') | Out-Null
        return $Result
    }

    if ($captureLevel -eq 'fallback') {
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'FAILED' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u5931\u8d25') | Out-Null
        if (-not (Test-HasValue $failedStep)) { Set-ObjectField -Object $Result -Name 'failed_step' -Value 'capture' | Out-Null }
        $captureFallbackMessageEn = if (Test-HasValue $fallbackReason) { $fallbackReason } else { 'Capture fell back to a minimal note because the source could not be parsed or fetched.' }
        $captureFallbackMessageZh = if (Test-HasValue $fallbackReason) {
            '{0}{1}' -f (Zh '\u6293\u53d6\u5931\u8d25\uff0c\u5df2\u964d\u7ea7\u4e3a\u6700\u5c0f\u7b14\u8bb0\uff1a'), $fallbackReason
        } else {
            Zh '\u6293\u53d6\u5931\u8d25\uff0c\u5df2\u964d\u7ea7\u4e3a\u6700\u5c0f\u7b14\u8bb0\u3002'
        }
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value $captureFallbackMessageEn | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $captureFallbackMessageZh | Out-Null
        return $Result
    }

    if ($downloadStatus -in @('failed', 'blocked')) {
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'FAILED' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u5931\u8d25') | Out-Null
        if (Test-HasValue $authActionRequired) {
            $failedStepName = if ($authActionRequired -eq 'refresh_douyin_auth') { 'auth_refresh_required' } else { 'access_blocked' }
            $finalMessageEn = if (Test-HasValue $authGuidanceEn) { $authGuidanceEn } else { 'Platform access is blocked. Retry in a trusted environment.' }
            $finalMessageZh = if (Test-HasValue $authGuidanceZh) { $authGuidanceZh } else { Zh '\u5e73\u53f0\u62e6\u622a\u4e86\u8fd9\u6b21\u8bf7\u6c42\uff0c\u8bf7\u5728\u53ef\u4fe1\u73af\u5883\u4e2d\u91cd\u8bd5\u3002' }
            Set-ObjectField -Object $Result -Name 'failed_step' -Value $failedStepName | Out-Null
            Set-ObjectField -Object $Result -Name 'final_message_en' -Value $finalMessageEn | Out-Null
            Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $finalMessageZh | Out-Null
        } else {
            if (-not (Test-HasValue $failedStep)) { Set-ObjectField -Object $Result -Name 'failed_step' -Value 'download' | Out-Null }
            $firstError = if ($errors.Count -gt 0) { [string]$errors[0] } else { 'Video download failed.' }
            $downloadMessageEn = $firstError
            $downloadMessageZh = ('{0}{1}' -f (Zh '\u89c6\u9891\u4e0b\u8f7d\u5931\u8d25\uff1a'), $firstError)
            if ($platform -eq 'xiaohongshu') {
                $downloadMessageEn = 'Xiaohongshu content capture succeeded, but the video file was not downloaded. Retry the downloader path or continue with the note-only result.'
                if ($errors.Count -gt 0) {
                    $downloadMessageEn = '{0} Error: {1}' -f $downloadMessageEn, $firstError
                }
                $downloadMessageZh = Zh '\u5c0f\u7ea2\u4e66\u5185\u5bb9\u5df2\u6293\u53d6\u6210\u529f\uff0c\u4f46\u89c6\u9891\u6587\u4ef6\u4ecd\u672a\u843d\u76d8\u3002\u53ef\u4ee5\u7ee7\u7eed\u4f7f\u7528\u5f53\u524d\u7b14\u8bb0\u7ed3\u679c\uff0c\u6216\u91cd\u8bd5\u4e0b\u8f7d\u540e\u7aef\u3002'
                if ($errors.Count -gt 0) {
                    $downloadMessageZh = '{0} {1}{2}' -f $downloadMessageZh, (Zh '\u9519\u8bef\uff1a'), $firstError
                }
            }
            Set-ObjectField -Object $Result -Name 'final_message_en' -Value $downloadMessageEn | Out-Null
            Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $downloadMessageZh | Out-Null
        }
        return $Result
    }

    Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'SUCCESS' | Out-Null
    Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u6210\u529f') | Out-Null
    if ($knowledgeSummaryStatus -eq 'failed') {
        $knowledgeSummaryMessageEn = 'The clipper run completed successfully, but the knowledge summary step failed.'
        if (Test-HasValue $knowledgeSummaryError) {
            $knowledgeSummaryMessageEn = '{0} Details: {1}' -f $knowledgeSummaryMessageEn, $knowledgeSummaryError
        }
        $knowledgeSummaryMessageZh = Zh '\u672c\u6b21 Clipper \u4e3b\u6d41\u7a0b\u5df2\u6210\u529f\u5b8c\u6210\uff0c\u4f46\u77e5\u8bc6\u901f\u89c8\u56de\u5199\u5931\u8d25\u3002'
        if (Test-HasValue $knowledgeSummaryError) {
            $knowledgeSummaryMessageZh = '{0} {1}{2}' -f $knowledgeSummaryMessageZh, (Zh '\u8be6\u60c5\uff1a'), $knowledgeSummaryError
        }
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value $knowledgeSummaryMessageEn | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $knowledgeSummaryMessageZh | Out-Null
        return $Result
    }

    Set-ObjectField -Object $Result -Name 'final_message_en' -Value 'The clipper run completed successfully.' | Out-Null
    Set-ObjectField -Object $Result -Name 'final_message_zh' -Value (Zh '\u672c\u6b21 Clipper \u8fd0\u884c\u6210\u529f\u5b8c\u6210\u3002') | Out-Null
    $Result
}

function Get-RunSummaryLines {
    param($Result)
    $lines = New-Object System.Collections.Generic.List[string]
    $failedStep = Get-StringValue -Data $Result -Name 'failed_step' -DefaultValue ''
    $authActionRequired = Get-StringValue -Data $Result -Name 'auth_action_required' -DefaultValue ''
    $flowLabel = 'clip'
    $flowLabelZh = Zh '\u666e\u901a\u526a\u85cf'
    if ($authActionRequired -eq 'refresh_douyin_auth') {
        $flowLabel = 'auth_refresh'
        $flowLabelZh = Zh '\u5237\u65b0\u767b\u5f55\u6001'
    } elseif ($authActionRequired -eq 'switch_xiaohongshu_network') {
        $flowLabel = 'network_retry'
        $flowLabelZh = Zh '\u5207\u6362\u7f51\u7edc\u540e\u91cd\u8bd5'
    }
    $lines.Add('=== Clipper Summary ===')
    $lines.Add("route    : $($Result.route)")
    $lines.Add("platform : $($Result.platform)")
    $lines.Add("title    : $($Result.title)")
    $lines.Add("capture  : $($Result.capture_id)")
    $lines.Add("flow     : $flowLabel")
    $lines.Add(("{0}     : {1}" -f (Zh '\u6d41\u7a0b'), $flowLabelZh))
    $lines.Add("download : $($Result.download_status) / $($Result.download_method)")
    $lines.Add("video    : $($Result.video_path)")
    if ($null -ne $Result.PSObject.Properties['audio_download_status']) { $lines.Add("audio    : $($Result.audio_download_status) / $($Result.audio_path)") }
    if ($null -ne $Result.PSObject.Properties['transcript_status']) { $lines.Add("transcript: $($Result.transcript_status) / $($Result.transcript_source)") }
    if ($null -ne $Result.PSObject.Properties['asr_status']) { $lines.Add("asr      : $($Result.asr_status) / $($Result.asr_provider)") }
    if ($null -ne $Result.PSObject.Properties['asr_normalization'] -and (Test-HasValue ([string]$Result.asr_normalization))) { $lines.Add("asr_norm : $($Result.asr_normalization)") }
    if ($null -ne $Result.PSObject.Properties['diarization_status']) { $lines.Add("speaker  : $($Result.diarization_status) / $($Result.diarization_provider)") }
    if ($null -ne $Result.PSObject.Properties['knowledge_summary_status']) {
        $knowledgeLine = [string]$Result.knowledge_summary_status
        if ($null -ne $Result.PSObject.Properties['knowledge_summary_note_updated']) {
            $knowledgeLine = '{0} / note_updated={1}' -f $knowledgeLine, ([bool]$Result.knowledge_summary_note_updated).ToString().ToLowerInvariant()
        }
        $lines.Add("knowledge: $knowledgeLine")
    }
    if ($null -ne $Result.PSObject.Properties['final_run_status']) { $lines.Add("result   : $($Result.final_run_status)") }
    if ($null -ne $Result.PSObject.Properties['final_run_status_zh']) { $lines.Add(("{0}     : {1}" -f (Zh '\u7ed3\u679c'), $Result.final_run_status_zh)) }
    if (Test-HasValue $failedStep) {
        $lines.Add("step     : $failedStep")
        $lines.Add(("{0}     : {1}" -f (Zh '\u6b65\u9aa4'), $failedStep))
    }
    if ($null -ne $Result.PSObject.Properties['note_path']) {
        $lines.Add("note     : $($Result.note_path)")
    }
    if ($null -ne $Result.PSObject.Properties['knowledge_note_path'] -and (Test-HasValue ([string]$Result.knowledge_note_path))) {
        $lines.Add("insight  : $($Result.knowledge_note_path)")
    }
    if ($null -ne $Result.PSObject.Properties['support_bundle_path']) {
        $lines.Add("share    : $($Result.support_bundle_path)")
    }
    if ($null -ne $Result.PSObject.Properties['debug_directory']) {
        $lines.Add("debug    : $($Result.debug_directory)")
    }
    if ($null -ne $Result.PSObject.Properties['auth_action_required'] -and (Test-HasValue ([string]$Result.auth_action_required))) {
        $lines.Add("auth     : $($Result.auth_action_required)")
    }
    if ($null -ne $Result.PSObject.Properties['auth_refresh_command'] -and (Test-HasValue ([string]$Result.auth_refresh_command))) {
        $lines.Add("refresh  : $($Result.auth_refresh_command)")
        $lines.Add(("{0}     : {1}" -f (Zh '\u63d0\u793a'), (Zh '\u6267\u884c\u8be5\u5237\u65b0\u547d\u4ee4\u65f6\uff0c\u5c06\u6253\u5f00\u6d4f\u89c8\u5668\u5237\u65b0\u767b\u5f55\u6001\u3002')))
    }
    if ($null -ne $Result.PSObject.Properties['errors'] -and @($Result.errors).Count -gt 0) {
        $lines.Add("error    : $((@($Result.errors) | Select-Object -First 1))")
    }
    if ($null -ne $Result.PSObject.Properties['knowledge_summary_error'] -and (Test-HasValue ([string]$Result.knowledge_summary_error))) {
        $lines.Add("knowledge_err: $($Result.knowledge_summary_error)")
    }
    if ($null -ne $Result.PSObject.Properties['final_message_en']) { $lines.Add("detail_en: $($Result.final_message_en)") }
    if ($null -ne $Result.PSObject.Properties['final_message_zh']) { $lines.Add(("{0}     : {1}" -f (Zh '\u8be6\u60c5'), $Result.final_message_zh)) }
    $lines.Add('issue_en : Upload support-bundle or the whole debug directory to your issue for troubleshooting and updates.')
    $lines.Add(("{0} : {1}" -f (Zh '\u95ee\u9898\u4e0a\u62a5'), (Zh '\u8bf7\u5c06 support-bundle \u6216\u6574\u4e2a debug \u76ee\u5f55\u4e0a\u4f20\u5230\u4f60\u7684 issue\uff0c\u4fbf\u4e8e\u6392\u67e5\u548c\u66f4\u65b0\u3002')))
    return @($lines)
}

function Write-RunSummary {
    param($Result)
    $lines = Get-RunSummaryLines -Result $Result
    Write-Host ''
    Write-Host $lines[0] -ForegroundColor Cyan
    foreach ($line in @($lines | Select-Object -Skip 1)) {
        if ($line -like 'error    :*' -or $line -like 'result   : FAILED' -or $line -like '*澶辫触' -or $line -like 'step     :*') {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
    Write-Host ''
}

$resolvedConfigPath = ''
$config = $null
$resolvedVaultPath = ''
$artifactDirectory = ''
$defaultDebugDirectory = ''
$script:ClipperCurrentStep = 'startup'

try {
    $script:ClipperCurrentStep = 'config_load'
    if (-not (Test-HasValue $ConfigPath)) {
        if (Test-Path (Join-Path $PSScriptRoot '..\references\local-config.json')) { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.json' } else { $ConfigPath = Join-Path $PSScriptRoot '..\references\local-config.example.json' }
    }
    $resolvedConfigPath = $ConfigPath
    $config = Get-Config -Path $resolvedConfigPath
    $resolvedVaultPath = Get-ResolvedVaultPath -Config $config -VaultPath $VaultPath
    $defaultDebugDirectory = Get-DefaultDebugDirectory -Config $config -RequestedDebugDirectory $DebugDirectory

    $script:ClipperCurrentStep = 'input_resolve'
    $resolvedSourceInput = Resolve-SourceInput -InputText $SourceUrl
    $rawSourceInput = $SourceUrl
    $SourceUrl = $resolvedSourceInput.source_url

    $script:ClipperCurrentStep = 'debug_prepare'
    $artifactDirectory = Get-ArtifactDirectory -ExplicitDirectory $DebugDirectory -JsonPath $OutputJsonPath -DefaultDirectory $defaultDebugDirectory

    if (-not $DryRun -and -not (Test-HasValue $resolvedVaultPath)) { throw 'No vault path provided. Supply -VaultPath or set obsidian.vault_path in config.' }

    $script:ClipperCurrentStep = 'detect'
    if (Test-HasValue $DetectionJsonPath) {
        if (-not (Test-Path $DetectionJsonPath)) { throw "Detection JSON not found: $DetectionJsonPath" }
        $detection = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $DetectionJsonPath) -Depth 64
    } else {
        $detection = Get-Detection -Url $SourceUrl
    }

    $script:ClipperCurrentStep = 'capture'
    if (Test-HasValue $CaptureJsonPath) {
        if (-not (Test-Path $CaptureJsonPath)) { throw "Capture JSON not found: $CaptureJsonPath" }
        $capture = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $CaptureJsonPath) -Depth 100
    } else {
        $capture = Invoke-CaptureRoute -Config $config -Detection $detection -Url $SourceUrl -TitleHint $TitleHint -ResolvedVaultPath $resolvedVaultPath -DryRun:$DryRun
    }

    $script:ClipperCurrentStep = 'note_render'
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
    $audioPathForResult = Get-StringValue -Data $capture -Name 'audio_path' -DefaultValue ''
    if (-not (Test-HasValue $audioPathForResult) -and $null -ne $captureMetadata) { $audioPathForResult = Get-StringValue -Data $captureMetadata -Name 'audio_path' -DefaultValue '' }
    $audioDownloadStatusForResult = Get-StringValue -Data $capture -Name 'audio_download_status' -DefaultValue ''
    if (-not (Test-HasValue $audioDownloadStatusForResult) -and $null -ne $captureMetadata) { $audioDownloadStatusForResult = Get-StringValue -Data $captureMetadata -Name 'audio_download_status' -DefaultValue '' }
    $transcriptStatusForResult = Get-StringValue -Data $capture -Name 'transcript_status' -DefaultValue ''
    if (-not (Test-HasValue $transcriptStatusForResult) -and $null -ne $captureMetadata) { $transcriptStatusForResult = Get-StringValue -Data $captureMetadata -Name 'transcript_status' -DefaultValue '' }
    $transcriptSourceForResult = Get-StringValue -Data $capture -Name 'transcript_source' -DefaultValue ''
    if (-not (Test-HasValue $transcriptSourceForResult) -and $null -ne $captureMetadata) { $transcriptSourceForResult = Get-StringValue -Data $captureMetadata -Name 'transcript_source' -DefaultValue '' }
    $asrStatusForResult = Get-StringValue -Data $capture -Name 'asr_status' -DefaultValue ''
    if (-not (Test-HasValue $asrStatusForResult) -and $null -ne $captureMetadata) { $asrStatusForResult = Get-StringValue -Data $captureMetadata -Name 'asr_status' -DefaultValue '' }
    $asrProviderForResult = Get-StringValue -Data $capture -Name 'asr_provider' -DefaultValue ''
    if (-not (Test-HasValue $asrProviderForResult) -and $null -ne $captureMetadata) { $asrProviderForResult = Get-StringValue -Data $captureMetadata -Name 'asr_provider' -DefaultValue '' }
    $asrNormalizationForResult = Get-StringValue -Data $capture -Name 'asr_normalization' -DefaultValue ''
    if (-not (Test-HasValue $asrNormalizationForResult) -and $null -ne $captureMetadata) { $asrNormalizationForResult = Get-StringValue -Data $captureMetadata -Name 'asr_normalization' -DefaultValue '' }
    $diarizationStatusForResult = Get-StringValue -Data $capture -Name 'diarization_status' -DefaultValue ''
    if (-not (Test-HasValue $diarizationStatusForResult) -and $null -ne $captureMetadata) { $diarizationStatusForResult = Get-StringValue -Data $captureMetadata -Name 'diarization_status' -DefaultValue '' }
    $diarizationProviderForResult = Get-StringValue -Data $capture -Name 'diarization_provider' -DefaultValue ''
    if (-not (Test-HasValue $diarizationProviderForResult) -and $null -ne $captureMetadata) { $diarizationProviderForResult = Get-StringValue -Data $captureMetadata -Name 'diarization_provider' -DefaultValue '' }
    $sidecarPathForResult = Get-StringValue -Data $capture -Name 'sidecar_path' -DefaultValue ''
    if (-not (Test-HasValue $sidecarPathForResult) -and $null -ne $captureMetadata) { $sidecarPathForResult = Get-StringValue -Data $captureMetadata -Name 'sidecar_path' -DefaultValue '' }
    $authActionRequiredForResult = Get-StringValue -Data $capture -Name 'auth_action_required' -DefaultValue ''
    if (-not (Test-HasValue $authActionRequiredForResult) -and $null -ne $captureMetadata) { $authActionRequiredForResult = Get-StringValue -Data $captureMetadata -Name 'auth_action_required' -DefaultValue '' }
    $authFailureReasonForResult = Get-StringValue -Data $capture -Name 'auth_failure_reason' -DefaultValue ''
    if (-not (Test-HasValue $authFailureReasonForResult) -and $null -ne $captureMetadata) { $authFailureReasonForResult = Get-StringValue -Data $captureMetadata -Name 'auth_failure_reason' -DefaultValue '' }
    $authRefreshCommandForResult = Get-StringValue -Data $capture -Name 'auth_refresh_command' -DefaultValue ''
    if (-not (Test-HasValue $authRefreshCommandForResult) -and $null -ne $captureMetadata) { $authRefreshCommandForResult = Get-StringValue -Data $captureMetadata -Name 'auth_refresh_command' -DefaultValue '' }
    $authGuidanceEnForResult = Get-StringValue -Data $capture -Name 'auth_guidance_en' -DefaultValue ''
    if (-not (Test-HasValue $authGuidanceEnForResult) -and $null -ne $captureMetadata) { $authGuidanceEnForResult = Get-StringValue -Data $captureMetadata -Name 'auth_guidance_en' -DefaultValue '' }
    $authGuidanceZhForResult = Get-StringValue -Data $capture -Name 'auth_guidance_zh' -DefaultValue ''
    if (-not (Test-HasValue $authGuidanceZhForResult) -and $null -ne $captureMetadata) { $authGuidanceZhForResult = Get-StringValue -Data $captureMetadata -Name 'auth_guidance_zh' -DefaultValue '' }
    $authSessionStateForResult = Get-StringValue -Data $capture -Name 'auth_session_state' -DefaultValue ''
    $authSessionLikelyValidForResult = Get-DataValue -Data $capture -Name 'auth_session_likely_valid'
    $captureLevelForResult = if ($null -ne $captureMetadata) { Get-StringValue -Data $captureMetadata -Name 'capture_level' -DefaultValue '' } else { '' }
    $fallbackReasonForResult = if ($null -ne $captureMetadata) { Get-StringValue -Data $captureMetadata -Name 'fallback_reason' -DefaultValue '' } else { '' }
    $notePathFromRenderer = Get-StringValue -Data $note -Name 'note_path' -DefaultValue ''
    $knowledgeSummaryAttempted = $false
    $knowledgeSummaryStatus = 'skipped'
    $knowledgeSummaryNoteUpdated = $false
    $knowledgeSummaryError = ''
    $knowledgeNotePathForResult = ''
    $knowledgeAnalyzerOutputJsonPath = ''
    $knowledgeAnalysisInputPath = ''

    if (Test-ShouldAutoRunKnowledgeSummary -Detection $detection -Capture $capture -ResolvedVaultPath $resolvedVaultPath -NotePath $notePathFromRenderer -DryRun:$DryRun) {
        $knowledgeSummaryAttempted = $true
        try {
            $script:ClipperCurrentStep = 'knowledge_summary_prepare'
            $knowledgeSummaryStatus = 'running'
            $capture = Set-CaptureAnalyzerStatus -Capture $capture -AnalyzerStatus 'running'
            Write-CaptureStateFiles -Capture $capture -ResolvedVaultPath $resolvedVaultPath -CaptureJsonInputPath $CaptureJsonPath

            $script:ClipperCurrentStep = 'knowledge_summary_analyze'
            $knowledgeAnalyzerResult = Invoke-KnowledgeAnalyzerFromClipper -NotePath $notePathFromRenderer -ResolvedVaultPath $resolvedVaultPath -ArtifactDirectory $artifactDirectory
            $knowledgeAnalyzerOutputJsonPath = Get-StringValue -Data $knowledgeAnalyzerResult -Name 'output_json_path' -DefaultValue ''
            $knowledgeAnalysisInputPath = Get-StringValue -Data $knowledgeAnalyzerResult -Name 'analysis_input_path' -DefaultValue ''
            $knowledgeNotePathForResult = Get-StringValue -Data $knowledgeAnalyzerResult -Name 'knowledge_note_path' -DefaultValue ''

            if ([bool]$knowledgeAnalyzerResult.success) {
                $capture = Set-CaptureAnalyzerStatus -Capture $capture -AnalyzerStatus 'done'
                Write-CaptureStateFiles -Capture $capture -ResolvedVaultPath $resolvedVaultPath -CaptureJsonInputPath $CaptureJsonPath

                $script:ClipperCurrentStep = 'knowledge_summary_update'
                $knowledgeUpdateResult = Invoke-KnowledgeSummaryUpdater -NotePath $notePathFromRenderer -ResolvedVaultPath $resolvedVaultPath -ArtifactDirectory $artifactDirectory -AnalyzerStatus 'done' -AnalysisJsonPath $knowledgeAnalysisInputPath -KnowledgeNotePath $knowledgeNotePathForResult
                if ([bool]$knowledgeUpdateResult.success) {
                    $knowledgeSummaryStatus = 'done'
                    $knowledgeSummaryNoteUpdated = [bool]$knowledgeUpdateResult.knowledge_section_written
                    $updatedNotePath = Get-StringValue -Data $knowledgeUpdateResult -Name 'note_path' -DefaultValue ''
                    if (Test-HasValue $updatedNotePath) { $notePathFromRenderer = $updatedNotePath }
                } else {
                    $knowledgeSummaryStatus = 'failed'
                    $knowledgeSummaryError = Get-StringValue -Data $knowledgeUpdateResult -Name 'error_message' -DefaultValue 'Knowledge summary updater failed after analyzer success.'
                    $capture = Set-CaptureAnalyzerStatus -Capture $capture -AnalyzerStatus 'failed'
                    Write-CaptureStateFiles -Capture $capture -ResolvedVaultPath $resolvedVaultPath -CaptureJsonInputPath $CaptureJsonPath
                }
            } else {
                $knowledgeSummaryStatus = 'failed'
                $knowledgeSummaryError = Get-StringValue -Data $knowledgeAnalyzerResult -Name 'error_message' -DefaultValue 'Knowledge analyzer failed.'
                $knowledgeNotePathForResult = ''
                $capture = Set-CaptureAnalyzerStatus -Capture $capture -AnalyzerStatus 'failed'
                Write-CaptureStateFiles -Capture $capture -ResolvedVaultPath $resolvedVaultPath -CaptureJsonInputPath $CaptureJsonPath

                $script:ClipperCurrentStep = 'knowledge_summary_update'
                $knowledgeUpdateResult = Invoke-KnowledgeSummaryUpdater -NotePath $notePathFromRenderer -ResolvedVaultPath $resolvedVaultPath -ArtifactDirectory $artifactDirectory -AnalyzerStatus 'failed' -AnalysisJsonPath '' -KnowledgeNotePath ''
                if ([bool]$knowledgeUpdateResult.success) {
                    $updatedNotePath = Get-StringValue -Data $knowledgeUpdateResult -Name 'note_path' -DefaultValue ''
                    if (Test-HasValue $updatedNotePath) { $notePathFromRenderer = $updatedNotePath }
                } else {
                    $updaterError = Get-StringValue -Data $knowledgeUpdateResult -Name 'error_message' -DefaultValue ''
                    if (Test-HasValue $updaterError) {
                        $knowledgeSummaryError = if (Test-HasValue $knowledgeSummaryError) { '{0} | updater: {1}' -f $knowledgeSummaryError, $updaterError } else { $updaterError }
                    }
                }
            }
        } catch {
            $knowledgeSummaryStatus = 'failed'
            if (-not (Test-HasValue $knowledgeSummaryError)) {
                $knowledgeSummaryError = $_.Exception.Message
            }

            try {
                $capture = Set-CaptureAnalyzerStatus -Capture $capture -AnalyzerStatus 'failed'
                Write-CaptureStateFiles -Capture $capture -ResolvedVaultPath $resolvedVaultPath -CaptureJsonInputPath $CaptureJsonPath
            } catch {
            }

            try {
                $knowledgeUpdateResult = Invoke-KnowledgeSummaryUpdater -NotePath $notePathFromRenderer -ResolvedVaultPath $resolvedVaultPath -ArtifactDirectory $artifactDirectory -AnalyzerStatus 'failed' -AnalysisJsonPath '' -KnowledgeNotePath ''
                if ([bool]$knowledgeUpdateResult.success) {
                    $updatedNotePath = Get-StringValue -Data $knowledgeUpdateResult -Name 'note_path' -DefaultValue ''
                    if (Test-HasValue $updatedNotePath) { $notePathFromRenderer = $updatedNotePath }
                } else {
                    $updaterError = Get-StringValue -Data $knowledgeUpdateResult -Name 'error_message' -DefaultValue ''
                    if (Test-HasValue $updaterError) {
                        $knowledgeSummaryError = if (Test-HasValue $knowledgeSummaryError) { '{0} | updater: {1}' -f $knowledgeSummaryError, $updaterError } else { $updaterError }
                    }
                }
            } catch {
                if (-not (Test-HasValue $knowledgeSummaryError)) {
                    $knowledgeSummaryError = $_.Exception.Message
                }
            }
        } finally {
            $script:ClipperCurrentStep = 'result_finalize'
        }
    }

    $result = [ordered]@{
        success = $true
        dry_run = [bool]$DryRun
        title = $note.title
        folder = $note.folder
        file_name = $note.file_name
        route = $detection.route
        platform = $detection.platform
        content_type = $detection.content_type
        capture_id = $captureIdForResult
        download_status = $downloadStatusForResult
        download_method = $downloadMethodForResult
        video_path = $videoPathForResult
        audio_path = $audioPathForResult
        audio_download_status = $audioDownloadStatusForResult
        transcript_status = $transcriptStatusForResult
        transcript_source = $transcriptSourceForResult
        asr_status = $asrStatusForResult
        asr_provider = $asrProviderForResult
        asr_normalization = $asrNormalizationForResult
        diarization_status = $diarizationStatusForResult
        diarization_provider = $diarizationProviderForResult
        sidecar_path = $sidecarPathForResult
        auth_action_required = $authActionRequiredForResult
        auth_failure_reason = $authFailureReasonForResult
        auth_refresh_command = $authRefreshCommandForResult
        auth_guidance_en = $authGuidanceEnForResult
        auth_guidance_zh = $authGuidanceZhForResult
        auth_session_state = $authSessionStateForResult
        auth_session_likely_valid = if ($null -ne $authSessionLikelyValidForResult) { [bool]$authSessionLikelyValidForResult } else { $null }
        capture_level = $captureLevelForResult
        fallback_reason = $fallbackReasonForResult
        tags = $note.tags
        note_preview = $note.note_body
        vault_path = $resolvedVaultPath
        source_url = $SourceUrl
        source_input_kind = $resolvedSourceInput.input_kind
        source_url_extracted = [bool]$resolvedSourceInput.extraction_applied
        knowledge_summary_attempted = $knowledgeSummaryAttempted
        knowledge_summary_status = $knowledgeSummaryStatus
        knowledge_summary_note_updated = $knowledgeSummaryNoteUpdated
        knowledge_note_path = $knowledgeNotePathForResult
        knowledge_analyzer_output_json_path = $knowledgeAnalyzerOutputJsonPath
        knowledge_analysis_input_path = $knowledgeAnalysisInputPath
    }
    $captureErrors = Get-DataValue -Data $capture -Name 'errors'
    if ($null -ne $captureErrors -and @($captureErrors).Count -gt 0) { $result.errors = @($captureErrors) }
    if (Test-HasValue $notePathFromRenderer) { $result.note_path = $notePathFromRenderer }
    if (Test-HasValue $knowledgeSummaryError) { $result.knowledge_summary_error = $knowledgeSummaryError }
    if (Test-HasValue $artifactDirectory) {
        $result.debug_directory = $artifactDirectory
        $result.support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
    }

    $resultObject = Add-RunFinalStatusFields -Result ([pscustomobject]$result)
    $summaryLines = Get-RunSummaryLines -Result $resultObject
    $json = $resultObject | ConvertTo-Json -Depth 20

    if (Test-HasValue $artifactDirectory) {
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-clipper-summary.txt') -Content ($summaryLines -join "`r`n")
        $rawJsonPath = if (Test-HasValue $OutputJsonPath) { $OutputJsonPath } else { Join-Path $artifactDirectory 'run-clipper.json' }
        Write-Utf8Text -Path $rawJsonPath -Content $json

        $supportBundleDirectory = New-Directory -Path (Join-Path $artifactDirectory 'support-bundle')
        $sanitizedResult = Get-SanitizedData -Value $resultObject
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper.json') -Content (($sanitizedResult | ConvertTo-Json -Depth 20))
        $sanitizedSummaryLines = @((Get-RunSummaryLines -Result ([pscustomobject]$sanitizedResult)) | ForEach-Object { Sanitize-Text -Text ([string]$_) })
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper-summary.txt') -Content ($sanitizedSummaryLines -join "`r`n")
    } elseif (Test-HasValue $OutputJsonPath) {
        Write-Utf8Text -Path $OutputJsonPath -Content $json
    }

    Write-RunSummary -Result $resultObject
    $json
} catch {
    if (-not (Test-HasValue $artifactDirectory)) {
        $artifactDirectory = Get-ArtifactDirectory -ExplicitDirectory $DebugDirectory -JsonPath $OutputJsonPath -DefaultDirectory $defaultDebugDirectory
    }
    $failure = [ordered]@{
        success = $false
        dry_run = [bool]$DryRun
        title = ''
        folder = ''
        file_name = ''
        route = ''
        platform = ''
        content_type = ''
        capture_id = ''
        download_status = ''
        download_method = ''
        video_path = ''
        vault_path = $resolvedVaultPath
        source_url = $SourceUrl
        failed_step = $script:ClipperCurrentStep
        error_message = $_.Exception.Message
        error_message_zh = ('Clipper [{0}] {1}{2}' -f $script:ClipperCurrentStep, (Zh '\u5931\u8d25\uff1a'), $_.Exception.Message)
    }
    if (Test-HasValue $artifactDirectory) {
        $failure.debug_directory = $artifactDirectory
        $failure.support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
    }
    $failureObject = Add-RunFinalStatusFields -Result ([pscustomobject]$failure)
    $summaryLines = Get-RunSummaryLines -Result $failureObject
    $json = $failureObject | ConvertTo-Json -Depth 20

    if (Test-HasValue $artifactDirectory) {
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-clipper-summary.txt') -Content ($summaryLines -join "`r`n")
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-clipper.json') -Content $json
        $supportBundleDirectory = New-Directory -Path (Join-Path $artifactDirectory 'support-bundle')
        $sanitizedFailure = Get-SanitizedData -Value $failureObject
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper.json') -Content (($sanitizedFailure | ConvertTo-Json -Depth 20))
        $sanitizedSummaryLines = @((Get-RunSummaryLines -Result ([pscustomobject]$sanitizedFailure)) | ForEach-Object { Sanitize-Text -Text ([string]$_) })
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-clipper-summary.txt') -Content ($sanitizedSummaryLines -join "`r`n")
    } elseif (Test-HasValue $OutputJsonPath) {
        Write-Utf8Text -Path $OutputJsonPath -Content $json
    }

    Write-RunSummary -Result $failureObject
    throw
}

