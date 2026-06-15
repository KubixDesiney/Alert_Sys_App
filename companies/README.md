# Company provisioning

Each customer runs as a **dedicated instance** — its own Firebase project and its
own Cloudflare workers — so isolation comes from separate deployments, not a shared
tenant layer. This folder holds the generated, per-company deployment manifests.

## Provision a new company

```bash
node tool/provision_company.mjs \
  --id=acme --name="ACME Manufacturing" --project=acme-alerts \
  --account=<cloudflare-account-id> --subdomain=<your-workers-subdomain> \
  --brand=0xFFEA580C --logo=https://acme.com/logo.png --support=ops@acme.com \
  --sso=oidc.acme-azure --mfa
```

…or put the same fields in a JSON file and pass `--config=companies/acme.input.json`
(flags still override file values). See `example.input.json`.

## What it generates → `companies/<id>/`

| File | Purpose |
|------|---------|
| `company.json` | Canonical, non-secret config record (the deployment manifest). |
| `build.ps1` / `build.sh` | The exact `flutter build apk/web` commands with every `--dart-define` pre-filled. |
| `wrangler.{ai,notify,backup,monitor}.toml` | Per-company worker configs — names prefixed with the company id, backup gets its own R2 bucket. Read live from the repo templates so they never drift. |
| `secrets.md` | The `wrangler secret put` checklist per worker (names only). |
| `PROVISION.md` | The ordered, copy-pasteable runbook (Firebase → rules → R2 → workers → build → first admin → distribute). |

## Safety

- **No secrets are ever written to disk.** Secret values are only referenced by
  name; the build scripts pull `ALERTSYS_WORKER_SHARED_SECRET` from the environment.
- The generated manifests are safe to commit — they're the audit trail of what was
  provisioned for whom. Build outputs (`build/`) are not committed.
- The app enforces isolation at runtime: it refuses to start if the wired Firebase
  project id doesn't match `COMPANY_FIREBASE_PROJECT` (see `CompanyConfig.verifyFirebaseProject`).
