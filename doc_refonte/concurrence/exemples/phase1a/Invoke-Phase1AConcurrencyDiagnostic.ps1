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
    [string]$DiagnosticPythonPath = "",
    [string]$SourceEvidenceDirectory = "",
    [switch]$KeepDiagnosticDatabase
)

# FuelToken — Phase 1A runtime diagnostic.
# Repository example derived from the diagnostic that produced the documented proof.
#
# PowerShell only:
#   Docker, Odoo, PostgreSQL, temporary database, runtime diagnostics,
#   health check and final archive.
#
# No Git command. No patch application. No "exit". No terminal-closing command.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# PowerShell 7 can promote non-zero native exits to PowerShell errors.
# The script handles native return codes explicitly instead.
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

if ([string]::IsNullOrWhiteSpace($DiagnosticPythonPath)) {
    $DiagnosticPythonPath = Join-Path $PSScriptRoot "phase1a_concurrency_diag.py"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DiagnosticDatabase = "fueltoken_lockdiag_$Stamp"
$OutputDirectoryName = "phase1a_runtime_$Stamp"
$OutputDirectory = Join-Path $OutputRoot $OutputDirectoryName
$RuntimeLog = Join-Path $OutputDirectory "00_runtime_report.txt"
$SummaryPath = Join-Path $OutputDirectory "01_summary.txt"
$DockerInitialLog = Join-Path $OutputDirectory "10_docker_initial.txt"
$DatabaseInitialLog = Join-Path $OutputDirectory "11_database_initial.txt"
$CloneLog = Join-Path $OutputDirectory "12_database_clone.txt"
$OdooShellLog = Join-Path $OutputDirectory "20_odoo_shell.txt"
$ResultsPath = Join-Path $OutputDirectory "21_results.jsonl"
$ResultSummaryPath = Join-Path $OutputDirectory "22_results_summary.txt"
$DatabaseFinalLog = Join-Path $OutputDirectory "30_database_final.txt"
$DockerFinalLog = Join-Path $OutputDirectory "31_docker_final.txt"
$ArchivePath = Join-Path $OutputRoot "$OutputDirectoryName.tar.gz"
$FallbackZipPath = Join-Path $OutputRoot "$OutputDirectoryName.zip"
$FinalArchivePath = $ArchivePath
$CopiedPythonPath = Join-Path $OutputDirectory "phase1a_concurrency_diag.py"
$DumpPathInContainer = "/tmp/$DiagnosticDatabase.dump"

$script:MainCode = 0
$script:CleanupCode = 0
$script:ArchiveCode = 0
$script:OdooWasRunning = $false
$script:DiagnosticDatabaseCreated = $false
$script:SourceFingerprintBefore = ""
$script:SourceFingerprintAfter = ""

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
New-Item -ItemType File -Force -Path $RuntimeLog | Out-Null
New-Item -ItemType File -Force -Path $SummaryPath | Out-Null

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
        Add-ReportLine -Path $LogPath -Text ("native_wrapper_error=" + $_.Exception.Message)
        $ReturnCode = 999
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    Append-FileIfPresent -SourcePath $StandardOutputPath -TargetPath $LogPath -SectionName "stdout"
    Append-FileIfPresent -SourcePath $StandardErrorPath -TargetPath $LogPath -SectionName "stderr"

    Remove-Item -LiteralPath $StandardOutputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StandardErrorPath -Force -ErrorAction SilentlyContinue

    Add-ReportLine -Path $LogPath -Text "[return_code=$ReturnCode]"
    return [int]$ReturnCode
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

    $Value = & docker inspect --format "{{.State.Running}}" $ContainerName 2>$null
    $ReturnCode = $LASTEXITCODE

    if ($ReturnCode -ne 0) {
        return $false
    }

    $TextValue = [string]($Value -join "")
    return ($TextValue.Trim().ToLowerInvariant() -eq "true")
}

function Get-HealthCode {
    param(
        [string]$Uri = "http://localhost:8019/web/health",
        [int]$Attempts = 30,
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
        SELECT concat_ws(
            ':',
            count(*),
            COALESCE(max(id), 0)
        )
        FROM acpec_fuel_qr
    ),
    (
        SELECT concat_ws(
            ':',
            count(*),
            COALESCE(max(id), 0)
        )
        FROM acpec_fuel_transaction
    )
);
"@

    $Arguments = @(
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

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $Output = & docker @Arguments 2>$null
        $ReturnCode = $LASTEXITCODE
    }
    catch {
        $ReturnCode = 999
        $Output = @()
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($ReturnCode -ne 0) {
        return "fingerprint_error_rc_$ReturnCode"
    }

    return ([string]($Output -join "")).Trim()
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

function Write-ResultSummary {
    param(
        [string]$JsonLinesPath,
        [string]$TargetPath
    )

    New-Item -ItemType File -Force -Path $TargetPath | Out-Null

    if (-not (Test-Path -LiteralPath $JsonLinesPath)) {
        Add-ReportLine -Path $TargetPath -Text "results_file_missing=true"
        return
    }

    $Lines = Get-Content -LiteralPath $JsonLinesPath

    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        try {
            $Row = $Line | ConvertFrom-Json
            Add-ReportLine -Path $TargetPath -Text ($Row.scenario + "`t" + $Row.status)
        }
        catch {
            Add-ReportLine -Path $TargetPath -Text ("invalid_json_line=" + $Line)
        }
    }
}

function Cleanup-Runtime {
    Add-RuntimeLine -Text ""
    Add-RuntimeLine -Text "===== CLEANUP ====="

    try {
        $FilterValue = "name=docker_for_odoo-" + $OdooService + "-run-"
        $RunIds = & docker ps -aq --filter $FilterValue 2>$null

        foreach ($RunId in $RunIds) {
            if (-not [string]::IsNullOrWhiteSpace($RunId)) {
                $RemoveCode = Invoke-DockerLogged -Label ("remove residual run container " + $RunId.Trim()) -Arguments @("rm", "-f", $RunId.Trim()) -LogPath $DockerFinalLog

                if ($RemoveCode -ne 0) {
                    $script:CleanupCode = 70
                }
            }
        }
    }
    catch {
        Add-RuntimeLine -Text ("cleanup_run_containers_error=" + $_.Exception.Message)
        $script:CleanupCode = 71
    }

    if ($script:DiagnosticDatabaseCreated) {
        if ($KeepDiagnosticDatabase.IsPresent) {
            Add-RuntimeLine -Text "diagnostic_database_kept=$DiagnosticDatabase"
        }
        else {
            $DropCode = Invoke-DockerLogged -Label "drop diagnostic database" -Arguments @(
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
                $script:CleanupCode = 72
            }
            else {
                $script:DiagnosticDatabaseCreated = $false
            }
        }
    }

    $RemoveDumpCode = Invoke-DockerLogged -Label "remove temporary dump" -Arguments @(
        "exec",
        $PgContainer,
        "rm",
        "-f",
        $DumpPathInContainer
    ) -LogPath $DatabaseFinalLog

    if ($RemoveDumpCode -ne 0) {
        $script:CleanupCode = 73
    }

    if ($script:OdooWasRunning) {
        $StartCode = Invoke-ComposeLogged -Label "restart permanent Odoo" -Arguments @("up", "-d", $OdooService) -LogPath $DockerFinalLog

        if ($StartCode -ne 0) {
            $script:CleanupCode = 74
        }
        else {
            $HealthCode = Get-HealthCode
            Add-ReportLine -Path $DockerFinalLog -Text "health_http_code=$HealthCode"

            if ($HealthCode -ne 200) {
                $script:CleanupCode = 75
            }
        }
    }
    else {
        Add-RuntimeLine -Text "odoo_not_restarted=it_was_not_running_initially"
    }

    $FinalDockerCode = Invoke-DockerLogged -Label "final docker state" -Arguments @("ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}") -LogPath $DockerFinalLog

    if ($FinalDockerCode -ne 0) {
        $script:CleanupCode = 76
    }
}

try {
    Add-RuntimeLine -Text "FuelToken Phase 1A runtime diagnostic"
    Add-RuntimeLine -Text "harness_version=v5"
    Add-RuntimeLine -Text "timestamp=$Stamp"
    Add-RuntimeLine -Text "docker_directory=$DockerDirectory"
    Add-RuntimeLine -Text "repository_path=$RepositoryPath"
    Add-RuntimeLine -Text "source_database=$SourceDatabase"
    Add-RuntimeLine -Text "postgres_container=$PgContainer"
    Add-RuntimeLine -Text "postgres_service=$PgService"
    Add-RuntimeLine -Text "postgres_role=$PgDbUser"
    Add-RuntimeLine -Text "postgres_port=$PgDbPort"
    Add-RuntimeLine -Text "diagnostic_database=$DiagnosticDatabase"
    Add-RuntimeLine -Text "patch_applied=false"
    Add-RuntimeLine -Text "git_commands_executed=false"
    Add-RuntimeLine -Text "source_database_write_intended=false"

    if (-not (Test-Path -LiteralPath $DockerDirectory)) {
        throw "Docker directory not found: $DockerDirectory"
    }

    if (-not (Test-Path -LiteralPath $DiagnosticPythonPath)) {
        throw "Diagnostic Python file not found: $DiagnosticPythonPath"
    }

    Set-Location -LiteralPath $DockerDirectory
    Copy-Item -LiteralPath $DiagnosticPythonPath -Destination $CopiedPythonPath -Force
    Copy-SourceEvidence

    $DockerInitialCode = Invoke-DockerLogged -Label "initial docker state" -Arguments @("ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}") -LogPath $DockerInitialLog

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

SELECT
    count(*) FILTER (WHERE qty_available < 0) AS negative_available,
    count(*) FILTER (WHERE qty_qr_active < 0) AS negative_qr_active,
    count(*) FILTER (WHERE qty_qr_blocked < 0) AS negative_qr_blocked,
    count(*) FILTER (WHERE qty_consumed < 0) AS negative_consumed,
    count(*) FILTER (WHERE qty_expired < 0) AS negative_expired,
    count(*) FILTER (WHERE qty_transferred_out < 0) AS negative_transferred
FROM acpec_fuel_face_line;
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
        $StopCode = Invoke-ComposeLogged -Label "stop permanent Odoo before diagnostic" -Arguments @("stop", $OdooService) -LogPath $DockerInitialLog

        if ($StopCode -ne 0) {
            throw "unable to stop permanent Odoo"
        }
    }

    $script:SourceFingerprintBefore = Get-SourceDatabaseFingerprint -DatabaseName $SourceDatabase
    Add-RuntimeLine -Text "source_fingerprint_before=$($script:SourceFingerprintBefore)"

    $DatabaseOwner = $PgDbUser
    Add-RuntimeLine -Text "source_database_owner=$DatabaseOwner"

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

    $DropBeforeCode = Invoke-DockerLogged -Label "drop stale diagnostic database" -Arguments @(
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
        throw "drop stale diagnostic database failed"
    }

    $CreateCode = Invoke-DockerLogged -Label "create diagnostic database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "createdb",
        "-U",
        $PgDbUser,
        "-O",
        $DatabaseOwner,
        $DiagnosticDatabase
    ) -LogPath $CloneLog

    if ($CreateCode -ne 0) {
        throw "create diagnostic database failed"
    }

    $script:DiagnosticDatabaseCreated = $true

    $RestoreCode = Invoke-DockerLogged -Label "restore diagnostic database" -Arguments @(
        "exec",
        "-e",
        ("PGPASSWORD=" + $PgDbPassword),
        $PgContainer,
        "pg_restore",
        "-U",
        $PgDbUser,
        "--no-owner",
        "--no-acl",
        ("--role=" + $DatabaseOwner),
        ("--dbname=" + $DiagnosticDatabase),
        $DumpPathInContainer
    ) -LogPath $CloneLog

    if ($RestoreCode -ne 0) {
        throw "pg_restore failed"
    }

    $CloneCheckCode = Invoke-DockerLogged -Label "diagnostic database check" -Arguments @(
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
        $DiagnosticDatabase,
        "-c",
        "SELECT current_database(), count(*) FROM acpec_fuel_face_line;"
    ) -LogPath $CloneLog

    if ($CloneCheckCode -ne 0) {
        throw "diagnostic database check failed"
    }

    $ComposeArguments = @(
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

    Add-ReportLine -Path $OdooShellLog -Text ("command=docker " + ($ComposeArguments -join " "))

    $ShellTemporaryBase = Join-Path ([System.IO.Path]::GetTempPath()) ("fueltoken_odoo_shell_" + [guid]::NewGuid().ToString("N"))
    $ShellStandardOutputPath = $ShellTemporaryBase + ".stdout.txt"
    $ShellStandardErrorPath = $ShellTemporaryBase + ".stderr.txt"
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $OdooShellCode = 999

    try {
        Get-Content -LiteralPath $DiagnosticPythonPath -Raw |
            & docker @ComposeArguments 1> $ShellStandardOutputPath 2> $ShellStandardErrorPath
        $OdooShellCode = $LASTEXITCODE
    }
    catch {
        Add-ReportLine -Path $OdooShellLog -Text ("odoo_shell_wrapper_error=" + $_.Exception.Message)
        $OdooShellCode = 999
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    Append-FileIfPresent -SourcePath $ShellStandardOutputPath -TargetPath $OdooShellLog -SectionName "stdout"
    Append-FileIfPresent -SourcePath $ShellStandardErrorPath -TargetPath $OdooShellLog -SectionName "stderr"

    Remove-Item -LiteralPath $ShellStandardOutputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ShellStandardErrorPath -Force -ErrorAction SilentlyContinue

    Add-ReportLine -Path $OdooShellLog -Text "[return_code=$OdooShellCode]"

    $Prefix = "LOCKDIAG_RESULT="
    $ResultLines = @(
        Get-Content -LiteralPath $OdooShellLog |
        Where-Object { $_.StartsWith($Prefix) } |
        ForEach-Object { $_.Substring($Prefix.Length) }
    )

    New-Item -ItemType File -Force -Path $ResultsPath | Out-Null

    if ($ResultLines.Count -gt 0) {
        $ResultLines | Set-Content -LiteralPath $ResultsPath -Encoding UTF8
    }

    Write-ResultSummary -JsonLinesPath $ResultsPath -TargetPath $ResultSummaryPath

    $ResultCount = $ResultLines.Count
    Add-RuntimeLine -Text "result_count=$ResultCount"
    Add-RuntimeLine -Text "odoo_shell_return_code=$OdooShellCode"

    if ($ResultCount -ne 4) {
        $script:MainCode = 40
        Add-RuntimeLine -Text "warning=expected_4_results_got_$ResultCount"
    }

    if ($OdooShellCode -ne 0) {
        if ($script:MainCode -eq 0) {
            $script:MainCode = 41
        }
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

    Add-ReportLine -Path $SummaryPath -Text "FuelToken Phase 1A runtime summary"
    Add-ReportLine -Path $SummaryPath -Text "timestamp=$Stamp"
    Add-ReportLine -Path $SummaryPath -Text "source_database=$SourceDatabase"
    Add-ReportLine -Path $SummaryPath -Text "diagnostic_database=$DiagnosticDatabase"
    Add-ReportLine -Path $SummaryPath -Text "postgres_role=$PgDbUser"
    Add-ReportLine -Path $SummaryPath -Text "postgres_service=$PgService"
    Add-ReportLine -Path $SummaryPath -Text "main_code=$($script:MainCode)"
    Add-ReportLine -Path $SummaryPath -Text "cleanup_code=$($script:CleanupCode)"
    Add-ReportLine -Path $SummaryPath -Text "patch_applied=false"
    Add-ReportLine -Path $SummaryPath -Text "git_commands_executed=false"
    Add-ReportLine -Path $SummaryPath -Text "output_directory=$OutputDirectory"
}

$TarArguments = @(
    "-czf",
    $ArchivePath,
    "-C",
    $OutputRoot,
    $OutputDirectoryName
)

$script:ArchiveCode = Invoke-NativeLogged -Label "create tar.gz archive" -Program "tar.exe" -Arguments $TarArguments -LogPath $RuntimeLog

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
else {
    $FinalArchivePath = $ArchivePath
}

Add-ReportLine -Path $SummaryPath -Text "archive_code=$($script:ArchiveCode)"
Add-ReportLine -Path $SummaryPath -Text "archive=$FinalArchivePath"

Write-Host "Phase 1A runtime diagnostic complete."
Write-Host "main_code=$($script:MainCode)"
Write-Host "cleanup_code=$($script:CleanupCode)"
Write-Host "archive_code=$($script:ArchiveCode)"
Write-Host "summary=$SummaryPath"
Write-Host "archive=$FinalArchivePath"
