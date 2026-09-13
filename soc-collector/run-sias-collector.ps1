param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceAccountFile,
    [string]$DatabaseUrl = "https://alertappsys-default-rtdb.firebaseio.com",
    [string]$Environment = "development",
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$env:FB_DB_URL = $DatabaseUrl
$env:FIREBASE_SERVICE_ACCOUNT_FILE = (Resolve-Path -LiteralPath $ServiceAccountFile).Path
$env:SOC_EVENTS_FILE = "C:\SOC-Lab\events\sias.ndjson"
$env:SOC_STATE_FILE = "C:\SOC-Lab\state\sias-collector.json"
$env:SIAS_ENVIRONMENT = $Environment

& $Python (Join-Path $PSScriptRoot "sias_collector.py") --interval 15

