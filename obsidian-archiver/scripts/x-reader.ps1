param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$env:PYTHONPATH = (Resolve-Path (Join-Path $PSScriptRoot '..\..\.x-reader-site')).Path
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
& python -m x_reader.cli @Args
exit $LASTEXITCODE
