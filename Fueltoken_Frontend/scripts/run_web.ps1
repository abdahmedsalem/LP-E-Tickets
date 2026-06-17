# FuelToken - Web LAN launcher for Windows PowerShell.
# Usage: .\scripts\run_web.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$Root = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $Root

$envDir = Join-Path $Root "scripts\env"
$envFile = Join-Path $envDir "flutter.mobile.env"
$envLocalOverride = Join-Path $envDir "flutter.mobile.local.env"
$TeamOdooUrl = "http://127.0.0.1:8069"
$webPort = 8091

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

if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

if (-not (Test-Path $envFile)) {
    if (Test-Path (Join-Path $envDir "flutter.mobile.example.env")) {
        Copy-Item (Join-Path $envDir "flutter.mobile.example.env") $envFile
    } else {
        @"
ODOO_JSONRPC_BASE_URL=$TeamOdooUrl
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
"@ | Set-Content -Path $envFile -Encoding UTF8
    }
}

Import-FlutterMobileEnvFile $envFile
Import-FlutterMobileEnvFile $envLocalOverride

if (-not $env:ODOO_JSONRPC_BASE_URL) {
    $env:ODOO_JSONRPC_BASE_URL = $TeamOdooUrl
}
if (-not $env:ODOO_USE_ACPEC_AUTH) { $env:ODOO_USE_ACPEC_AUTH = "true" }
if (-not $env:ODOO_FUEL_ENABLED) { $env:ODOO_FUEL_ENABLED = "true" }

$defines = @(
    "--release",
    "--dart-define=ODOO_JSONRPC_BASE_URL=$($env:ODOO_JSONRPC_BASE_URL)",
    "--dart-define=ODOO_USE_ACPEC_AUTH=$($env:ODOO_USE_ACPEC_AUTH)",
    "--dart-define=ODOO_FUEL_ENABLED=$($env:ODOO_FUEL_ENABLED)"
)

if ($env:API_BASE_URL) {
    $defines += "--dart-define=API_BASE_URL=$($env:API_BASE_URL)"
}

if ($env:ODOO_DATABASE) {
    $defines += "--dart-define=ODOO_DATABASE=$($env:ODOO_DATABASE)"
}

if ($env:ODOO_JSONRPC_CONTROLLER_PATH) {
    $defines += "--dart-define=ODOO_JSONRPC_CONTROLLER_PATH=$($env:ODOO_JSONRPC_CONTROLLER_PATH)"
}

Write-Host "Build web..." -ForegroundColor Cyan
& flutter build web @defines
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$env:PORT = "$webPort"
$env:ODOO_ORIGIN = $env:ODOO_JSONRPC_BASE_URL

$lanIp = $null
try {
    $lanIp = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -ne "WellKnown" -and
            $_.InterfaceOperationalStatus -eq "Up"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
} catch {
    $lanIp = $null
}

if (-not $lanIp) {
    $lanIp = "127.0.0.1"
}

Write-Host ""
Write-Host "Lancement du serveur web..." -ForegroundColor Cyan
Write-Host "URL locale : http://127.0.0.1:$webPort" -ForegroundColor Green
Write-Host "URL Wi-Fi   : http://$lanIp`:$webPort" -ForegroundColor Green
Write-Host "Proxy API   : $env:ODOO_ORIGIN" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "Partage aux appareils du même Wi-Fi : http://$lanIp`:$webPort" -ForegroundColor Yellow
Write-Host "Ctrl+C pour arrêter."
Write-Host ""

node "$Root\tool\web_proxy_server.js"
