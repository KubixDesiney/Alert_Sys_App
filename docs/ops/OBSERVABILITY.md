# Observability — SIA

What the platform emits, where it lands, and how to read it during an incident.
SIA is instrumented end-to-end so an operator can answer "is it healthy, and if
not, where is it broken?" without shell access — everything surfaces in the
SuperAdmin console or via documented endpoints.

## 1. Signals at a glance

| Signal | Source | Sink (RTDB / endpoint) | Surfaced in |
|---|---|---|---|
| App logs (DEBUG→ERROR) | `AppLogger` + `AppLogBuffer` (ring buffer, 200) | in-memory + mirror | SuperAdmin → Logs → Console (live) |
| Client crashes/errors | `bug_report_service.dart` (FNV-1a dedup, 5-min rate limit) | `bugs/client/{hash}` | SuperAdmin → Logs → Bugs |
| Worker cron health | `health.js` / notify worker | `workers/health/lastRun`, `workers/health/notifyLastRun` | SuperAdmin → Logs → Cron Health |
| Security enforcement | `_securityGuard`, anomaly scan | `security/actions`, `security/logs` (indexed at/kind/fingerprint) | SuperAdmin → Logs → Security |
| AI decisions | scoring/assignment | `ai_decisions`, `ai_agents/*/stats`, `ai_agents/*/logs` | SuperAdmin → AI Agents |
| Forecaster accuracy | continuous learner + worker grader | `ai_forecast/accuracy/{latest,history,pending}` | SuperAdmin → AI Agents → Predictive Core |
| Guardian runs | bugfix agent | `bugs/agent` | SuperAdmin → AI Agents → Guardian |
| RTDB topology/health | console probes (REST shallow counts) | live | SuperAdmin → Logs → Database |
| Synthetic uptime | `tool/smoke_test.mjs` | CI run logs / job summary | GitHub Actions → uptime |

## 2. Health endpoints (no console needed)

- `GET /config` (AI worker, notify worker) — liveness + build/status metadata.
- `GET /security-status` (AI worker, admin) — `{ policy, runtime: { tracked_fingerprints, pending_actions } }`.
- `workers/health/lastRun` — AI cron pulse: duration, assignments, collaborations, handovers, securityActions, errorCount.
- `workers/health/notifyLastRun` — notify cron pulse; `{ skipped, reason }` when a lock is held.

A pulse is **fresh** if its age ≤ 120 s (matches SLI-4). The on-instance monitor
worker continuously watches these and is the always-on counterpart to the 15-min
CI synthetic check.

## 3. Reading levels

- **Green:** all pulses fresh, `errorCount: 0`, `securityActions: 0`, smoke test passing.
- **Amber:** `securityActions > 0` (enforcement happening, expected under probing), or one supporting feature stale.
- **Red:** any pulse stale > 2 min, `errorCount > 0`, push success below SLO, or smoke test failing → open the relevant runbook entry.

## 4. Correlation IDs & forensics

- Security events carry a `fingerprint` (CF IP + SHA-256(UA)) + `endpoint` — pivot across `security/logs` and `security/actions` on the same fingerprint.
- Alerts carry full lifecycle timestamps (`timestamp`, `takenAtTimestamp`, `resolvedAt`, push lock fields) for latency reconstruction.
- Client errors are keyed by content hash with `count`/first/last timestamps, so a recurring bug is one row, not a flood.

## 5. Synthetic monitoring

`tool/smoke_test.mjs` probes worker liveness, `/security-status`, and
`workers/health` freshness, exiting non-zero on any breach. Run locally:

```bash
ALERTSYS_AI_WORKER_URL=https://<ai>.workers.dev \
ALERTSYS_NOTIFY_WORKER_URL=https://<notify>.workers.dev \
FB_DB_URL=https://<proj>-default-rtdb.firebaseio.com \
WORKER_SHARED_SECRET=*** \
node tool/smoke_test.mjs
```

`.github/workflows/uptime.yml` runs it every 15 minutes against the configured
instance and on manual dispatch.

## 6. What is intentionally NOT collected
- No third-party analytics/ad SDKs (see Anthropic-style ad-free posture is irrelevant here; this is a B2B tool).
- No PII in logs beyond the minimum operational identifiers; fingerprints are hashed; client error payloads are scrubbed of stack-local values where feasible.
- App logs are in-memory only (die with the process) — no unbounded log retention by default.
