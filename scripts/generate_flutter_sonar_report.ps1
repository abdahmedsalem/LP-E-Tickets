[CmdletBinding()]
param(
  [string]$ProjectRoot,
  [string]$ReportPath,
  [string]$RawLogPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $ReportPath = Join-Path $ProjectRoot 'analysis\flutter-analyzer-report.json'
}
if ([string]::IsNullOrWhiteSpace($RawLogPath)) {
  $RawLogPath = Join-Path $ProjectRoot 'analysis\flutter-analyzer-output.txt'
}

function Convert-ToSonarSeverity {
  param([Parameter(Mandatory)] [string]$AnalyzerSeverity)

  switch ($AnalyzerSeverity.ToLowerInvariant()) {
    'error' { return 'BLOCKER' }
    'warning' { return 'MAJOR' }
    'info' { return 'MINOR' }
    default { return 'MAJOR' }
  }
}

function Convert-ToSonarType {
  param([Parameter(Mandatory)] [string]$AnalyzerSeverity)

  switch ($AnalyzerSeverity.ToLowerInvariant()) {
    'error' { return 'BUG' }
    'warning' { return 'CODE_SMELL' }
    'info' { return 'CODE_SMELL' }
    default { return 'CODE_SMELL' }
  }
}

function Normalize-PathForSonar {
  param([Parameter(Mandatory)] [string]$PathValue)

  $normalized = $PathValue.Trim().Replace('\', '/')
  if ([System.IO.Path]::IsPathRooted($normalized)) {
    try {
      $root = (Resolve-Path $ProjectRoot).Path.TrimEnd('\').Replace('\', '/')
      $full = (Resolve-Path $normalized).Path.Replace('\', '/')
      if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart('/')
      }
      return $full
    } catch {
      return $normalized
    }
  }
  return $normalized
}

function Get-RuleName {
  param(
    [Parameter(Mandatory)] [string]$Code,
    [Parameter(Mandatory)] [string]$Message
  )

  if ($Code -and $Code.Trim()) { return $Code.Trim() }
  return $Message.Trim()
}

New-Item -ItemType Directory -Force -Path (Split-Path $ReportPath) | Out-Null

Push-Location $ProjectRoot
try {
  try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & flutter analyze --no-pub --suppress-analytics 2>&1
    $ErrorActionPreference = $oldEap
    $exitCode = $LASTEXITCODE
    $output | Set-Content -Path $RawLogPath -Encoding UTF8

    if ($exitCode -gt 1) {
      throw "flutter analyze exited with code $exitCode"
    }

    $ruleMap = @{}
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($line in $output) {
      $text = $line.ToString()
      if ([string]::IsNullOrWhiteSpace($text)) { continue }

      $match = [regex]::Match(
        $text,
        '^\s*(?<severity>error|warning|info)\s*[•-]\s*(?<message>.*?)\s*[•-]\s*(?<file>.+?):(?<line>\d+):(?<column>\d+)\s*[•-]\s*(?<code>[A-Za-z0-9_]+)\s*$'
      )

      if (-not $match.Success) { continue }

      $analyzerSeverity = $match.Groups['severity'].Value
      $message = $match.Groups['message'].Value.Trim()
      $filePath = Normalize-PathForSonar $match.Groups['file'].Value
      $lineNumber = [int]$match.Groups['line'].Value
      $columnNumber = [int]$match.Groups['column'].Value
      $code = $match.Groups['code'].Value.Trim()
      if ([string]::IsNullOrWhiteSpace($code)) {
        $code = 'flutter_analyze_issue'
      }

      if (-not $ruleMap.ContainsKey($code)) {
        $ruleMap[$code] = @{
          id = $code
          name = Get-RuleName -Code $code -Message $message
          description = "Issue reported by flutter analyze: $message"
          engineId = 'flutter-analyze'
          cleanCodeAttribute = 'CONVENTIONAL'
          type = Convert-ToSonarType -AnalyzerSeverity $analyzerSeverity
          severity = Convert-ToSonarSeverity -AnalyzerSeverity $analyzerSeverity
        }
      }

      $results.Add(@{
        engineId = 'flutter-analyze'
        ruleId = $code
        severity = Convert-ToSonarSeverity -AnalyzerSeverity $analyzerSeverity
        type = Convert-ToSonarType -AnalyzerSeverity $analyzerSeverity
        effortMinutes = 5
        primaryLocation = @{
          message = $message
          filePath = $filePath
          textRange = @{
            startLine = $lineNumber
            endLine = $lineNumber
            startColumn = $columnNumber
            endColumn = $columnNumber + 1
          }
        }
      })
    }

    $rules = @()
    foreach ($rule in $ruleMap.Values) {
      $rules += $rule
    }

    $issues = @()
    foreach ($issue in $results) {
      $issues += $issue
    }

    $report = [ordered]@{
      rules = $rules
      issues = $issues
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportPath -Encoding UTF8

    Write-Host "Generated Sonar external issues report: $ReportPath"
    Write-Host "Raw analyzer log: $RawLogPath"
    Write-Host "Issues exported: $($results.Count)"
  } catch {
    throw "Failed while generating Sonar report at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
  }
}
finally {
  Pop-Location
}
