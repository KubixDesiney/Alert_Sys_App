# ADR-0001: Split Cloudflare Workers (AI/security vs notifications)

Status: Accepted — 2026-06

## Context
A single Worker originally handled both AI/escalation/prediction work and push
notification fan-out on the same one-minute cron and request path. AI and
security work (model calls, anomaly scans, prediction rebuilds) is CPU- and
latency-heavy; notification fan-out is latency-critical (a supervisor must be
buzzed within seconds). Sharing one invocation meant slow AI work could delay or
starve push delivery, and one deploy risked both concerns at once.

## Decision
Run two independent Workers:
- `alert-notifier` (`cloudflare_ai_worker.js`, `wrangler.ai.toml`) — AI assignment,
  escalation, collaboration automation, predictions, security guard, health.
- `alertsys` (`cloudflare_notify_worker.js`, `wrangler.notify.toml`) — new-alert
  push fan-out, queued notification delivery, FCM token cleanup.

Each has its own cron, lock (`cron_lock/ai` vs `cron_lock/notify`), health pulse,
and deploy config. The AI worker triggers the notify worker via an explicit
worker-to-worker `POST /notify` for real-time delivery; the one-minute crons are
durable fallbacks.

## Consequences
**Positive:** notification latency is isolated from AI compute; either worker can
be deployed/rolled back independently; failure domains are separated (RB-1 vs
RB-2 in the runbook); per-worker rate limits and locks are simpler to reason about.

**Negative:** two deploy targets and two health pulses to monitor; a small amount
of duplicated helper code must be kept in sync (notably notification fan-out logic
between `cloudflare_notify_worker.js` and `worker/alerts.js`) — called out as a
maintenance gotcha in `CLAUDE.md`.
