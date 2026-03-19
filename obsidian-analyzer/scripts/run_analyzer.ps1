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

function Get-ResolvedVaultPath {
    param($Config, [string]$RequestedVaultPath)
    if (Test-HasValue $RequestedVaultPath) { return $RequestedVaultPath }
    if ($null -ne $Config.obsidian -and (Test-HasValue $Config.obsidian.vault_path)) {
        return [string]$Config.obsidian.vault_path
    }
    ''
}

function Get-FrontmatterData {
    param([string]$NoteText)
    $result = [ordered]@{}
    if (-not $NoteText.StartsWith('---')) { return [pscustomobject]$result }
    $lines = $NoteText -split "`r?`n"
    if ($lines.Count -lt 3) { return [pscustomobject]$result }
    $index = 1
    while ($index -lt $lines.Count) {
        $line = $lines[$index]
        if ($line -eq '---') { break }
        if ($line -match '^(?<key>[^:]+):\s*(?<value>.*)$') {
            $result[$Matches['key'].Trim()] = $Matches['value'].Trim().Trim("'")
        }
        $index += 1
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
    param(
        [string]$ResolvedVaultPath,
        [string]$ResolvedNotePath,
        [string]$ResolvedCaptureJsonPath,
        [string]$AnalysisMode,
        [string]$PayloadJsonPath
    )
    $pythonCommand = 'python'
    $builderScriptPath = Join-Path $PSScriptRoot 'build_analyzer_payload.py'
    $builderArguments = @($builderScriptPath, '--mode', $AnalysisMode, '--output-json', $PayloadJsonPath)
    if (Test-HasValue $ResolvedVaultPath) { $builderArguments += @('--vault-path', $ResolvedVaultPath) }
    if (Test-HasValue $ResolvedNotePath) { $builderArguments += @('--note-path', $ResolvedNotePath) }
    if (Test-HasValue $ResolvedCaptureJsonPath) { $builderArguments += @('--capture-json-path', $ResolvedCaptureJsonPath) }
    & $pythonCommand @builderArguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "build_analyzer_payload.py failed with exit code $LASTEXITCODE." }
    ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $PayloadJsonPath) -Depth 100
}

function Build-MockAnalysisResult {
    param(
        $Payload,
        [string]$OutputLanguage = 'zh-CN'
    )

    $mode = [string]$Payload.analysis_mode
    $isEnglish = $OutputLanguage.ToLowerInvariant() -in @('en', 'en-us', 'english')
    $commentHighlights = @()
    if ($null -ne $Payload.PSObject.Properties['comments']) {
        $commentHighlights = @(
            $Payload.comments |
            Select-Object -First 3 |
            ForEach-Object {
                $displayText = Get-StringValue -Data $_ -Name 'display_text' -DefaultValue ''
                if (Test-HasValue $displayText) { $displayText }
            } |
            Where-Object { Test-HasValue $_ }
        )
    }
    if ($commentHighlights.Count -eq 0 -and $null -ne $Payload.PSObject.Properties['top_comments']) {
        $commentHighlights = @($Payload.top_comments | Select-Object -First 3 | Where-Object { Test-HasValue $_ })
    }

    $metricsLike = [string]$Payload.metrics_like
    $metricsComment = [string]$Payload.metrics_comment
    $metricsShare = [string]$Payload.metrics_share
    $metricsCollect = [string]$Payload.metrics_collect
    $commentsCount = [string]$Payload.comments_count

    $sourceHighlights = @()
    if (Test-HasValue ([string]$Payload.raw_text)) {
        $sourceHighlights += [pscustomobject]@{
            quote = [string]$Payload.raw_text
            reason = 'Primary source copy from the clipping payload.'
        }
    }
    if (Test-HasValue ([string]$Payload.summary)) {
        $sourceHighlights += [pscustomobject]@{
            quote = [string]$Payload.summary
            reason = 'Capture summary used to anchor the main promise and packaging.'
        }
    }

    $analysisTitle = if ($mode -eq 'analyze') {
        if ($isEnglish) { "$($Payload.title) - Breakdown" } else { "$($Payload.title) - Analyze" }
    } else {
        if ($isEnglish) { "$($Payload.title) - Learn Note" } else { "$($Payload.title) - Learn" }
    }
    $promptTemplate = if ($mode -eq 'analyze') { 'references/prompts/analyze.md' } else { 'references/prompts/learn.md' }
    $outputContractVersion = if ($mode -eq 'analyze') { 'analyze-v1' } else { 'learn-v0' }
    $coreConclusion = if ($mode -eq 'analyze') {
        'This is deterministic mock output. The current value is validating the final analyze output contract before a real LLM adapter is connected.'
    } else {
        'This is deterministic mock output. The current value is validating the final output contract before a real LLM adapter is connected.'
    }
    $hookBreakdown = if (Test-HasValue ([string]$Payload.summary)) { [string]$Payload.summary } else { '(none)' }
    $commentFeedback = if ($commentHighlights.Count -gt 0) {
        @($commentHighlights)
    } else {
        @('Visible comments were unavailable in this payload, so audience feedback is incomplete.')
    }
    $reusableFormula = @(
        [pscustomobject]@{
            name = 'Problem opening + scenario + proof'
            detail = 'Start with a user question, explain the use case, and end with a technical or expert proof signal.'
        },
        [pscustomobject]@{
            name = 'Utility-first short video'
            detail = 'Use direct explanation and practical detail instead of entertainment-heavy performance.'
        }
    )
    $riskFlags = @(
        'This is mock output and should not be treated as final analysis.'
        'The current payload may still contain missing or weak interaction metrics.'
    ) + @($Payload.payload_warnings | Select-Object -First 3)
    $sourceHighlightItems = if ($sourceHighlights.Count -gt 0) {
        @($sourceHighlights)
    } else {
        @([pscustomobject]@{
            quote = '(none)'
            reason = 'No source highlight was available.'
        })
    }

    [pscustomobject]@{
        title = $analysisTitle
        analysis_mode = $mode
        source_note_path = [string]$Payload.source_note_path
        capture_json_path = [string]$Payload.capture_json_path
        source_url = [string]$Payload.source_url
        normalized_url = [string]$Payload.normalized_url
        platform = [string]$Payload.platform
        content_type = [string]$Payload.content_type
        capture_id = [string]$Payload.capture_id
        video_path = [string]$Payload.video_path
        analyzed_at = (Get-Date).ToString('yyyy-MM-dd')
        model = "mock:$mode"
        analysis_status = 'mock_generated'
        prompt_template = $promptTemplate
        output_contract_version = $outputContractVersion
        output_language = $OutputLanguage
        core_conclusion = $coreConclusion
        hook_breakdown = $hookBreakdown
        structure_breakdown = @(
            'Start from the explicit problem or search-intent phrasing in the title or copy.'
            'Use a short explanatory segment to anchor what the product or offer actually does.'
            'Close with concrete details, proof, or a professional signal to support trust.'
        )
        emotion_trust_signals = @(
            'Problem-led phrasing reduces comprehension cost and matches user intent.'
            'Technical wording and product detail suggest expertise and implementation credibility.'
            'Short-form packaging is direct and utility-first rather than entertainment-first.'
        )
        comment_feedback = $commentFeedback
        engagement_insights = @(
            "Likes: $metricsLike"
            "Comments: $metricsComment"
            "Shares: $metricsShare"
            "Collects: $metricsCollect"
            "Visible comments: $commentsCount"
        )
        reusable_formula = $reusableFormula
        risk_flags = $riskFlags
        source_highlights = $sourceHighlightItems
        metrics_like = $metricsLike
        metrics_comment = $metricsComment
        metrics_share = $metricsShare
        metrics_collect = $metricsCollect
        comments_count = $commentsCount
    }
}

function Test-RealLlmConfigured {
    param($Config)
    if ($null -eq $Config -or $null -eq $Config.llm) { return $false }
    $provider = [string]$Config.llm.provider
    $model = [string]$Config.llm.model
    if (-not (Test-HasValue $provider) -or -not (Test-HasValue $model)) { return $false }
    if ($provider -like 'REPLACE_*' -or $model -like 'REPLACE_*') { return $false }
    $apiKeyEnv = if (Test-HasValue ([string]$Config.llm.api_key_env)) { [string]$Config.llm.api_key_env } else { 'DASHSCOPE_API_KEY' }
    $apiKey = [Environment]::GetEnvironmentVariable($apiKeyEnv)
    Test-HasValue $apiKey
}

function Invoke-AnalyzerLlmWithPython {
    param(
        [string]$PayloadJsonPath,
        [string]$ConfigJsonPath,
        [string]$PromptPath,
        [string]$SchemaPath,
        [string]$OutputPath,
        [string]$RequestJsonPath,
        [string]$ResponseJsonPath
    )
    $pythonCommand = 'python'
    $adapterScriptPath = Join-Path $PSScriptRoot 'invoke_analyzer_llm.py'
    $arguments = @(
        $adapterScriptPath,
        '--payload-json', $PayloadJsonPath,
        '--config-json', $ConfigJsonPath,
        '--prompt-path', $PromptPath,
        '--schema-path', $SchemaPath,
        '--output-json', $OutputPath
    )
    if (Test-HasValue $RequestJsonPath) { $arguments += @('--request-json', $RequestJsonPath) }
    if (Test-HasValue $ResponseJsonPath) { $arguments += @('--response-json', $ResponseJsonPath) }
    & $pythonCommand @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "invoke_analyzer_llm.py failed with exit code $LASTEXITCODE." }
    ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $OutputPath) -Depth 100
}

function Write-AnalyzerSummary {
    param($Result)
    Write-Host ''
    Write-Host '=== Analyzer Summary ===' -ForegroundColor Cyan
    Write-Host "mode     : $($Result.analysis_mode)"
    Write-Host "platform : $($Result.platform)"
    Write-Host "title    : $($Result.title)"
    Write-Host "status   : $($Result.analysis_status)"
    if ($null -ne $Result.PSObject.Properties['provider']) {
        Write-Host "provider : $($Result.provider)"
    }
    if ($null -ne $Result.PSObject.Properties['model']) {
        Write-Host "model    : $($Result.model)"
    }
    if ($null -ne $Result.PSObject.Properties['analyzer_payload_path']) {
        Write-Host "payload  : $($Result.analyzer_payload_path)"
    }
    if ($null -ne $Result.PSObject.Properties['analyzer_payload_warning_count']) {
        Write-Host "warnings : $($Result.analyzer_payload_warning_count)"
    }
    if ($null -ne $Result.PSObject.Properties['note_path']) {
        Write-Host "note     : $($Result.note_path)"
    }
    if ($null -ne $Result.PSObject.Properties['support_bundle_path']) {
        Write-Host "share    : $($Result.support_bundle_path)"
    }
    Write-Host ''
}

function Mask-TextValue {
    param(
        [string]$Text,
        [string]$Value,
        [string]$Mask
    )
    if (-not (Test-HasValue $Value)) { return $Text }
    $masked = $Text -replace [regex]::Escape($Value), $Mask
    $jsonEncodedValue = (($Value | ConvertTo-Json -Compress).Trim('"'))
    $masked -replace [regex]::Escape($jsonEncodedValue), $Mask
}

function Sanitize-Value {
    param(
        $Value,
        [string]$VaultPath
    )
    if ($Value -is [string]) {
        if ($Value.StartsWith('data:video/')) { return '<inline-video-base64>' }
        if (Test-HasValue $VaultPath) { return $Value.Replace($VaultPath, '<vault-root>') }
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $output = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $output[$key] = Sanitize-Value -Value $Value[$key] -VaultPath $VaultPath
        }
        return [pscustomobject]$output
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(Sanitize-Value -Value $item -VaultPath $VaultPath)
        }
        return $items
    }
    if ($null -ne $Value -and $Value -is [psobject]) {
        $output = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $output[$property.Name] = Sanitize-Value -Value $property.Value -VaultPath $VaultPath
        }
        return [pscustomobject]$output
    }
    $Value
}

$configPathResolved = Get-ConfigPathResolved -RequestedPath $ConfigPath
$config = Get-Config -Path $configPathResolved
$resolvedVaultPath = Get-ResolvedVaultPath -Config $config -RequestedVaultPath $VaultPath

if (-not (Test-HasValue $NotePath) -and -not (Test-HasValue $CaptureJsonPath)) {
    throw 'Provide either -NotePath or -CaptureJsonPath.'
}

$resolvedNotePath = ''
$frontmatter = [pscustomobject]@{}
if (Test-HasValue $NotePath) {
    $resolvedNotePath = $NotePath
    if (-not (Test-Path $resolvedNotePath)) { throw "Note not found: $resolvedNotePath" }
    $noteText = Read-Utf8Text -Path $resolvedNotePath
    $frontmatter = Get-FrontmatterData -NoteText $noteText
}

$resolvedCaptureJsonPath = ''
$capture = $null
if (Test-HasValue $CaptureJsonPath) {
    $resolvedCaptureJsonPath = $CaptureJsonPath
} elseif ($null -ne $frontmatter.PSObject.Properties['sidecar_path'] -and (Test-HasValue $frontmatter.sidecar_path)) {
    $resolvedCaptureJsonPath = Resolve-PathFromVault -VaultRoot $resolvedVaultPath -RelativeOrAbsolutePath $frontmatter.sidecar_path
}

if (Test-HasValue $resolvedCaptureJsonPath) {
    if (-not (Test-Path $resolvedCaptureJsonPath)) { throw "Capture JSON not found: $resolvedCaptureJsonPath" }
    $capture = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $resolvedCaptureJsonPath) -Depth 100
}

$analysisMode = if (Test-HasValue $Mode) { $Mode } else { Get-DefaultMode -Frontmatter $frontmatter -Capture $capture }

$artifactDirectory = ''
if (Test-HasValue $DebugDirectory) {
    $artifactDirectory = New-Directory -Path $DebugDirectory
} elseif (Test-HasValue $OutputJsonPath) {
    $artifactDirectory = New-Directory -Path (Split-Path -Parent $OutputJsonPath)
}

$pythonCommand = 'python'
$rendererScriptPath = Join-Path $PSScriptRoot 'render_breakdown_note.py'
$promptPath = if ($analysisMode -eq 'analyze') { Join-Path $PSScriptRoot '..\references\prompts\analyze.md' } else { Join-Path $PSScriptRoot '..\references\prompts\learn.md' }
$schemaPath = if ($analysisMode -eq 'analyze') { Join-Path $PSScriptRoot '..\references\analyze-output.schema.json' } else { '' }
$tempDirectory = if (Test-HasValue $artifactDirectory) { $artifactDirectory } else { New-Directory -Path (Join-Path $PSScriptRoot "..\\.tmp\\analyzer-$([guid]::NewGuid().ToString('N'))") }
$payloadJsonPath = Join-Path $tempDirectory 'analyzer-payload.json'
$payload = Build-AnalyzerPayloadWithPython -ResolvedVaultPath $resolvedVaultPath -ResolvedNotePath $resolvedNotePath -ResolvedCaptureJsonPath $resolvedCaptureJsonPath -AnalysisMode $analysisMode -PayloadJsonPath $payloadJsonPath
$analysisJsonPath = Join-Path $tempDirectory 'analysis-input.json'
$llmRequestJsonPath = Join-Path $tempDirectory 'llm-request.json'
$llmResponseJsonPath = Join-Path $tempDirectory 'llm-response.json'
$analysis = $null
if ($analysisMode -eq 'analyze' -and (Test-RealLlmConfigured -Config $config)) {
    try {
        $analysis = Invoke-AnalyzerLlmWithPython -PayloadJsonPath $payloadJsonPath -ConfigJsonPath $configPathResolved -PromptPath $promptPath -SchemaPath $schemaPath -OutputPath $analysisJsonPath -RequestJsonPath $llmRequestJsonPath -ResponseJsonPath $llmResponseJsonPath
    } catch {
        $analysis = Build-MockAnalysisResult -Payload $payload -OutputLanguage ([string]$config.analyzer.output_language)
        $analysis.analysis_status = 'mock_fallback_after_llm_error'
        $analysis.risk_flags = @($analysis.risk_flags) + @("LLM adapter failed and the pipeline fell back to mock output: $($_.Exception.Message)")
    }
} else {
    $analysis = Build-MockAnalysisResult -Payload $payload -OutputLanguage ([string]$config.analyzer.output_language)
}
if (-not (Test-HasValue ([string](Get-DataValue -Data $analysis -Name 'output_language')))) {
    $defaultOutputLanguage = if (Test-HasValue ([string]$config.analyzer.output_language)) { [string]$config.analyzer.output_language } else { 'zh-CN' }
    $analysis | Add-Member -NotePropertyName output_language -NotePropertyValue $defaultOutputLanguage -Force
}

$rendererOutputJsonPath = if (Test-HasValue $artifactDirectory) { Join-Path $artifactDirectory 'run-analyzer.json' } elseif (Test-HasValue $OutputJsonPath) { $OutputJsonPath } else { Join-Path $tempDirectory 'run-analyzer.json' }
Write-Utf8Text -Path $analysisJsonPath -Content ($analysis | ConvertTo-Json -Depth 20)

$targetFolder = if ($analysisMode -eq 'analyze') { [string]$config.analyzer.default_analyze_folder } else { [string]$config.analyzer.default_learn_folder }
if (-not (Test-HasValue $targetFolder)) { $targetFolder = if ($analysisMode -eq 'analyze') { '爆款拆解' } else { 'Insights' } }

$rendererArguments = @($rendererScriptPath, '--analysis-json', $analysisJsonPath, '--folder', $targetFolder, '--output-json', $rendererOutputJsonPath)
if (Test-HasValue $resolvedVaultPath) { $rendererArguments += @('--vault-path', $resolvedVaultPath) }
if ($DryRun) { $rendererArguments += '--dry-run' }
& $pythonCommand @rendererArguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw "render_breakdown_note.py failed with exit code $LASTEXITCODE." }

$rendererResult = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $rendererOutputJsonPath) -Depth 100
$result = [ordered]@{
    success = $true
    dry_run = [bool]$DryRun
    analysis_mode = $analysisMode
    analysis_status = [string]$rendererResult.analysis_status
    title = [string]$rendererResult.title
    platform = [string]$payload.platform
    content_type = [string]$payload.content_type
    source_note_path = $resolvedNotePath
    capture_json_path = $resolvedCaptureJsonPath
    source_url = [string]$payload.source_url
    normalized_url = [string]$payload.normalized_url
    capture_id = [string]$payload.capture_id
    model = [string]$rendererResult.model
    provider = if ($null -ne $analysis.PSObject.Properties['provider']) { [string]$analysis.provider } else { if (Test-RealLlmConfigured -Config $config) { [string]$config.llm.provider } else { 'mock' } }
    provider_reported_model = if ($null -ne $analysis.PSObject.Properties['provider_reported_model']) { [string]$analysis.provider_reported_model } else { '' }
    prompt_template = [string]$rendererResult.prompt_template
    output_contract_version = [string]$rendererResult.output_contract_version
    output_language = [string]$rendererResult.output_language
    output_folder = [string]$rendererResult.folder
    output_file_name = [string]$rendererResult.file_name
    note_preview = [string]$rendererResult.note_body
    vault_path = $resolvedVaultPath
    analyzer_payload_path = $payloadJsonPath
    analyzer_payload_warning_count = @($payload.payload_warnings).Count
}
if (Test-HasValue ([string]$rendererResult.note_path)) {
    $result.note_path = [string]$rendererResult.note_path
}

if (Test-HasValue $artifactDirectory) {
    $result.debug_directory = $artifactDirectory
    $result.support_bundle_path = Join-Path $artifactDirectory 'support-bundle'
    Write-Utf8Text -Path $rendererOutputJsonPath -Content (($result | ConvertTo-Json -Depth 20))

    $summary = @(
        '=== Analyzer Summary ==='
        "mode     : $($result.analysis_mode)"
        "platform : $($result.platform)"
        "title    : $($result.title)"
        "status   : $($result.analysis_status)"
        "provider : $($result.provider)"
        "model    : $($result.model)"
        "payload  : $($result.analyzer_payload_path)"
        "warnings : $($result.analyzer_payload_warning_count)"
        "note     : $(if ($null -ne $result.PSObject.Properties['note_path']) { $result.note_path } else { '' })"
        "share    : $($result.support_bundle_path)"
    ) -join "`r`n"
    Write-Utf8Text -Path (Join-Path $artifactDirectory 'run-analyzer-summary.txt') -Content $summary

    $supportBundleDirectory = New-Directory -Path (Join-Path $artifactDirectory 'support-bundle')
    $sanitizedResultObject = Sanitize-Value -Value ([pscustomobject]$result) -VaultPath $resolvedVaultPath
    $sanitizedJson = $sanitizedResultObject | ConvertTo-Json -Depth 20
    $sanitizedSummary = Mask-TextValue -Text $summary -Value $resolvedVaultPath -Mask '<vault-root>'
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer.json') -Content $sanitizedJson
    Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'run-analyzer-summary.txt') -Content $sanitizedSummary
    if (Test-Path $payloadJsonPath) {
        $payloadRaw = Read-Utf8Text -Path $payloadJsonPath
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'analyzer-payload.json') -Content $payloadRaw
        $sanitizedPayloadObject = Sanitize-Value -Value $payload -VaultPath $resolvedVaultPath
        $sanitizedPayload = $sanitizedPayloadObject | ConvertTo-Json -Depth 20
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'analyzer-payload.json') -Content $sanitizedPayload
    }
    if (Test-Path $llmRequestJsonPath) {
        $requestRaw = Read-Utf8Text -Path $llmRequestJsonPath
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'llm-request.json') -Content $requestRaw
        $sanitizedRequestObject = Sanitize-Value -Value (ConvertFrom-JsonCompat -Json $requestRaw -Depth 100) -VaultPath $resolvedVaultPath
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-request.json') -Content ($sanitizedRequestObject | ConvertTo-Json -Depth 20)
    }
    if (Test-Path $llmResponseJsonPath) {
        $responseRaw = Read-Utf8Text -Path $llmResponseJsonPath
        Write-Utf8Text -Path (Join-Path $artifactDirectory 'llm-response.json') -Content $responseRaw
        $sanitizedResponseObject = Sanitize-Value -Value (ConvertFrom-JsonCompat -Json $responseRaw -Depth 100) -VaultPath $resolvedVaultPath
        Write-Utf8Text -Path (Join-Path $supportBundleDirectory 'llm-response.json') -Content ($sanitizedResponseObject | ConvertTo-Json -Depth 20)
    }
}

$resultObject = [pscustomobject]$result
Write-AnalyzerSummary -Result $resultObject
$json = $resultObject | ConvertTo-Json -Depth 20
if (Test-HasValue $OutputJsonPath -and -not (Test-HasValue $artifactDirectory)) {
    Write-Utf8Text -Path $OutputJsonPath -Content $json
}
$json
