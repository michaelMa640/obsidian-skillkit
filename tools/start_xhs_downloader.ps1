param(
    [switch]$ForceRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolRoot = Join-Path $PSScriptRoot 'XHS-Downloader'
$exePath = Join-Path $toolRoot 'main.exe'
$logDir = Join-Path $toolRoot 'logs'
$pidPath = Join-Path $toolRoot 'xhs-downloader.pid'
$runnerPath = Join-Path $toolRoot 'run_api_logged.cmd'
$stdoutPath = Join-Path $logDir 'stdout.log'
$stderrPath = Join-Path $logDir 'stderr.log'
$port = 5556

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "XHS-Downloader executable was not found: $exePath"
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Test-ApiReady {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/docs" -UseBasicParsing -TimeoutSec 5
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

if (Test-ApiReady) {
    if (-not $ForceRestart) {
        Write-Host "XHS-Downloader is already running."
        Write-Host "API: http://127.0.0.1:5556/xhs/detail"
        Write-Host "Logs: $stdoutPath"
        exit 0
    }

    try {
        if (Test-Path -LiteralPath $pidPath) {
            $pidText = (Get-Content -Path $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($pidText -match '^\d+$') {
                Stop-Process -Id ([int]$pidText) -Force -ErrorAction Stop
            }
        }
        Start-Sleep -Seconds 1
    } catch {
        throw "Failed to stop the existing XHS-Downloader window: $($_.Exception.Message)"
    }
}

$runnerLines = @(
    '@echo off',
    "cd /d `"$toolRoot`"",
    "`"$exePath`" api 1>>`"$stdoutPath`" 2>>`"$stderrPath`""
)
$runnerLines | Set-Content -Path $runnerPath -Encoding ascii

$wrapperProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList '/k', $runnerPath -WorkingDirectory $toolRoot -PassThru

$wrapperProcess.Id | Set-Content -Path $pidPath -Encoding ascii

Start-Sleep -Seconds 3

$started = $false
for ($attempt = 0; $attempt -lt 5; $attempt++) {
    if (Test-ApiReady) {
        $started = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $started) {
    $stderrTail = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Path $stderrPath -Tail 30 | Out-String } else { '' }
    throw "XHS-Downloader did not start responding on port ${port}.`n$stderrTail"
}

Write-Host "XHS-Downloader started successfully."
Write-Host "Window PID: $($wrapperProcess.Id)"
Write-Host "API: http://127.0.0.1:5556/xhs/detail"
Write-Host "Logs: $stdoutPath"
