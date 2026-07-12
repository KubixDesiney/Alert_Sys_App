# SIAS Edge — Windows production installer (PowerShell 5.1+).
# Idempotent: safe to re-run; never overwrites existing secrets or data.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Say($msg) { Write-Host "[sias-install] $msg" -ForegroundColor Cyan }
function Die($msg) { Write-Host "[sias-install] ERROR: $msg" -ForegroundColor Red; exit 1 }

function New-RandomHex([int]$bytes = 32) {
  $buf = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
  ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

# ── Preflight ────────────────────────────────────────────────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'docker is required (Docker Desktop or Engine)' }
docker compose version *> $null
if (-not $?) { Die 'docker compose v2 plugin is required' }
docker info *> $null
if (-not $?) { Die 'docker daemon not reachable' }

# ── .env (secrets generated once, never overwritten) ────────────────────────
if (-not (Test-Path .env)) {
  Say 'creating .env from template with generated secrets'
  $env_ = Get-Content .env.example -Raw
  $env_ = $env_ -replace '(?m)^WORKER_SHARED_SECRET=.*$', "WORKER_SHARED_SECRET=$(New-RandomHex)"
  $env_ = $env_ -replace '(?m)^PB_ADMIN_PASSWORD=.*$', "PB_ADMIN_PASSWORD=$((New-RandomHex).Substring(0,24))"
  $env_ = $env_ -replace '(?m)^INSTALLATION_ID=.*$', "INSTALLATION_ID=inst-$(New-RandomHex 8)"
  [System.IO.File]::WriteAllText((Join-Path $PWD '.env'), $env_)
} else {
  Say '.env exists - keeping it (secrets are never regenerated)'
}

# ── Directories & default configs ────────────────────────────────────────────
foreach ($d in 'secrets', 'web') { if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null } }
if (-not (Test-Path gateway.config.json)) {
  Say 'writing minimal gateway.config.json (examples in edge-gateway/config.examples/)'
  $gatewayKey = New-RandomHex
  @"
{
  "ingestUrl": "http://worker-runner:8787/ingest",
  "apiKeys": { "default": "$gatewayKey" },
  "rateLimit": { "capacity": 120, "refillPerSec": 2 },
  "devices": {},
  "webhooks": {},
  "adapters": {}
}
"@ | Set-Content -Encoding utf8 gateway.config.json
  Say "gateway HTTP API key (give to device installers): $gatewayKey"
}
if (-not (Test-Path 'web/index.html')) { Say 'NOTE: copy the Flutter web build into ./web (flutter build web ... --dart-define=SIAS_BACKEND=pocketbase)' }
if (-not (Test-Path 'secrets/license.sias')) { Say 'NOTE: no licence file yet - drop the vendor token at secrets/license.sias; core alerting runs regardless' }

# ── Build & start (production overlay) ───────────────────────────────────────
Say 'building pinned images'
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
if (-not $?) { Die 'image build failed' }
Say 'starting the stack'
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
if (-not $?) { Die 'compose up failed' }

Say 'waiting for services to become healthy...'
Start-Sleep -Seconds 8
& powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
if (-not $?) { Die 'validation failed - see output above' }

Say 'install complete.'
Say 'next steps:'
Say '  1. Open https://<SIA_HOST>/api/_/ and create the PocketBase superuser.'
Say '  2. Import deploy/onprem/pocketbase/pb_schema.json (Settings -> Import collections).'
Say '  3. Create the worker-runner service token, put it in .env as PB_TOKEN, then: docker compose up -d worker-runner'
Say '  4. Provision the first company_owner account.'
Say '  5. Fire a test alert: powershell -File scripts/test-alert.ps1'
