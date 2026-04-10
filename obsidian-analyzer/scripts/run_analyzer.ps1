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

function Initialize-Utf8ProcessEncoding {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $script:OutputEncoding = $utf8NoBom
    $env:PYTHONIOENCODING = 'utf-8'
}

Initialize-Utf8ProcessEncoding

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

function Get-CheckMarkedTitle {
    param([string]$Title)
    $value = if (Test-HasValue $Title) { $Title.Trim() } else { '' }
    if (-not (Test-HasValue $value)) { return ([string][char]0x2713) }
    if ($value -match '^[\u2713\u2714\u221A\u2705]\s*') { return $value }
    ('{0} {1}' -f ([string][char]0x2713), $value)
}

function Get-CleanClippingNoteTitle {
    param([string]$RawTitle)
    $text = if (Test-HasValue $RawTitle) { [regex]::Replace($RawTitle.Trim(), '\s+', ' ') } else { '' }
    if (-not (Test-HasValue $text)) { return (Zh '\u672a\u547d\u540d\u526a\u85cf') }
    $text = [regex]::Replace($text, 'https?://\S+', ' ', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $text = [regex]::Replace($text, '@\S+', ' ')
    $text = [regex]::Replace($text, '#\S+', ' ')
    $text = $text.Replace((Zh '\u89c6\u9891\u5f88\u957f\uff0c\u5efa\u8bae\u5927\u5bb6\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u89c6\u9891\u5f88\u957f,\u5efa\u8bae\u5927\u5bb6\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u5efa\u8bae\u5927\u5bb6\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u5efa\u8bae\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u8bb0\u5f97\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u5148\u6536\u85cf'), ' ')
    $text = $text.Replace((Zh '\u503c\u5f97\u6536\u85cf'), ' ')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    $text = [regex]::Replace($text, '^[\s,.;:!?闂佹寧绋戠悮顐﹀焵椤掆偓閸嬪﹦妲愰幒妤佹櫖闁绘梻琛ラ崑?@\-_/]+', '')
    $text = [regex]::Replace($text, '[\s,.;:!?闂佹寧绋戠悮顐﹀焵椤掆偓閸嬪﹦妲愰幒妤佹櫖闁绘梻琛ラ崑?@\-_/]+$', '')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if (Test-HasValue $text) { return $text }
    (Zh '\u672a\u547d\u540d\u526a\u85cf')
}
function Get-SafeFileName {
    param([string]$Value)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $sanitized = -join ($Value.ToCharArray() | ForEach-Object { if ($invalidChars -contains $_) { '_' } else { $_ } })
    $trimmed = $sanitized.Trim()
    if (Test-HasValue $trimmed) { return $trimmed }
    'untitled.md'
}

function Set-FrontmatterScalarLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [int]$FrontmatterEndIndex,
        [string]$Key,
        [string]$Value
    )
    $updated = $false
    for ($index = 1; $index -lt $FrontmatterEndIndex; $index += 1) {
        if ($Lines[$index] -match ('^{0}:' -f [regex]::Escape($Key))) {
            $Lines[$index] = ('{0}: {1}' -f $Key, ("'" + $Value.Replace("'", "''") + "'"))
            $updated = $true
            break
        }
    }
    if (-not $updated) {
        $Lines.Insert($FrontmatterEndIndex, ('{0}: {1}' -f $Key, ("'" + $Value.Replace("'", "''") + "'")))
    }
}

function Mark-ClippingNoteAsAnalyzed {
    param([string]$NotePath)

    $result = [ordered]@{
        note_path = $NotePath
        changed = $false
        warning = ''
    }
    if (-not (Test-ExistingPath $NotePath)) { return [pscustomobject]$result }

    $content = Read-Utf8Text -Path $NotePath
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($content -split "`r?`n")) { $lines.Add([string]$line) }
    if ($lines.Count -eq 0) { return [pscustomobject]$result }

    $frontmatterEndIndex = -1
    if ($lines[0] -eq '---') {
        for ($index = 1; $index -lt $lines.Count; $index += 1) {
            if ($lines[$index] -eq '---') {
                $frontmatterEndIndex = $index
                break
            }
        }
    }

    $frontmatterTitle = ''
    $frontmatterCapturedAt = ''
    $frontmatterPublishedAt = ''
    $currentNoteTitle = ''
    if ($frontmatterEndIndex -gt 0) {
        for ($index = 1; $index -lt $frontmatterEndIndex; $index += 1) {
            if ($lines[$index] -match '^title:\s*''(?<value>.*)''\s*$') {
                $frontmatterTitle = $Matches['value'].Replace("''", "'")
            }
            if ($lines[$index] -match '^captured_at:\s*''(?<value>.*)''\s*$') {
                $frontmatterCapturedAt = $Matches['value'].Replace("''", "'")
            }
            if ($lines[$index] -match '^published_at:\s*''(?<value>.*)''\s*$') {
                $frontmatterPublishedAt = $Matches['value'].Replace("''", "'")
            }
            if ($lines[$index] -match '^note_title:\s*''(?<value>.*)''\s*$') {
                $currentNoteTitle = $Matches['value'].Replace("''", "'")
            }
        }
    }
    if (Test-HasValue $frontmatterTitle) {
        $currentNoteTitle = $frontmatterTitle
    }
    if (-not (Test-HasValue $currentNoteTitle)) {
        for ($index = 0; $index -lt $lines.Count; $index += 1) {
            if ($lines[$index] -match '^#\s+(?<value>.+)$') {
                $currentNoteTitle = [string]$Matches['value']
                break
            }
        }
    }
    if (-not (Test-HasValue $currentNoteTitle)) {
        $currentNoteTitle = [System.IO.Path]::GetFileNameWithoutExtension($NotePath)
    }

    $cleanNoteTitle = Get-CleanClippingNoteTitle -RawTitle $currentNoteTitle
    $markedNoteTitle = Get-CheckMarkedTitle -Title $cleanNoteTitle
    if ($markedNoteTitle -ne $currentNoteTitle) {
        $result.changed = $true
    }

    if ($frontmatterEndIndex -gt 0) {
        Set-FrontmatterScalarLine -Lines $lines -FrontmatterEndIndex $frontmatterEndIndex -Key 'note_title' -Value $markedNoteTitle
        Set-FrontmatterScalarLine -Lines $lines -FrontmatterEndIndex $frontmatterEndIndex -Key 'analyzer_status' -Value 'analyzed'
    }

    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index] -match '^#\s+') {
            $lines[$index] = '# ' + $markedNoteTitle
            break
        }
    }
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index] -match '^- Analyzer ') {
            $lines[$index] = '- Analyzer 状态: analyzed'
            break
        }
    }

    $currentFileName = [System.IO.Path]::GetFileName($NotePath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($NotePath)
    $prefix = ''
    if ($baseName -match '^(?<date>\d{4}-\d{2}-\d{2})(?:\s+|-)') {
        $prefix = $Matches['date'] + ' '
    }
    if (-not (Test-HasValue $prefix)) {
        foreach ($dateCandidate in @($frontmatterCapturedAt, $frontmatterPublishedAt)) {
            if ([string]::IsNullOrWhiteSpace($dateCandidate)) { continue }
            if ($dateCandidate -match '^(?<date>\d{4}-\d{2}-\d{2})') {
                $prefix = $Matches['date'] + ' '
                break
            }
        }
    }
    $targetNameCore = if (Test-HasValue $prefix) { $prefix + $cleanNoteTitle } else { $cleanNoteTitle }
    $targetFileName = Get-SafeFileName -Value ('{0} {1}.md' -f ([string][char]0x2713), $targetNameCore)
    if ($targetFileName -ne $currentFileName) {
        $result.changed = $true
    }
    $targetPath = Join-Path (Split-Path -Parent $NotePath) $targetFileName
    if (($targetPath -ne $NotePath) -and (Test-Path $targetPath)) {
        $result.warning = "Marked clipping note already exists: $targetPath"
        return [pscustomobject]$result
    }

    $updatedContent = ($lines -join "`n")
    if (-not $updatedContent.EndsWith("`n")) { $updatedContent += "`n" }
    Write-Utf8Text -Path $NotePath -Content $updatedContent
    if ($targetPath -ne $NotePath) {
        Move-Item -LiteralPath $NotePath -Destination $targetPath
        $result.note_path = $targetPath
    }

    [pscustomobject]$result
}

function Invoke-NoteRenderer {
    param(
        [string]$RendererScriptPath,
        [string]$AnalysisJsonPath,
        [string]$TargetFolder,
        [string]$RendererOutputJsonPath,
        [string]$ResolvedVaultPath,
        [bool]$DryRun
    )
    $vaultPathFile = ''
    $folderFile = ''
    try {
        $args = @($RendererScriptPath, '--analysis-json', $AnalysisJsonPath, '--output-json', $RendererOutputJsonPath)
        if (Test-HasValue $ResolvedVaultPath) {
            $vaultPathFile = [System.IO.Path]::GetTempFileName()
            Write-Utf8Text -Path $vaultPathFile -Content $ResolvedVaultPath
            $args += @('--vault-path-file', $vaultPathFile)
        }
        if (Test-HasValue $TargetFolder) {
            $folderFile = [System.IO.Path]::GetTempFileName()
            Write-Utf8Text -Path $folderFile -Content $TargetFolder
            $args += @('--folder-file', $folderFile)
        }
        if ($DryRun) { $args += '--dry-run' }
        $rendererOutput = & python @args 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = (($rendererOutput | Out-String).Trim())
            $rendererName = [System.IO.Path]::GetFileName($RendererScriptPath)
            throw "$rendererName failed with exit code $LASTEXITCODE. Details: $detail"
        }
        ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $RendererOutputJsonPath) -Depth 100
    } finally {
        foreach ($tempPath in @($vaultPathFile, $folderFile)) {
            if (Test-HasValue $tempPath) {
                if (Test-Path -LiteralPath $tempPath) {
                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
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
    'knowledge'
}

function Get-NormalizedAnalysisMode {
    param([string]$Mode)
    $normalized = if (Test-HasValue $Mode) { $Mode.Trim().ToLowerInvariant() } else { '' }
    switch ($normalized) {
        'learn' { 'knowledge' }
        'analyze' { 'analyze' }
        'knowledge' { 'knowledge' }
        default {
            if (Test-HasValue $normalized) { $normalized } else { 'knowledge' }
        }
    }
}

function Get-PromptPathForMode {
    param([string]$AnalysisMode)
    switch (Get-NormalizedAnalysisMode -Mode $AnalysisMode) {
        'analyze' { Join-Path $PSScriptRoot '..\references\prompts\analyze.md' }
        default { Join-Path $PSScriptRoot '..\references\prompts\knowledge.md' }
    }
}

function Get-SchemaPathForMode {
    param([string]$AnalysisMode)
    switch (Get-NormalizedAnalysisMode -Mode $AnalysisMode) {
        'analyze' { Join-Path $PSScriptRoot '..\references\analyze-output.schema.json' }
        default { Join-Path $PSScriptRoot '..\references\knowledge-output.schema.json' }
    }
}

function Get-RendererScriptPathForMode {
    param([string]$AnalysisMode)
    switch (Get-NormalizedAnalysisMode -Mode $AnalysisMode) {
        'analyze' { Join-Path $PSScriptRoot 'render_breakdown_note.py' }
        default { Join-Path $PSScriptRoot 'render_knowledge_note.py' }
    }
}

function Get-TargetFolderForMode {
    param($Config, [string]$AnalysisMode)
    $normalizedMode = Get-NormalizedAnalysisMode -Mode $AnalysisMode
    if ($normalizedMode -eq 'analyze') {
        $configuredFolder = if ($null -ne $Config.analyzer) { [string]$Config.analyzer.default_analyze_folder } else { '' }
        if (Test-HasValue $configuredFolder) { return $configuredFolder }
        return (Zh '\u7206\u6b3e\u62c6\u89e3')
    }

    $configuredKnowledgeFolder = if ($null -ne $Config.analyzer) { [string]$Config.analyzer.default_knowledge_folder } else { '' }
    if (-not (Test-HasValue $configuredKnowledgeFolder) -and $null -ne $Config.analyzer) {
        $configuredKnowledgeFolder = [string]$Config.analyzer.default_learn_folder
    }
    if (Test-HasValue $configuredKnowledgeFolder) { return $configuredKnowledgeFolder }
    (Zh 'Insights/\u77e5\u8bc6\u89e3\u8bfb')
}

function Build-AnalyzerPayloadWithPython {
    param([string]$ResolvedVaultPath, [string]$ResolvedNotePath, [string]$ResolvedCaptureJsonPath, [string]$AnalysisMode, [string]$PayloadJsonPath)
    $vaultPathFile = ''
    $notePathFile = ''
    $captureJsonPathFile = ''
    try {
        $args = @((Join-Path $PSScriptRoot 'build_analyzer_payload.py'), '--mode', $AnalysisMode, '--output-json', $PayloadJsonPath)
        if (Test-HasValue $ResolvedVaultPath) {
            $vaultPathFile = [System.IO.Path]::GetTempFileName()
            Write-Utf8Text -Path $vaultPathFile -Content $ResolvedVaultPath
            $args += @('--vault-path-file', $vaultPathFile)
        }
        if (Test-HasValue $ResolvedNotePath) {
            $notePathFile = [System.IO.Path]::GetTempFileName()
            Write-Utf8Text -Path $notePathFile -Content $ResolvedNotePath
            $args += @('--note-path-file', $notePathFile)
        }
        if (Test-HasValue $ResolvedCaptureJsonPath) {
            $captureJsonPathFile = [System.IO.Path]::GetTempFileName()
            Write-Utf8Text -Path $captureJsonPathFile -Content $ResolvedCaptureJsonPath
            $args += @('--capture-json-path-file', $captureJsonPathFile)
        }
        $output = & python @args 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = (($output | Out-String).Trim())
            throw "build_analyzer_payload.py failed with exit code $LASTEXITCODE. Details: $detail"
        }
        ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $PayloadJsonPath) -Depth 100
    } finally {
        foreach ($tempPath in @($vaultPathFile, $notePathFile, $captureJsonPathFile)) {
            if (Test-HasValue $tempPath) {
                if (Test-Path -LiteralPath $tempPath) {
                    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
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
    $analysisMode = Get-NormalizedAnalysisMode -Mode (Get-StringValue -Data $Payload -Name 'analysis_mode' -DefaultValue 'knowledge')
    $analysisGoal = if ($analysisMode -eq 'analyze') { 'analyze' } else { 'knowledge' }

    if ($analysisMode -eq 'analyze') {
        return [pscustomobject]@{
            title = Get-StringValue -Data $Payload -Name 'title' -DefaultValue 'Untitled'
            analysis_mode = 'analyze'
            analysis_goal = $analysisGoal
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
            audio_path = Get-StringValue -Data $Payload -Name 'audio_path' -DefaultValue ''
            transcript_path = Get-StringValue -Data $Payload -Name 'transcript_path' -DefaultValue ''
            transcript_raw_path = Get-StringValue -Data $Payload -Name 'transcript_raw_path' -DefaultValue ''
            transcript_segments_path = Get-StringValue -Data $Payload -Name 'transcript_segments_path' -DefaultValue ''
            asr_normalization = Get-StringValue -Data $Payload -Name 'asr_normalization' -DefaultValue ''
        }
    }

    [pscustomobject]@{
        title = Get-StringValue -Data $Payload -Name 'title' -DefaultValue 'Untitled'
        analysis_mode = 'knowledge'
        analysis_goal = $analysisGoal
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
        model = 'mock:knowledge'
        analysis_status = 'mock_generated'
        prompt_template = 'references/prompts/knowledge.md'
        output_contract_version = 'knowledge-v1'
        output_language = $OutputLanguage
        content_summary = Get-StringValue -Data $Payload -Name 'summary' -DefaultValue (Get-StringValue -Data $Payload -Name 'description' -DefaultValue 'This is mock output generated because no real model was invoked.')
        core_points = @()
        methods = @()
        tips_and_facts = @()
        concepts = @()
        knowledge_cards = @()
        topic_candidates = @()
        action_items = @()
        open_questions = @()
        quotes = @()
        timestamp_index = @()
        speaker_map = @()
        source_highlights = @()
        video_path = Get-StringValue -Data $Payload -Name 'video_path' -DefaultValue ''
        audio_path = Get-StringValue -Data $Payload -Name 'audio_path' -DefaultValue ''
        transcript_path = Get-StringValue -Data $Payload -Name 'transcript_path' -DefaultValue ''
        transcript_raw_path = Get-StringValue -Data $Payload -Name 'transcript_raw_path' -DefaultValue ''
        transcript_segments_path = Get-StringValue -Data $Payload -Name 'transcript_segments_path' -DefaultValue ''
        asr_normalization = Get-StringValue -Data $Payload -Name 'asr_normalization' -DefaultValue ''
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
    if ([bool]$Result.dry_run -or $status -in @('success', 'partial', 'completed')) {
        if ([bool]$Result.dry_run) {
            $messageEn = 'Dry run completed successfully.'
            $messageZh = Zh 'DryRun \u5df2\u6210\u529f\u5b8c\u6210\u3002'
        } elseif ($status -eq 'partial') {
            $messageEn = 'The analyzer run completed with partial output.'
            $messageZh = Zh '\u672c\u6b21 Analyzer \u8fd0\u884c\u5df2\u5b8c\u6210\uff0c\u4f46\u8f93\u51fa\u4e3a partial\u3002'
        } elseif ($status -eq 'completed') {
            $messageEn = 'The analyzer run completed successfully.'
            $messageZh = Zh '\u672c\u6b21 Analyzer \u8fd0\u884c\u6210\u529f\u5b8c\u6210\u3002'
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
    if ($null -ne $Result.PSObject.Properties['analysis_goal']) { $lines.Add("goal     : $($Result.analysis_goal)") }
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
    if ($null -ne $Result.PSObject.Properties['source_note_path'] -and (Test-HasValue ([string]$Result.source_note_path))) { $lines.Add("source   : $($Result.source_note_path)") }
    if ($null -ne $Result.PSObject.Properties['clipping_note_marked']) { $lines.Add("marked   : $($Result.clipping_note_marked)") }
    if ($null -ne $Result.PSObject.Properties['clipping_note_mark_warning'] -and (Test-HasValue ([string]$Result.clipping_note_mark_warning))) { $lines.Add("markwarn : $($Result.clipping_note_mark_warning)") }
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
        } elseif ($line -like 'result   : FAILED' -or $line -like 'step     :*') {
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
$analysisMode = ''
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

    $resolvedCaptureJsonPath = if (Test-HasValue $CaptureJsonPath) {
        Resolve-PathFromVault -VaultRoot $resolvedVaultPath -RelativeOrAbsolutePath $CaptureJsonPath
    } else {
        Resolve-PathFromVault -VaultRoot $resolvedVaultPath -RelativeOrAbsolutePath (Get-StringValue -Data $frontmatter -Name 'sidecar_path' -DefaultValue '')
    }
    $capture = $null
    if (Test-HasValue $resolvedCaptureJsonPath) {
        if (-not (Test-Path $resolvedCaptureJsonPath)) { throw "Capture JSON not found: $resolvedCaptureJsonPath" }
        $capture = ConvertFrom-JsonCompat -Json (Read-Utf8Text -Path $resolvedCaptureJsonPath) -Depth 100
    }
    $analysisMode = if (Test-HasValue $Mode) { Get-NormalizedAnalysisMode -Mode $Mode } else { Get-NormalizedAnalysisMode -Mode (Get-DefaultMode -Frontmatter $frontmatter -Capture $capture) }

    $script:AnalyzerCurrentStep = 'debug_prepare'
    $artifactDirectory = New-Directory -Path $resolvedDebugDirectory
    $payloadJsonPath = Join-Path $artifactDirectory 'analyzer-payload.json'

    $script:AnalyzerCurrentStep = 'payload_build'
    $payload = Build-AnalyzerPayloadWithPython -ResolvedVaultPath $resolvedVaultPath -ResolvedNotePath $resolvedNotePath -ResolvedCaptureJsonPath $resolvedCaptureJsonPath -AnalysisMode $analysisMode -PayloadJsonPath $payloadJsonPath

    $analysisJsonPath = Join-Path $artifactDirectory 'analysis-input.json'
    $llmRequestJsonPath = Join-Path $artifactDirectory 'llm-request.json'
    $llmResponseJsonPath = Join-Path $artifactDirectory 'llm-response.json'
    $promptPath = Get-PromptPathForMode -AnalysisMode $analysisMode
    $schemaPath = Get-SchemaPathForMode -AnalysisMode $analysisMode

    $script:AnalyzerCurrentStep = 'llm_invoke'
    if (Test-RealLlmConfigured -Config $config) {
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
    $targetFolder = Get-TargetFolderForMode -Config $config -AnalysisMode $analysisMode
    $rendererScriptPath = Get-RendererScriptPathForMode -AnalysisMode $analysisMode
    $rendererOutputJsonPath = Join-Path $artifactDirectory 'run-analyzer.json'
    $rendererResult = Invoke-NoteRenderer -RendererScriptPath $rendererScriptPath -AnalysisJsonPath $analysisJsonPath -TargetFolder $targetFolder -RendererOutputJsonPath $rendererOutputJsonPath -ResolvedVaultPath $resolvedVaultPath -DryRun ([bool]$DryRun)

    $markedSourceNotePath = Get-StringValue -Data $payload -Name 'source_note_path' -DefaultValue ''
    $clippingNoteMarked = $false
    $clippingNoteMarkWarning = ''
    if (-not [bool]$DryRun -and $analysisMode -eq 'analyze' -and $rendererResult.analysis_status -in @('success', 'partial', 'completed')) {
        $markResult = Mark-ClippingNoteAsAnalyzed -NotePath $markedSourceNotePath
        $markedSourceNotePath = [string]$markResult.note_path
        $clippingNoteMarked = [bool]$markResult.changed
        $clippingNoteMarkWarning = [string]$markResult.warning
        if (Test-HasValue $markedSourceNotePath) {
            Set-ObjectField -Object $payload -Name 'source_note_path' -Value $markedSourceNotePath | Out-Null
            Set-ObjectField -Object $analysis -Name 'source_note_path' -Value $markedSourceNotePath | Out-Null
            Write-Utf8Text -Path $analysisJsonPath -Content ($analysis | ConvertTo-Json -Depth 20)
            $rendererResult = Invoke-NoteRenderer -RendererScriptPath $rendererScriptPath -AnalysisJsonPath $analysisJsonPath -TargetFolder $targetFolder -RendererOutputJsonPath $rendererOutputJsonPath -ResolvedVaultPath $resolvedVaultPath -DryRun $false
        }
    }

    $result = [pscustomobject]@{
        success = $true
        dry_run = [bool]$DryRun
        analysis_mode = $analysisMode
        analysis_goal = Get-StringValue -Data $payload -Name 'analysis_goal' -DefaultValue $(if ($analysisMode -eq 'analyze') { 'analyze' } else { 'knowledge' })
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
        source_note_path = $markedSourceNotePath
        clipping_note_marked = [bool]$clippingNoteMarked
        clipping_note_mark_warning = $clippingNoteMarkWarning
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
        analysis_mode = if (Test-HasValue $analysisMode) { $analysisMode } else { Get-NormalizedAnalysisMode -Mode $Mode }
        analysis_goal = if ((if (Test-HasValue $analysisMode) { $analysisMode } else { Get-NormalizedAnalysisMode -Mode $Mode }) -eq 'analyze') { 'analyze' } else { 'knowledge' }
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
