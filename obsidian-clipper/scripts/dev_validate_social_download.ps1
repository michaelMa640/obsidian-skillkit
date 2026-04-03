param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUrl,
    [string]$VaultPath,
    [string]$ConfigPath,
    [string]$OutputRoot,
    [switch]$SkipFullClipper
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
    $text = [string]$value
    if (Test-HasValue $text) { return $text }
    $DefaultValue
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

function New-Directory {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $Path
}

function Resolve-ConfigPath {
    param([string]$RequestedPath)
    if (Test-HasValue $RequestedPath) { return $RequestedPath }
    $localConfig = Join-Path $PSScriptRoot '..\references\local-config.json'
    if (Test-Path $localConfig) { return $localConfig }
    Join-Path $PSScriptRoot '..\references\local-config.example.json'
}

function Resolve-SocialScriptPath {
    param($Config)
    $configured = ''
    if ($null -ne $Config.routes -and $null -ne $Config.routes.social) {
        $configured = [string]$Config.routes.social.script
    }
    if (
        (Test-HasValue $configured) -and
        ($configured -notlike '*REPLACE/WITH/YOUR*') -and
        ($configured -notlike '*REPLACE\WITH\YOUR*') -and
        (Test-Path $configured)
    ) {
        return $configured
    }
    Join-Path $PSScriptRoot 'capture_social_playwright.py'
}

function Get-ConfiguredPathValue {
    param($Object, [string]$PropertyName)
    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return '' }
    $value = [string]$property.Value
    if (-not (Test-HasValue $value)) { return '' }
    if ($value -like '*REPLACE/WITH/YOUR*' -or $value -like '*REPLACE\WITH\YOUR*') { return '' }
    $value
}

function Get-SocialPlatformAuthConfig {
    param($Config, [string]$Platform)
    if ($null -eq $Config.routes -or $null -eq $Config.routes.social) { return $null }
    $authConfig = $Config.routes.social.auth
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

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    $output = ''
    $exitCode = 0
    $previousErrorActionPreference = $ErrorActionPreference
    $nativePreferenceExists = $null -ne (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($nativePreferenceExists) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
        $script:PSNativeCommandUseErrorActionPreference = $false
    }
    $script:ErrorActionPreference = 'Continue'
    try {
        $output = (& $Command @Arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    } catch {
        $output = $_ | Out-String
        $exitCode = 1
    } finally {
        $script:ErrorActionPreference = $previousErrorActionPreference
        if ($nativePreferenceExists) {
            $script:PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }
    Write-Utf8Text -Path $LogPath -Content $output.TrimEnd()
    [pscustomobject]@{
        command = $Command
        arguments = $Arguments
        exit_code = $exitCode
        success = ($exitCode -eq 0)
        log_path = $LogPath
        output_preview = if (Test-HasValue $output) { $output.Trim() } else { '' }
    }
}

function Get-RelativePath {
    param([string]$BasePath, [string]$TargetPath)
    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    if ($targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($targetFull.Substring($baseFull.Length).TrimStart('\', '/')) -replace '\\', '/'
    }
    $TargetPath -replace '\\', '/'
}

function Get-PreviewLine {
    param([string]$Text, [int]$MaxLength = 180)
    if (-not (Test-HasValue $Text)) { return '' }
    $line = (($Text -split "`r?`n") | Where-Object { Test-HasValue $_ } | Select-Object -First 1)
    if (-not (Test-HasValue $line)) { return '' }
    if ($line.Length -le $MaxLength) { return $line }
    $line.Substring(0, $MaxLength) + '...'
}

function Write-StepStatus {
    param(
        [string]$Step,
        [bool]$Success,
        [string]$Details = '',
        [string]$Hint = ''
    )
    $state = if ($Success) { 'OK' } else { 'FAIL' }
    $color = if ($Success) { 'Green' } else { 'Red' }
    $suffix = if (Test-HasValue $Details) { " | $Details" } else { '' }
    Write-Host "[$Step] $state$suffix" -ForegroundColor $color
    if (Test-HasValue $Hint) {
        Write-Host "[$Step] hint | $Hint" -ForegroundColor Yellow
    }
}

function Test-IsAbsolutePath {
    param([string]$Value)
    if (-not (Test-HasValue $Value)) { return $false }
    try {
        return [System.IO.Path]::IsPathRooted($Value)
    } catch {
        return $false
    }
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
    if (Test-HasValue $VaultPath) {
        $vaultFull = [System.IO.Path]::GetFullPath($VaultPath).TrimEnd('\', '/')
        $vaultFullForward = ($vaultFull -replace '\\', '/')
        $sanitized = $sanitized.Replace($vaultFull, '<vault-root>')
        $sanitized = $sanitized.Replace($vaultFullForward, '<vault-root>')
    }
    if (Test-HasValue $storageStatePath) {
        $storageFull = [System.IO.Path]::GetFullPath($storageStatePath)
        $storageFullForward = ($storageFull -replace '\\', '/')
        $sanitized = $sanitized.Replace($storageFull, '<auth-storage-state>')
        $sanitized = $sanitized.Replace($storageFullForward, '<auth-storage-state>')
    }
    if (Test-HasValue $cookiesFile) {
        $cookiesFull = [System.IO.Path]::GetFullPath($cookiesFile)
        $cookiesFullForward = ($cookiesFull -replace '\\', '/')
        $sanitized = $sanitized.Replace($cookiesFull, '<auth-cookies-file>')
        $sanitized = $sanitized.Replace($cookiesFullForward, '<auth-cookies-file>')
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
        if ($name -like '*url*') {
            return (Sanitize-Url -Url $Value)
        }
        if ($name -like '*path*' -or $name -like '*directory*' -or $name -eq 'run_directory' -or $name -eq 'validation_vault' -or $name -eq 'config_path') {
            return (Sanitize-PathValue -Value $Value)
        }
        return (Sanitize-Text -Text $Value)
    }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return $Value
    }
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

function Get-SanitizedDataCopy {
    param($Value, [int]$Depth = 100)
    if ($null -eq $Value) { return $null }
    $sanitized = Get-SanitizedData -Value $Value
    ConvertFrom-JsonCompat -Json (($sanitized | ConvertTo-Json -Depth $Depth)) -Depth $Depth
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

function Sanitize-FileInPlace {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $content = Read-Utf8Text -Path $Path
    Write-Utf8Text -Path $Path -Content (Sanitize-Text -Text $content)
}

function Copy-JsonObject {
    param($Object, [int]$Depth = 100)
    if ($null -eq $Object) { return $null }
    ConvertFrom-JsonCompat -Json (($Object | ConvertTo-Json -Depth $Depth)) -Depth $Depth
}

function Set-ObjectValue {
    param($Object, [string]$Name, $Value)
    if ($null -eq $Object) { return }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $property.Value = $Value
    }
}

function New-DownloadFailurePayload {
    param(
        $CapturePayload,
        [string]$LogPath
    )
    $payload = Copy-JsonObject -Object $CapturePayload -Depth 100
    if ($null -eq $payload) {
        $payload = [pscustomobject]@{}
    }
    $logText = if (Test-Path $LogPath) { Read-Utf8Text -Path $LogPath } else { '' }
    $errorPreview = Get-PreviewLine -Text $logText -MaxLength 300
    $errors = if (Test-HasValue $errorPreview) { @($errorPreview) } else { @('download step did not produce output json') }
    Set-ObjectValue -Object $payload -Name 'download_status' -Value 'failed'
    Set-ObjectValue -Object $payload -Name 'download_method' -Value 'none'
    Set-ObjectValue -Object $payload -Name 'media_downloaded' -Value $false
    Set-ObjectValue -Object $payload -Name 'video_path' -Value ''
    Set-ObjectValue -Object $payload -Name 'sidecar_path' -Value ''
    Set-ObjectValue -Object $payload -Name 'comments_path' -Value ''
    Set-ObjectValue -Object $payload -Name 'metadata_path' -Value ''
    Set-ObjectValue -Object $payload -Name 'yt_dlp_auth_mode' -Value ''
    Set-ObjectValue -Object $payload -Name 'yt_dlp_cookies_file_used' -Value ''
    Set-ObjectValue -Object $payload -Name 'yt_dlp_cookie_file_generated' -Value $false
    Set-ObjectValue -Object $payload -Name 'errors' -Value $errors
    Set-ObjectValue -Object $payload -Name 'fallbacks' -Value @()

    $metadata = $payload.PSObject.Properties['metadata']
    if ($null -ne $metadata -and $null -ne $metadata.Value) {
        Set-ObjectValue -Object $metadata.Value -Name 'download_status' -Value 'failed'
        Set-ObjectValue -Object $metadata.Value -Name 'download_method' -Value 'none'
        Set-ObjectValue -Object $metadata.Value -Name 'media_downloaded' -Value $false
        Set-ObjectValue -Object $metadata.Value -Name 'video_path' -Value ''
        Set-ObjectValue -Object $metadata.Value -Name 'sidecar_path' -Value ''
        Set-ObjectValue -Object $metadata.Value -Name 'comments_path' -Value ''
        Set-ObjectValue -Object $metadata.Value -Name 'metadata_path' -Value ''
    }
    $payload
}

function New-RunClipperFailurePayload {
    param(
        [string]$SourceUrl,
        [string]$VaultPath,
        [string]$LogPath,
        $CapturePayload
    )
    $title = if ($null -ne $CapturePayload -and (Test-HasValue (Get-DataValue -Data $CapturePayload -Name 'title'))) {
        [string](Get-DataValue -Data $CapturePayload -Name 'title')
    } else {
        ''
    }
    $downloadStatus = if ($null -ne $CapturePayload -and (Test-HasValue (Get-DataValue -Data $CapturePayload -Name 'download_status'))) {
        [string](Get-DataValue -Data $CapturePayload -Name 'download_status')
    } else {
        ''
    }
    $downloadMethod = if ($null -ne $CapturePayload -and (Test-HasValue (Get-DataValue -Data $CapturePayload -Name 'download_method'))) {
        [string](Get-DataValue -Data $CapturePayload -Name 'download_method')
    } else {
        ''
    }
    $logText = if (Test-Path $LogPath) { Read-Utf8Text -Path $LogPath } else { '' }
    $errorPreview = Get-PreviewLine -Text $logText -MaxLength 300
    [pscustomobject]@{
        source_url = $SourceUrl
        note_path = ''
        title = $title
        vault_path = $VaultPath
        route = if ($null -ne $CapturePayload) { Get-StringValue -Data $CapturePayload -Name 'route' } else { '' }
        platform = if ($null -ne $CapturePayload) { Get-StringValue -Data $CapturePayload -Name 'platform' } else { '' }
        content_type = if ($null -ne $CapturePayload) { Get-StringValue -Data $CapturePayload -Name 'content_type' } else { '' }
        capture_id = if ($null -ne $CapturePayload) { Get-StringValue -Data $CapturePayload -Name 'capture_id' } else { '' }
        download_status = if (Test-HasValue $downloadStatus) { $downloadStatus } else { 'failed' }
        download_method = if (Test-HasValue $downloadMethod) { $downloadMethod } else { 'none' }
        status = 'failed'
        errors = if (Test-HasValue $errorPreview) { @($errorPreview) } else { @('run_clipper step did not produce output json') }
    }
}

function New-CaptureFailurePayload {
    param(
        [string]$SourceUrl,
        $Detection,
        [string]$LogPath
    )
    $logText = if (Test-Path $LogPath) { Read-Utf8Text -Path $LogPath } else { '' }
    $errorPreview = Get-PreviewLine -Text $logText -MaxLength 300
    [pscustomobject]@{
        capture_version = 'phase3-social-v2'
        capture_id = ''
        capture_key = ''
        source_url = $SourceUrl
        normalized_url = $SourceUrl
        platform = if ($null -ne $Detection) { [string]$Detection.platform } else { '' }
        content_type = if ($null -ne $Detection) { [string]$Detection.content_type } else { '' }
        route = if ($null -ne $Detection) { [string]$Detection.route } else { '' }
        source_item_id = ''
        title = 'Capture Failed'
        author = 'unknown'
        published_at = 'unknown'
        summary = 'capture step failed before a structured payload was produced'
        description = ''
        raw_text = ''
        transcript = ''
        tags = @('clipped', 'social', 'capture_failed')
        images = @()
        videos = @()
        candidate_video_refs = @()
        cover_url = ''
        top_comments = @()
        comments = @()
        comments_count = 0
        comments_capture_status = 'failed'
        comments_login_required = $false
        auth_applied = $false
        auth_mode = 'unknown'
        auth_cookie_count = 0
        auth_session_state = 'unknown'
        auth_session_likely_valid = $false
        engagement = @{
            like = ''
            comment = ''
            share = ''
            collect = ''
        }
        metrics_like = ''
        metrics_comment = ''
        metrics_share = ''
        metrics_collect = ''
        status = 'capture_failed'
        download_status = 'blocked'
        download_method = 'none'
        media_downloaded = $false
        analyzer_status = 'pending'
        bitable_sync_status = 'pending'
        errors = if (Test-HasValue $errorPreview) { @($errorPreview) } else { @('capture step did not produce output json') }
        fallbacks = @()
        metadata = @{
            capture_level = 'failed'
            transcript_status = 'missing'
            media_downloaded = $false
            analysis_ready = $false
            extractor = 'playwright'
            route = if ($null -ne $Detection) { [string]$Detection.route } else { '' }
            platform = if ($null -ne $Detection) { [string]$Detection.platform } else { '' }
            content_type = if ($null -ne $Detection) { [string]$Detection.content_type } else { '' }
            source_url = $SourceUrl
            normalized_url = $SourceUrl
            capture_error = if (Test-HasValue $errorPreview) { $errorPreview } else { 'capture step did not produce output json' }
        }
    }
}

function Write-ValidationSummary {
    param($Report)
    Write-Host ''
    Write-Host '=== Validation Summary ===' -ForegroundColor Cyan
    Write-Host "source   : $($Report.source_url)"
    if ($null -ne $Report.PSObject.Properties['source_input_kind']) {
        Write-Host "input    : $($Report.source_input_kind) extracted=$($Report.source_url_extracted)"
    }
    Write-Host "auth     : configured=$($Report.auth.configured) session=$($Report.auth.session_state) likely_valid=$($Report.auth.session_likely_valid)"
    Write-Host "capture  : success=$($Report.capture.success) capture_id=$($Report.capture.capture_id) comments=$($Report.capture.comments_count) refs=$($Report.capture.candidate_video_ref_count)"
    Write-Host "download : success=$($Report.download.success) status=$($Report.download.download_status) method=$($Report.download.download_method)"
    if ($null -ne $Report.download.errors -and @($Report.download.errors).Count -gt 0) {
        Write-Host "download : error=$(Get-PreviewLine -Text ((@($Report.download.errors) -join '; ')) -MaxLength 220)" -ForegroundColor Yellow
    }
    Write-Host "clipper  : success=$($Report.end_to_end.success) note=$($Report.end_to_end.note_path)"
    Write-Host "debug    : $($Report.run_directory)"
    if ($null -ne $Report.PSObject.Properties['support_bundle_path']) {
        Write-Host "share    : $($Report.support_bundle_path)"
    }
    Write-Host ''
}

function Get-ToolVersionRecord {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments,
        [string]$RunDirectory
    )
    $logPath = Join-Path $RunDirectory ("tool-" + $Name + ".log")
    $exists = $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
    if (-not $exists) {
        Write-Utf8Text -Path $logPath -Content "$Command not found on PATH."
        return [ordered]@{
            name = $Name
            command = $Command
            available = $false
            success = $false
            exit_code = 1
            log_path = Get-RelativePath -BasePath $RunDirectory -TargetPath $logPath
            preview = ''
        }
    }
    $result = Invoke-LoggedCommand -Command $Command -Arguments $Arguments -LogPath $logPath
    [ordered]@{
        name = $Name
        command = $Command
        available = $true
        success = $result.success
        exit_code = $result.exit_code
        log_path = Get-RelativePath -BasePath $RunDirectory -TargetPath $logPath
        preview = if (Test-HasValue $result.output_preview) { ($result.output_preview -split "`r?`n" | Select-Object -First 1) } else { '' }
    }
}

function Write-MarkdownReport {
    param(
        [Parameter(Mandatory = $true)]
        $Report,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Social Download Validation Report')
    $lines.Add('')
    $lines.Add("- Source URL: $($Report.source_url)")
    $lines.Add("- Generated At: $($Report.generated_at)")
    $lines.Add("- Validation Folder: $($Report.run_directory)")
    $lines.Add("- Validation Vault: $($Report.validation_vault)")
    $lines.Add("- Full Clipper Run: $($Report.full_clipper_run)")
    $lines.Add('')
    $lines.Add('## Auth')
    $lines.Add("- Configured: $($Report.auth.configured)")
    $lines.Add("- Storage State: $($Report.auth.storage_state_path)")
    $lines.Add("- Storage State Exists: $($Report.auth.storage_state_exists)")
    $lines.Add("- Cookies File: $($Report.auth.cookies_file)")
    $lines.Add("- Cookies File Exists: $($Report.auth.cookies_file_exists)")
    $lines.Add("- Session State: $($Report.auth.session_state)")
    $lines.Add("- Session Likely Valid: $($Report.auth.session_likely_valid)")
    if ([string]::IsNullOrWhiteSpace([string]$Report.auth.session_reason) -eq $false) {
        $lines.Add("- Session Reason: $($Report.auth.session_reason)")
    }
    $lines.Add('')
    $lines.Add('## Detection')
    $lines.Add("- Success: $($Report.detection.success)")
    $lines.Add("- Route: $($Report.detection.route)")
    $lines.Add("- Platform: $($Report.detection.platform)")
    $lines.Add("- Content Type: $($Report.detection.content_type)")
    $lines.Add("- JSON: $($Report.detection.json_path)")
    $lines.Add("- Log: $($Report.detection.log_path)")
    $lines.Add('')
    $lines.Add('## Capture')
    $lines.Add("- Success: $($Report.capture.success)")
    $lines.Add("- Capture ID: $($Report.capture.capture_id)")
    $lines.Add("- Comments Count: $($Report.capture.comments_count)")
    $lines.Add("- Candidate Video Ref Count: $($Report.capture.candidate_video_ref_count)")
    $lines.Add("- Comments Capture Status: $($Report.capture.comments_capture_status)")
    $lines.Add("- Comments Login Required: $($Report.capture.comments_login_required)")
    $lines.Add("- Auth Applied: $($Report.capture.auth_applied)")
    $lines.Add("- Auth Mode: $($Report.capture.auth_mode)")
    $lines.Add("- Auth Cookie Count: $($Report.capture.auth_cookie_count)")
    $lines.Add("- Auth Session State: $($Report.capture.auth_session_state)")
    $lines.Add("- Auth Session Likely Valid: $($Report.capture.auth_session_likely_valid)")
    $lines.Add("- JSON: $($Report.capture.json_path)")
    $lines.Add("- Log: $($Report.capture.log_path)")
    $lines.Add('')
    $lines.Add('## Download')
    $lines.Add("- Success: $($Report.download.success)")
    $lines.Add("- Download Status: $($Report.download.download_status)")
    $lines.Add("- Download Method: $($Report.download.download_method)")
    $lines.Add("- Video Path: $($Report.download.video_path)")
    $lines.Add("- Sidecar Path: $($Report.download.sidecar_path)")
    $lines.Add("- yt-dlp Auth Mode: $($Report.download.yt_dlp_auth_mode)")
    $lines.Add("- yt-dlp Cookies File: $($Report.download.yt_dlp_cookies_file_used)")
    $lines.Add("- yt-dlp Generated Cookie File: $($Report.download.yt_dlp_cookie_file_generated)")
    $lines.Add("- JSON: $($Report.download.json_path)")
    $lines.Add("- Log: $($Report.download.log_path)")
    if ($null -ne $Report.download.errors -and @($Report.download.errors).Count -gt 0) {
        $lines.Add("- Errors: $((@($Report.download.errors) -join '; '))")
    }
    if ($null -ne $Report.download.fallbacks -and @($Report.download.fallbacks).Count -gt 0) {
        $lines.Add("- Fallbacks: $((@($Report.download.fallbacks) -join ', '))")
    }
    $lines.Add('')
    $lines.Add('## End To End')
    $lines.Add("- Success: $($Report.end_to_end.success)")
    $lines.Add("- Note Path: $($Report.end_to_end.note_path)")
    $lines.Add("- JSON: $($Report.end_to_end.json_path)")
    $lines.Add("- Log: $($Report.end_to_end.log_path)")
    $lines.Add('')
    $lines.Add('## Tooling')
    foreach ($tool in @($Report.tooling)) {
        $lines.Add("- $($tool.name): available=$($tool.available), success=$($tool.success), preview=$($tool.preview)")
    }
    $lines.Add('')
    $lines.Add('## Cleanup')
    $lines.Add("- To delete this whole validation bundle later: remove `"$($Report.run_directory)`".")
    Write-Utf8Text -Path $Path -Content ($lines -join "`r`n")
}

$resolvedConfigPath = Resolve-ConfigPath -RequestedPath $ConfigPath
$config = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $resolvedConfigPath) -Depth 100
$resolvedSourceInput = Resolve-SourceInput -InputText $SourceUrl
$SourceUrl = $resolvedSourceInput.source_url

$validationRoot = if (Test-HasValue $OutputRoot) {
    $OutputRoot
} else {
    Join-Path $PSScriptRoot '..\.tmp\social-download-validation'
}
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = New-Directory -Path (Join-Path $validationRoot $runId)
$validationVault = if (Test-HasValue $VaultPath) { $VaultPath } else { Join-Path $runDirectory 'validation-vault' }
New-Directory -Path $validationVault | Out-Null

$pythonCommand = if ($null -ne $config.routes -and $null -ne $config.routes.social -and (Test-HasValue $config.routes.social.command)) { [string]$config.routes.social.command } else { 'python' }
$socialScriptPath = Resolve-SocialScriptPath -Config $config
$timeoutMs = if ($null -ne $config.routes -and $null -ne $config.routes.social -and (Test-HasValue $config.routes.social.timeout_ms)) { [string]$config.routes.social.timeout_ms } else { '25000' }
$downloadCommand = if ($null -ne $config.routes -and $null -ne $config.routes.social -and (Test-HasValue $config.routes.social.download_command)) { [string]$config.routes.social.download_command } else { 'yt-dlp' }
$attachmentsRoot = if ($null -ne $config.clipper -and (Test-HasValue $config.clipper.attachments_root)) { [string]$config.clipper.attachments_root } else { 'Attachments/ShortVideos' }
$storageStatePath = ''
$cookiesFile = ''
$storageStateExists = $false
$cookiesFileExists = $false

$tooling = @(
    Get-ToolVersionRecord -Name 'python' -Command $pythonCommand -Arguments @('--version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'yt-dlp' -Command $downloadCommand -Arguments @('--version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'ffprobe' -Command 'ffprobe' -Arguments @('-version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'playwright-python' -Command $pythonCommand -Arguments @('-c', 'import importlib; importlib.import_module(''playwright.sync_api''); print(''playwright-ok'')') -RunDirectory $runDirectory
)
Write-Utf8Text -Path (Join-Path $runDirectory 'environment.json') -Content (($tooling | ConvertTo-Json -Depth 20))

$detectLogPath = Join-Path $runDirectory 'detect-platform.log'
$detectJsonPath = Join-Path $runDirectory 'detect-platform.json'
$detectScriptPath = Join-Path $PSScriptRoot 'detect_platform.ps1'
$detectionCommand = Invoke-LoggedCommand -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', $detectScriptPath, '-SourceUrl', $SourceUrl) -LogPath $detectLogPath
$detection = $null
if ($detectionCommand.success -and (Test-HasValue $detectionCommand.output_preview)) {
    Write-Utf8Text -Path $detectJsonPath -Content $detectionCommand.output_preview
    $detection = ConvertFrom-JsonCompat -Json $detectionCommand.output_preview -Depth 20
}
$detectSuccess = ($null -ne $detection -and [string]$detection.route -eq 'social')
$detectDetails = if ($null -ne $detection) { "route=$([string]$detection.route) platform=$([string]$detection.platform) content=$([string]$detection.content_type)" } else { 'no detection payload' }
$detectHint = if (-not $detectionCommand.success) { Get-PreviewLine -Text $detectionCommand.output_preview } else { '' }
Write-StepStatus -Step 'detect' -Success $detectSuccess -Details $detectDetails -Hint $detectHint
if ($null -eq $detection -or [string]$detection.route -ne 'social') {
    throw "This validation helper is only for the social route. Detection result route: $([string]$detection.route)"
}
$authConfig = Get-SocialPlatformAuthConfig -Config $config -Platform ([string]$detection.platform)
$storageStatePath = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'storage_state_path'
$cookiesFile = Get-ConfiguredPathValue -Object $authConfig -PropertyName 'cookies_file'
$storageStateExists = ((Test-HasValue $storageStatePath) -and (Test-Path $storageStatePath))
$cookiesFileExists = ((Test-HasValue $cookiesFile) -and (Test-Path $cookiesFile))

$captureJsonPath = Join-Path $runDirectory 'capture-social.json'
$captureLogPath = Join-Path $runDirectory 'capture-social.log'
$captureArguments = @($socialScriptPath, '--url', $SourceUrl, '--platform', [string]$detection.platform, '--timeout-ms', $timeoutMs, '--output-json', $captureJsonPath)
if (Test-HasValue $storageStatePath) { $captureArguments += @('--storage-state', $storageStatePath) }
if (Test-HasValue $cookiesFile) { $captureArguments += @('--cookies-file', $cookiesFile) }
$captureCommand = Invoke-LoggedCommand -Command $pythonCommand -Arguments $captureArguments -LogPath $captureLogPath
$capturePayload = $null
if (Test-Path $captureJsonPath) {
    $capturePayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $captureJsonPath) -Depth 100
} else {
    $capturePayload = New-CaptureFailurePayload -SourceUrl $SourceUrl -Detection $detection -LogPath $captureLogPath
    Write-Utf8Text -Path $captureJsonPath -Content ($capturePayload | ConvertTo-Json -Depth 100)
}
$captureSuccess = ($null -ne $capturePayload)
$captureDetails = if ($null -ne $capturePayload) { "capture_id=$([string]$capturePayload.capture_id) auth=$([string]$capturePayload.auth_mode) session=$([string]$capturePayload.auth_session_state) comments=$([string]$capturePayload.comments_count) refs=$(@($capturePayload.candidate_video_refs).Count)" } else { 'capture json missing' }
$captureHint = if ($captureCommand.success) { '' } else { Get-PreviewLine -Text $captureCommand.output_preview }
Write-StepStatus -Step 'capture' -Success $captureSuccess -Details $captureDetails -Hint $captureHint

$downloadJsonPath = Join-Path $runDirectory 'download-social.json'
$downloadLogPath = Join-Path $runDirectory 'download-social.log'
$downloadScriptPath = Join-Path $PSScriptRoot 'download_social_media.ps1'
$downloadPayload = $null
if ($null -ne $capturePayload -and [string]$capturePayload.status -ne 'capture_failed') {
    $downloadArguments = @('-ExecutionPolicy', 'Bypass', '-File', $downloadScriptPath, '-PayloadJsonPath', $captureJsonPath, '-VaultPath', $validationVault, '-Platform', [string]$detection.platform, '-SourceUrl', $SourceUrl, '-AttachmentsRoot', $attachmentsRoot, '-YtDlpCommand', $downloadCommand, '-OutputJsonPath', $downloadJsonPath)
    if (Test-HasValue $cookiesFile) { $downloadArguments += @('-CookiesFile', $cookiesFile) }
    if (Test-HasValue $storageStatePath) { $downloadArguments += @('-StorageStatePath', $storageStatePath) }
    $null = Invoke-LoggedCommand -Command 'powershell' -Arguments $downloadArguments -LogPath $downloadLogPath
    if (Test-Path $downloadJsonPath) {
        $downloadPayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $downloadJsonPath) -Depth 100
    } else {
        $downloadPayload = New-DownloadFailurePayload -CapturePayload $capturePayload -LogPath $downloadLogPath
        Write-Utf8Text -Path $downloadJsonPath -Content ($downloadPayload | ConvertTo-Json -Depth 100)
    }
} else {
    $downloadPayload = New-DownloadFailurePayload -CapturePayload $capturePayload -LogPath $captureLogPath
    if ($null -ne $downloadPayload) {
        Set-ObjectValue -Object $downloadPayload -Name 'download_status' -Value 'blocked'
        Set-ObjectValue -Object $downloadPayload -Name 'errors' -Value @('download skipped because capture step failed')
    }
    Write-Utf8Text -Path $downloadJsonPath -Content ($downloadPayload | ConvertTo-Json -Depth 100)
}
$downloadErrors = if ($null -ne $downloadPayload) { @(Get-DataValue -Data $downloadPayload -Name 'errors') } else { @() }
$downloadSuccess = ($null -ne $downloadPayload -and (Get-StringValue -Data $downloadPayload -Name 'download_status') -eq 'success')
$downloadDetails = if ($null -ne $downloadPayload) { "status=$(Get-StringValue -Data $downloadPayload -Name 'download_status') method=$(Get-StringValue -Data $downloadPayload -Name 'download_method') video=$(Get-StringValue -Data $downloadPayload -Name 'video_path')" } else { 'download json missing' }
$downloadHint = if (@($downloadErrors).Count -gt 0) { Get-PreviewLine -Text ((@($downloadErrors) -join '; ')) -MaxLength 220 } else { '' }
Write-StepStatus -Step 'download' -Success $downloadSuccess -Details $downloadDetails -Hint $downloadHint

$runClipperJsonPath = Join-Path $runDirectory 'run-clipper.json'
$runClipperLogPath = Join-Path $runDirectory 'run-clipper.log'
$runClipperPayload = $null
if (-not $SkipFullClipper) {
    $runClipperScriptPath = Join-Path $PSScriptRoot 'run_clipper.ps1'
    $runClipperArguments = @('-ExecutionPolicy', 'Bypass', '-File', $runClipperScriptPath, '-SourceUrl', $SourceUrl, '-VaultPath', $validationVault, '-ConfigPath', $resolvedConfigPath, '-OutputJsonPath', $runClipperJsonPath)
    if (Test-Path $detectJsonPath) {
        $runClipperArguments += @('-DetectionJsonPath', $detectJsonPath)
    }
    if (Test-Path $downloadJsonPath) {
        $runClipperArguments += @('-CaptureJsonPath', $downloadJsonPath)
    } elseif (Test-Path $captureJsonPath) {
        $runClipperArguments += @('-CaptureJsonPath', $captureJsonPath)
    }
    $null = Invoke-LoggedCommand -Command 'powershell' -Arguments $runClipperArguments -LogPath $runClipperLogPath
    if (Test-Path $runClipperJsonPath) {
        $runClipperPayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $runClipperJsonPath) -Depth 100
    }
}
if ($null -eq $runClipperPayload) {
    $runClipperPayload = New-RunClipperFailurePayload -SourceUrl $SourceUrl -VaultPath $validationVault -LogPath $runClipperLogPath -CapturePayload $(if ($null -ne $downloadPayload) { $downloadPayload } else { $capturePayload })
    Write-Utf8Text -Path $runClipperJsonPath -Content ($runClipperPayload | ConvertTo-Json -Depth 100)
}
$clipperStatus = if ($null -ne $runClipperPayload) { Get-StringValue -Data $runClipperPayload -Name 'status' } else { '' }
$clipperSuccess = ($null -ne $runClipperPayload -and $clipperStatus -ne 'failed')
$clipperNotePath = if ($null -ne $runClipperPayload) { Get-StringValue -Data $runClipperPayload -Name 'note_path' } else { '' }
$clipperDownloadStatus = if ($null -ne $runClipperPayload) { Get-StringValue -Data $runClipperPayload -Name 'download_status' } else { '' }
$clipperDownloadMethod = if ($null -ne $runClipperPayload) { Get-StringValue -Data $runClipperPayload -Name 'download_method' } else { '' }
$clipperDetails = if ($null -ne $runClipperPayload) { "note=$clipperNotePath download=$clipperDownloadStatus/$clipperDownloadMethod" } else { 'run-clipper json missing' }
$clipperErrors = if ($null -ne $runClipperPayload) { @(Get-DataValue -Data $runClipperPayload -Name 'errors') } else { @() }
$clipperHint = if (@($clipperErrors).Count -gt 0) { Get-PreviewLine -Text ((@($clipperErrors) -join '; ')) -MaxLength 220 } elseif (Test-Path $runClipperLogPath) { Get-PreviewLine -Text (Read-Utf8Text -Path $runClipperLogPath) } else { '' }
Write-StepStatus -Step 'clipper' -Success $clipperSuccess -Details $clipperDetails -Hint $clipperHint

$treePath = Join-Path $runDirectory 'validation-vault-tree.txt'
$treeLines = @()
if (Test-Path $validationVault) {
    $treeLines = Get-ChildItem -Path $validationVault -Recurse -Force | ForEach-Object {
        Get-RelativePath -BasePath $validationVault -TargetPath $_.FullName
    }
}
Write-Utf8Text -Path $treePath -Content (($treeLines | Where-Object { Test-HasValue $_ }) -join "`r`n")

$captureMetadata = if ($null -ne $capturePayload) { Get-DataValue -Data $capturePayload -Name 'metadata' } else { $null }
$authSessionState = if ($null -ne $capturePayload) { Get-StringValue -Data $capturePayload -Name 'auth_session_state' -DefaultValue '' } else { '' }
$authSessionLikelyValid = if ($null -ne $capturePayload) { [bool](Get-DataValue -Data $capturePayload -Name 'auth_session_likely_valid') } else { $false }
$authSessionReason = if ($null -ne $captureMetadata) { Get-StringValue -Data $captureMetadata -Name 'auth_session_reason' -DefaultValue '' } else { '' }
$captureAuthApplied = if ($null -ne $capturePayload) { [bool](Get-DataValue -Data $capturePayload -Name 'auth_applied') } else { $false }
$captureAuthMode = if ($null -ne $capturePayload) { Get-StringValue -Data $capturePayload -Name 'auth_mode' -DefaultValue '' } else { '' }
$captureAuthCookieCount = if ($null -ne $capturePayload -and $null -ne (Get-DataValue -Data $capturePayload -Name 'auth_cookie_count')) { [int](Get-DataValue -Data $capturePayload -Name 'auth_cookie_count') } else { 0 }
$captureCommentsLoginRequired = if ($null -ne $capturePayload) { [bool](Get-DataValue -Data $capturePayload -Name 'comments_login_required') } else { $false }
$captureCommentsCount = if ($null -ne $capturePayload -and $null -ne (Get-DataValue -Data $capturePayload -Name 'comments_count')) { [int](Get-DataValue -Data $capturePayload -Name 'comments_count') } else { 0 }
$captureCandidateRefCount = if ($null -ne $capturePayload) { @((Get-DataValue -Data $capturePayload -Name 'candidate_video_refs')).Count } else { 0 }

$report = [ordered]@{
    source_url = $SourceUrl
    source_input_kind = $resolvedSourceInput.input_kind
    source_url_extracted = [bool]$resolvedSourceInput.extraction_applied
    generated_at = (Get-Date).ToString('o')
    run_directory = $runDirectory
    support_bundle_path = (Join-Path $runDirectory 'support-bundle')
    validation_vault = $validationVault
    config_path = $resolvedConfigPath
    full_clipper_run = (-not $SkipFullClipper)
    tooling = $tooling
    auth = [ordered]@{
        configured = [bool]((Test-HasValue $storageStatePath) -or (Test-HasValue $cookiesFile))
        storage_state_path = $storageStatePath
        storage_state_exists = [bool]$storageStateExists
        cookies_file = $cookiesFile
        cookies_file_exists = [bool]$cookiesFileExists
        session_state = $authSessionState
        session_likely_valid = $authSessionLikelyValid
        session_reason = $authSessionReason
    }
    detection = [ordered]@{
        success = [bool]($null -ne $detection)
        route = if ($null -ne $detection) { [string]$detection.route } else { '' }
        platform = if ($null -ne $detection) { [string]$detection.platform } else { '' }
        content_type = if ($null -ne $detection) { [string]$detection.content_type } else { '' }
        json_path = if (Test-Path $detectJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $detectJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $detectLogPath
    }
    capture = [ordered]@{
        success = [bool]($null -ne $capturePayload)
        capture_id = if ($null -ne $capturePayload) { Get-StringValue -Data $capturePayload -Name 'capture_id' -DefaultValue '' } else { '' }
        comments_count = $captureCommentsCount
        candidate_video_ref_count = $captureCandidateRefCount
        comments_capture_status = if ($null -ne $capturePayload) { Get-StringValue -Data $capturePayload -Name 'comments_capture_status' -DefaultValue '' } else { '' }
        comments_login_required = $captureCommentsLoginRequired
        auth_applied = $captureAuthApplied
        auth_mode = $captureAuthMode
        auth_cookie_count = $captureAuthCookieCount
        auth_session_state = $authSessionState
        auth_session_likely_valid = $authSessionLikelyValid
        json_path = if (Test-Path $captureJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $captureJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $captureLogPath
    }
    download = [ordered]@{
        success = [bool]($null -ne $downloadPayload)
        download_status = if ($null -ne $downloadPayload) { Get-StringValue -Data $downloadPayload -Name 'download_status' } else { '' }
        download_method = if ($null -ne $downloadPayload) { Get-StringValue -Data $downloadPayload -Name 'download_method' } else { '' }
        video_path = if ($null -ne $downloadPayload) { Get-StringValue -Data $downloadPayload -Name 'video_path' } else { '' }
        sidecar_path = if ($null -ne $downloadPayload) { [string]$downloadPayload.sidecar_path } else { '' }
        yt_dlp_auth_mode = if ($null -ne $downloadPayload) { [string]$downloadPayload.yt_dlp_auth_mode } else { '' }
        yt_dlp_cookies_file_used = if ($null -ne $downloadPayload) { [string]$downloadPayload.yt_dlp_cookies_file_used } else { '' }
        yt_dlp_cookie_file_generated = if ($null -ne $downloadPayload) { [bool]$downloadPayload.yt_dlp_cookie_file_generated } else { $false }
        json_path = if (Test-Path $downloadJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $downloadJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $downloadLogPath
        errors = if ($null -ne $downloadPayload) { @(Get-DataValue -Data $downloadPayload -Name 'errors') } else { @() }
        fallbacks = if ($null -ne $downloadPayload) { @($downloadPayload.fallbacks) } else { @() }
    }
    end_to_end = [ordered]@{
        success = [bool]$clipperSuccess
        note_path = if ($null -ne $runClipperPayload) { Get-StringValue -Data $runClipperPayload -Name 'note_path' } else { '' }
        json_path = if (Test-Path $runClipperJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $runClipperJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $runClipperLogPath
    }
    vault_tree_path = Get-RelativePath -BasePath $runDirectory -TargetPath $treePath
}

$reportJsonPath = Join-Path $runDirectory 'validation-report.json'
$reportMdPath = Join-Path $runDirectory 'validation-report.md'
Write-Utf8Text -Path $reportJsonPath -Content ($report | ConvertTo-Json -Depth 50)
Write-MarkdownReport -Report $report -Path $reportMdPath

$supportBundleDirectory = New-Directory -Path (Join-Path $runDirectory 'support-bundle')
$sanitizedReport = Get-SanitizedDataCopy -Value $report -Depth 100
Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'validation-report.json') -Content ($sanitizedReport | ConvertTo-Json -Depth 50)
Write-MarkdownReport -Report $sanitizedReport -Path (Join-Path $supportBundleDirectory 'validation-report.md')
Write-SanitizedJsonFile -Path (Join-Path $supportBundleDirectory 'detect-platform.json') -Data $detection -Depth 50
Write-SanitizedJsonFile -Path (Join-Path $supportBundleDirectory 'capture-social.json') -Data $capturePayload -Depth 100
Write-SanitizedJsonFile -Path (Join-Path $supportBundleDirectory 'download-social.json') -Data $downloadPayload -Depth 100
Write-SanitizedJsonFile -Path (Join-Path $supportBundleDirectory 'run-clipper.json') -Data $runClipperPayload -Depth 100
Write-SanitizedJsonFile -Path (Join-Path $supportBundleDirectory 'environment.json') -Data $tooling -Depth 20

$textArtifacts = Get-ChildItem -Path $runDirectory -File -Filter '*.log'
foreach ($artifact in $textArtifacts) {
    $sanitizedLogPath = Join-Path $supportBundleDirectory $artifact.Name
    $sanitizedContent = Sanitize-Text -Text (Read-Utf8Text -Path $artifact.FullName)
    Write-Utf8Text -Path $sanitizedLogPath -Content $sanitizedContent
}

if (Test-Path $treePath) {
    $sanitizedTreePath = Join-Path $supportBundleDirectory 'validation-vault-tree.txt'
    Write-Utf8Text -Path $sanitizedTreePath -Content (Sanitize-Text -Text (Read-Utf8Text -Path $treePath))
}

Write-ValidationSummary -Report $sanitizedReport

$sanitizedReport | ConvertTo-Json -Depth 50
