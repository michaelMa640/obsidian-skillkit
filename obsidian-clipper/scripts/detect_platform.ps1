param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'source_input_helpers.ps1')

function Get-PlatformDetection {
    param([string]$Url)

    $uri = [System.Uri]$Url
    $hostName = $uri.Host.ToLowerInvariant()

    if ($hostName -match 'xiaohongshu\.com$' -or $hostName -match 'xhslink\.com$') {
        return [pscustomobject]@{
            platform = 'xiaohongshu'
            content_type = 'social_post'
            route = 'social'
        }
    }

    if ($hostName -match 'douyin\.com$') {
        return [pscustomobject]@{
            platform = 'douyin'
            content_type = 'short_video'
            route = 'social'
        }
    }

    if ($hostName -match 'bilibili\.com$' -or $hostName -match 'b23\.tv$') {
        return [pscustomobject]@{
            platform = 'bilibili'
            content_type = 'long_video'
            route = 'video_metadata'
        }
    }

    if ($hostName -match 'youtube\.com$' -or $hostName -match 'youtu\.be$') {
        return [pscustomobject]@{
            platform = 'youtube'
            content_type = 'long_video'
            route = 'video_metadata'
        }
    }

    if ($hostName -match 'xiaoyuzhoufm\.com$') {
        return [pscustomobject]@{
            platform = 'xiaoyuzhou'
            content_type = 'podcast'
            route = 'podcast'
        }
    }

    return [pscustomobject]@{
        platform = 'web'
        content_type = 'article'
        route = 'article'
    }
}

$resolvedSourceInput = Resolve-SourceInput -InputText $SourceUrl
$detection = Get-PlatformDetection -Url $resolvedSourceInput.source_url
$detection | Add-Member -NotePropertyName 'source_url' -NotePropertyValue $resolvedSourceInput.source_url
$detection | Add-Member -NotePropertyName 'source_input_kind' -NotePropertyValue $resolvedSourceInput.input_kind
$detection | Add-Member -NotePropertyName 'source_url_extracted' -NotePropertyValue ([bool]$resolvedSourceInput.extraction_applied)
$detection | ConvertTo-Json -Depth 5
