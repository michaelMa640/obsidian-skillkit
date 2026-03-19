param(
    [string]$NotePath,
    [string]$CaptureJsonPath,
    [string]$Mode,
    [string]$VaultPath,
    [string]$ConfigPath,
    [string]$OutputJsonPath,
    [string]$DebugDirectory,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Utf8Text { param([string]$Path) [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)) }
function Write-Utf8Text { param([string]$Path, [string]$Content) [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false)) }
function Test-HasValue { param($Value) $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value) }
function Zh { param([string]$Escaped) [regex]::Unescape($Escaped) }
function Test-ExistingPath { param([string]$Path) if (-not (Test-HasValue $Path)) { return $false }; Test-Path $Path }

function ConvertFrom-JsonCompat {
    param([Parameter(Mandatory = $true)][string]$Json, [int]$Depth = 64)
    $params = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('Depth')) { $params.Depth = $Depth }
    $Json | ConvertFrom-Json @params
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

function Set-ObjectField {
    param($Object, [string]$Name, $Value)
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return $Object
    }
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $Object
}

function New-Directory {
    param([string]$Path)
    if (-not (Test-HasValue $Path)) { return '' }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $Path
}

function Get-ConfigPathResolved {
    param([string]$RequestedPath)
    if (Test-HasValue $RequestedPath) { return $RequestedPath }
    $localConfig = Join-Path $PSScriptRoot '..\references\local-config.json'
    if (Test-Path $localConfig) { return $localConfig }
    Join-Path $PSScriptRoot '..\references\local-config.example.json'
}

function Get-Config {
    param([string]$Path)
    ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $Path) -Depth 100
}

function Resolve-ConfigDirectoryPath {
    param([string]$ConfiguredPath, [string]$BasePath)
    if (-not (Test-HasValue $ConfiguredPath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) { return $ConfiguredPath }
    Join-Path $BasePath $ConfiguredPath
}

function Get-ResolvedVaultPath {
    param($Config, [string]$RequestedVaultPath)
    if (Test-HasValue $RequestedVaultPath) { return $RequestedVaultPath }
    if ($null -ne $Config.obsidian -and (Test-HasValue $Config.obsidian.vault_path)) { return [string]$Config.obsidian.vault_path }
    ''
}

function Get-DefaultDebugDirectory {
    param($Config, [string]$RequestedDebugDirectory)
    if (Test-HasValue $RequestedDebugDirectory) { return $RequestedDebugDirectory }
    $configured = ''
    if ($null -ne $Config.analyzer -and (Test-HasValue ([string]$Config.analyzer.default_debug_directory))) { $configured = [string]$Config.analyzer.default_debug_directory }
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $base = if (Test-HasValue $configured) { Resolve-ConfigDirectoryPath -ConfiguredPath $configured -BasePath $root } else { Join-Path $root '.tmp\run-analyzer' }
    Join-Path $base (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-FrontmatterData {
    param([string]$NoteText)
    $result = [ordered]@{}
    if (-not $NoteText.StartsWith('---')) { return [pscustomobject]$result }
    $lines = $NoteText -split "`r?`n"
    for ($index = 1; $index -lt $lines.Count; $index += 1) {
        $line = $lines[$index]
        if ($line -eq '---') { break }
        if ($line -match '^(?<key>[^:]+):\s*(?<value>.*)$') {
            $result[$Matches['key'].Trim()] = $Matches['value'].Trim().Trim("'")
        }
    }
    [pscustomobject]$result
}

function Resolve-PathFromVault {
    param([string]$VaultRoot, [string]$RelativeOrAbsolutePath)
    if (-not (Test-HasValue $RelativeOrAbsolutePath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($RelativeOrAbsolutePath)) { return $RelativeOrAbsolutePath }
    if (-not (Test-HasValue $VaultRoot)) { return $RelativeOrAbsolutePath }
    $parts = ($RelativeOrAbsolutePath -replace '\\', '/') -split '/'
    Join-Path $VaultRoot ($parts -join '\')
}

function Get-DefaultMode {
    param($Frontmatter, $Capture)
    $route = Get-StringValue -Data $Frontmatter -Name 'route' -DefaultValue ''
    $platform = Get-StringValue -Data $Frontmatter -Name 'platform' -DefaultValue ''
    $contentType = Get-StringValue -Data $Frontmatter -Name 'content_type' -DefaultValue ''
    if (-not (Test-HasValue $route) -and $null -ne $Capture) { $route = Get-StringValue -Data $Capture -Name 'route' -DefaultValue '' }
    if (-not (Test-HasValue $platform) -and $null -ne $Capture) { $platform = Get-StringValue -Data $Capture -Name 'platform' -DefaultValue '' }
    if (-not (Test-HasValue $contentType) -and $null -ne $Capture) { $contentType = Get-StringValue -Data $Capture -Name 'content_type' -DefaultValue '' }
    if ($route -eq 'social' -and $contentType -eq 'short_video') { return 'analyze' }
    if ($platform -in @('douyin', 'xiaohongshu')) { return 'analyze' }
    'learn'
}

function Build-AnalyzerPayloadWithPython {
    param([string]$ResolvedVaultPath, [string]$ResolvedNotePath, [string]$ResolvedCaptureJsonPath, [string]$AnalysisMode, [string]$PayloadJsonPath)
    $args = @((Join-Path $PSScriptRoot 'build_analyzer_payload.py'), '--mode', $AnalysisMode, '--output-json', $PayloadJsonPath)
    if (Test-HasValue $ResolvedVaultPath) { $args += @('--vault-path', $ResolvedVaultPath) }
    if (Test-HasValue $ResolvedNotePath) { $args += @('--note-path', $ResolvedNotePath) }
    if (Test-HasValue $ResolvedCaptureJsonPath) { $args += @('--capture-json-path', $ResolvedCaptureJsonPath) }
    $output = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = (($output | Out-String).Trim())
        throw "build_analyzer_payload.py failed with exit code $LASTEXITCODE. Details: $detail"
    }
    ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $PayloadJsonPath) -Depth 100
}

function Test-RealLlmConfigured {
    param($Config)
    if ($null -eq $Config -or $null -eq $Config.llm) { return $false }
    if (Test-HasValue ([string]$Config.llm.api_key)) { return $true }
    $apiKeyEnv = if (Test-HasValue ([string]$Config.llm.api_key_env)) { [string]$Config.llm.api_key_env } else { 'DASHSCOPE_API_KEY' }
    Test-HasValue ([Environment]::GetEnvironmentVariable($apiKeyEnv))
}

function Invoke-AnalyzerLlmWithPython {
    param([string]$PayloadJsonPath, [string]$ConfigJsonPath, [string]$PromptPath, [string]$SchemaPath, [string]$OutputPath, [string]$RequestJsonPath, [string]$ResponseJsonPath)
    $args = @((Join-Path $PSScriptRoot 'invoke_analyzer_llm.py'), '--payload-json', $PayloadJsonPath, '--config-json', $ConfigJsonPath, '--prompt-path', $PromptPath, '--schema-path', $SchemaPath, '--output-json', $OutputPath)
    if (Test-HasValue $RequestJsonPath) { $args += @('--request-json', $RequestJsonPath) }
    if (Test-HasValue $ResponseJsonPath) { $args += @('--response-json', $ResponseJsonPath) }
    $output = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = (($output | Out-String).Trim())
        throw "invoke_analyzer_llm.py failed with exit code $LASTEXITCODE. Details: $detail"
    }
    ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $OutputPath) -Depth 100
}

function Build-MockAnalysisResult {
    param($Payload, [string]$OutputLanguage = 'zh-CN')
    [pscustomobject]@{
        title = Get-StringValue -Data $Payload -Name 'title' -DefaultValue 'Untitled'
        analysis_mode = Get-StringValue -Data $Payload -Name 'analysis_mode' -DefaultValue 'analyze'
        source_note_path = Get-StringValue -Data $Payload -Name 'source_note_path' -DefaultValue ''
        capture_json_path = Get-StringValue -Data $Payload -Name 'capture_json_path' -DefaultValue ''
        source_url = Get-StringValue -Data $Payload -Name 'source_url' -DefaultValue ''
        normalized_url = Get-StringValue -Data $Payload -Name 'normalized_url' -DefaultValue ''
        platform = Get-StringValue -Data $Payload -Name 'platform' -DefaultValue ''
        content_type = Get-StringValue -Data $Payload -Name 'content_type' -DefaultValue ''
        capture_id = Get-StringValue -Data $Payload -Name 'capture_id' -DefaultValue ''
        analyzed_at = Get-Date -Format 'yyyy-MM-dd'
        provider = 'mock'
        provider_reported_model = ''
        model = 'mock:analyze'
        analysis_status = 'mock_generated'
        prompt_template = 'references/prompts/analyze.md'
        output_contract_version = 'analyze-v1'
        output_language = $OutputLanguage
        core_conclusion = 'This is mock output generated because no real model was invoked.'
        hook_breakdown = Get-StringValue -Data $Payload -Name 'summary' -DefaultValue ''
        structure_breakdown = @()
        emotion_trust_signals = @()
        comment_feedback = @()
        engagement_insights = @()
        reusable_formula = @()
        risk_flags = @('Mock output only.')
        source_highlights = @()
        metrics_like = Get-StringValue -Data $Payload -Name 'metrics_like' -DefaultValue '0'
        metrics_comment = Get-StringValue -Data $Payload -Name 'metrics_comment' -DefaultValue '0'
        metrics_share = Get-StringValue -Data $Payload -Name 'metrics_share' -DefaultValue '0'
        metrics_collect = Get-StringValue -Data $Payload -Name 'metrics_collect' -DefaultValue '0'
        comments_count = Get-StringValue -Data $Payload -Name 'comments_count' -DefaultValue '0'
        video_path = Get-StringValue -Data $Payload -Name 'video_path' -DefaultValue ''
    }
}

function Add-AnalyzerFinalStatusFields {
    param($Result)
    $status = Get-StringValue -Data $Result -Name 'analysis_status' -DefaultValue ''
    $failedStep = Get-StringValue -Data $Result -Name 'failed_step' -DefaultValue ''
    if (-not [bool]$Result.success) {
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'FAILED' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u5931\u8d25') | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value (Get-StringValue -Data $Result -Name 'error_message' -DefaultValue 'The analyzer run failed.') | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value (Get-StringValue -Data $Result -Name 'error_message_zh' -DefaultValue (Zh '\u672c\u6b21 Analyzer \u8fd0\u884c\u5931\u8d25\u3002')) | Out-Null
        if (-not (Test-HasValue $failedStep)) { Set-ObjectField -Object $Result -Name 'failed_step' -Value 'unknown' | Out-Null }
        return $Result
    }
    if ([bool]$Result.dry_run -or $status -eq 'success' -or $status -eq 'partial') {
        if ([bool]$Result.dry_run) {
            $messageEn = 'Dry run completed successfully.'
            $messageZh = Zh 'DryRun \u5df2\u6210\u529f\u5b8c\u6210\u3002'
        } elseif ($status -eq 'partial') {
            $messageEn = 'The analyzer run completed with partial output.'
            $messageZh = Zh '\u672c\u6b21 Analyzer \u8fd0\u884c\u5df2\u5b8c\u6210\uff0c\u4f46\u8f93\u51fa\u4e3a partial\u3002'
        } else {
            $messageEn = 'The analyzer run completed successfully.'
            $messageZh = Zh '\u672c\u6b21 Analyzer \u8fd0\u884c\u6210\u529f\u5b8c\u6210\u3002'
        }
        Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'SUCCESS' | Out-Null
        Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u6210\u529f') | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_en' -Value $messageEn | Out-Null
        Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $messageZh | Out-Null
        return $Result
    }
    $messageEn = if ($status -eq 'mock_fallback_after_llm_error') { 'Real model invocation failed and the pipeline fell back to mock output.' } else { 'Real model was not invoked; mock output was generated.' }
    $messageZh = if ($status -eq 'mock_fallback_after_llm_error') { Zh '\u771f\u5b9e\u6a21\u578b\u8c03\u7528\u5931\u8d25\uff0c\u6d41\u7a0b\u5df2\u56de\u9000\u4e3a mock \u8f93\u51fa\u3002' } else { Zh '\u672c\u6b21\u672a\u8c03\u7528\u771f\u5b9e\u6a21\u578b\uff0c\u751f\u6210\u7684\u662f mock \u8f93\u51fa\u3002' }
    Set-ObjectField -Object $Result -Name 'final_run_status' -Value 'FAILED' | Out-Null
    Set-ObjectField -Object $Result -Name 'final_run_status_zh' -Value (Zh '\u5931\u8d25') | Out-Null
    if (-not (Test-HasValue $failedStep)) { Set-ObjectField -Object $Result -Name 'failed_step' -Value 'llm_invoke' | Out-Null }
    Set-ObjectField -Object $Result -Name 'final_message_en' -Value $messageEn | Out-Null
    Set-ObjectField -Object $Result -Name 'final_message_zh' -Value $messageZh | Out-Null
    $Result
}

function Get-AnalyzerSummaryLines {
    param($Result)
    $lines = New-Object System.Collections.Generic.List[string]
    $failedStep = Get-StringValue -Data $Result -Name 'failed_step' -DefaultValue ''
    $lines.Add('=== Analyzer Summary ===')
    $lines.Add("mode     : $($Result.analysis_mode)")
    $lines.Add("platform : $($Result.platform)")
    $lines.Add("title    : $($Result.title)")
    $lines.Add("status   : $($Result.analysis_status)")
    $lines.Add("provider : $($Result.provider)")
    $lines.Add("model    : $($Result.model)")
    $lines.Add("language : $($Result.output_language)")
    $lines.Add("folder   : $($Result.output_folder)")
    if ($null -ne $Result.PSObject.Properties['analyzer_payload_path']) { $lines.Add("payload  : $($Result.analyzer_payload_path)") }
    if ($null -ne $Result.PSObject.Properties['analysis_input_path'] -and (Test-HasValue ([string]$Result.analysis_input_path))) { $lines.Add("analysis : $($Result.analysis_input_path)") }
    if ($null -ne $Result.PSObject.Properties['analyzer_payload_warning_count']) { $lines.Add("warnings : $($Result.analyzer_payload_warning_count)") }
    if ($null -ne $Result.PSObject.Properties['note_path']) { $lines.Add("note     : $($Result.note_path)") }
    if ($null -ne $Result.PSObject.Properties['support_bundle_path']) { $lines.Add("share    : $($Result.support_bundle_path)") }
    if ($null -ne $Result.PSObject.Properties['debug_directory']) { $lines.Add("debug    : $($Result.debug_directory)") }
    $lines.Add("result   : $($Result.final_run_status)")
    $lines.Add(("{0}     : {1}" -f (Zh '\u7ed3\u679c'), $Result.final_run_status_zh))
    if (Test-HasValue $failedStep) {
        $lines.Add("step     : $failedStep")
        $lines.Add(("{0}     : {1}" -f (Zh '\u6b65\u9aa4'), $failedStep))
    }
    $lines.Add("detail_en: $($Result.final_message_en)")
    $lines.Add(("{0}     : {1}" -f (Zh '\u8be6\u60c5'), $Result.final_message_zh))
    $lines.Add('issue_en : Upload support-bundle or the whole debug directory to your issue for troubleshooting and updates.')
    $lines.Add(("{0} : {1}" -f (Zh '\u95ee\u9898\u4e0a\u62a5'), (Zh '\u8bf7\u5c06 support-bundle \u6216\u6574\u4e2a debug \u76ee\u5f55\u4e0a\u4f20\u5230\u4f60\u7684 issue\uff0c\u4fbf\u4e8e\u6392\u67e5\u548c\u66f4\u65b0\u3002')))
    @($lines)
}

function Write-AnalyzerSummary {
    param($Result)
    Write-Host ''
    foreach ($line in (Get-AnalyzerSummaryLines -Result $Result)) {
        if ($line -eq '=== Analyzer Summary ===') {
            Write-Host $line -ForegroundColor Cyan
        } elseif ($line -like 'result   : FAILED' -or $line -like '*失败' -or $line -like 'step     :*') {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
    Write-Host ''
}

function Sanitize-Value {
    param($Value, [string]$VaultPath)
    if ($Value -is [string]) {
        if ($Value.StartsWith('data:video/')) { return '<inline-video-base64>' }
        if (Test-HasValue $VaultPath) { return $Value.Replace($VaultPath, '<vault-root>') }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $output = [ordered]@{}
        foreach ($key in $Value.Keys) { $output[$key] = Sanitize-Value -Value $Value[$key] -VaultPath $VaultPath }
        return [pscustomobject]$output
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Sanitize-Value -Value $_ -VaultPath $VaultPath })
    }
    if ($null -ne $Value -and $Value -is [psobject]) {
        $output = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $output[$property.Name] = Sanitize-Value -Value $property.Value -VaultPath $VaultPath }
        return [pscustomobject]$output
    }
    $Value
}

$configPathResolved = ''
$config = $null
$resolvedVaultPath = ''
$resolvedDebugDirectory = ''
$artifactDirectory = ''
$payloadJsonPath = ''
$analysisJsonPath = ''
$llmRequestJsonPath = ''
$llmResponseJsonPath = ''
$script:AnalyzerCurrentStep = 'startup'

try {
    $script:AnalyzerCurrentStep = 'config_load'
    $configPathResolved = Get-ConfigPathResolved -RequestedPath $ConfigPath
    $config = Get-Config -Path $configPathResolved
    $resolvedVaultPath = Get-ResolvedVaultPath -Config $config -RequestedVaultPath $VaultPath
    $resolvedDebugDirectory = Get-DefaultDebugDirectory -Config $config -RequestedDebugDirectory $DebugDirectory
    if (-not (Test-HasValue $NotePath) -and -not (Test-HasValue $CaptureJsonPath)) { throw 'Provide either -NotePath or -CaptureJsonPath.' }

    $script:AnalyzerCurrentStep = 'input_resolve'
    $resolvedNotePath = ''
    $frontmatter = [pscustomobject]@{}
    if (Test-HasValue $NotePath) {
        $resolvedNotePath = $NotePath
        if (-not (Test-Path $resolvedNotePath)) { throw "Note not found: $resolvedNotePath" }
        $frontmatter = Get-FrontmatterData -NoteText (Read-Utf8Text -Path $resolvedNotePath)
    }

    $resolvedCaptureJsonPath = if (Test-HasValue $CaptureJsonPath) { $CaptureJsonPath } else { Resolve-PathFromVault -VaultRoot $resolvedVaultPath -RelativeOrAbsolutePath (Get-StringValue -Data $frontmatter -Name 'sidecar_path' -DefaultValue '') }
    $capture = $null
    if (Test-HasValue $resolvedCaptureJsonPath) {
        if (-not (Test-Path $resolvedCaptureJsonPath)) { throw "Capture JSON not found: $resolvedCaptureJsonPath" }
        $capture = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $resolvedCaptureJsonPath) -Depth 100
    }
    $analysisMode = if (Test-HasValue $Mode) { $Mode } else { Get-DefaultMode -Frontmatter $frontmatter -Capture $capture }

    $script:AnalyzerCurrentStep = 'debug_prepare'
    $artifactDirectory = New-Directory -Path $resolvedDebugDirectory
    $payloadJsonPath = Join-Path $artifactDirectory 'analyzer-payload.json'

    $script:AnalyzerCurrentStep = 'payload_build'
    $payload = Build-AnalyzerPayloadWithPython -ResolvedVaultPath $resolvedVaultPath -ResolvedNotePath $resolvedNotePath -ResolvedCaptureJsonPath $resolvedCaptureJsonPath -AnalysisMode $analysisMode -PayloadJsonPath $payloadJsonPath

    $analysisJsonPath = Join-Path $artifactDirectory 'analysis-input.json'
    $llmRequestJsonPath = Join-Path $artifactDirectory 'llm-request.json'
    $llmResponseJsonPath = Join-Path $artifactDirectory 'llm-response.json'
    $promptPath = if ($analysisMode -eq 'analyze') { Join-Path $PSScriptRoot '..\references\prompts\analyze.md' } else { Join-Path $PSScriptRoot '..\references\prompts\learn.md' }
    $schemaPath = if ($analysisMode -eq 'analyze') { Join-Path $PSScriptRoot '..\references\analyze-output.schema.json' } else { '' }

    $script:AnalyzerCurrentStep = 'llm_invoke'
    if ($analysisMode -eq 'analyze' -and (Test-RealLlmConfigured -Config $config)) {
        try {
            $analysis = Invoke-AnalyzerLlmWithPython -PayloadJsonPath $payloadJsonPath -ConfigJsonPath $configPathResolved -PromptPath $promptPath -SchemaPath $schemaPath -OutputPath $analysisJsonPath -RequestJsonPath $llmRequestJsonPath -ResponseJsonPath $llmResponseJsonPath
        } catch {
            $analysis = Build-MockAnalysisResult -Payload $payload -OutputLanguage ([string]$config.analyzer.output_language)
            $analysis.analysis_status = 'mock_fallback_after_llm_error'
        }
    } else {
        $analysis = Build-MockAnalysisResult -Payload $payload -OutputLanguage ([string]$config.analyzer.output_language)
    }
    Write-Utf8Text -Path $analysisJsonPath -Content ($analysis | ConvertTo-Json -Depth 20)

    $script:AnalyzerCurrentStep = 'note_render'
    $targetFolder = if ($analysisMode -eq 'analyze') { [string]$config.analyzer.default_analyze_folder } else { [string]$config.analyzer.default_learn_folder }
    if (-not (Test-HasValue $targetFolder)) { $targetFolder = if ($analysisMode -eq 'analyze') { Zh '\u7206\u6b3e\u62c6\u89e3' } else { 'Insights' } }
    $rendererOutputJsonPath = Join-Path $artifactDirectory 'run-analyzer.json'
    $args = @((Join-Path $PSScriptRoot 'render_breakdown_note.py'), '--analysis-json', $analysisJsonPath, '--folder', $targetFolder, '--output-json', $rendererOutputJsonPath)
    if (Test-HasValue $resolvedVaultPath) { $args += @('--vault-path', $resolvedVaultPath) }
    if ($DryRun) { $args += '--dry-run' }
    $rendererOutput = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = (($rendererOutput | Out-String).Trim())
        throw "render_breakdown_note.py failed with exit code $LASTEXITCODE. Details: $detail"
    }

    $rendererResult = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $rendererOutputJsonPath) -Depth 100
    $result = [pscustomobject]@{
        success = $true
        dry_run = [bool]$DryRun
        analysis_mode = $analysisMode
        analysis_status = [string]$rendererResult.analysis_status
        title = [string]$rendererResult.title
        platform = [string]$payload.platform
        content_type = [string]$payload.content_type
        provider = if ($null -ne $analysis.PSObject.Properties['provider']) { [string]$analysis.provider } else { 'mock' }
        model = [string]$rendererResult.model
        output_language = [string]$rendererResult.output_language
        output_folder = [string]$rendererResult.folder
        analyzer_payload_path = $payloadJsonPath
        analysis_input_path = $analysisJsonPath
        analyzer_payload_warning_count = @($payload.payload_warnings).Count
        debug_directory = $artifactDirectory
        support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
    }
    if (Test-HasValue ([string]$rendererResult.note_path)) { $result | Add-Member -NotePropertyName note_path -NotePropertyValue ([string]$rendererResult.note_path) -Force }
    $result = Add-AnalyzerFinalStatusFields -Result $result

    $supportBundleDirectory = New-Directory -Path $result.support_bundle_path
    $summary = (Get-AnalyzerSummaryLines -Result $result) -join "`r`n"
    Write-Utf8Text -Path $rendererOutputJsonPath -Content (($result | ConvertTo-Json -Depth 20))
    Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-analyzer-summary.txt') -Content $summary
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer.json') -Content (((Sanitize-Value -Value $result -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20))
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer-summary.txt') -Content (($summary -replace [regex]::Escape($resolvedVaultPath), '<vault-root>'))
    if (Test-ExistingPath $payloadJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'analyzer-payload.json') -Content (((Sanitize-Value -Value $payload -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $analysisJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'analysis-input.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $analysisJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $llmRequestJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-request.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $llmRequestJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $llmResponseJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-response.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $llmResponseJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }

    Write-AnalyzerSummary -Result $result
    $json = $result | ConvertTo-Json -Depth 20
    if (Test-HasValue $OutputJsonPath) { Write-Utf8Text -Path $OutputJsonPath -Content $json }
    $json
} catch {
    if (-not (Test-HasValue $artifactDirectory)) {
        $fallbackDebugDirectory = if (Test-HasValue $resolvedDebugDirectory) { $resolvedDebugDirectory } else { Join-Path $PSScriptRoot "..\\.tmp\\run-analyzer\\$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
        $artifactDirectory = New-Directory -Path $fallbackDebugDirectory
    }
    $failure = [pscustomobject]@{
        success = $false
        dry_run = [bool]$DryRun
        analysis_mode = if (Test-HasValue $Mode) { $Mode } else { '' }
        analysis_status = 'failed'
        failed_step = $script:AnalyzerCurrentStep
        title = ''
        platform = ''
        provider = ''
        model = ''
        output_language = ''
        output_folder = ''
        analysis_input_path = ''
        debug_directory = $artifactDirectory
        support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
        error_message = $_.Exception.Message
        error_message_zh = ('Analyzer [{0}] {1}{2}' -f $script:AnalyzerCurrentStep, (Zh '\u5931\u8d25\uff1a'), $_.Exception.Message)
    }
    $failure = Add-AnalyzerFinalStatusFields -Result $failure
    $supportBundleDirectory = New-Directory -Path $failure.support_bundle_path
    $summary = (Get-AnalyzerSummaryLines -Result $failure) -join "`r`n"
    Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-analyzer.json') -Content (($failure | ConvertTo-Json -Depth 20))
    Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-analyzer-summary.txt') -Content $summary
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer.json') -Content (((Sanitize-Value -Value $failure -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20))
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer-summary.txt') -Content (($summary -replace [regex]::Escape($resolvedVaultPath), '<vault-root>'))
    if (Test-ExistingPath $payloadJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'analyzer-payload.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $payloadJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $analysisJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'analysis-input.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $analysisJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $llmRequestJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-request.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $llmRequestJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    if (Test-ExistingPath $llmResponseJsonPath) { Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-response.json') -Content (((Sanitize-Value -Value (ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $llmResponseJsonPath) -Depth 100) -VaultPath $resolvedVaultPath) | ConvertTo-Json -Depth 20)) }
    Write-AnalyzerSummary -Result $failure
    throw
}
