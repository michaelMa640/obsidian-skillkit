function Test-SourceInputHasValue {
    param($Value)
    $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-TrimmedUrlCandidate {
    param([string]$Value)
    if (-not (Test-SourceInputHasValue $Value)) { return '' }
    $trimmed = $Value.Trim()
    while ($trimmed.Length -gt 0 -and $trimmed[-1] -in @('"', "'", ')', ']', '}', ',', ';', '!', '?')) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }
    $trimmed
}

function Get-FirstUrlFromSourceInput {
    param([string]$InputText)
    if (-not (Test-SourceInputHasValue $InputText)) { return '' }

    $candidate = ''
    try {
        $uri = [System.Uri]$InputText.Trim()
        if ($uri.AbsoluteUri) {
            $candidate = $uri.AbsoluteUri
        }
    } catch {
    }

    if (Test-SourceInputHasValue $candidate) {
        return (Get-TrimmedUrlCandidate -Value $candidate)
    }

    $match = [regex]::Match($InputText, "https?://[^\s""'<>]+", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    Get-TrimmedUrlCandidate -Value $match.Value
}

function Resolve-SourceInput {
    param([string]$InputText)
    if (-not (Test-SourceInputHasValue $InputText)) {
        throw 'Source input is empty.'
    }

    $firstUrl = Get-FirstUrlFromSourceInput -InputText $InputText
    if (-not (Test-SourceInputHasValue $firstUrl)) {
        throw 'No URL found in source input.'
    }

    $inputTrimmed = $InputText.Trim()
    $extractionApplied = ($inputTrimmed -ne $firstUrl)
    [pscustomobject]@{
        raw_input = $InputText
        source_url = $firstUrl
        input_kind = if ($extractionApplied) { 'share_text' } else { 'url' }
        extraction_applied = [bool]$extractionApplied
    }
}
