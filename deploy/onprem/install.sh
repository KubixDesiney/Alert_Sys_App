#!/usr/bin/env bash
# SIAS Edge — Linux production installer.
# Idempotent: safe to re-run; never overwrites existing secrets or data.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\033[1;36m[sias-install]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[sias-install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "docker is required (https://docs.docker.com/engine/install/)"
docker compose version >/dev/null 2>&1 || die "docker compose v2 plugin is required"
command -v openssl >/dev/null 2>&1 || die "openssl is required for secret generation"
docker info >/dev/null 2>&1 || die "docker daemon not reachable (permissions?)"

rand() { openssl rand -hex 32; }

# ── .env (secrets generated once, never overwritten) ────────────────────────
if [[ ! -f .env ]]; then
  say "creating .env from template with generated secrets"
  cp .env.example .env
  sed -i "s|^WORKER_SHARED_SECRET=.*|WORKER_SHARED_SECRET=$(rand)|" .env
  sed -i "s|^PB_ADMIN_PASSWORD=.*|PB_ADMIN_PASSWORD=$(rand | cut -c1-24)|" .env
  sed -i "s|^INSTALLATION_ID=.*|INSTALLATION_ID=inst-$(openssl rand -hex 8)|" .env
  chmod 600 .env
else
  say ".env exists — keeping it (secrets are never regenerated)"
fi

# ── Directories & default configs ────────────────────────────────────────────
mkdir -p secrets web
chmod 700 secrets
if [[ ! -f gateway.config.json ]]; then
  say "writing minimal gateway.config.json (edit device maps later; examples in edge-gateway/config.examples/)"
  GATEWAY_KEY=$(rand)
  cat > gateway.config.json <<EOF
{
  "ingestUrl": "http://worker-runner:8787/ingest",
  "apiKeys": { "default": "${GATEWAY_KEY}" },
  "rateLimit": { "capacity": 120, "refillPerSec": 2 },
  "devices": {},
  "webhooks": {},
  "adapters": {}
}
EOF
  chmod 600 gateway.config.json
  say "gateway HTTP API key (give to device installers): ${GATEWAY_KEY}"
fi
[[ -f web/index.html ]] || say "NOTE: copy the Flutter web build into ./web (flutter build web ... --dart-define=SIAS_BACKEND=pocketbase)"
[[ -f secrets/license.sias ]] || say "NOTE: no licence file yet — drop the vendor-issued token at secrets/license.sias (plus license_public.pem); core alerting runs regardless"

# ── Build & start (production overlay) ───────────────────────────────────────
say "building pinned images"
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
say "starting the stack"
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

say "waiting for services to become healthy…"
sleep 8
./scripts/validate.sh || die "validation failed — see output above (containers keep running for diagnosis)"

say "install complete."
say "next steps:"
say "  1. Open https://\$SIA_HOST/api/_/ and create the PocketBase superuser."
say "  2. Import deploy/onprem/pocketbase/pb_schema.json (Settings -> Import collections)."
say "  3. Create the worker-runner service token, put it in .env as PB_TOKEN, then: docker compose up -d worker-runner"
say "  4. Provision the first company_owner account."
say "  5. Fire a test alert: ./scripts/test-alert.sh"
