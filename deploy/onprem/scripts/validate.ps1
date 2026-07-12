# Setup validation: every service up, healthy and answering. (Windows)
$ErrorActionPreference = 'Continue'
Set-Location (Join-Path $PSScriptRoot '..')
$fail = $false

function Check($name, [scriptblock]$block) {
  try { & $block *> $null; $ok = $? } catch { $ok = $false }
  if ($ok) { Write-Host "  OK   $name" -ForegroundColor Green }
  else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:fail = $true }
}

Write-Host 'SIAS on-prem validation:'
Check 'docker compose services running' { if ((docker compose ps -q).Count -eq 0) { throw 'none' }; if ((docker compose ps --status exited --status dead -q)) { throw 'dead' } }
Check 'PocketBase /api/health' { docker compose exec -T pocketbase wget -qO- --timeout=5 http://127.0.0.1:8090/api/health }
Check 'worker-runner /health' { docker compose exec -T worker-runner wget -qO- --timeout=5 http://127.0.0.1:8787/health }
Check 'worker-runner /ready (PB reachable)' { docker compose exec -T worker-runner wget -qO- --timeout=5 http://127.0.0.1:8787/ready }
Check 'edge-gateway /health' { docker compose exec -T edge-gateway wget -qO- --timeout=5 http://127.0.0.1:8788/health }

Write-Host "`nlicence status:"
docker compose exec -T worker-runner wget -qO- --timeout=5 http://127.0.0.1:8787/license-status

if ($fail) {
  Write-Host 'One or more checks FAILED. Inspect with: docker compose logs --tail 100 <service>' -ForegroundColor Red
  exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
