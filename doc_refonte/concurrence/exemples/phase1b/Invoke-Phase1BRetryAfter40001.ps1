[CmdletBinding()]
param(
    [string]$DockerDirectory = "D:\docker_for_odoo",
    [string]$RepositoryPath = "D:\dev\github\fuelToken",
    [string]$OutputRoot = "D:\tmp\fueltoken",
    [string]$SourceDatabase = "fueltoken6",
    [string]$PgContainer = "postgres16",
    [string]$PgService = "postgres16_svc",
    [string]$PgDbUser = "postgres16_odoo",
    [string]$PgDbPassword = $env:FUELTOKEN_DIAG_PG_PASSWORD,
    [int]$PgDbPort = 5432,
    [string]$OdooContainer = "odoo19",
    [string]$OdooService = "odoo19_svc",
    [string]$ComposeFileMain = ".\docker-compose19.yml",
    [string]$ComposeFileOtp = ".\docker-compose.dev-otp.override.yml",
    [string]$SourceEvidenceDirectory = "",
    [int]$LockHoldSeconds = 15,
    [switch]$KeepDiagnosticDatabase
)

# FuelToken Phase 1B-A2
# Repository example derived from the diagnostic that produced the documented proof.
#
# Scope:
# - real HTTP station/qr/use calls against a temporary cloned database;
# - one controlled HTTP concurrency collision;
# - proof that the failed key committed no business transaction;
# - retry of the failed request with the same key and payload;
# - idempotent replay after that retry commits.
#
# Excluded:
# - no Git command;
# - no patch;
# - no schema change;
# - no source database write;
# - no cron behavior change;
# - no "exit" or terminal-closing command.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# Example safety:
# - the source database is only dumped and fingerprinted;
# - all mutations run on a timestamped temporary clone;
# - the PostgreSQL password is never stored in this repository.
#
# Supply the password through FUELTOKEN_DIAG_PG_PASSWORD, through
# -PgDbPassword, or enter it interactively when prompted.

if ([string]::IsNullOrWhiteSpace($PgDbPassword)) {
    $SecurePassword = Read-Host ("PostgreSQL password for " + $PgDbUser) -AsSecureString
    $Credential = [System.Management.Automation.PSCredential]::new(
        $PgDbUser,
        $SecurePassword
    )
    $PgDbPassword = $Credential.GetNetworkCredential().Password
}

if ([string]::IsNullOrWhiteSpace($PgDbPassword)) {
    throw "PostgreSQL password is required."
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DiagnosticDatabase = "fueltoken_phase1b_$Stamp"
$DiagnosticDbFilter = "^" + [regex]::Escape($DiagnosticDatabase) + "$"
$HttpContainerName = "fueltoken-phase1b-http-$Stamp"
$OutputDirectoryName = "phase1b_retry_after_40001_$Stamp"
$OutputDirectory = Join-Path $OutputRoot $OutputDirectoryName
$RuntimeLog = Join-Path $OutputDirectory "00_runtime_report.txt"
$SummaryPath = Join-Path $OutputDirectory "01_summary.txt"
$DockerInitialLog = Join-Path $OutputDirectory "10_docker_initial.txt"
$DatabaseInitialLog = Join-Path $OutputDirectory "11_database_initial.txt"
$CloneLog = Join-Path $OutputDirectory "12_database_clone.txt"
$FixtureLog = Join-Path $OutputDirectory "20_fixture_setup.txt"
$ManifestPath = Join-Path $OutputDirectory "21_manifest.json"
$HttpDirectory = Join-Path $OutputDirectory "http_responses"
$HttpSummaryPath = Join-Path $OutputDirectory "30_http_summary.jsonl"
$HttpServerLog = Join-Path $OutputDirectory "31_http_server.log"
$CollisionOutcomePath = Join-Path $OutputDirectory "32_collision_outcome.json"
$PreRetryDatabasePath = Join-Path $OutputDirectory "33_pre_retry_database_state.txt"
$RetryVerdictPath = Join-Path $OutputDirectory "34_retry_verdict.json"
$DatabaseEvidencePath = Join-Path $OutputDirectory "40_database_evidence.txt"
$DatabaseFinalLog = Join-Path $OutputDirectory "50_database_final.txt"
$DockerFinalLog = Join-Path $OutputDirectory "51_docker_final.txt"
$ArchivePath = Join-Path $OutputRoot "$OutputDirectoryName.tar.gz"
$FallbackZipPath = Join-Path $OutputRoot "$OutputDirectoryName.zip"
$FinalArchivePath = $ArchivePath
$FixturePythonPath = Join-Path $OutputDirectory "phase1b_http_fixture_setup.py"
$DumpPathInContainer = "/tmp/$DiagnosticDatabase.dump"
$HttpUri = "http://localhost:8019/api/acpec/fueltoken/v1/station/qr/use"

$script:MainCode = 0
$script:CleanupCode = 0
$script:ArchiveCode = 0
$script:OdooWasRunning = $false
$script:DiagnosticDatabaseCreated = $false
$script:HttpContainerStarted = $false
$script:SourceFingerprintBefore = ""
$script:SourceFingerprintAfter = ""

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $HttpDirectory | Out-Null

$EmbeddedFixturePython = @'
# -*- coding: utf-8 -*-
"""FuelToken Phase 1B-A fixture setup.

Run only through Odoo shell on a temporary cloned database.
It creates:
- three deterministic HTTP concurrency cases;
- one same-key replay case;
- one same-key / different-payload case;
- trusted station sessions and temporary Bearer tokens.

No production/source database is targeted by this file.
"""

import json
import uuid

from odoo import fields
from odoo.addons.acpec_fueltoken_core.tests.test_consume_station_concurrency import (
    _ConsumeFixtureMixin,
)


class Harness(_ConsumeFixtureMixin):
    pass


harness = Harness()
PIN = "1234"


def create_trusted_session(user, label):
    user.set_mobile_pin(PIN)
    token_data = env["acpec.mobile.session"].sudo().create_for_user(
        user,
        {
            "device_uid": "phase1b-device-%s-%s" % (
                label,
                uuid.uuid4().hex[:8],
            ),
            "device_name": "Phase 1B %s" % label,
            "platform": "android",
            "app_version": "phase1b-diagnostic",
        },
    )
    token_data["session"].action_trust_device()
    return {
        "session_id": token_data["session"].id,
        "access_token": token_data["access_token"],
        "refresh_token": token_data["refresh_token"],
        "device_uid": token_data["session"].device_uid,
    }


def create_second_station(company, label):
    user = env["res.users"].sudo().with_context(
        no_reset_password=True,
    ).create(
        harness._station_mobile_user_vals(
            env,
            {
                "name": "[TEST_ODOO_AUTO] Phase1B station %s" % label,
                "company_id": company.id,
                "company_ids": [(6, 0, [company.id])],
            },
            "phase1b-station-%s" % label,
        )
    )
    station = env["acpec.fuel.station"].sudo().create(
        {
            "name": "Phase1B station %s" % label,
            "user_id": user.id,
            "company_id": company.id,
        }
    )
    session = create_trusted_session(user, label)
    return {
        "user_id": user.id,
        "station_id": station.id,
        **session,
    }


def base_case(label):
    ids = harness._build_consume_fixture(env)
    station_user = env["res.users"].sudo().browse(
        ids["station_user_id"]
    )
    first_session = create_trusted_session(
        station_user,
        "%s-a" % label,
    )
    qr = env["acpec.fuel.qr"].sudo().browse(ids["qr_id"])
    face_line = env["acpec.fuel.face.line"].sudo().browse(
        ids["face_line_id"]
    )
    wallet = env["acpec.fuel.wallet"].sudo().browse(
        ids["wallet_id"]
    )
    client_user = env["res.users"].sudo().browse(
        ids["client_user_id"]
    )

    return {
        "ids": ids,
        "qr": qr,
        "face_line": face_line,
        "wallet": wallet,
        "client_user": client_user,
        "station_one": {
            "user_id": station_user.id,
            "station_id": ids["station_id"],
            **first_session,
        },
    }


def concurrency_case(index):
    label = "concurrency-%s" % index
    case = base_case(label)

    qr_two = env["acpec.fuel.qr"]._issue_from_available_internal(
        case["client_user"],
        case["wallet"],
        [
            {
                "face_line_id": case["face_line"].id,
                "qty": harness.QR_FACE_QTY,
            }
        ],
        idempotency_key="phase1b-source-%s-qr2" % index,
        request_hash="phase1b-source-hash-%s-qr2" % index,
    )
    station_two = create_second_station(
        case["face_line"].company_id,
        "%s-b" % label,
    )

    return {
        "case": label,
        "face_line_id": case["face_line"].id,
        "initial": {
            "qty_initial": case["face_line"].qty_initial,
            "qty_available": case["face_line"].qty_available,
            "qty_qr_active": case["face_line"].qty_qr_active,
            "qty_consumed": case["face_line"].qty_consumed,
        },
        "request_one": {
            "qr_id": case["qr"].id,
            "public_code": case["qr"].public_code,
            "idempotency_key": "phase1b-concurrency-%s-a" % index,
            "station": case["station_one"],
        },
        "request_two": {
            "qr_id": qr_two.id,
            "public_code": qr_two.public_code,
            "idempotency_key": "phase1b-concurrency-%s-b" % index,
            "station": station_two,
        },
    }


def single_case(label, key):
    case = base_case(label)
    return {
        "case": label,
        "face_line_id": case["face_line"].id,
        "qr_id": case["qr"].id,
        "public_code": case["qr"].public_code,
        "idempotency_key": key,
        "station": case["station_one"],
    }


manifest = {
    "database": env.cr.dbname,
    "started_at": fields.Datetime.to_string(fields.Datetime.now()),
    "pin": PIN,
    "baseline": {
        "transaction_max_id": env["acpec.fuel.transaction"].sudo().search(
            [],
            order="id desc",
            limit=1,
        ).id
        or 0,
        "audit_max_id": env[
            "acpec.mobile.security.audit.log"
        ].sudo().search(
            [],
            order="id desc",
            limit=1,
        ).id
        or 0,
        "error_marker_max_id": env[
            "acpec.mobile.api.error.marker"
        ].sudo().search(
            [],
            order="id desc",
            limit=1,
        ).id
        or 0,
    },
    "concurrency_cases": [
        concurrency_case(1),
    ],
}

env.cr.commit()

print(
    "PHASE1B_MANIFEST="
    + json.dumps(
        manifest,
        ensure_ascii=False,
        default=str,
        separators=(",", ":"),
    ),
    flush=True,
)
'@

Set-Content -LiteralPath $FixturePythonPath -Value $EmbeddedFixturePython -Encoding UTF8
New-Item -ItemType File -Force -Path $RuntimeLog | Out-Null
New-Item -ItemType File -Force -Path $SummaryPath | Out-Null
New-Item -ItemType File -Force -Path $HttpSummaryPath | Out-Null

function Add-ReportLine {
    param(
        [string]$Path,
        [string]$Text
    )

    Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Add-RuntimeLine {
    param([string]$Text)

    Add-ReportLine -Path $RuntimeLog -Text $Text
}

function Append-FileIfPresent {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$SectionName
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    $Content = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return
    }

    Add-ReportLine -Path $TargetPath -Text ""
    Add-ReportLine -Path $TargetPath -Text ("--- " + $SectionName + " ---")
    Add-Content -LiteralPath $TargetPath -Value $Content -Encoding UTF8
}

function Invoke-NativeCapture {
    param(
        [string]$Program,
        [string[]]$Arguments
    )

    $TemporaryBase = Join-Path ([System.IO.Path]::GetTempPath()) ("fueltoken_" + [guid]::NewGuid().ToString("N"))
    $StandardOutputPath = $TemporaryBase + ".stdout.txt"
    $StandardErrorPath = $TemporaryBase + ".stderr.txt"
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $ReturnCode = 999

    try {
        & $Program @Arguments 1> $StandardOutputPath 2> $StandardErrorPath
        $ReturnCode = $LASTEXITCODE
    }
    catch {
        $ReturnCode = 999
        Set-Content -LiteralPath $StandardErrorPath -Value $_.Exception.Message -Encoding UTF8
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    $StandardOutput = ""
    $StandardError = ""

    if (Test-Path -LiteralPath $StandardOutputPath) {
        $StandardOutput = Get-Content -LiteralPath $StandardOutputPath -Raw -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $StandardErrorPath) {
        $StandardError = Get-Content -LiteralPath $StandardErrorPath -Raw -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $StandardOutputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StandardErrorPath -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        Code = [int]$ReturnCode
        Stdout = [string]$StandardOutput
        Stderr = [string]$StandardError
    }
}

function Invoke-NativeLogged {
    param(
        [string]$Label,
        [string]$Program,
        [string[]]$Arguments,
        [string]$LogPath
    )

    Add-ReportLine -Path $LogPath -Text ""
    Add-ReportLine -Path $LogPath -Text "===== $Label ====="
    Add-ReportLine -Path $LogPath -Text ("command=" + $Program + " " + ($Arguments -join " "))

    $Result = Invoke-NativeCapture -Program $Program -Arguments $Arguments

    if (-not [string]::IsNullOrWhiteSpace($Result.Stdout)) {
        Add-ReportLine -Path $LogPath -Text "--- stdout ---"
        Add-Content -LiteralPath $LogPath -Value $Result.Stdout -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($Result.Stderr)) {
        Add-ReportLine -Path $LogPath -Text "--- stderr ---"
        Add-Content -LiteralPath $LogPath -Value $Result.Stderr -Encoding UTF8
    }

    Add-ReportLine -Path $LogPath -Text ("[return_code=" + $Result.Code + "]")
    return [int]$Result.Code
}

function Invoke-DockerLogged {
    param(
        [string]$Label,
        [string[]]$Arguments,
        [string]$LogPath
    )

    return Invoke-NativeLogged -Label $Label -Program "docker" -Arguments $Arguments -LogPath $LogPath
}

function Invoke-ComposeLogged {
    param(
        [string]$Label,
        [string[]]$Arguments,
        [string]$LogPath
    )

    $DockerArguments = @(
        "compose",
        "-f",
        $ComposeFileMain,
        "-f",
        $ComposeFileOtp
    ) + $Arguments

    return Invoke-DockerLogged -Label $Label -Arguments $DockerArguments -LogPath $LogPath
}

function Test-ContainerRunning {
    param([string]$ContainerName)

    $Result = Invoke-NativeCapture -Program "docker" -Arguments @(
        "inspect",
        "--format",
        "{{.State.Running}}",
        $ContainerName
    )

    if ($Result.Code -ne 0) {
        return $false
    }

    return ($Result.Stdout.Trim().ToLowerInvariant() -eq "true")
}

function Get-HealthCode {
    param(
        [string]$Uri = "http://localhost:8019/web/health",
        [int]$Attempts = 45,
        [int]$DelaySeconds = 2
    )

    $LastCode = 0

    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            $Response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 5
            $LastCode = [int]$Response.StatusCode

            if ($LastCode -eq 200) {
                return $LastCode
            }
        }
        catch {
            $LastCode = 0
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    return $LastCode
}

function Get-SourceDatabaseFingerprint {
    param([string]$DatabaseName)

    $Sql = @"
SELECT concat_ws(
    '|',
    current_database(),
    (
        SELECT concat_ws(
            ':',
            count(*),
            COALESCE(max(id), 0),
            COALESCE(sum(qty_initial), 0),
            COALESCE(sum(qty_available), 0),
            COALESCE(sum(qty_qr_active), 0),
            COALESCE(sum(qty_qr_blocked), 0),
            COALESCE(sum(qty_consumed), 0),
            COALESCE(sum(qty_expired), 0),
            COALESCE(sum(qty_transferred_out), 0)
        )
        FROM acpec_fuel_face_line
    ),
    (
        SELECT concat_ws(':', count(*), COALESCE(max(id), 0))
        FROM acpec_fuel_qr
    ),
    (
        SELECT concat_ws(':', count(*), COALESCE(max(id), 0))
        FROM acpec_fuel_transaction
    )
);
"@

    $Result = Invoke-NativeCapture -Program "docker" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "psql",
        "-U",
        $PgDbUser,
        "-At",
        "-v",
        "ON_ERROR_STOP=1",
        "-d",
        $DatabaseName,
        "-c",
        $Sql
    )

    if ($Result.Code -ne 0) {
        return "fingerprint_error_rc_$($Result.Code)"
    }

    return $Result.Stdout.Trim()
}

function Copy-SourceEvidence {
    if ([string]::IsNullOrWhiteSpace($SourceEvidenceDirectory)) {
        Add-RuntimeLine -Text "source_evidence=not_provided"
        return
    }

    if (-not (Test-Path -LiteralPath $SourceEvidenceDirectory)) {
        Add-RuntimeLine -Text "source_evidence_missing=$SourceEvidenceDirectory"
        return
    }

    $Destination = Join-Path $OutputDirectory "source_evidence"
    Copy-Item -LiteralPath $SourceEvidenceDirectory -Destination $Destination -Recurse -Force
    Add-RuntimeLine -Text "source_evidence_copied_from=$SourceEvidenceDirectory"
}

function New-JsonRpcBody {
    param(
        [hashtable]$Parameters,
        [int]$RequestId
    )

    return @{
        jsonrpc = "2.0"
        method = "call"
        params = $Parameters
        id = $RequestId
    } | ConvertTo-Json -Compress -Depth 20
}

function Invoke-JsonRpcRequest {
    param(
        [string]$Label,
        [string]$Token,
        [string]$Body,
        [string]$TargetPath
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $TransportOk = $false
    $StatusCode = 0
    $ResponseContent = ""
    $ErrorMessage = ""

    try {
        $Response = Invoke-WebRequest -Uri $HttpUri -Method Post -Headers @{
            Authorization = "Bearer " + $Token
        } -ContentType "application/json" -Body $Body -UseBasicParsing -TimeoutSec 90

        $TransportOk = $true
        $StatusCode = [int]$Response.StatusCode
        $ResponseContent = [string]$Response.Content
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        if ($_.Exception.Response) {
            try {
                $StatusCode = [int]$_.Exception.Response.StatusCode.value__
            }
            catch {
                $StatusCode = 0
            }
        }
    }

    $Stopwatch.Stop()

    $Record = [ordered]@{
        label = $Label
        transport_ok = $TransportOk
        http_status = $StatusCode
        elapsed_ms = $Stopwatch.ElapsedMilliseconds
        response_raw = $ResponseContent
        transport_error = $ErrorMessage
    }

    $Record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
    Add-HttpSummary -Record $Record
    return [pscustomobject]$Record
}

function Add-HttpSummary {
    param($Record)

    $BusinessSuccess = $null
    $BusinessErrorCode = $null
    $TransactionId = $null
    $ParseError = $null

    if (-not [string]::IsNullOrWhiteSpace($Record.response_raw)) {
        try {
            $Outer = $Record.response_raw | ConvertFrom-Json
            $Payload = $Outer.result

            if ($null -ne $Payload) {
                $SuccessProperty = $Payload.PSObject.Properties["success"]
                $ErrorProperty = $Payload.PSObject.Properties["error"]
                $DataProperty = $Payload.PSObject.Properties["data"]

                if ($null -ne $SuccessProperty) {
                    $BusinessSuccess = $SuccessProperty.Value
                }

                if ($null -ne $ErrorProperty) {
                    $ErrorValue = $ErrorProperty.Value

                    if ($null -ne $ErrorValue) {
                        $CodeProperty = $ErrorValue.PSObject.Properties["code"]

                        if ($null -ne $CodeProperty) {
                            $BusinessErrorCode = $CodeProperty.Value
                        }
                    }
                }

                if ($null -ne $DataProperty) {
                    $DataValue = $DataProperty.Value

                    if ($null -ne $DataValue) {
                        $TransactionProperty = $DataValue.PSObject.Properties["transaction_id"]

                        if ($null -ne $TransactionProperty) {
                            $TransactionId = $TransactionProperty.Value
                        }
                    }
                }
            }
        }
        catch {
            $ParseError = $_.Exception.Message
        }
    }

    $Summary = [ordered]@{
        label = $Record.label
        transport_ok = $Record.transport_ok
        http_status = $Record.http_status
        elapsed_ms = $Record.elapsed_ms
        business_success = $BusinessSuccess
        business_error_code = $BusinessErrorCode
        transaction_id = $TransactionId
        parse_error = $ParseError
    }

    Add-Content -LiteralPath $HttpSummaryPath -Value ($Summary | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
}

function Get-BusinessOutcome {
    param($Record)

    $BusinessSuccess = $null
    $BusinessErrorCode = $null
    $TransactionId = $null
    $Reference = $null
    $ParseError = $null

    if (-not [string]::IsNullOrWhiteSpace($Record.response_raw)) {
        try {
            $Outer = $Record.response_raw | ConvertFrom-Json
            $Payload = $Outer.result

            if ($null -ne $Payload) {
                $SuccessProperty = $Payload.PSObject.Properties["success"]
                $ErrorProperty = $Payload.PSObject.Properties["error"]
                $DataProperty = $Payload.PSObject.Properties["data"]

                if ($null -ne $SuccessProperty) {
                    $BusinessSuccess = $SuccessProperty.Value
                }

                if ($null -ne $ErrorProperty) {
                    $ErrorValue = $ErrorProperty.Value

                    if ($null -ne $ErrorValue) {
                        $CodeProperty = $ErrorValue.PSObject.Properties["code"]
                        $ReferenceProperty = $ErrorValue.PSObject.Properties["reference"]

                        if ($null -ne $CodeProperty) {
                            $BusinessErrorCode = $CodeProperty.Value
                        }

                        if ($null -ne $ReferenceProperty) {
                            $Reference = $ReferenceProperty.Value
                        }
                    }
                }

                if ($null -ne $DataProperty) {
                    $DataValue = $DataProperty.Value

                    if ($null -ne $DataValue) {
                        $TransactionProperty = $DataValue.PSObject.Properties["transaction_id"]

                        if ($null -ne $TransactionProperty) {
                            $TransactionId = $TransactionProperty.Value
                        }
                    }
                }
            }
        }
        catch {
            $ParseError = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        label = $Record.label
        transport_ok = $Record.transport_ok
        http_status = $Record.http_status
        business_success = $BusinessSuccess
        business_error_code = $BusinessErrorCode
        transaction_id = $TransactionId
        error_reference = $Reference
        parse_error = $ParseError
    }
}

function Start-HttpJob {
    param(
        [string]$Label,
        [string]$Token,
        [string]$Body
    )

    $ScriptBlock = {
        param(
            $RequestLabel,
            $RequestUri,
            $AccessToken,
            $RequestBody
        )

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $TransportOk = $false
        $StatusCode = 0
        $ResponseContent = ""
        $ErrorMessage = ""

        try {
            $Response = Invoke-WebRequest -Uri $RequestUri -Method Post -Headers @{
                Authorization = "Bearer " + $AccessToken
            } -ContentType "application/json" -Body $RequestBody -UseBasicParsing -TimeoutSec 90

            $TransportOk = $true
            $StatusCode = [int]$Response.StatusCode
            $ResponseContent = [string]$Response.Content
        }
        catch {
            $ErrorMessage = $_.Exception.Message

            if ($_.Exception.Response) {
                try {
                    $StatusCode = [int]$_.Exception.Response.StatusCode.value__
                }
                catch {
                    $StatusCode = 0
                }
            }
        }

        $Stopwatch.Stop()

        return [pscustomobject]@{
            label = $RequestLabel
            transport_ok = $TransportOk
            http_status = $StatusCode
            elapsed_ms = $Stopwatch.ElapsedMilliseconds
            response_raw = $ResponseContent
            transport_error = $ErrorMessage
        }
    }

    return Start-Job -ScriptBlock $ScriptBlock -ArgumentList @(
        $Label,
        $HttpUri,
        $Token,
        $Body
    )
}

function Save-HttpJobResult {
    param(
        $Job,
        [string]$TargetPath
    )

    Wait-Job -Job $Job -Timeout 120 | Out-Null
    $Record = Receive-Job -Job $Job -ErrorAction SilentlyContinue

    if ($null -eq $Record) {
        $Record = [pscustomobject]@{
            label = $Job.Name
            transport_ok = $false
            http_status = 0
            elapsed_ms = 0
            response_raw = ""
            transport_error = "HTTP job produced no result."
        }
    }

    $Record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
    Add-HttpSummary -Record $Record
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    return $Record
}

function Start-FaceLineLockJob {
    param(
        [int]$FaceLineId,
        [string]$Label
    )

    $Sql = @"
BEGIN;
SELECT id
FROM acpec_fuel_face_line
WHERE id = $FaceLineId
FOR UPDATE;
SELECT pg_sleep($LockHoldSeconds);
COMMIT;
"@

    $ScriptBlock = {
        param(
            $Container,
            $Database,
            $DatabaseUser,
            $DatabasePassword,
            $SqlText,
            $LockLabel
        )

        $Output = & docker exec -e ("PGPASSWORD=" + $DatabasePassword) $Container psql -U $DatabaseUser -v ON_ERROR_STOP=1 -d $Database -c $SqlText 2>&1
        $Code = $LASTEXITCODE

        return [pscustomobject]@{
            label = $LockLabel
            return_code = $Code
            output = [string]($Output -join "`n")
        }
    }

    return Start-Job -ScriptBlock $ScriptBlock -ArgumentList @(
        $PgContainer,
        $DiagnosticDatabase,
        $PgDbUser,
        $PgDbPassword,
        $Sql,
        $Label
    )
}

function Save-LockJobResult {
    param(
        $Job,
        [string]$TargetPath
    )

    Wait-Job -Job $Job -Timeout ($LockHoldSeconds + 30) | Out-Null
    $Result = Receive-Job -Job $Job -ErrorAction SilentlyContinue

    if ($null -eq $Result) {
        $Result = [pscustomobject]@{
            label = $Job.Name
            return_code = 999
            output = "Lock job produced no result."
        }
    }

    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
}

function Build-DatabaseEvidenceSql {
    param($Manifest)

    $Case = $Manifest.concurrency_cases[0]
    $FaceLineId = [int]$Case.face_line_id
    $QrOneId = [int]$Case.request_one.qr_id
    $QrTwoId = [int]$Case.request_two.qr_id
    $KeyOne = ([string]$Case.request_one.idempotency_key).Replace("'", "''")
    $KeyTwo = ([string]$Case.request_two.idempotency_key).Replace("'", "''")
    $TransactionBaseline = [int]$Manifest.baseline.transaction_max_id
    $AuditBaseline = [int]$Manifest.baseline.audit_max_id
    $MarkerBaseline = [int]$Manifest.baseline.error_marker_max_id
    $StartedAt = ([string]$Manifest.started_at).Replace("'", "''")

    return @"
SELECT 'FACE_LINE' AS section;
SELECT
    id,
    qty_initial,
    qty_available,
    qty_qr_active,
    qty_qr_blocked,
    qty_consumed,
    qty_expired,
    qty_transferred_out,
    (
        qty_available
        + qty_qr_active
        + qty_qr_blocked
        + qty_consumed
        + qty_expired
        + qty_transferred_out
    ) AS accounted_total
FROM acpec_fuel_face_line
WHERE id = $FaceLineId;

SELECT 'QRS' AS section;
SELECT
    id,
    public_code,
    state,
    consumed_station_id,
    consumed_user_id,
    consumed_at
FROM acpec_fuel_qr
WHERE id IN ($QrOneId, $QrTwoId)
ORDER BY id;

SELECT 'BUSINESS_TRANSACTIONS' AS section;
SELECT
    id,
    transaction_type,
    qr_id,
    station_id,
    idempotency_key,
    request_hash,
    operation_ref,
    create_date
FROM acpec_fuel_transaction
WHERE id > $TransactionBaseline
   OR idempotency_key IN ('$KeyOne', '$KeyTwo')
ORDER BY id;

SELECT 'TRANSACTION_COUNTS_BY_KEY' AS section;
SELECT
    idempotency_key,
    count(*) AS transaction_count,
    min(id) AS first_transaction_id,
    max(id) AS last_transaction_id
FROM acpec_fuel_transaction
WHERE idempotency_key IN ('$KeyOne', '$KeyTwo')
GROUP BY idempotency_key
ORDER BY idempotency_key;

SELECT 'SECURITY_AUDITS' AS section;
SELECT
    id,
    event_type,
    code,
    success,
    blocked,
    operation,
    idempotency_key,
    endpoint,
    create_date
FROM acpec_mobile_security_audit_log
WHERE id > $AuditBaseline
ORDER BY id;

SELECT 'API_ERROR_MARKERS' AS section;
SELECT
    id,
    name,
    code,
    endpoint,
    operation,
    exception_type,
    occurrence_count,
    first_seen_date,
    last_seen_date
FROM acpec_mobile_api_error_marker
WHERE id > $MarkerBaseline
   OR last_seen_date >= '$StartedAt'
ORDER BY id;
"@
}

function Cleanup-Runtime {
    Add-RuntimeLine -Text ""
    Add-RuntimeLine -Text "===== CLEANUP ====="

    if ($script:HttpContainerStarted) {
        $LogsResult = Invoke-NativeCapture -Program "docker" -Arguments @(
            "logs",
            $HttpContainerName
        )

        Set-Content -LiteralPath $HttpServerLog -Value $LogsResult.Stdout -Encoding UTF8

        if (-not [string]::IsNullOrWhiteSpace($LogsResult.Stderr)) {
            Add-Content -LiteralPath $HttpServerLog -Value $LogsResult.Stderr -Encoding UTF8
        }

        $StopCode = Invoke-DockerLogged -Label "stop phase1b HTTP container" -Arguments @(
            "stop",
            $HttpContainerName
        ) -LogPath $DockerFinalLog

        if ($StopCode -ne 0) {
            $script:CleanupCode = 70
        }

        $script:HttpContainerStarted = $false
    }

    Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    if ($script:DiagnosticDatabaseCreated) {
        if ($KeepDiagnosticDatabase.IsPresent) {
            Add-RuntimeLine -Text "diagnostic_database_kept=$DiagnosticDatabase"
        }
        else {
            $DropCode = Invoke-DockerLogged -Label "drop phase1b diagnostic database" -Arguments @(
                "exec",
                "-e",
                ("PGPASSWORD=" + $PgDbPassword),
                $PgContainer,
                "dropdb",
                "-U",
                $PgDbUser,
                "--if-exists",
                $DiagnosticDatabase
            ) -LogPath $DatabaseFinalLog

            if ($DropCode -ne 0) {
                $script:CleanupCode = 71
            }
            else {
                $script:DiagnosticDatabaseCreated = $false
            }
        }
    }

    $RemoveDumpCode = Invoke-DockerLogged -Label "remove phase1b temporary dump" -Arguments @(
        "exec",
        $PgContainer,
        "rm",
        "-f",
        $DumpPathInContainer
    ) -LogPath $DatabaseFinalLog

    if ($RemoveDumpCode -ne 0) {
        $script:CleanupCode = 72
    }

    if ($script:OdooWasRunning) {
        $StartCode = Invoke-ComposeLogged -Label "restart permanent Odoo" -Arguments @(
            "up",
            "-d",
            $OdooService
        ) -LogPath $DockerFinalLog

        if ($StartCode -ne 0) {
            $script:CleanupCode = 73
        }
        else {
            $HealthCode = Get-HealthCode
            Add-ReportLine -Path $DockerFinalLog -Text "health_http_code=$HealthCode"

            if ($HealthCode -ne 200) {
                $script:CleanupCode = 74
            }
        }
    }
    else {
        Add-RuntimeLine -Text "odoo_not_restarted=it_was_not_running_initially"
    }

    $FinalDockerCode = Invoke-DockerLogged -Label "final docker state" -Arguments @(
        "ps",
        "--format",
        "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ) -LogPath $DockerFinalLog

    if ($FinalDockerCode -ne 0) {
        $script:CleanupCode = 75
    }
}

try {
    Add-RuntimeLine -Text "FuelToken Phase 1B-A2 retry-after-40001 diagnostic"
    Add-RuntimeLine -Text "harness_version=1B-A2-v2-parser-fix"
    Add-RuntimeLine -Text "timestamp=$Stamp"
    Add-RuntimeLine -Text "source_database=$SourceDatabase"
    Add-RuntimeLine -Text "diagnostic_database=$DiagnosticDatabase"
    Add-RuntimeLine -Text "diagnostic_dbfilter=$DiagnosticDbFilter"
    Add-RuntimeLine -Text "http_container=$HttpContainerName"
    Add-RuntimeLine -Text "patch_applied=false"
    Add-RuntimeLine -Text "git_commands_executed=false"
    Add-RuntimeLine -Text "source_database_write_intended=false"
    Add-RuntimeLine -Text "cron_tested=false"
    Add-RuntimeLine -Text "lock_hold_seconds=$LockHoldSeconds"

    if (-not (Test-Path -LiteralPath $DockerDirectory)) {
        throw "Docker directory not found: $DockerDirectory"
    }

    Set-Location -LiteralPath $DockerDirectory
    Copy-SourceEvidence

    $DockerInitialCode = Invoke-DockerLogged -Label "initial docker state" -Arguments @(
        "ps",
        "--format",
        "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ) -LogPath $DockerInitialLog

    if ($DockerInitialCode -ne 0) {
        throw "docker ps failed"
    }

    if (-not (Test-ContainerRunning -ContainerName $PgContainer)) {
        throw "PostgreSQL container is not running: $PgContainer"
    }

    $script:OdooWasRunning = Test-ContainerRunning -ContainerName $OdooContainer
    Add-RuntimeLine -Text "odoo_was_running=$($script:OdooWasRunning)"

    $DatabaseInfoSql = @"
SELECT
    current_database(),
    current_setting('transaction_isolation'),
    current_setting('lock_timeout'),
    current_setting('deadlock_timeout'),
    version();
"@

    $ReadOnlySql = "BEGIN TRANSACTION READ ONLY; " + $DatabaseInfoSql + " COMMIT;"
    $DatabaseInitialCode = Invoke-DockerLogged -Label "source database read-only facts" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "psql",
        "-U",
        $PgDbUser,
        "-v",
        "ON_ERROR_STOP=1",
        "-d",
        $SourceDatabase,
        "-c",
        $ReadOnlySql
    ) -LogPath $DatabaseInitialLog

    if ($DatabaseInitialCode -ne 0) {
        throw "source database read-only inspection failed"
    }

    if ($script:OdooWasRunning) {
        $StopCode = Invoke-ComposeLogged -Label "stop permanent Odoo before phase1b" -Arguments @(
            "stop",
            $OdooService
        ) -LogPath $DockerInitialLog

        if ($StopCode -ne 0) {
            throw "unable to stop permanent Odoo"
        }
    }

    $script:SourceFingerprintBefore = Get-SourceDatabaseFingerprint -DatabaseName $SourceDatabase
    Add-RuntimeLine -Text "source_fingerprint_before=$($script:SourceFingerprintBefore)"

    $DumpCode = Invoke-DockerLogged -Label "dump source database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "pg_dump",
        "-U",
        $PgDbUser,
        "--format=custom",
        "--no-owner",
        "--no-acl",
        "--file=$DumpPathInContainer",
        $SourceDatabase
    ) -LogPath $CloneLog

    if ($DumpCode -ne 0) {
        throw "pg_dump failed"
    }

    $DropBeforeCode = Invoke-DockerLogged -Label "drop stale phase1b database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "dropdb",
        "-U",
        $PgDbUser,
        "--if-exists",
        $DiagnosticDatabase
    ) -LogPath $CloneLog

    if ($DropBeforeCode -ne 0) {
        throw "drop stale phase1b database failed"
    }

    $CreateCode = Invoke-DockerLogged -Label "create phase1b database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "createdb",
        "-U",
        $PgDbUser,
        "-O",
        $PgDbUser,
        $DiagnosticDatabase
    ) -LogPath $CloneLog

    if ($CreateCode -ne 0) {
        throw "create phase1b database failed"
    }

    $script:DiagnosticDatabaseCreated = $true

    $RestoreCode = Invoke-DockerLogged -Label "restore phase1b database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "pg_restore",
        "-U",
        $PgDbUser,
        "--no-owner",
        "--no-acl",
        ("--role=" + $PgDbUser),
        ("--dbname=" + $DiagnosticDatabase),
        $DumpPathInContainer
    ) -LogPath $CloneLog

    if ($RestoreCode -ne 0) {
        throw "pg_restore failed"
    }

    $FixtureComposeArguments = @(
        "compose",
        "-f",
        $ComposeFileMain,
        "-f",
        $ComposeFileOtp,
        "run",
        "--rm",
        "--no-deps",
        "-T",
        $OdooService,
        "odoo",
        "shell",
        "-d",
        $DiagnosticDatabase,
        ("--db_host=" + $PgService),
        ("--db_port=" + $PgDbPort),
        ("--db_user=" + $PgDbUser),
        ("--db_password=" + $PgDbPassword),
        "--no-http",
        "--log-level=info"
    )

    $FixtureStdout = Join-Path ([System.IO.Path]::GetTempPath()) ("phase1b_fixture_" + [guid]::NewGuid().ToString("N") + ".stdout.txt")
    $FixtureStderr = Join-Path ([System.IO.Path]::GetTempPath()) ("phase1b_fixture_" + [guid]::NewGuid().ToString("N") + ".stderr.txt")
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        Get-Content -LiteralPath $FixturePythonPath -Raw |
            & docker @FixtureComposeArguments 1> $FixtureStdout 2> $FixtureStderr
        $FixtureCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    Append-FileIfPresent -SourcePath $FixtureStdout -TargetPath $FixtureLog -SectionName "stdout"
    Append-FileIfPresent -SourcePath $FixtureStderr -TargetPath $FixtureLog -SectionName "stderr"
    Add-ReportLine -Path $FixtureLog -Text "[return_code=$FixtureCode]"

    $FixtureOutput = Get-Content -LiteralPath $FixtureStdout -Raw -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $FixtureStdout -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $FixtureStderr -Force -ErrorAction SilentlyContinue

    if ($FixtureCode -ne 0) {
        throw "phase1b fixture setup failed"
    }

    $ManifestLine = @(
        $FixtureOutput -split "`r?`n" |
        Where-Object { $_.StartsWith("PHASE1B_MANIFEST=") }
    ) | Select-Object -Last 1

    if ([string]::IsNullOrWhiteSpace($ManifestLine)) {
        throw "PHASE1B_MANIFEST line missing"
    }

    $ManifestJson = $ManifestLine.Substring("PHASE1B_MANIFEST=".Length)
    Set-Content -LiteralPath $ManifestPath -Value $ManifestJson -Encoding UTF8
    $Manifest = $ManifestJson | ConvertFrom-Json
    Add-RuntimeLine -Text "fixture_manifest_loaded=true"
    Add-RuntimeLine -Text "concurrency_case_count=$($Manifest.concurrency_cases.Count)"

    $HttpStartArguments = @(
        "compose",
        "-f",
        $ComposeFileMain,
        "-f",
        $ComposeFileOtp,
        "run",
        "-d",
        "--rm",
        "--no-deps",
        "--service-ports",
        "--name",
        $HttpContainerName,
        $OdooService,
        "odoo",
        "-d",
        $DiagnosticDatabase,
        ("--db_host=" + $PgService),
        ("--db_port=" + $PgDbPort),
        ("--db_user=" + $PgDbUser),
        ("--db_password=" + $PgDbPassword),
        ("--db-filter=" + $DiagnosticDbFilter),
        "--no-database-list",
        "--max-cron-threads=0",
        "--log-level=info"
    )

    $HttpStartResult = Invoke-NativeCapture -Program "docker" -Arguments $HttpStartArguments

    Add-ReportLine -Path $DockerInitialLog -Text ""
    Add-ReportLine -Path $DockerInitialLog -Text "===== start phase1b HTTP container ====="
    Add-Content -LiteralPath $DockerInitialLog -Value $HttpStartResult.Stdout -Encoding UTF8
    Add-Content -LiteralPath $DockerInitialLog -Value $HttpStartResult.Stderr -Encoding UTF8
    Add-ReportLine -Path $DockerInitialLog -Text "[return_code=$($HttpStartResult.Code)]"

    if ($HttpStartResult.Code -ne 0) {
        throw "unable to start phase1b HTTP container"
    }

    $script:HttpContainerStarted = $true
    $HealthCode = Get-HealthCode
    Add-RuntimeLine -Text "phase1b_http_health=$HealthCode"

    if ($HealthCode -ne 200) {
        throw "phase1b HTTP server did not become healthy"
    }

    $RoutingGuardResult = Invoke-NativeCapture -Program "docker" -Arguments @(
        "logs",
        $HttpContainerName
    )

    $RoutingGuardText = $RoutingGuardResult.Stdout + "`n" + $RoutingGuardResult.Stderr
    $ExpectedRoutingToken = $DiagnosticDatabase + " werkzeug:"
    $SourceRoutingToken = $SourceDatabase + " werkzeug:"
    $ExpectedRoutingSeen = $RoutingGuardText.Contains($ExpectedRoutingToken)
    $SourceRoutingSeen = $RoutingGuardText.Contains($SourceRoutingToken)

    Add-RuntimeLine -Text "http_db_guard_expected_token=$ExpectedRoutingToken"
    Add-RuntimeLine -Text "http_db_guard_expected_seen=$ExpectedRoutingSeen"
    Add-RuntimeLine -Text "http_db_guard_source_seen=$SourceRoutingSeen"

    Set-Content -LiteralPath (Join-Path $OutputDirectory "22_http_db_routing_guard.log") -Value $RoutingGuardText -Encoding UTF8

    if (-not $ExpectedRoutingSeen) {
        throw "HTTP database guard failed: diagnostic database was not observed in request logs"
    }

    if ($SourceRoutingSeen) {
        throw "HTTP database guard failed: source database appeared in temporary HTTP request logs"
    }

    $RequestCounter = 2000
    $Case = $Manifest.concurrency_cases[0]
    $CaseLabel = "retry_after_40001"
    $LockJob = Start-FaceLineLockJob -FaceLineId ([int]$Case.face_line_id) -Label ($CaseLabel + "_face_line_lock")

    Start-Sleep -Seconds 3

    $ParametersOne = @{
        public_code = [string]$Case.request_one.public_code
        action_code = [string]$Manifest.pin
        idempotency_key = [string]$Case.request_one.idempotency_key
    }

    $ParametersTwo = @{
        public_code = [string]$Case.request_two.public_code
        action_code = [string]$Manifest.pin
        idempotency_key = [string]$Case.request_two.idempotency_key
    }

    $RequestCounter++
    $BodyOne = New-JsonRpcBody -Parameters $ParametersOne -RequestId $RequestCounter
    $RequestCounter++
    $BodyTwo = New-JsonRpcBody -Parameters $ParametersTwo -RequestId $RequestCounter

    $JobOne = Start-HttpJob -Label ($CaseLabel + "_initial_a") -Token ([string]$Case.request_one.station.access_token) -Body $BodyOne
    $JobTwo = Start-HttpJob -Label ($CaseLabel + "_initial_b") -Token ([string]$Case.request_two.station.access_token) -Body $BodyTwo

    $RecordOne = Save-HttpJobResult -Job $JobOne -TargetPath (Join-Path $HttpDirectory ($CaseLabel + "_initial_a.json"))
    $RecordTwo = Save-HttpJobResult -Job $JobTwo -TargetPath (Join-Path $HttpDirectory ($CaseLabel + "_initial_b.json"))
    Save-LockJobResult -Job $LockJob -TargetPath (Join-Path $HttpDirectory ($CaseLabel + "_lock.json"))

    $OutcomeOne = Get-BusinessOutcome -Record $RecordOne
    $OutcomeTwo = Get-BusinessOutcome -Record $RecordTwo

    $CollisionReport = [ordered]@{
        request_a = $OutcomeOne
        request_b = $OutcomeTwo
    }

    $CollisionReport | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CollisionOutcomePath -Encoding UTF8

    $SuccessfulDescriptor = $null
    $FailedDescriptor = $null

    if ($OutcomeOne.business_success -eq $true) {
        $SuccessfulDescriptor = [pscustomobject]@{
            name = "a"
            outcome = $OutcomeOne
            key = [string]$Case.request_one.idempotency_key
            token = [string]$Case.request_one.station.access_token
            parameters = $ParametersOne
        }
    }

    if ($OutcomeTwo.business_success -eq $true) {
        $SuccessfulDescriptor = [pscustomobject]@{
            name = "b"
            outcome = $OutcomeTwo
            key = [string]$Case.request_two.idempotency_key
            token = [string]$Case.request_two.station.access_token
            parameters = $ParametersTwo
        }
    }

    if ($OutcomeOne.business_error_code -eq "SERVER_ERROR") {
        $FailedDescriptor = [pscustomobject]@{
            name = "a"
            outcome = $OutcomeOne
            key = [string]$Case.request_one.idempotency_key
            token = [string]$Case.request_one.station.access_token
            parameters = $ParametersOne
        }
    }

    if ($OutcomeTwo.business_error_code -eq "SERVER_ERROR") {
        $FailedDescriptor = [pscustomobject]@{
            name = "b"
            outcome = $OutcomeTwo
            key = [string]$Case.request_two.idempotency_key
            token = [string]$Case.request_two.station.access_token
            parameters = $ParametersTwo
        }
    }

    if ($null -eq $SuccessfulDescriptor) {
        throw "No successful request found in the controlled collision"
    }

    if ($null -eq $FailedDescriptor) {
        throw "No SERVER_ERROR request found in the controlled collision"
    }

    Add-RuntimeLine -Text ("collision_success_key=" + $SuccessfulDescriptor.key)
    Add-RuntimeLine -Text ("collision_failed_key=" + $FailedDescriptor.key)

    $EscapedSuccessKey = $SuccessfulDescriptor.key.Replace("'", "''")
    $EscapedFailedKey = $FailedDescriptor.key.Replace("'", "''")

    $PreRetrySql = @"
SELECT 'TRANSACTIONS_BEFORE_RETRY' AS section;
SELECT
    idempotency_key,
    count(*) AS transaction_count,
    min(id) AS transaction_id
FROM acpec_fuel_transaction
WHERE idempotency_key IN ('$EscapedSuccessKey', '$EscapedFailedKey')
GROUP BY idempotency_key
ORDER BY idempotency_key;

SELECT 'QR_STATES_BEFORE_RETRY' AS section;
SELECT id, public_code, state
FROM acpec_fuel_qr
WHERE id IN ($([int]$Case.request_one.qr_id), $([int]$Case.request_two.qr_id))
ORDER BY id;
"@

    $PreRetryCode = Invoke-DockerLogged -Label "database state after 40001 and before retry" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "psql",
        "-U",
        $PgDbUser,
        "-v",
        "ON_ERROR_STOP=1",
        "-d",
        $DiagnosticDatabase,
        "-c",
        $PreRetrySql
    ) -LogPath $PreRetryDatabasePath

    if ($PreRetryCode -ne 0) {
        throw "pre-retry database evidence query failed"
    }

    $RequestCounter++
    $RetryBody = New-JsonRpcBody -Parameters $FailedDescriptor.parameters -RequestId $RequestCounter
    $RetryRecord = Invoke-JsonRpcRequest -Label "failed_request_retry_same_key_same_payload" -Token $FailedDescriptor.token -Body $RetryBody -TargetPath (Join-Path $HttpDirectory "failed_request_retry.json")
    $RetryOutcome = Get-BusinessOutcome -Record $RetryRecord

    $RequestCounter++
    $ReplayBody = New-JsonRpcBody -Parameters $FailedDescriptor.parameters -RequestId $RequestCounter
    $ReplayRecord = Invoke-JsonRpcRequest -Label "failed_request_replay_after_commit_same_key" -Token $FailedDescriptor.token -Body $ReplayBody -TargetPath (Join-Path $HttpDirectory "failed_request_replay.json")
    $ReplayOutcome = Get-BusinessOutcome -Record $ReplayRecord

    $RetrySucceeded = ($RetryOutcome.business_success -eq $true)
    $ReplaySucceeded = ($ReplayOutcome.business_success -eq $true)
    $RetryTransactionPresent = ($null -ne $RetryOutcome.transaction_id)
    $ReplayTransactionPresent = ($null -ne $ReplayOutcome.transaction_id)
    $TransactionIdsEqual = (
        [string]$RetryOutcome.transaction_id -eq
        [string]$ReplayOutcome.transaction_id
    )
    $BothTransactionIdsPresent = (
        $RetryTransactionPresent -and
        $ReplayTransactionPresent
    )
    $SameTransaction = (
        $BothTransactionIdsPresent -and
        $TransactionIdsEqual
    )

    $RetryVerdict = [ordered]@{
        collision_success = $SuccessfulDescriptor.outcome
        collision_failure = $FailedDescriptor.outcome
        failed_key = $FailedDescriptor.key
        retry_outcome = $RetryOutcome
        replay_outcome = $ReplayOutcome
        retry_succeeded = $RetrySucceeded
        replay_succeeded = $ReplaySucceeded
        retry_and_replay_same_transaction = $SameTransaction
        expected_contract_met = ($RetrySucceeded -and $ReplaySucceeded -and $SameTransaction)
    }

    $RetryVerdict | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RetryVerdictPath -Encoding UTF8

    if (-not $RetryVerdict.expected_contract_met) {
        $script:MainCode = 42
        Add-RuntimeLine -Text "warning=retry_after_40001_contract_not_met"
    }

    $DatabaseEvidenceSql = Build-DatabaseEvidenceSql -Manifest $Manifest
    $EvidenceCode = Invoke-DockerLogged -Label "phase1b database evidence" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "psql",
        "-U",
        $PgDbUser,
        "-v",
        "ON_ERROR_STOP=1",
        "-d",
        $DiagnosticDatabase,
        "-c",
        $DatabaseEvidenceSql
    ) -LogPath $DatabaseEvidencePath

    if ($EvidenceCode -ne 0) {
        $script:MainCode = 40
        Add-RuntimeLine -Text "warning=database_evidence_query_failed"
    }

    $HttpResultCount = @(
        Get-Content -LiteralPath $HttpSummaryPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count

    Add-RuntimeLine -Text "http_result_count=$HttpResultCount"

    if ($HttpResultCount -ne 4) {
        if ($script:MainCode -eq 0) {
            $script:MainCode = 41
        }
        Add-RuntimeLine -Text "warning=expected_4_http_results_got_$HttpResultCount"
    }
}
catch {
    if ($script:MainCode -eq 0) {
        $script:MainCode = 50
    }

    Add-RuntimeLine -Text ("fatal_error_class=" + $_.Exception.GetType().FullName)
    Add-RuntimeLine -Text ("fatal_error_message=" + $_.Exception.Message)
    Add-RuntimeLine -Text ("fatal_error_position=" + $_.InvocationInfo.PositionMessage)
}
finally {
    try {
        $script:SourceFingerprintAfter = Get-SourceDatabaseFingerprint -DatabaseName $SourceDatabase
        Add-RuntimeLine -Text "source_fingerprint_after=$($script:SourceFingerprintAfter)"

        $BeforeAvailable = -not [string]::IsNullOrWhiteSpace($script:SourceFingerprintBefore)
        $AfterAvailable = -not [string]::IsNullOrWhiteSpace($script:SourceFingerprintAfter)

        if ($BeforeAvailable -and $AfterAvailable) {
            if ($script:SourceFingerprintBefore -ne $script:SourceFingerprintAfter) {
                Add-RuntimeLine -Text "warning=source_fingerprint_changed"

                if ($script:MainCode -eq 0) {
                    $script:MainCode = 60
                }
            }
            else {
                Add-RuntimeLine -Text "source_fingerprint_unchanged=true"
            }
        }
        else {
            Add-RuntimeLine -Text "source_fingerprint_comparison=incomplete"
        }
    }
    catch {
        Add-RuntimeLine -Text ("source_fingerprint_after_error=" + $_.Exception.Message)

        if ($script:MainCode -eq 0) {
            $script:MainCode = 61
        }
    }

    try {
        Cleanup-Runtime
    }
    catch {
        Add-RuntimeLine -Text ("cleanup_fatal_error=" + $_.Exception.Message)

        if ($script:CleanupCode -eq 0) {
            $script:CleanupCode = 79
        }
    }

    Add-ReportLine -Path $SummaryPath -Text "FuelToken Phase 1B-A2 retry-after-40001 summary"
    Add-ReportLine -Path $SummaryPath -Text "timestamp=$Stamp"
    Add-ReportLine -Path $SummaryPath -Text "source_database=$SourceDatabase"
    Add-ReportLine -Path $SummaryPath -Text "diagnostic_database=$DiagnosticDatabase"
    Add-ReportLine -Path $SummaryPath -Text "main_code=$($script:MainCode)"
    Add-ReportLine -Path $SummaryPath -Text "cleanup_code=$($script:CleanupCode)"
    Add-ReportLine -Path $SummaryPath -Text "patch_applied=false"
    Add-ReportLine -Path $SummaryPath -Text "cron_tested=false"
    Add-ReportLine -Path $SummaryPath -Text "http_dbfilter=$DiagnosticDbFilter"
    Add-ReportLine -Path $SummaryPath -Text "output_directory=$OutputDirectory"
}

$TarArguments = @(
    "-czf",
    $ArchivePath,
    "-C",
    $OutputRoot,
    $OutputDirectoryName
)

$script:ArchiveCode = Invoke-NativeLogged -Label "create phase1b tar.gz archive" -Program "tar.exe" -Arguments $TarArguments -LogPath $RuntimeLog

if ($script:ArchiveCode -ne 0) {
    Add-RuntimeLine -Text "tar_archive_failed=true"
    Add-RuntimeLine -Text "zip_fallback_started=true"

    try {
        if (Test-Path -LiteralPath $FallbackZipPath) {
            Remove-Item -LiteralPath $FallbackZipPath -Force
        }

        Compress-Archive -LiteralPath $OutputDirectory -DestinationPath $FallbackZipPath -CompressionLevel Optimal -Force
        $script:ArchiveCode = 0
        $FinalArchivePath = $FallbackZipPath
        Add-RuntimeLine -Text "zip_fallback_success=true"
    }
    catch {
        $script:ArchiveCode = 91
        $FinalArchivePath = $FallbackZipPath
        Add-RuntimeLine -Text ("zip_fallback_error=" + $_.Exception.Message)
    }
}

Add-ReportLine -Path $SummaryPath -Text "archive_code=$($script:ArchiveCode)"
Add-ReportLine -Path $SummaryPath -Text "archive=$FinalArchivePath"

Write-Host "Phase 1B-A2 retry-after-40001 diagnostic complete."
Write-Host "main_code=$($script:MainCode)"
Write-Host "cleanup_code=$($script:CleanupCode)"
Write-Host "archive_code=$($script:ArchiveCode)"
Write-Host "summary=$SummaryPath"
Write-Host "archive=$FinalArchivePath"
