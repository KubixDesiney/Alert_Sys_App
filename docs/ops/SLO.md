# Service Level Objectives (SLOs) — SIA

Defines the reliability targets for a SIA production instance, the indicators
(SLIs) that measure them, and the error budgets that govern release pace. These
are the numbers an enterprise buyer's reliability/procurement team will ask for.

Review cadence: monthly. Owner: Reliability Lead. Window: rolling 28 days.

## 1. Service tiers

| Tier | Surface | Why it matters |
|---|---|---|
| Critical | Alert intake → push delivery → claim | A missed/late alert is the product's core failure mode on a factory floor. |
| Important | AI assignment, escalation, collaboration | Degrades coordination quality but alerts still flow. |
| Supporting | Forecasting, briefings, Guardian, SuperAdmin console | Value-add; an outage is not safety-relevant. |

## 2. SLIs and SLO targets

| # | SLI (what we measure) | How it's measured | SLO target |
|---|---|---|---|
| 1 | **Push delivery latency** (new alert → FCM accepted) | `push_sent_at − timestamp` on alerts; fast-path vs cron | p95 ≤ 5 s (fast-path), p99 ≤ 60 s (cron fallback) |
| 2 | **Push delivery success rate** | alerts reaching `push_sent: true` without exhausting retries | ≥ 99.5% |
| 3 | **Claim transaction success** | successful `takeAlert` ÷ attempts (excl. legitimate "already claimed") | ≥ 99.9% |
| 4 | **Worker cron freshness** | age of `workers/health/lastRun` (and `notifyLastRun`) | ≤ 120 s for ≥ 99% of samples |
| 5 | **Worker endpoint availability** | non-5xx ÷ total on `/config`, `/notify`, AI endpoints | ≥ 99.9% |
| 6 | **Worker endpoint latency** | edge response time | p95 ≤ 800 ms |
| 7 | **AI assignment success** | alerts assigned within 2 cron cycles when an eligible supervisor exists | ≥ 99% |
| 8 | **App crash-free sessions** | sessions without a fatal error reaching `bugs/client` | ≥ 99.5% |
| 9 | **Forecaster self-eval freshness** (supporting) | `ai_forecast/accuracy/latest` graded within 48 h of due | ≥ 95% |

## 3. Error budgets

Availability SLO of **99.9%** ⇒ ~43 min/month of allowed downtime per service.
Push success SLO of **99.5%** ⇒ 1 in 200 alerts may exhaust retries before manual
follow-up. The budget governs change velocity:

- **Budget healthy (>50% remaining):** ship normally; Guardian may auto-deploy low-risk fixes.
- **Budget low (<25% remaining):** freeze non-critical deploys; Guardian switches to "human review required" (PR only); focus on reliability fixes.
- **Budget exhausted:** full change freeze except rollbacks and incident fixes; post-incident review required before resuming (`docs/ops/RUNBOOK.md`).

## 4. Where the numbers come from

| SLI | Source of truth |
|---|---|
| 1–2 push | `alerts/*` push lock fields (`push_sent_at`, `push_last_error_at`); notify worker health |
| 3 claim | `supervisor_active_alerts` transactions; client telemetry |
| 4 cron | `workers/health/lastRun`, `workers/health/notifyLastRun` (monitor worker watches these) |
| 5–6 endpoints | Cloudflare analytics + `tool/smoke_test.mjs` synthetic probes (`.github/workflows/uptime.yml`) |
| 7 AI | `ai_decisions`, `workers/health` assignment counters |
| 8 crashes | `bugs/client` deduplicated error pipeline |
| 9 forecaster | `ai_forecast/accuracy/{latest,history}` |

## 5. Reporting

A monthly reliability report rolls these up (attainment vs target, budget burn,
top incidents). Synthetic checks run every 15 min (`uptime.yml`); the on-instance
monitor worker writes continuous health to `workers/health`. See
`docs/ops/OBSERVABILITY.md` for the live dashboards and `docs/ops/RUNBOOK.md` for
the response procedures when an SLO is at risk.
