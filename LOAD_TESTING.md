# Load & scale testing

## Summary
The AI assignment engine was benchmarked at industrial scale on a single worker
invocation. Even an extreme **2,000-supervisor plant with 100,000 alerts of history**
assigns in **~1.4 ms per alert (p50)** at **~1.3M scoring ops/second**, using **51 MB**.
The compute core has large headroom against Cloudflare Workers' per-request CPU and
memory limits.

## What this measures
The CPU-bound hot paths that run on every assignment cron tick:
- `buildSupStats` - aggregates the full alert history into per-supervisor profiles.
- `scoreSupervisor` - ranks every candidate supervisor for an alert.

This is **pure compute scale**, isolated from the network - the axis that decides
whether one worker can serve a large plant inside its CPU budget.

## What this does NOT measure
Firebase Realtime Database read/write latency and throughput (network I/O). That is
covered by the end-to-end plan below and must be run against a **staging** project.

## How to run
```bash
node tool/load_benchmark.mjs --sups=300 --alerts=10000 --decisions=2000
```

## Results (Node 22, single core)

| Plant profile | Supervisors | History alerts | buildSupStats | Per-alert decision (p50 / p95 / p99) | Throughput | Peak heap |
|---|---|---|---|---|---|---|
| Medium  | 300   | 10,000  | 30 ms  | 0.1 / 0.2 / 0.4 ms | 2.46M ops/s | 11 MB |
| Large   | 1,000 | 50,000  | 136 ms | 0.5 / 0.9 / 1.2 ms | 1.85M ops/s | 24 MB |
| Extreme | 2,000 | 100,000 | 308 ms | 1.4 / 2.2 / 3.0 ms | 1.30M ops/s | 51 MB |

## Interpretation
- `buildSupStats` is linear in history size and runs once per cron tick (cron = every
  minute), so even 100k alerts (~0.3 s) is a tiny fraction of the budget.
- Scoring an entire plant for one alert is sub-2 ms even at 2,000 supervisors.
- Memory stays well under typical limits (51 MB at the extreme).

## End-to-end load test plan (I/O axis - run on STAGING only)
1. Provision a **staging** Firebase project (never production).
2. Seed history with `tool/generate_alerts.cjs` (point `service-account.json` at staging).
3. Drive synthetic new-alert bursts (10/s, 50/s, 100/s) and measure:
   - notify-worker push fan-out latency (`push_sent_at - timestamp`)
   - assignment latency (`aiAssignedAt - timestamp`)
   - cron lock contention / skipped runs (`workers/health`)
   - RTDB write throughput and any throttling
4. Soak test: sustained load 2-4 h; watch worker health, memory, error rate.
5. Record results against the SLOs below.

## Recommended production SLOs (for the buyer SLA)
- New-alert push delivery: **p95 < 5 s, p99 < 15 s**
- AI assignment: **p95 < 10 s** after an alert becomes assignable
- Worker cron success rate: **> 99.5%** (no missed ticks)
- Availability: **99.9% monthly** (composite of Firebase + Cloudflare)

## Regression guard
Wire `node tool/load_benchmark.mjs` into CI to fail if p99 per-decision exceeds a
threshold (e.g. 5 ms at 1,000 supervisors), catching performance regressions before release.
