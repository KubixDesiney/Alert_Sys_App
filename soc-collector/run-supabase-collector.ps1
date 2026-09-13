param(
  [Parameter(Mandatory = $true)]
  [string]$KeyFile,
  [Parameter(Mandatory = $true)]
  [string]$ProjectUrl,
  [string]$Python = "python",
  [string]$EventsFile = "C:\SOC-Lab\events\supabase.ndjson",
  [string]$StateFile = "C:\SOC-Lab\state\supabase-collector.json"
)

$ErrorActionPreference = "Stop"
$env:SUPABASE_URL = $ProjectUrl
$env:SUPABASE_KEY_FILE = $KeyFile
$env:SOC_EVENTS_FILE = $EventsFile
$env:SOC_STATE_FILE = $StateFile

$scriptPath = Join-Path $PSScriptRoot "supabase_collector.py"
& $Python $scriptPath
exit $LASTEXITCODE

