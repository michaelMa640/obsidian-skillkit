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
    $lines.Add("- JSON: $($Report.capture.json_path)")
    $lines.Add("- Log: $($Report.capture.log_path)")
    $lines.Add('')
    $lines.Add('## Download')
    $lines.Add("- Success: $($Report.download.success)")
    $lines.Add("- Download Status: $($Report.download.download_status)")
    $lines.Add("- Download Method: $($Report.download.download_method)")
    $lines.Add("- Video Path: $($Report.download.video_path)")
    $lines.Add("- Sidecar Path: $($Report.download.sidecar_path)")
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

$tooling = @(
    Get-ToolVersionRecord -Name 'python' -Command $pythonCommand -Arguments @('--version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'yt-dlp' -Command $downloadCommand -Arguments @('--version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'ffprobe' -Command 'ffprobe' -Arguments @('-version') -RunDirectory $runDirectory
    Get-ToolVersionRecord -Name 'playwright-python' -Command $pythonCommand -Arguments @('-c', 'from playwright.sync_api import sync_playwright; print("playwright-ok")') -RunDirectory $runDirectory
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
if ($null -eq $detection -or [string]$detection.route -ne 'social') {
    throw "This validation helper is only for the social route. Detection result route: $([string]$detection.route)"
}

$captureJsonPath = Join-Path $runDirectory 'capture-social.json'
$captureLogPath = Join-Path $runDirectory 'capture-social.log'
$captureCommand = Invoke-LoggedCommand -Command $pythonCommand -Arguments @($socialScriptPath, '--url', $SourceUrl, '--platform', [string]$detection.platform, '--timeout-ms', $timeoutMs, '--output-json', $captureJsonPath) -LogPath $captureLogPath
$capturePayload = $null
if (Test-Path $captureJsonPath) {
    $capturePayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $captureJsonPath) -Depth 100
}

$downloadJsonPath = Join-Path $runDirectory 'download-social.json'
$downloadLogPath = Join-Path $runDirectory 'download-social.log'
$downloadScriptPath = Join-Path $PSScriptRoot 'download_social_media.ps1'
$downloadPayload = $null
if ($null -ne $capturePayload) {
    $null = Invoke-LoggedCommand -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', $downloadScriptPath, '-PayloadJsonPath', $captureJsonPath, '-VaultPath', $validationVault, '-Platform', [string]$detection.platform, '-SourceUrl', $SourceUrl, '-AttachmentsRoot', $attachmentsRoot, '-YtDlpCommand', $downloadCommand, '-OutputJsonPath', $downloadJsonPath) -LogPath $downloadLogPath
    if (Test-Path $downloadJsonPath) {
        $downloadPayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $downloadJsonPath) -Depth 100
    }
}

$runClipperJsonPath = Join-Path $runDirectory 'run-clipper.json'
$runClipperLogPath = Join-Path $runDirectory 'run-clipper.log'
$runClipperPayload = $null
if (-not $SkipFullClipper) {
    $runClipperScriptPath = Join-Path $PSScriptRoot 'run_clipper.ps1'
    $null = Invoke-LoggedCommand -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', $runClipperScriptPath, '-SourceUrl', $SourceUrl, '-VaultPath', $validationVault, '-ConfigPath', $resolvedConfigPath, '-OutputJsonPath', $runClipperJsonPath) -LogPath $runClipperLogPath
    if (Test-Path $runClipperJsonPath) {
        $runClipperPayload = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $runClipperJsonPath) -Depth 100
    }
}

$treePath = Join-Path $runDirectory 'validation-vault-tree.txt'
$treeLines = @()
if (Test-Path $validationVault) {
    $treeLines = Get-ChildItem -Path $validationVault -Recurse -Force | ForEach-Object {
        Get-RelativePath -BasePath $validationVault -TargetPath $_.FullName
    }
}
Write-Utf8Text -Path $treePath -Content (($treeLines | Where-Object { Test-HasValue $_ }) -join "`r`n")

$report = [ordered]@{
    source_url = $SourceUrl
    generated_at = (Get-Date).ToString('o')
    run_directory = $runDirectory
    validation_vault = $validationVault
    config_path = $resolvedConfigPath
    full_clipper_run = (-not $SkipFullClipper)
    tooling = $tooling
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
        capture_id = if ($null -ne $capturePayload) { [string]$capturePayload.capture_id } else { '' }
        comments_count = if ($null -ne $capturePayload -and $null -ne $capturePayload.comments_count) { [int]$capturePayload.comments_count } else { 0 }
        candidate_video_ref_count = if ($null -ne $capturePayload -and $null -ne $capturePayload.candidate_video_refs) { @($capturePayload.candidate_video_refs).Count } else { 0 }
        json_path = if (Test-Path $captureJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $captureJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $captureLogPath
    }
    download = [ordered]@{
        success = [bool]($null -ne $downloadPayload)
        download_status = if ($null -ne $downloadPayload) { [string]$downloadPayload.download_status } else { '' }
        download_method = if ($null -ne $downloadPayload) { [string]$downloadPayload.download_method } else { '' }
        video_path = if ($null -ne $downloadPayload) { [string]$downloadPayload.video_path } else { '' }
        sidecar_path = if ($null -ne $downloadPayload) { [string]$downloadPayload.sidecar_path } else { '' }
        json_path = if (Test-Path $downloadJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $downloadJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $downloadLogPath
        errors = if ($null -ne $downloadPayload) { @($downloadPayload.errors) } else { @() }
        fallbacks = if ($null -ne $downloadPayload) { @($downloadPayload.fallbacks) } else { @() }
    }
    end_to_end = [ordered]@{
        success = [bool]($null -ne $runClipperPayload)
        note_path = if ($null -ne $runClipperPayload -and (Test-HasValue $runClipperPayload.note_path)) { [string]$runClipperPayload.note_path } else { '' }
        json_path = if (Test-Path $runClipperJsonPath) { Get-RelativePath -BasePath $runDirectory -TargetPath $runClipperJsonPath } else { '' }
        log_path = Get-RelativePath -BasePath $runDirectory -TargetPath $runClipperLogPath
    }
    vault_tree_path = Get-RelativePath -BasePath $runDirectory -TargetPath $treePath
}

$reportJsonPath = Join-Path $runDirectory 'validation-report.json'
$reportMdPath = Join-Path $runDirectory 'validation-report.md'
Write-Utf8Text -Path $reportJsonPath -Content ($report | ConvertTo-Json -Depth 50)
Write-MarkdownReport -Report $report -Path $reportMdPath

$report | ConvertTo-Json -Depth 50