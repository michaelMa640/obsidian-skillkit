param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadJsonPath,
    [Parameter(Mandatory = $true)]
    [string]$VaultPath,
    [Parameter(Mandatory = $true)]
    [string]$Platform,
    [Parameter(Mandatory = $true)]
    [string]$SourceUrl,
    [string]$AttachmentsRoot = 'Attachments/ShortVideos',
    [string]$YtDlpCommand = 'yt-dlp',
    [string]$CookiesFile,
    [string]$StorageStatePath,
    [string]$XiaohongshuAdapterCommand = 'python',
    [string]$XiaohongshuAdapterScriptPath,
    [string]$XiaohongshuAdapterServerUrl = 'http://127.0.0.1:5556/xhs/detail',
    [int]$XiaohongshuAdapterTimeoutMs = 30000,
    [bool]$XiaohongshuAdapterSaveBackendPayload = $true,
    [string]$OutputJsonPath
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

function Zh {
    param([string]$Escaped)
    [regex]::Unescape($Escaped)
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

function Test-HasValue {
    param($Value)
    $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)
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

function Set-DataValue {
    param($Data, [string]$Name, $Value)
    if ($Data -is [System.Collections.IDictionary]) {
        $Data[$Name] = $Value
        return
    }
    $property = $Data.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Data | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $property.Value = $Value
    }
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

function Get-NestedStringValue {
    param($Data, [string]$PropertyName, [string]$DefaultValue = '')
    $value = Get-StringValue -Data $Data -Name $PropertyName -DefaultValue ''
    if (Test-HasValue $value) { return $value }
    $metadata = Get-DataValue -Data $Data -Name 'metadata'
    if ($null -ne $metadata) {
        return (Get-StringValue -Data $metadata -Name $PropertyName -DefaultValue $DefaultValue)
    }
    $DefaultValue
}

function Get-CollectionCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    if ($Value -is [System.Array]) { return @($Value).Count }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value).Count }
    if (Test-HasValue ([string]$Value)) { return 1 }
    0
}

function Test-LooksLikeInterstitialTitle {
    param([string]$Text)
    if (-not (Test-HasValue $Text)) { return $false }
    return ([regex]::IsMatch($Text, '(?i)captcha|verify'))
}

function Get-RecordRichnessScore {
    param($Record)
    if ($null -eq $Record) { return 0 }

    $score = 0
    $title = Get-StringValue -Data $Record -Name 'title' -DefaultValue ''
    $author = Get-StringValue -Data $Record -Name 'author' -DefaultValue ''
    $publishedAt = Get-StringValue -Data $Record -Name 'published_at' -DefaultValue ''
    $description = Get-StringValue -Data $Record -Name 'description' -DefaultValue ''
    $rawText = Get-StringValue -Data $Record -Name 'raw_text' -DefaultValue ''
    $coverUrl = Get-StringValue -Data $Record -Name 'cover_url' -DefaultValue ''
    $metricsLike = Get-StringValue -Data $Record -Name 'metrics_like' -DefaultValue ''
    $metricsComment = Get-StringValue -Data $Record -Name 'metrics_comment' -DefaultValue ''
    $metricsShare = Get-StringValue -Data $Record -Name 'metrics_share' -DefaultValue ''
    $metricsCollect = Get-StringValue -Data $Record -Name 'metrics_collect' -DefaultValue ''
    $images = Get-StringArrayValue -Data $Record -Name 'images'
    $videos = Get-StringArrayValue -Data $Record -Name 'videos'
    $candidateVideoRefs = Get-StringArrayValue -Data $Record -Name 'candidate_video_refs'
    $topComments = Get-StringArrayValue -Data $Record -Name 'top_comments'
    $comments = Get-DataValue -Data $Record -Name 'comments'

    if (Test-HasValue $title -and $title -notlike 'Social Clip*' -and -not (Test-LooksLikeInterstitialTitle -Text $title)) { $score += 2 }
    if (Test-HasValue $author -and $author -ne 'unknown') { $score += 1 }
    if (Test-HasValue $publishedAt -and $publishedAt -ne 'unknown') { $score += 1 }
    if (Test-HasValue $description) { $score += 2 }
    if (Test-HasValue $rawText -and $rawText.Length -ge 20) { $score += 1 }
    if (@($images).Count -gt 0) { $score += 1 }
    if (@($videos).Count -gt 0) { $score += 1 }
    if (@($candidateVideoRefs).Count -gt 0) { $score += 2 }
    if (Get-CollectionCount -Value $comments -gt 0 -or @($topComments).Count -gt 0) { $score += 2 }
    if ((Test-HasValue $metricsLike) -or (Test-HasValue $metricsComment) -or (Test-HasValue $metricsShare) -or (Test-HasValue $metricsCollect)) { $score += 2 }
    if (Test-HasValue $coverUrl) { $score += 1 }

    return $score
}

function Get-NormalizedRelativePath {
    param([string]$BasePath, [string]$TargetPath)
    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    if ($targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($targetFull.Substring($baseFull.Length).TrimStart('\', '/')) -replace '\\', '/'
    }
    $TargetPath -replace '\\', '/'
}

function Get-DownloadFileExtension {
    param([string]$Url, [string]$DefaultExtension = '.mp4')
    try {
        $path = ([System.Uri]$Url).AbsolutePath
        $extension = [System.IO.Path]::GetExtension($path)
        if (Test-HasValue $extension -and $extension.Length -le 6) { return $extension }
    } catch {
    }
    $DefaultExtension
}

function Get-CookieHeaderFromNetscapeFile {
    param([string]$EffectiveCookiesFile)
    if (-not (Test-HasValue $EffectiveCookiesFile) -or -not (Test-Path $EffectiveCookiesFile)) { return '' }
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach ($rawLine in Get-Content -LiteralPath $EffectiveCookiesFile -ErrorAction SilentlyContinue) {
        $line = [string]$rawLine
        if (-not (Test-HasValue $line) -or $line.StartsWith('#')) { continue }
        $parts = $line -split "`t"
        if ($parts.Length -lt 7) { continue }
        $name = [string]$parts[$parts.Length - 2]
        $value = [string]$parts[$parts.Length - 1]
        if (Test-HasValue $name) { $pairs.Add("$name=$value") | Out-Null }
    }
    return ($pairs -join '; ')
}

function Invoke-DirectMediaDownload {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$Referer,
        [string]$Origin,
        [string]$CookieHeader
    )
    $headers = @{
        'Referer' = $Referer
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    }
    if (Test-HasValue $Origin) {
        $headers['Origin'] = $Origin
    }
    if (Test-HasValue $CookieHeader) {
        $headers['Cookie'] = $CookieHeader
    }
    Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -Headers $headers -UseBasicParsing
}

function Add-ResolvedMediaCandidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Url,
        [string]$Source = 'record',
        [string]$Method = 'direct',
        [int]$Priority = 100
    )
    if (-not (Test-HasValue $Url)) { return }
    $trimmedUrl = $Url.Trim()
    if (-not $trimmedUrl.StartsWith('http')) { return }
    if ($trimmedUrl.StartsWith('blob:')) { return }
    foreach ($existing in @($Candidates)) {
        if ($null -eq $existing) { continue }
        if ([string]$existing.url -eq $trimmedUrl) { return }
    }
    $Candidates.Add([ordered]@{
        url = $trimmedUrl
        source = $Source
        method = $Method
        priority = $Priority
    }) | Out-Null
}

function Get-ResolvedMediaCandidatesFromRecord {
    param(
        $Record,
        [string]$PlatformName = ''
    )
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $canonicalVideoUrl = Get-StringValue -Data $Record -Name 'canonical_video_url' -DefaultValue ''
    $preferredMethod = if ($PlatformName -eq 'xiaohongshu') { 'xiaohongshu-extractor' } else { 'playwright' }
    Add-ResolvedMediaCandidate -Candidates $candidates -Url $canonicalVideoUrl -Source 'canonical_video_url' -Method $preferredMethod -Priority 10
    foreach ($candidate in @(Get-StringArrayValue -Data $Record -Name 'candidate_video_refs')) {
        Add-ResolvedMediaCandidate -Candidates $candidates -Url $candidate -Source 'candidate_video_refs' -Method $preferredMethod -Priority 20
    }
    foreach ($candidate in @(Get-StringArrayValue -Data $Record -Name 'videos')) {
        Add-ResolvedMediaCandidate -Candidates $candidates -Url $candidate -Source 'videos' -Method $preferredMethod -Priority 30
    }
    return @($candidates | Sort-Object priority, source, url)
}

function Invoke-ResolvedMediaCandidatesDownload {
    param(
        [object[]]$Candidates,
        [string]$AttachmentDirectory,
        [string]$Referer,
        [string]$Origin,
        [string]$CookieHeader,
        [System.Collections.Generic.List[string]]$Errors,
        [System.Collections.Generic.List[string]]$Fallbacks
    )
    foreach ($candidate in @($Candidates)) {
        if ($null -eq $candidate) { continue }
        $candidateUrl = [string]$candidate.url
        if (-not (Test-HasValue $candidateUrl)) { continue }
        try {
            $sourceName = Get-StringValue -Data $candidate -Name 'source' -DefaultValue 'resolved'
            $methodName = Get-StringValue -Data $candidate -Name 'method' -DefaultValue 'direct'
            $sanitizedSource = ($sourceName -replace '[^a-zA-Z0-9_-]', '-').ToLowerInvariant()
            if (-not (Test-HasValue $sanitizedSource)) { $sanitizedSource = 'resolved' }
            $extension = Get-DownloadFileExtension -Url $candidateUrl
            $destinationPath = Join-Path $AttachmentDirectory ("video-" + $sanitizedSource + $extension)
            Invoke-DirectMediaDownload -Url $candidateUrl -DestinationPath $destinationPath -Referer $Referer -Origin $Origin -CookieHeader $CookieHeader
            if ((Test-Path $destinationPath) -and ((Get-Item -LiteralPath $destinationPath).Length -gt 0)) {
                return [ordered]@{
                    success = $true
                    video_file = Get-Item -LiteralPath $destinationPath
                    download_method = $methodName
                    resolved_from = $sourceName
                    resolved_url = $candidateUrl
                }
            }
        } catch {
            if ($null -ne $Errors) {
                $Errors.Add("Resolved media download failed for candidate ref: $candidateUrl")
            }
        }
    }

    return [ordered]@{
        success = $false
        video_file = $null
        download_method = 'none'
        resolved_from = ''
        resolved_url = ''
    }
}

function Invoke-PlatformMediaBackend {
    param(
        [string]$PlatformName,
        [string]$Command,
        [string]$ScriptPath,
        [string]$SourceUrl,
        [string]$NormalizedUrl,
        [string]$CaptureId,
        [string]$AttachmentDirectory,
        [string]$CookiesPath,
        [string]$StorageState,
        [string]$ServerUrl,
        [int]$TimeoutMs,
        [bool]$SaveBackendPayload
    )
    if ($PlatformName -eq 'xiaohongshu') {
        $result = Invoke-XiaohongshuAdapter `
            -Command $Command `
            -ScriptPath $ScriptPath `
            -SourceUrl $SourceUrl `
            -NormalizedUrl $NormalizedUrl `
            -CaptureId $CaptureId `
            -AttachmentDirectory $AttachmentDirectory `
            -CookiesPath $CookiesPath `
            -StorageState $StorageState `
            -ServerUrl $ServerUrl `
            -TimeoutMs $TimeoutMs `
            -SaveBackendPayload $SaveBackendPayload
        return [ordered]@{
            attempted = $true
            backend_name = 'xhs-downloader'
            backend_status = Get-StringValue -Data $result -Name 'download_status' -DefaultValue ''
            backend_error_code = Get-StringValue -Data $result -Name 'backend_error_code' -DefaultValue ''
            backend_error_message = Get-StringValue -Data $result -Name 'backend_error_message' -DefaultValue ''
            backend_payload_path = Get-StringValue -Data $result -Name 'backend_payload_path' -DefaultValue ''
            backend_status_code = $(try { [int](Get-DataValue -Data $result -Name 'backend_status_code') } catch { 0 })
            download_status = Get-StringValue -Data $result -Name 'download_status' -DefaultValue ''
            download_method = Get-StringValue -Data $result -Name 'download_method' -DefaultValue ''
            video_path = Get-StringValue -Data $result -Name 'video_path' -DefaultValue ''
            errors = @((Get-DataValue -Data $result -Name 'errors'))
            fallbacks = @((Get-DataValue -Data $result -Name 'fallbacks'))
            resolved_media_candidates = @()
        }
    }

    return [ordered]@{
        attempted = $false
        backend_name = ''
        backend_status = ''
        backend_error_code = ''
        backend_error_message = ''
        backend_payload_path = ''
        backend_status_code = 0
        download_status = ''
        download_method = ''
        video_path = ''
        errors = @()
        fallbacks = @()
        resolved_media_candidates = @()
    }
}

function Get-VideoFile {
    param([string]$Directory)
    Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like 'video*' } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-CoverFile {
    param([string]$Directory)
    Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like 'cover*' } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-YtDlpMetadata {
    param([string]$Command, [string]$Url, [string[]]$ExtraArgs = @())
    try {
        $arguments = @('--dump-single-json', '--skip-download', '--no-warnings', '--no-playlist')
        if ($null -ne $ExtraArgs -and @($ExtraArgs).Count -gt 0) {
            $arguments += $ExtraArgs
        }
        $arguments += $Url
        $output = & $Command @arguments 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        $text = ($output | Out-String).Trim()
        if (-not (Test-HasValue $text)) { return $null }
        return (ConvertFrom-JsonCompat -Json $text -Depth 100)
    } catch {
        return $null
    }
}

function Export-StorageStateCookiesFile {
    param(
        [string]$StorageStatePath,
        [string]$OutputPath
    )
    if (-not (Test-HasValue $StorageStatePath) -or -not (Test-Path $StorageStatePath)) { return '' }
    $storageState = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $StorageStatePath) -Depth 100
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Netscape HTTP Cookie File')
    foreach ($cookie in @($storageState.cookies)) {
        if ($null -eq $cookie) { continue }
        $domain = [string]$cookie.domain
        $name = [string]$cookie.name
        $value = [string]$cookie.value
        if (-not (Test-HasValue $domain) -or -not (Test-HasValue $name)) { continue }
        $includeSubdomains = if ($domain.StartsWith('.')) { 'TRUE' } else { 'FALSE' }
        $pathValue = if (Test-HasValue ([string]$cookie.path)) { [string]$cookie.path } else { '/' }
        $isSecure = if ($cookie.secure -eq $true) { 'TRUE' } else { 'FALSE' }
        $expires = 0
        if ($null -ne $cookie.expires) {
            try {
                $expiresNumeric = [double]$cookie.expires
                if ($expiresNumeric -gt 0) { $expires = [int64][Math]::Floor($expiresNumeric) }
            } catch {
            }
        }
        $domainValue = if ($cookie.httpOnly -eq $true) { '#HttpOnly_' + $domain } else { $domain }
        $lines.Add("$domainValue`t$includeSubdomains`t$pathValue`t$isSecure`t$expires`t$name`t$value")
    }
    Write-Utf8Text -Path $OutputPath -Content ($lines -join "`r`n")
    $OutputPath
}

function Get-YtDlpAuthArguments {
    param([string]$EffectiveCookiesFile)
    if (Test-HasValue $EffectiveCookiesFile) {
        return @('--cookies', $EffectiveCookiesFile)
    }
    @()
}

function Invoke-XiaohongshuAdapter {
    param(
        [string]$Command,
        [string]$ScriptPath,
        [string]$SourceUrl,
        [string]$NormalizedUrl,
        [string]$CaptureId,
        [string]$AttachmentDirectory,
        [string]$CookiesPath,
        [string]$StorageState,
        [string]$ServerUrl,
        [int]$TimeoutMs,
        [bool]$SaveBackendPayload
    )
    if (-not (Test-HasValue $ScriptPath) -or -not (Test-Path $ScriptPath)) {
        return [ordered]@{
            success = $false
            download_status = 'failed'
            download_method = 'none'
            video_path = ''
            backend_error_code = 'backend_script_missing'
            backend_error_message = "Xiaohongshu adapter script was not found: $ScriptPath"
            backend_payload_path = ''
            backend_status_code = 0
            errors = @("Xiaohongshu adapter script was not found: $ScriptPath")
            fallbacks = @('xhs_adapter_missing')
        }
    }

    $outputPath = Join-Path $AttachmentDirectory 'xhs-downloader-result.json'
    $backendPayloadPath = if ($SaveBackendPayload) { Join-Path $AttachmentDirectory 'xhs-downloader-response.json' } else { '' }
    $arguments = @(
        $ScriptPath,
        '--source-url', $SourceUrl,
        '--normalized-url', $NormalizedUrl,
        '--capture-id', $CaptureId,
        '--attachment-dir', $AttachmentDirectory,
        '--server-url', $ServerUrl,
        '--timeout-ms', ([string]$TimeoutMs),
        '--output-json', $outputPath
    )
    if (Test-HasValue $CookiesPath) { $arguments += @('--cookies-file', $CookiesPath) }
    if (Test-HasValue $StorageState) { $arguments += @('--storage-state-path', $StorageState) }
    if (Test-HasValue $backendPayloadPath) { $arguments += @('--backend-payload-path', $backendPayloadPath) }

    try {
        & $Command @arguments 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Xiaohongshu adapter exited with code $LASTEXITCODE."
        }
        if (-not (Test-Path $outputPath)) {
            throw 'Xiaohongshu adapter did not write its JSON output.'
        }
        $payload = Read-Utf8Text -Path $outputPath
        if (-not (Test-HasValue $payload)) {
            throw 'Xiaohongshu adapter returned an empty payload.'
        }
        return (ConvertFrom-JsonCompat -Json $payload -Depth 100)
    } catch {
        return [ordered]@{
            success = $false
            download_status = 'failed'
            download_method = 'none'
            video_path = ''
            backend_error_code = 'backend_invoke_failed'
            backend_error_message = $_.Exception.Message
            backend_payload_path = $backendPayloadPath
            backend_status_code = 0
            errors = @($_.Exception.Message)
            fallbacks = @('xhs_adapter_invoke_failed')
        }
    }
}

function Test-IsAuthRefreshRequired {
    param([string[]]$Errors)
    foreach ($entry in @($Errors)) {
        $text = [string]$entry
        if (-not (Test-HasValue $text)) { continue }
        if (
            $text -match '(?i)Fresh cookies are needed' -or
            $text -match '(?i)login required' -or
            $text -match '(?i)cookies file was not found' -or
            $text -match '(?i)storage state file was not found'
        ) {
            return $true
        }
    }
    $false
}

function Get-VideoTechnicalMetadata {
    param([string]$VideoPath, $YtMetadata)
    $result = [ordered]@{
        video_duration_seconds = 0
        video_width = 0
        video_height = 0
    }
    $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($null -ne $ffprobe) {
        try {
            $probeJson = & $ffprobe.Source '-v' 'quiet' '-print_format' 'json' '-show_format' '-show_streams' $VideoPath 2>&1
            $probeText = ($probeJson | Out-String).Trim()
            if (Test-HasValue $probeText) {
                $probe = ConvertFrom-JsonCompat -Json $probeText -Depth 100
                $videoStream = @($probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1)[0]
                if ($null -ne $videoStream) {
                    if ($null -ne $videoStream.width) { $result.video_width = [int]$videoStream.width }
                    if ($null -ne $videoStream.height) { $result.video_height = [int]$videoStream.height }
                }
                if ($null -ne $probe.format -and $null -ne $probe.format.duration) { $result.video_duration_seconds = [double]$probe.format.duration }
                return $result
            }
        } catch {
        }
    }
    if ($null -ne $YtMetadata) {
        if ($null -ne $YtMetadata.duration) { $result.video_duration_seconds = [double]$YtMetadata.duration }
        if ($null -ne $YtMetadata.width) { $result.video_width = [int]$YtMetadata.width }
        if ($null -ne $YtMetadata.height) { $result.video_height = [int]$YtMetadata.height }
    }
    $result
}

$record = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $PayloadJsonPath) -Depth 100
$captureId = Get-StringValue -Data $record -Name 'capture_id' -DefaultValue ''
if (-not (Test-HasValue $captureId)) { throw 'Payload is missing capture_id.' }

$attachmentRootPath = Join-Path $VaultPath $AttachmentsRoot
$attachmentDir = Join-Path (Join-Path $attachmentRootPath $Platform) $captureId
New-Item -ItemType Directory -Path $attachmentDir -Force | Out-Null
$existingVideoFile = Get-VideoFile -Directory $attachmentDir
$existingCaptureRecord = $null
$existingCaptureSidecarPath = Join-Path $attachmentDir 'capture.json'
if (Test-Path $existingCaptureSidecarPath) {
    try {
        $existingCaptureRecord = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $existingCaptureSidecarPath) -Depth 100
    } catch {
        $existingCaptureRecord = $null
    }
}

$errors = New-Object System.Collections.Generic.List[string]
$fallbacks = New-Object System.Collections.Generic.List[string]
$currentRecordScore = Get-RecordRichnessScore -Record $record
$existingRecordScore = Get-RecordRichnessScore -Record $existingCaptureRecord
$existingCaptureId = if ($null -ne $existingCaptureRecord) { Get-StringValue -Data $existingCaptureRecord -Name 'capture_id' -DefaultValue '' } else { '' }
if (
    ($null -ne $existingCaptureRecord) -and
    (Test-HasValue $existingCaptureId) -and
    ($existingCaptureId -eq $captureId) -and
    ($existingRecordScore -gt ($currentRecordScore + 2))
) {
    $record = $existingCaptureRecord
    $fallbacks.Add('existing_capture_reused')
}
$downloadOutput = ''
$videoFile = $null
$downloadMethod = 'none'
$downloadStatus = 'failed'
$generatedCookiesFile = ''
$effectiveCookiesFile = ''
$ytDlpAuthMode = 'none'
$authActionRequired = ''
$authFailureReason = ''
$authRefreshCommand = ''
$authGuidanceEn = ''
$authGuidanceZh = ''
$xiaohongshuAdapterAttempted = $false
$xiaohongshuAdapterStatus = ''
$xiaohongshuAdapterErrorCode = ''
$xiaohongshuAdapterErrorMessage = ''
$xiaohongshuAdapterPayloadPath = ''
$xiaohongshuAdapterStatusCode = 0
$mediaBackendAttempted = $false
$mediaBackendName = ''
$mediaBackendStatus = ''
$mediaBackendErrorCode = ''
$mediaBackendErrorMessage = ''
$mediaBackendPayloadPath = ''
$mediaBackendStatusCode = 0
$mediaBackendTriggerReason = ''
$resolvedMediaCandidates = @()
$resolvedMediaFrom = ''
$resolvedMediaUrl = ''
$resolvedMediaDownloadAttempted = $false
$resolvedMediaDownloadFailed = $false

$storageStateAvailable = ((Test-HasValue $StorageStatePath) -and (Test-Path $StorageStatePath))
$cookiesFileAvailable = ((Test-HasValue $CookiesFile) -and (Test-Path $CookiesFile))
if ($cookiesFileAvailable) {
    $effectiveCookiesFile = $CookiesFile
    $ytDlpAuthMode = if ($storageStateAvailable) { 'storage_state+cookies_file' } else { 'cookies_file' }
} elseif ($storageStateAvailable) {
    $generatedCookiesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("obsidian-clipper-" + $captureId + "-cookies.txt")
    $effectiveCookiesFile = Export-StorageStateCookiesFile -StorageStatePath $StorageStatePath -OutputPath $generatedCookiesFile
    if ((Test-HasValue $effectiveCookiesFile) -and (Test-Path $effectiveCookiesFile)) {
        $ytDlpAuthMode = 'storage_state'
    }
}
if ((Test-HasValue $CookiesFile) -and -not $cookiesFileAvailable) {
    $errors.Add("Configured cookies file was not found: $CookiesFile")
}
if ((Test-HasValue $StorageStatePath) -and -not $storageStateAvailable) {
    $errors.Add("Configured storage state file was not found: $StorageStatePath")
}
$ytDlpAuthArgs = Get-YtDlpAuthArguments -EffectiveCookiesFile $effectiveCookiesFile
$cookieHeader = Get-CookieHeaderFromNetscapeFile -EffectiveCookiesFile $effectiveCookiesFile
$downloadUrl = Get-StringValue -Data $record -Name 'normalized_url' -DefaultValue ''
if (-not (Test-HasValue $downloadUrl)) {
    $downloadUrl = Get-StringValue -Data $record -Name 'source_url' -DefaultValue $SourceUrl
}
if (-not (Test-HasValue $downloadUrl)) {
    $downloadUrl = $SourceUrl
}
$downloadReferer = if (Test-HasValue $downloadUrl) { $downloadUrl } else { $SourceUrl }
$downloadOrigin = ''
try {
    $downloadOrigin = ([System.Uri]$downloadReferer).GetLeftPart([System.UriPartial]::Authority)
} catch {
    $downloadOrigin = ''
}
$accessBlockType = Get-NestedStringValue -Data $record -PropertyName 'access_block_type'
$accessBlockCode = Get-NestedStringValue -Data $record -PropertyName 'access_block_error_code'
$accessBlockMessage = Get-NestedStringValue -Data $record -PropertyName 'access_block_error_message'
$accessBlocked = ((Test-HasValue $accessBlockType) -or ((Get-NestedStringValue -Data $record -PropertyName 'auth_failure_reason') -like 'xiaohongshu_*'))
$shouldSkipDownload = $false
$ytMetadata = $null

function Invoke-YtDlpVideoDownload {
    param(
        [string]$Command,
        [string]$Url,
        [string]$AttachmentDirectory,
        [string[]]$AuthArgs = @()
    )
    $videoTemplate = Join-Path $AttachmentDirectory 'video.%(ext)s'
    $downloadArguments = @('--no-playlist', '--no-warnings')
    if ($null -ne $AuthArgs -and @($AuthArgs).Count -gt 0) {
        $downloadArguments += $AuthArgs
    }
    $downloadArguments += @('-o', $videoTemplate, $Url)
    $downloadOutputText = (& $Command @downloadArguments 2>&1 | Out-String)
    $downloadedVideoFile = $null
    if ($LASTEXITCODE -eq 0) {
        $downloadedVideoFile = Get-VideoFile -Directory $AttachmentDirectory
        if ($null -eq $downloadedVideoFile) {
            throw 'yt-dlp completed but no downloaded video file was found.'
        }
    } else {
        throw "yt-dlp download failed with exit code $LASTEXITCODE."
    }

    [ordered]@{
        output_text = $downloadOutputText
        video_file = $downloadedVideoFile
    }
}

if ($Platform -eq 'xiaohongshu' -and $accessBlocked) {
    $downloadStatus = 'blocked'
    $downloadMethod = 'none'
    $authActionRequired = 'switch_xiaohongshu_network'
    $authFailureReason = if ($accessBlockType -eq 'ip_risk') { 'xiaohongshu_ip_risk_blocked' } else { 'xiaohongshu_website_error' }
    $authGuidanceEn = if ($accessBlockType -eq 'ip_risk') {
        'Xiaohongshu blocked this request with an IP risk page. Switch to a trusted network environment and retry.'
    } else {
        'Xiaohongshu redirected this request to a website error page before the real note loaded.'
    }
    $authGuidanceZh = if ($accessBlockType -eq 'ip_risk') {
        Zh '\u5c0f\u7ea2\u4e66\u5c06\u8fd9\u6b21\u8bf7\u6c42\u62e6\u622a\u4e3a IP \u98ce\u9669\uff0c\u8bf7\u5207\u6362\u5230\u53ef\u4fe1\u7f51\u7edc\u73af\u5883\u540e\u91cd\u8bd5\u3002'
    } else {
        Zh '\u5c0f\u7ea2\u4e66\u5728\u771f\u5b9e\u7b14\u8bb0\u9875\u52a0\u8f7d\u524d\u8df3\u8f6c\u5230\u4e86\u7ad9\u70b9\u9519\u8bef\u9875\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002'
    }
    $reasonParts = @($authGuidanceZh)
    if (Test-HasValue $accessBlockCode) { $reasonParts += "error_code=$accessBlockCode" }
    if (Test-HasValue $accessBlockMessage) { $reasonParts += $accessBlockMessage }
    $errors.Add(($reasonParts -join ' | '))
    $fallbacks.Add('xiaohongshu_access_blocked')
    $shouldSkipDownload = $true
}

if (-not $shouldSkipDownload) {
    $ytMetadata = Get-YtDlpMetadata -Command $YtDlpCommand -Url $downloadUrl -ExtraArgs $ytDlpAuthArgs
}

$resolvedMediaCandidates = Get-ResolvedMediaCandidatesFromRecord -Record $record -PlatformName $Platform

if ($null -eq $videoFile -and -not $shouldSkipDownload) {
    $resolvedMediaDownloadAttempted = (@($resolvedMediaCandidates).Count -gt 0)
    $resolvedMediaResult = Invoke-ResolvedMediaCandidatesDownload `
        -Candidates $resolvedMediaCandidates `
        -AttachmentDirectory $attachmentDir `
        -Referer $downloadReferer `
        -Origin $downloadOrigin `
        -CookieHeader $cookieHeader `
        -Errors $errors `
        -Fallbacks $fallbacks
    if ($resolvedMediaResult.success -eq $true) {
        $videoFile = $resolvedMediaResult.video_file
        $downloadMethod = [string]$resolvedMediaResult.download_method
        $downloadStatus = 'success'
        $resolvedMediaFrom = [string]$resolvedMediaResult.resolved_from
        $resolvedMediaUrl = [string]$resolvedMediaResult.resolved_url
        if (Test-HasValue $resolvedMediaFrom) {
            $fallbacks.Add("resolved_media:$resolvedMediaFrom")
        }
    } elseif ($resolvedMediaDownloadAttempted) {
        $resolvedMediaDownloadFailed = $true
    }
}

if ($null -eq $videoFile -and -not $shouldSkipDownload -and $Platform -eq 'xiaohongshu') {
    if (@($resolvedMediaCandidates).Count -eq 0) {
        $mediaBackendTriggerReason = 'resolved_media_missing'
    } elseif ($resolvedMediaDownloadFailed) {
        $mediaBackendTriggerReason = 'resolved_media_download_failed'
    } else {
        $mediaBackendTriggerReason = 'fallback_requested'
    }
    if (-not (Test-HasValue $XiaohongshuAdapterScriptPath)) {
        $XiaohongshuAdapterScriptPath = Join-Path $PSScriptRoot 'xiaohongshu_downloader_adapter.py'
    }
    $backendResult = Invoke-PlatformMediaBackend `
        -PlatformName $Platform `
        -Command $XiaohongshuAdapterCommand `
        -ScriptPath $XiaohongshuAdapterScriptPath `
        -SourceUrl $SourceUrl `
        -NormalizedUrl $downloadUrl `
        -CaptureId $captureId `
        -AttachmentDirectory $attachmentDir `
        -CookiesPath $CookiesFile `
        -StorageState $StorageStatePath `
        -ServerUrl $XiaohongshuAdapterServerUrl `
        -TimeoutMs $XiaohongshuAdapterTimeoutMs `
        -SaveBackendPayload $XiaohongshuAdapterSaveBackendPayload

    $mediaBackendAttempted = [bool]$backendResult.attempted
    $mediaBackendName = Get-StringValue -Data $backendResult -Name 'backend_name' -DefaultValue ''
    $mediaBackendStatus = Get-StringValue -Data $backendResult -Name 'backend_status' -DefaultValue ''
    $mediaBackendErrorCode = Get-StringValue -Data $backendResult -Name 'backend_error_code' -DefaultValue ''
    $mediaBackendErrorMessage = Get-StringValue -Data $backendResult -Name 'backend_error_message' -DefaultValue ''
    $mediaBackendPayloadPath = Get-StringValue -Data $backendResult -Name 'backend_payload_path' -DefaultValue ''
    try {
        $mediaBackendStatusCode = [int](Get-DataValue -Data $backendResult -Name 'backend_status_code')
    } catch {
        $mediaBackendStatusCode = 0
    }

    foreach ($adapterError in @(Get-DataValue -Data $backendResult -Name 'errors')) {
        if (Test-HasValue ([string]$adapterError)) { $errors.Add([string]$adapterError) }
    }
    foreach ($adapterFallback in @(Get-DataValue -Data $backendResult -Name 'fallbacks')) {
        if (Test-HasValue ([string]$adapterFallback)) { $fallbacks.Add([string]$adapterFallback) }
    }

    $adapterVideoPath = Get-StringValue -Data $backendResult -Name 'video_path' -DefaultValue ''
    if (Test-HasValue $adapterVideoPath -and (Test-Path $adapterVideoPath)) {
        $videoFile = Get-Item -LiteralPath $adapterVideoPath
        $downloadMethod = Get-StringValue -Data $backendResult -Name 'download_method' -DefaultValue 'backend'
        $downloadStatus = 'success'
        $resolvedMediaFrom = if (Test-HasValue $mediaBackendName) { "backend:$mediaBackendName" } else { 'backend' }
        $resolvedMediaUrl = ''
        if (Test-HasValue $mediaBackendName) {
            $fallbacks.Add("media_backend:$mediaBackendName")
        }
    }
}

if ($null -eq $videoFile -and -not $shouldSkipDownload) {
    try {
        $ytDlpResult = Invoke-YtDlpVideoDownload -Command $YtDlpCommand -Url $downloadUrl -AttachmentDirectory $attachmentDir -AuthArgs $ytDlpAuthArgs
        $downloadOutput = [string]$ytDlpResult.output_text
        $videoFile = $ytDlpResult.video_file
        if ($null -ne $videoFile) {
            $downloadMethod = 'yt-dlp'
            $downloadStatus = 'success'
        }
    } catch {
        $errors.Add($_.Exception.Message)
        $fallbacks.Add('yt-dlp_failed')
    }
}

if ($null -eq $videoFile -and -not $shouldSkipDownload -and $null -ne $existingVideoFile -and $existingVideoFile.Length -gt 0) {
    $videoFile = $existingVideoFile
    $existingDownloadMethod = if ($null -ne $existingCaptureRecord) { Get-StringValue -Data $existingCaptureRecord -Name 'download_method' -DefaultValue '' } else { '' }
    if (-not (Test-HasValue $existingDownloadMethod) -or $existingDownloadMethod -eq 'none') { $existingDownloadMethod = 'existing' }
    $downloadStatus = 'success'
    $downloadMethod = $existingDownloadMethod
    $fallbacks.Add('existing_video_reused')
}

if ($null -eq $videoFile -and -not $shouldSkipDownload) {
    $downloadStatus = 'failed'
    $downloadMethod = 'none'
}

if (-not $shouldSkipDownload -and (Test-IsAuthRefreshRequired -Errors @($errors))) {
    $authActionRequired = 'refresh_douyin_auth'
    $authFailureReason = 'cookies_expired_or_missing'
    $authRefreshCommand = ('python "{0}" --platform douyin' -f (Join-Path $PSScriptRoot 'bootstrap_social_auth.py'))
    $authGuidanceEn = 'Douyin auth appears expired or missing. Refresh local auth and retry. Running the refresh command will open a browser window for login.'
    $authGuidanceZh = Zh '\u6296\u97f3\u767b\u5f55\u6001\u7591\u4f3c\u5df2\u8fc7\u671f\u6216\u7f3a\u5931\u3002\u8bf7\u5148\u5237\u65b0\u672c\u5730\u767b\u5f55\u6001\uff0c\u518d\u91cd\u65b0\u8fd0\u884c\u3002\u6267\u884c\u5237\u65b0\u547d\u4ee4\u65f6\u4f1a\u6253\u5f00\u6d4f\u89c8\u5668\u7528\u4e8e\u767b\u5f55\u3002'
}

if ($mediaBackendAttempted -and $mediaBackendName -eq 'xhs-downloader') {
    $xiaohongshuAdapterAttempted = $true
    $xiaohongshuAdapterStatus = $mediaBackendStatus
    $xiaohongshuAdapterErrorCode = $mediaBackendErrorCode
    $xiaohongshuAdapterErrorMessage = $mediaBackendErrorMessage
    $xiaohongshuAdapterPayloadPath = $mediaBackendPayloadPath
    $xiaohongshuAdapterStatusCode = $mediaBackendStatusCode
}

$coverUrl = Get-StringValue -Data $record -Name 'cover_url' -DefaultValue ''
if (-not (Test-HasValue $coverUrl)) {
    $images = Get-StringArrayValue -Data $record -Name 'images'
    if (@($images).Count -gt 0) { $coverUrl = [string]$images[0] }
}
$coverFile = $null
if (Test-HasValue $coverUrl -and $coverUrl.StartsWith('http')) {
    try {
        $coverExtension = Get-DownloadFileExtension -Url $coverUrl -DefaultExtension '.jpg'
        $coverPath = Join-Path $attachmentDir ("cover" + $coverExtension)
        $headers = @{ 'Referer' = $downloadReferer; 'User-Agent' = 'Mozilla/5.0' }
        if (Test-HasValue $downloadOrigin) {
            $headers['Origin'] = $downloadOrigin
        }
        Invoke-WebRequest -Uri $coverUrl -OutFile $coverPath -Headers $headers -UseBasicParsing
        if ((Test-Path $coverPath) -and ((Get-Item -LiteralPath $coverPath).Length -gt 0)) {
            $coverFile = Get-Item -LiteralPath $coverPath
        }
    } catch {
        $errors.Add('Cover download failed.')
    }
}
if ($null -eq $coverFile) {
    $coverFile = Get-CoverFile -Directory $attachmentDir
}

$videoPathRelative = ''
$videoSizeBytes = 0
$videoSha256 = ''
$videoTechnical = [ordered]@{ video_duration_seconds = 0; video_width = 0; video_height = 0 }
if ($null -ne $videoFile) {
    $videoPathRelative = Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $videoFile.FullName
    $videoSizeBytes = [int64]$videoFile.Length
    $videoSha256 = ((Get-FileHash -LiteralPath $videoFile.FullName -Algorithm SHA256).Hash).ToLowerInvariant()
    $videoTechnical = Get-VideoTechnicalMetadata -VideoPath $videoFile.FullName -YtMetadata $ytMetadata
}

$coverPathRelative = ''
if ($null -ne $coverFile) {
    $coverPathRelative = Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $coverFile.FullName
}

$sidecarCapturePath = Join-Path $attachmentDir 'capture.json'
$sidecarCommentsPath = Join-Path $attachmentDir 'comments.json'
$sidecarMetadataPath = Join-Path $attachmentDir 'metadata.json'
$sidecarCaptureRelative = Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $sidecarCapturePath
$sidecarCommentsRelative = Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $sidecarCommentsPath
$sidecarMetadataRelative = Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $sidecarMetadataPath
$xiaohongshuAdapterPayloadRelative = if (Test-HasValue $xiaohongshuAdapterPayloadPath) { Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $xiaohongshuAdapterPayloadPath } else { '' }
$mediaBackendPayloadRelative = if (Test-HasValue $mediaBackendPayloadPath) { Get-NormalizedRelativePath -BasePath $VaultPath -TargetPath $mediaBackendPayloadPath } else { '' }

Set-DataValue -Data $record -Name 'download_status' -Value $downloadStatus
Set-DataValue -Data $record -Name 'download_method' -Value $downloadMethod
Set-DataValue -Data $record -Name 'resolved_media_candidates' -Value @($resolvedMediaCandidates)
Set-DataValue -Data $record -Name 'resolved_media_source' -Value $resolvedMediaFrom
Set-DataValue -Data $record -Name 'resolved_media_url' -Value $resolvedMediaUrl
Set-DataValue -Data $record -Name 'media_downloaded' -Value ([bool]($null -ne $videoFile))
Set-DataValue -Data $record -Name 'video_path' -Value $videoPathRelative
Set-DataValue -Data $record -Name 'video_storage_url' -Value ''
Set-DataValue -Data $record -Name 'cover_path' -Value $coverPathRelative
Set-DataValue -Data $record -Name 'sidecar_path' -Value $sidecarCaptureRelative
Set-DataValue -Data $record -Name 'comments_path' -Value $sidecarCommentsRelative
Set-DataValue -Data $record -Name 'metadata_path' -Value $sidecarMetadataRelative
Set-DataValue -Data $record -Name 'video_size_bytes' -Value $videoSizeBytes
Set-DataValue -Data $record -Name 'video_sha256' -Value $videoSha256
Set-DataValue -Data $record -Name 'video_duration_seconds' -Value $videoTechnical.video_duration_seconds
Set-DataValue -Data $record -Name 'video_width' -Value $videoTechnical.video_width
Set-DataValue -Data $record -Name 'video_height' -Value $videoTechnical.video_height
$recordStatus = if ($downloadStatus -eq 'blocked') { 'blocked' } else { 'clipped' }
Set-DataValue -Data $record -Name 'status' -Value $recordStatus
Set-DataValue -Data $record -Name 'yt_dlp_auth_mode' -Value $ytDlpAuthMode
Set-DataValue -Data $record -Name 'yt_dlp_cookies_file_used' -Value $effectiveCookiesFile
Set-DataValue -Data $record -Name 'yt_dlp_cookie_file_generated' -Value ([bool](Test-HasValue $generatedCookiesFile))
Set-DataValue -Data $record -Name 'auth_action_required' -Value $authActionRequired
Set-DataValue -Data $record -Name 'auth_failure_reason' -Value $authFailureReason
Set-DataValue -Data $record -Name 'auth_refresh_command' -Value $authRefreshCommand
Set-DataValue -Data $record -Name 'auth_guidance_en' -Value $authGuidanceEn
Set-DataValue -Data $record -Name 'auth_guidance_zh' -Value $authGuidanceZh
Set-DataValue -Data $record -Name 'media_backend_attempted' -Value $mediaBackendAttempted
Set-DataValue -Data $record -Name 'media_backend_name' -Value $mediaBackendName
Set-DataValue -Data $record -Name 'media_backend_status' -Value $mediaBackendStatus
Set-DataValue -Data $record -Name 'media_backend_error_code' -Value $mediaBackendErrorCode
Set-DataValue -Data $record -Name 'media_backend_error_message' -Value $mediaBackendErrorMessage
Set-DataValue -Data $record -Name 'media_backend_payload_path' -Value $mediaBackendPayloadRelative
Set-DataValue -Data $record -Name 'media_backend_status_code' -Value $mediaBackendStatusCode
Set-DataValue -Data $record -Name 'media_backend_trigger_reason' -Value $mediaBackendTriggerReason
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_attempted' -Value $xiaohongshuAdapterAttempted
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_status' -Value $xiaohongshuAdapterStatus
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_error_code' -Value $xiaohongshuAdapterErrorCode
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_error_message' -Value $xiaohongshuAdapterErrorMessage
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_payload_path' -Value $xiaohongshuAdapterPayloadRelative
Set-DataValue -Data $record -Name 'xiaohongshu_adapter_status_code' -Value $xiaohongshuAdapterStatusCode
if (-not (Test-HasValue (Get-StringValue -Data $record -Name 'analyzer_status'))) {
    Set-DataValue -Data $record -Name 'analyzer_status' -Value 'pending'
}
if (-not (Test-HasValue (Get-StringValue -Data $record -Name 'bitable_sync_status'))) {
    Set-DataValue -Data $record -Name 'bitable_sync_status' -Value 'pending'
}
Set-DataValue -Data $record -Name 'errors' -Value @($errors)
Set-DataValue -Data $record -Name 'fallbacks' -Value @($fallbacks)

$metadataObject = Get-DataValue -Data $record -Name 'metadata'
if ($null -eq $metadataObject) {
    $metadataObject = [ordered]@{}
    Set-DataValue -Data $record -Name 'metadata' -Value $metadataObject
}
foreach ($pair in @(
    @{ Name = 'capture_id'; Value = $captureId },
    @{ Name = 'download_status'; Value = $downloadStatus },
    @{ Name = 'download_method'; Value = $downloadMethod },
    @{ Name = 'resolved_media_source'; Value = $resolvedMediaFrom },
    @{ Name = 'resolved_media_url'; Value = $resolvedMediaUrl },
    @{ Name = 'media_downloaded'; Value = ([bool]($null -ne $videoFile)) },
    @{ Name = 'video_path'; Value = $videoPathRelative },
    @{ Name = 'cover_path'; Value = $coverPathRelative },
    @{ Name = 'sidecar_path'; Value = $sidecarCaptureRelative },
    @{ Name = 'comments_path'; Value = $sidecarCommentsRelative },
    @{ Name = 'metadata_path'; Value = $sidecarMetadataRelative },
    @{ Name = 'video_size_bytes'; Value = $videoSizeBytes },
    @{ Name = 'video_sha256'; Value = $videoSha256 },
    @{ Name = 'video_duration_seconds'; Value = $videoTechnical.video_duration_seconds },
    @{ Name = 'video_width'; Value = $videoTechnical.video_width },
    @{ Name = 'video_height'; Value = $videoTechnical.video_height },
    @{ Name = 'yt_dlp_auth_mode'; Value = $ytDlpAuthMode },
    @{ Name = 'yt_dlp_cookies_file_used'; Value = $effectiveCookiesFile },
    @{ Name = 'yt_dlp_cookie_file_generated'; Value = ([bool](Test-HasValue $generatedCookiesFile)) },
    @{ Name = 'auth_action_required'; Value = $authActionRequired },
    @{ Name = 'auth_failure_reason'; Value = $authFailureReason },
    @{ Name = 'auth_refresh_command'; Value = $authRefreshCommand },
    @{ Name = 'auth_guidance_en'; Value = $authGuidanceEn },
    @{ Name = 'auth_guidance_zh'; Value = $authGuidanceZh },
    @{ Name = 'media_backend_attempted'; Value = $mediaBackendAttempted },
    @{ Name = 'media_backend_name'; Value = $mediaBackendName },
    @{ Name = 'media_backend_status'; Value = $mediaBackendStatus },
    @{ Name = 'media_backend_error_code'; Value = $mediaBackendErrorCode },
    @{ Name = 'media_backend_error_message'; Value = $mediaBackendErrorMessage },
    @{ Name = 'media_backend_payload_path'; Value = $mediaBackendPayloadRelative },
    @{ Name = 'media_backend_status_code'; Value = $mediaBackendStatusCode },
    @{ Name = 'media_backend_trigger_reason'; Value = $mediaBackendTriggerReason },
    @{ Name = 'xiaohongshu_adapter_attempted'; Value = $xiaohongshuAdapterAttempted },
    @{ Name = 'xiaohongshu_adapter_status'; Value = $xiaohongshuAdapterStatus },
    @{ Name = 'xiaohongshu_adapter_error_code'; Value = $xiaohongshuAdapterErrorCode },
    @{ Name = 'xiaohongshu_adapter_error_message'; Value = $xiaohongshuAdapterErrorMessage },
    @{ Name = 'xiaohongshu_adapter_payload_path'; Value = $xiaohongshuAdapterPayloadRelative },
    @{ Name = 'xiaohongshu_adapter_status_code'; Value = $xiaohongshuAdapterStatusCode }
)) {
    Set-DataValue -Data $metadataObject -Name $pair.Name -Value $pair.Value
}

$metadataPayload = [ordered]@{
    capture_id = $captureId
    source_url = $SourceUrl
    platform = $Platform
    downloaded_at = (Get-Date).ToString('o')
    download_status = $downloadStatus
    download_method = $downloadMethod
    resolved_media_source = $resolvedMediaFrom
    resolved_media_url = $resolvedMediaUrl
    resolved_media_candidates = @($resolvedMediaCandidates)
    video_path = $videoPathRelative
    cover_path = $coverPathRelative
    video_size_bytes = $videoSizeBytes
    video_sha256 = $videoSha256
    video_duration_seconds = $videoTechnical.video_duration_seconds
    video_width = $videoTechnical.video_width
    video_height = $videoTechnical.video_height
    yt_dlp_auth_mode = $ytDlpAuthMode
    yt_dlp_cookies_file_used = $effectiveCookiesFile
    yt_dlp_cookie_file_generated = ([bool](Test-HasValue $generatedCookiesFile))
    auth_action_required = $authActionRequired
    auth_failure_reason = $authFailureReason
    auth_refresh_command = $authRefreshCommand
    auth_guidance_en = $authGuidanceEn
    auth_guidance_zh = $authGuidanceZh
    media_backend_attempted = $mediaBackendAttempted
    media_backend_name = $mediaBackendName
    media_backend_status = $mediaBackendStatus
    media_backend_error_code = $mediaBackendErrorCode
    media_backend_error_message = $mediaBackendErrorMessage
    media_backend_payload_path = $mediaBackendPayloadRelative
    media_backend_status_code = $mediaBackendStatusCode
    media_backend_trigger_reason = $mediaBackendTriggerReason
    xiaohongshu_adapter_attempted = $xiaohongshuAdapterAttempted
    xiaohongshu_adapter_status = $xiaohongshuAdapterStatus
    xiaohongshu_adapter_error_code = $xiaohongshuAdapterErrorCode
    xiaohongshu_adapter_error_message = $xiaohongshuAdapterErrorMessage
    xiaohongshu_adapter_payload_path = $xiaohongshuAdapterPayloadRelative
    xiaohongshu_adapter_status_code = $xiaohongshuAdapterStatusCode
    yt_dlp_output = $downloadOutput.Trim()
    errors = @($errors)
    fallbacks = @($fallbacks)
}

Write-Utf8Text -Path $sidecarCapturePath -Content ($record | ConvertTo-Json -Depth 100)
Write-Utf8Text -Path $sidecarCommentsPath -Content ((Get-DataValue -Data $record -Name 'comments') | ConvertTo-Json -Depth 50)
Write-Utf8Text -Path $sidecarMetadataPath -Content ($metadataPayload | ConvertTo-Json -Depth 50)
if ((Test-HasValue $generatedCookiesFile) -and (Test-Path $generatedCookiesFile)) {
    Remove-Item -LiteralPath $generatedCookiesFile -Force -ErrorAction SilentlyContinue
}

$output = $record | ConvertTo-Json -Depth 100
if (Test-HasValue $OutputJsonPath) {
    Write-Utf8Text -Path $OutputJsonPath -Content $output
}
$output
