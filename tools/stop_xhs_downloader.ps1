Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolRoot = Join-Path $PSScriptRoot 'XHS-Downloader'
$pidPath = Join-Path $toolRoot 'xhs-downloader.pid'
$port = 5556

$stopped = $false

if (Test-Path -LiteralPath $pidPath) {
    $pidText = (Get-Content -Path $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($pidText -match '^\d+$') {
        try {
            Stop-Process -Id ([int]$pidText) -Force -ErrorAction Stop
            $stopped = $true
        } catch {
        }
    }
    Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
}

if ($stopped) {
    Write-Host 'XHS-Downloader stopped.'
} else {
    Write-Host 'XHS-Downloader was not running.'
}
