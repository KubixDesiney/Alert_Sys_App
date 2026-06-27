# Architecture — SIAS - Smart Industrial Alert System

A concise system map. For the exhaustive module-by-module reference see
`.claude/CLAUDE.md`; for the *why* behind key choices see `docs/adr/`.

## What it is
A multi-platform (Android-first) Flutter app for factory alert supervision:
real-time alert intake → assignment → claim → resolution → escalation, with AI
assignment, on-device risk forecasting, voice/lock-screen claim, offline
resilience, and a SuperAdmin command console. Sold as dedicated per-customer
instances (ADR-0003).

## C4 — Containers

```
                ┌──────────────────────────────────────────────┐
                │            Flutter client (lib/)               │
                │  Provider state · screens · services · models  │
                │  offline cache · voice stack · on-device GBDT  │
                └───────────────┬───────────────┬────────────────┘
              Firebase Auth ID  │               │  worker triggers (HTTPS)
                token           │               │
                ┌───────────────▼──────┐   ┌────▼─────────────────────────┐
                │  Firebase RTDB        │   │  Cloudflare Workers           │
                │  primary store        │◄──┤  alert-notifier (AI/security) │
                │  database.rules.json  │   │  alertsys (notifications)     │
                │  = authz boundary     │   │  alertsys-github (GH proxy)   │
                │  (ADR-0004)           │   │  monitor · backup · scim      │
                └───────────────────────┘   └────┬───────────┬─────────────┘
                                                  │           │
                                            FCM push    GitHub API / model providers
```

## Layers (client)
- **UI** — `lib/screens/`, `lib/widgets/` (incl. `screens/superadmin/` command console).
- **State** — `lib/providers/` (`AlertProvider` is the operational facade) + `ThemeProvider`, `ConnectivityService`.
- **Services** — `lib/services/` business logic: alerts, auth, FCM, voice, AI scoring, predictions/forecast, shifts, hierarchy, location, offline, worker queue. DI via `ServiceLocator`.
- **Models** — `lib/models/` entities + mapping.
- **Portability** — `lib/services/data/` `DataStore` abstraction (Firebase default, PocketBase for on-prem; ADR-0006).

## Backend
- **Workers** (`cloudflare_*_worker.js`, modular `worker/`) — cron every minute + HTTP triggers; per-worker locks (`cron_lock/*`), health pulses (`workers/health`), security guard.
- **Functions** (`functions/`) — AI-assignment retry triggers.
- **Rules** (`database.rules.json`) — deny-by-default authorization + validators + indexes.

## Cross-cutting
- **Security** — worker `_securityGuard` (rate limit, prompt-injection, sanitization), CodeQL, gitleaks, Dependabot, security headers. See `docs/security/`.
- **Observability** — `AppLogBuffer`, `bugs/client`, `workers/health`, `security/*`, forecaster accuracy ledger, synthetic `tool/smoke_test.mjs`. See `docs/ops/`.
- **Self-healing** — Guardian pipeline (ADR-0005).

## Key flows
Alert lifecycle, voice claim, offline/reconnect, AI assignment, shift handover, and
forecaster train/serve are documented step-by-step in `.claude/CLAUDE.md`
(Operational Sequences) and `CLAUDE.md` (Alert Lifecycle).

## Build & test
See `CLAUDE.md` → "Build And Test Commands" and `TESTING.md`. CI: `.github/workflows/ci.yml`.

## Decision records
`docs/adr/` — dual-worker split (0001), on-device GBDT (0002), dedicated instances
(0003), RTDB-as-authz (0004), Guardian (0005), data-layer abstraction (0006).
