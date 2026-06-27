# SIAS on-prem scaffold
Air-gapped infrastructure: Caddy (TLS/proxy/static) + PocketBase (data/auth/realtime) +
worker-runner (Node cron logic). Full plan in ../../ONPREM.md.

## Run
1. `cp .env.example .env` and edit secrets + host.
2. Build the Flutter web app and copy `build/web` to `./web`.
3. `docker compose up -d`
4. PocketBase admin UI: `https://<host>/api/_/` (create the superuser on first run).
5. worker-runner health: `https://<host>/ws/health` (proxied) or `:8787/health` direct.

## Status
- Caddy + PocketBase + worker-runner come up healthy out of the box.
- worker-runner runs cloud-parity **AI assignment** + **escalation** every cycle and pushes
  `assignment`/`escalation` events to LAN devices over **SSE** (`/events?uid=`, token-gated).
- Remaining engineering (see ONPREM.md): the Firebase->PocketBase **data-layer port** (so the
  Flutter app reads/writes PocketBase) and the **rules port**.

## Air-gap notes
- Vendor all images (caddy, pocketbase, node) into your internal registry.
- Use an internal CA or self-signed cert in the Caddyfile.
- Backups: copy the `pb_data` volume (PocketBase is a single SQLite dir).
