# SIA on-prem scaffold
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
- Remaining engineering (see ONPREM.md): the Firebase->PocketBase data-layer port and the
  worker-logic port. The runner currently ticks + serves `/health` as the placeholder.

## Air-gap notes
- Vendor all images (caddy, pocketbase, node) into your internal registry.
- Use an internal CA or self-signed cert in the Caddyfile.
- Backups: copy the `pb_data` volume (PocketBase is a single SQLite dir).
