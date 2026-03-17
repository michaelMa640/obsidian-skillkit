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
$downloadOutput = ''
$videoFile = $null
$downloadMethod = 'none'
$downloadStatus = 'failed'
$generatedCookiesFile = ''
$effectiveCookiesFile = ''
$ytDlpAuthMode = 'none'

$storageStateAvailable = Test-HasValue $StorageStatePath -and (Test-Path $StorageStatePath)
$cookiesFileAvailable = Test-HasValue $CookiesFile -and (Test-Path $CookiesFile)
if ($cookiesFileAvailable) {
    $effectiveCookiesFile = $CookiesFile
    $ytDlpAuthMode = if ($storageStateAvailable) { 'storage_state+cookies_file' } else { 'cookies_file' }
} elseif ($storageStateAvailable) {
    $generatedCookiesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("obsidian-clipper-" + $captureId + "-cookies.txt")
    $effectiveCookiesFile = Export-StorageStateCookiesFile -StorageStatePath $StorageStatePath -OutputPath $generatedCookiesFile
    if (Test-HasValue $effectiveCookiesFile -and (Test-Path $effectiveCookiesFile)) {
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
$ytMetadata = Get-YtDlpMetadata -Command $YtDlpCommand -Url $SourceUrl -ExtraArgs $ytDlpAuthArgs

try {
    $videoTemplate = Join-Path $attachmentDir 'video.%(ext)s'
    $downloadArguments = @('--no-playlist', '--no-warnings')
    if ($null -ne $ytDlpAuthArgs -and @($ytDlpAuthArgs).Count -gt 0) {
        $downloadArguments += $ytDlpAuthArgs
    }
    $downloadArguments += @('-o', $videoTemplate, $SourceUrl)
    $downloadOutput = (& $YtDlpCommand @downloadArguments 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) {
        $videoFile = Get-VideoFile -Directory $attachmentDir
        if ($null -ne $videoFile) {
            $downloadMethod = 'yt-dlp'
            $downloadStatus = 'success'
        } else {
            throw 'yt-dlp completed but no downloaded video file was found.'
        }
    } else {
        throw "yt-dlp download failed with exit code $LASTEXITCODE."
    }
} catch {
    $errors.Add($_.Exception.Message)
    $fallbacks.Add('yt-dlp_failed')
}

if ($null -eq $videoFile) {
    $candidateRefs = @()
    $candidateRefs += Get-StringArrayValue -Data $record -Name 'candidate_video_refs'
    if (@($candidateRefs).Count -eq 0) {
        $candidateRefs += Get-StringArrayValue -Data $record -Name 'videos'
    }
    foreach ($candidate in $candidateRefs) {
        if (-not (Test-HasValue $candidate)) { continue }
        if ($candidate.StartsWith('blob:')) { continue }
        if (-not $candidate.StartsWith('http')) { continue }
        try {
            $extension = Get-DownloadFileExtension -Url $candidate
            $fallbackVideoPath = Join-Path $attachmentDir ("video-playwright" + $extension)
            $headers = @{
                'Referer' = $SourceUrl
                'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
            }
            Invoke-WebRequest -Uri $candidate -OutFile $fallbackVideoPath -Headers $headers -UseBasicParsing
            if ((Test-Path $fallbackVideoPath) -and ((Get-Item -LiteralPath $fallbackVideoPath).Length -gt 0)) {
                $videoFile = Get-Item -LiteralPath $fallbackVideoPath
                $downloadMethod = 'playwright'
                $downloadStatus = 'success'
                $fallbacks.Add('playwright_candidate_ref')
                break
            }
        } catch {
            $errors.Add("Playwright fallback failed for candidate ref: $candidate")
        }
    }
}

if ($null -eq $videoFile -and $null -ne $existingVideoFile -and $existingVideoFile.Length -gt 0) {
    $videoFile = $existingVideoFile
    $existingDownloadMethod = if ($null -ne $existingCaptureRecord) { Get-StringValue -Data $existingCaptureRecord -Name 'download_method' -DefaultValue '' } else { '' }
    if (-not (Test-HasValue $existingDownloadMethod) -or $existingDownloadMethod -eq 'none') { $existingDownloadMethod = 'existing' }
    $downloadStatus = 'success'
    $downloadMethod = $existingDownloadMethod
    $fallbacks.Add('existing_video_reused')
}

if ($null -eq $videoFile) {
    $downloadStatus = 'failed'
    $downloadMethod = 'none'
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
        $headers = @{ 'Referer' = $SourceUrl; 'User-Agent' = 'Mozilla/5.0' }
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

Set-DataValue -Data $record -Name 'download_status' -Value $downloadStatus
Set-DataValue -Data $record -Name 'download_method' -Value $downloadMethod
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
Set-DataValue -Data $record -Name 'status' -Value 'clipped'
Set-DataValue -Data $record -Name 'yt_dlp_auth_mode' -Value $ytDlpAuthMode
Set-DataValue -Data $record -Name 'yt_dlp_cookies_file_used' -Value $effectiveCookiesFile
Set-DataValue -Data $record -Name 'yt_dlp_cookie_file_generated' -Value ([bool](Test-HasValue $generatedCookiesFile))
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
    @{ Name = 'yt_dlp_cookie_file_generated'; Value = ([bool](Test-HasValue $generatedCookiesFile)) }
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
    yt_dlp_output = $downloadOutput.Trim()
    errors = @($errors)
    fallbacks = @($fallbacks)
}

Write-Utf8Text -Path $sidecarCapturePath -Content ($record | ConvertTo-Json -Depth 100)
Write-Utf8Text -Path $sidecarCommentsPath -Content ((Get-DataValue -Data $record -Name 'comments') | ConvertTo-Json -Depth 50)
Write-Utf8Text -Path $sidecarMetadataPath -Content ($metadataPayload | ConvertTo-Json -Depth 50)
if (Test-HasValue $generatedCookiesFile -and (Test-Path $generatedCookiesFile)) {
    Remove-Item -LiteralPath $generatedCookiesFile -Force -ErrorAction SilentlyContinue
}

$output = $record | ConvertTo-Json -Depth 100
if (Test-HasValue $OutputJsonPath) {
    Write-Utf8Text -Path $OutputJsonPath -Content $output
}
$output