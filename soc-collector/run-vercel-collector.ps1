param(
  [Parameter(Mandatory = $true)]
  [string]$TokenFile,
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,
  [string]$TeamId = "",
  [string]$Python = "python",
  [string]$EventsFile = "C:\SOC-Lab\events\vercel.ndjson",
  [string]$StateFile = "C:\SOC-Lab\state\vercel-collector.json"
)

$ErrorActionPreference = "Stop"
$token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
if (-not $token) { throw "The Vercel token file is empty." }

$env:VERCEL_TOKEN = $token
$env:VERCEL_PROJECT_ID = $ProjectId
$env:VERCEL_TEAM_ID = $TeamId
$env:SOC_EVENTS_FILE = $EventsFile
$env:SOC_STATE_FILE = $StateFile

$scriptPath = Join-Path $PSScriptRoot "vercel_collector.py"
& $Python $scriptPath
exit $LASTEXITCODE
