$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$target = Join-Path $scriptDir "scripts\run.ps1"

if (-not (Test-Path -LiteralPath $target)) {
    throw "Impossible de trouver le lanceur frontend: $target"
}

Push-Location $scriptDir
try {
    & $target @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
