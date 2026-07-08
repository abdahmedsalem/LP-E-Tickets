# FuelToken - Windows PowerShell launcher.
# Usage from the frontend root:
#   .\scripts\run.ps1
#   .\scripts\run.ps1 -d chrome
#   .\scripts\run.ps1 build apk --release

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$root = (Resolve-Path (Join-Path $scriptDir "..")).Path
Set-Location $root

$envDir = Join-Path $root "scripts\env"
$envFile = Join-Path $envDir "flutter.mobile.env"
$envExample = Join-Path $envDir "flutter.mobile.example.env"
$envLocalOverride = Join-Path $envDir "flutter.mobile.local.env"
$teamOdooUrl = "https://lpft.odoorim.com"

function Write-EnvDiag {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== FuelToken configuration ===" -ForegroundColor Cyan
    Write-Host "Project root : $root"
    Write-Host "Env folder   : $envDir"
    Write-Host $Message
    Write-Host ""
    Write-Host "If scripts\env is empty after git pull:" -ForegroundColor Yellow
    Write-Host "  git pull"
    Write-Host "  .\scripts\setup_env.cmd"
    Write-Host "  Check scripts\env\flutter.mobile.env in Explorer"
    Write-Host ""
}

if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
    } else {
        Write-EnvDiag "Env files missing - using team fallback URL."
        @"
ODOO_JSONRPC_BASE_URL=$teamOdooUrl
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
"@ | Set-Content -Path $envFile -Encoding UTF8
    }
}

function Import-FlutterMobileEnvFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $idx = $line.IndexOf("=")
        if ($idx -lt 1) {
            return
        }

        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()

        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

Import-FlutterMobileEnvFile $envFile
Import-FlutterMobileEnvFile $envLocalOverride

if (-not $env:ODOO_JSONRPC_BASE_URL) {
    $env:ODOO_JSONRPC_BASE_URL = $teamOdooUrl
    Write-EnvDiag "ODOO_JSONRPC_BASE_URL was empty - fallback: $teamOdooUrl"
}

if (-not $env:ODOO_USE_ACPEC_AUTH) {
    $env:ODOO_USE_ACPEC_AUTH = "true"
}

if (-not $env:ODOO_FUEL_ENABLED) {
    $env:ODOO_FUEL_ENABLED = "true"
}

function Test-IsLoopbackUrl {
    param([string]$Url)
    if (-not $Url) { return $false }
    $lower = $Url.ToLowerInvariant()
    return $lower.Contains("127.0.0.1") -or $lower.Contains("localhost")
}

function Enable-AdbReverseForLocalOdoo {
    if (-not (Test-IsLoopbackUrl $env:ODOO_JSONRPC_BASE_URL)) {
        return
    }

    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        Write-Host "adb introuvable - impossible d'activer le reverse pour 127.0.0.1." -ForegroundColor Yellow
        return
    }

    try {
        & adb reverse tcp:8069 tcp:8069 | Out-Null
        Write-Host "ADB reverse actif: 127.0.0.1:8069 du téléphone -> PC:8069" -ForegroundColor Green
    } catch {
        Write-Host "Impossible d'activer adb reverse. Vérifiez que l'appareil Android est connecté." -ForegroundColor Yellow
    }
}

Write-Host "Odoo: $($env:ODOO_JSONRPC_BASE_URL)" -ForegroundColor Green
Enable-AdbReverseForLocalOdoo

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
    "ACPEC_ADMIN_EMAILS",
    "ACPEC_STATION_EMAILS",
    "ODOO_RPC_LOGIN_METHOD",
    "ODOO_RPC_SESSION_ME_METHOD",
    "ODOO_RPC_LOGOUT_METHOD",
    "ODOO_RPC_COMPLETE_REGISTRATION_METHOD",
    "ODOO_RPC_LOGIN_PATH",
    "ODOO_RPC_SESSION_PATH",
    "ODOO_RPC_LOGOUT_PATH",
    "ODOO_RPC_SIGNUP_PATH",
    "ODOO_SIGNUP_COMPANY_ID",
    "ODOO_ACPEC_VERSION_PATH",
    "ODOO_ACPEC_SIGNUP_COMPANIES_PATH",
    "ODOO_ACPEC_ADMIN_ACCOUNT_REQUESTS_PATH",
    "ODOO_RPC_FUEL_WALLET_PATH",
    "ODOO_RPC_FUEL_PURCHASES_CREATE_PATH",
    "ODOO_RPC_FUEL_PURCHASES_LIST_PATH",
    "ODOO_RPC_FUEL_FACES_PATH",
    "ODOO_RPC_FUEL_QR_ISSUE_PATH",
    "ODOO_RPC_FUEL_QR_LIST_PATH",
    "ODOO_RPC_FUEL_QR_DETAIL_PATH",
    "ODOO_RPC_FUEL_QR_SPLIT_PATH",
    "ODOO_RPC_FUEL_QR_RETIRER_PATH",
    "ODOO_RPC_FUEL_QR_SEPARER_PATH",
    "ODOO_RPC_FUEL_CARNETS_TRANSFER_PATH",
    "ODOO_RPC_FUEL_STATION_QR_USE_PATH"
)

foreach ($key in $extraKeys) {
    $value = [Environment]::GetEnvironmentVariable($key, "Process")
    if ($value) {
        $defines += "--dart-define=$key=$value"
    }
}

$flutterArgs = @($args)

if ($flutterArgs.Count -gt 0 -and $flutterArgs[0] -eq "build") {
    if ($env:ODOO_JSONRPC_BASE_URL.ToLowerInvariant().StartsWith("http://")) {
        Write-Error "Build release: use HTTPS in flutter.mobile.env."
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
