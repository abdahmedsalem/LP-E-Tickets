# FuelToken — Windows PowerShell : .\scripts\run.ps1   ou   .\scripts\run.cmd
# Depuis la racine du depot (dossier avec pubspec.yaml).

$ErrorActionPreference = "Stop"

# Racine fiable (PSScriptRoot fonctionne meme si ExecutionPolicy bloque autrement)
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$Root = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $Root

$envDir = Join-Path $Root "scripts\env"
$envFile = Join-Path $envDir "flutter.mobile.env"
$envExample = Join-Path $envDir "flutter.mobile.example.env"
$envLocalOverride = Join-Path $envDir "flutter.mobile.local.env"

# Valeurs equipe si fichiers absents (clone ancien ou dossier env non synchronise)
$TeamOdooUrl = "http://57.128.181.183:8199"

function Write-EnvDiag {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== FuelToken — configuration ===" -ForegroundColor Cyan
    Write-Host "Racine projet : $Root"
    Write-Host "Dossier env    : $envDir"
    Write-Host $Message
    Write-Host ""
    Write-Host "Si scripts\env est vide apres git pull :" -ForegroundColor Yellow
    Write-Host "  git pull"
    Write-Host "  .\scripts\setup_env.cmd"
    Write-Host "  Verifiez dans l'explorateur : scripts\env\flutter.mobile.env"
    Write-Host ""
}

if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
    Write-Host "Dossier cree : scripts\env"
}

if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
        Write-Host "-> Cree flutter.mobile.env depuis flutter.mobile.example.env"
    } else {
        Write-EnvDiag "Fichiers env manquants — utilisation URL equipe par defaut."
        @"
# Genere par scripts\run.ps1 — faites git pull puis .\scripts\setup_env.cmd
ODOO_JSONRPC_BASE_URL=$TeamOdooUrl
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
"@ | Set-Content -Path $envFile -Encoding UTF8
    }
}

function Import-FlutterMobileEnvFile([string]$path) {
    if (-not (Test-Path $path)) { return }
    Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith("#") -or $line.Length -eq 0) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim()
        if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
        [Environment]::SetEnvironmentVariable($k, $v, "Process")
    }
}

Import-FlutterMobileEnvFile $envFile
Import-FlutterMobileEnvFile $envLocalOverride

if (-not $env:ODOO_JSONRPC_BASE_URL) {
    $env:ODOO_JSONRPC_BASE_URL = $TeamOdooUrl
    Write-EnvDiag "ODOO_JSONRPC_BASE_URL vide — fallback : $TeamOdooUrl"
}

if (-not $env:ODOO_USE_ACPEC_AUTH) { $env:ODOO_USE_ACPEC_AUTH = "true" }
if (-not $env:ODOO_FUEL_ENABLED) { $env:ODOO_FUEL_ENABLED = "true" }

Write-Host "Odoo : $($env:ODOO_JSONRPC_BASE_URL)" -ForegroundColor Green

$defines = @(
    "--dart-define=ODOO_JSONRPC_BASE_URL=$($env:ODOO_JSONRPC_BASE_URL)",
    "--dart-define=ODOO_USE_ACPEC_AUTH=$($env:ODOO_USE_ACPEC_AUTH)"
)

if ($env:API_BASE_URL) {
    $defines += "--dart-define=API_BASE_URL=$($env:API_BASE_URL)"
}

if ($env:ODOO_FUEL_ENABLED -eq "true" -or $env:ODOO_FUEL_ENABLED -eq "1") {
    $defines += "--dart-define=ODOO_FUEL_ENABLED=true"
}

if ($env:ODOO_DATABASE) {
    $defines += "--dart-define=ODOO_DATABASE=$($env:ODOO_DATABASE)"
}

if ($env:ODOO_JSONRPC_CONTROLLER_PATH) {
    $defines += "--dart-define=ODOO_JSONRPC_CONTROLLER_PATH=$($env:ODOO_JSONRPC_CONTROLLER_PATH)"
}

$extraKeys = @(
    "ACPEC_ADMIN_EMAILS", "ACPEC_STATION_EMAILS",
    "ODOO_RPC_LOGIN_METHOD", "ODOO_RPC_SESSION_ME_METHOD", "ODOO_RPC_LOGOUT_METHOD",
    "ODOO_RPC_COMPLETE_REGISTRATION_METHOD",
    "ODOO_RPC_LOGIN_PATH", "ODOO_RPC_SESSION_PATH", "ODOO_RPC_LOGOUT_PATH", "ODOO_RPC_SIGNUP_PATH",
    "ODOO_SIGNUP_COMPANY_ID",
    "ODOO_ACPEC_VERSION_PATH", "ODOO_ACPEC_SIGNUP_COMPANIES_PATH", "ODOO_ACPEC_ADMIN_ACCOUNT_REQUESTS_PATH",
    "ODOO_RPC_FUEL_WALLET_PATH", "ODOO_RPC_FUEL_PURCHASES_CREATE_PATH", "ODOO_RPC_FUEL_PURCHASES_LIST_PATH",
    "ODOO_RPC_FUEL_FACES_PATH", "ODOO_RPC_FUEL_QR_ISSUE_PATH", "ODOO_RPC_FUEL_QR_LIST_PATH",
    "ODOO_RPC_FUEL_QR_DETAIL_PATH", "ODOO_RPC_FUEL_QR_SPLIT_PATH", "ODOO_RPC_FUEL_STATION_QR_USE_PATH"
)

foreach ($k in $extraKeys) {
    $v = [Environment]::GetEnvironmentVariable($k, "Process")
    if ($v) {
        $defines += "--dart-define=$k=$v"
    }
}

$flutterArgs = $args
if ($flutterArgs.Count -gt 0 -and $flutterArgs[0] -eq "build") {
    $urlLower = $env:ODOO_JSONRPC_BASE_URL.ToLowerInvariant()
    if ($urlLower.StartsWith("http://")) {
        Write-Error "Build release : utilisez HTTPS dans flutter.mobile.env (stores)."
    }
    if ($flutterArgs.Count -gt 1) {
        $flutterArgs = @($flutterArgs | Select-Object -Skip 1)
    } else {
        $flutterArgs = @()
    }
    & flutter build @flutterArgs @defines
    exit $LASTEXITCODE
}

& flutter run @defines @flutterArgs
exit $LASTEXITCODE
