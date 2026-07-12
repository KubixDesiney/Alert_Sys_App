# Fires a canonical test alert through the runner's /ingest. (Windows)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$secretLine = Select-String -Path .env -Pattern '^WORKER_SHARED_SECRET=(.*)$'
if (-not $secretLine) { Write-Host 'WORKER_SHARED_SECRET missing from .env' -ForegroundColor Red; exit 1 }
$secret = $secretLine.Matches[0].Groups[1].Value

$factory = if ($args.Count -ge 1) { $args[0] } else { 'Usine A' }
$payload = (@{
  factory = $factory; line = 1; station = 1; machine = 'TEST-RIG'
  metric = 'installer_selftest'; value = 1; severity = 'normal'
  type = 'maintenance'; description = 'Installer test alert - safe to resolve'
  source = 'test-alert'
} | ConvertTo-Json -Compress)

Write-Host "POSTing test alert for factory `"$factory`"..."
$result = docker compose exec -T worker-runner sh -c "wget -qO- --timeout=10 --header 'Content-Type: application/json' --header 'Authorization: Bearer $secret' --post-data '$payload' http://127.0.0.1:8787/ingest"
Write-Host "runner verdict: $result"

if ($result -match '"status":"created"') {
  Write-Host 'SUCCESS - alert created; it should appear on supervisor dashboards now.' -ForegroundColor Green
} elseif ($result -match '"status":"duplicate"') {
  Write-Host 'DEDUPED - an identical test alert exists within the dedup window (ingestion works).' -ForegroundColor Yellow
} else {
  Write-Host 'UNEXPECTED - inspect: docker compose logs --tail 50 worker-runner' -ForegroundColor Red
  exit 1
}
