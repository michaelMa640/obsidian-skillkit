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

function Get-CanonicalShareUrl {
    param([string]$Url)
    if (-not (Test-SourceInputHasValue $Url)) { return '' }

    $candidate = Get-TrimmedUrlCandidate -Value $Url
    $nestedMatch = [regex]::Match($candidate, 'https?://[^\s"''<>]+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($nestedMatch.Success) {
        $candidate = Get-TrimmedUrlCandidate -Value $nestedMatch.Value
    }

    try {
        $uri = [System.Uri]$candidate
    } catch {
        return $candidate
    }

    $hostName = $uri.Host.ToLowerInvariant()
    $path = $uri.AbsolutePath

    $queryValues = @{}
    foreach ($part in (($uri.Query.TrimStart('?')) -split '&')) {
        if (-not (Test-SourceInputHasValue $part)) { continue }
        $segments = $part -split '=', 2
        if ($segments.Count -lt 1) { continue }
        $key = [System.Uri]::UnescapeDataString($segments[0])
        $value = if ($segments.Count -gt 1) { [System.Uri]::UnescapeDataString($segments[1]) } else { '' }
        if (-not $queryValues.ContainsKey($key)) {
            $queryValues[$key] = $value
        }
    }

    if ($hostName -in @('www.douyin.com', 'douyin.com')) {
        $videoId = ''
        if (Test-SourceInputHasValue $queryValues['vid']) { $videoId = [string]$queryValues['vid'] }
        elseif (Test-SourceInputHasValue $queryValues['modal_id']) { $videoId = [string]$queryValues['modal_id'] }
        elseif ($path -match '/video/([0-9]+)') { $videoId = $Matches[1] }
        if (Test-SourceInputHasValue $videoId) {
            return "https://www.douyin.com/video/$videoId"
        }
    }

    if ($hostName -eq 'v.douyin.com' -and $path -match '^/([A-Za-z0-9_-]+)/?') {
        return "https://v.douyin.com/$($Matches[1])/"
    }

    if ($hostName -eq 'xhslink.com' -and $path -match '^/([A-Za-z0-9_-]+)/?') {
        return "https://xhslink.com/$($Matches[1])"
    }

    $builder = [System.UriBuilder]::new($uri)
    $builder.Fragment = ''
    $sanitized = $builder.Uri.AbsoluteUri
    if ($sanitized.EndsWith('/')) {
        return $sanitized.TrimEnd('/')
    }
    return $sanitized
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
        return (Get-CanonicalShareUrl -Url $candidate)
    }

    $match = [regex]::Match($InputText, 'https?://[^\s"''<>]+', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    Get-CanonicalShareUrl -Url $match.Value
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
