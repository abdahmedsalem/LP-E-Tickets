# Cree ou verifie scripts\env\flutter.mobile.env (Windows / macOS / Linux avec PowerShell)

$ErrorActionPreference = "Stop"
$Root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$envDir = Join-Path $Root "scripts\env"
$envFile = Join-Path $envDir "flutter.mobile.env"
$envExample = Join-Path $envDir "flutter.mobile.example.env"

if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
    Write-Host "Dossier cree : $envDir"
}

if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
        Write-Host "OK — cree : $envFile"
    } else {
        @"
# Configuration equipe FuelToken
ODOO_JSONRPC_BASE_URL=http://57.128.181.183:8199
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
"@ | Set-Content -Path $envFile -Encoding UTF8
        Write-Host "OK — cree $envFile (valeurs par defaut equipe)"
    }
} else {
    Write-Host "OK — deja present : $envFile"
}

Write-Host ""
Write-Host "Contenu :"
Get-Content $envFile | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
Write-Host ""
Write-Host "Lancer l'app :  .\scripts\run.cmd   ou   .\scripts\run.ps1"
