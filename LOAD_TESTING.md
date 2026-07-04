# Load & scale testing

## Summary
The system has two scaling axes, and they are **not** equally binding:

1. **CPU (scoring/assignment)** — benchmarked below. Effectively unlimited
   headroom: ~1.4 ms per assignment decision at an extreme 2,000-supervisor /
   100,000-alert profile.
2. **The full-table alert scan on every cron tick** — the real ceiling.
   The AI worker (`loadCoreData`) and the notify worker each read the entire
   `alerts` node from RTDB every minute. Cost per tick is linear in table
   size: latency, worker wall-clock, and Firebase download billing all grow
   with every alert ever created. Without retention the table grows forever,
   so *the number goes up until cron latency and the Firebase bill hurt*.

The CPU benchmark answers "can one worker score a big plant?" (yes). The
capacity question that actually decides fleet size and unit economics is the
I/O axis, which is governed by the **retention policy** below.

## The real bound: cron table scan × table size

Every minute, per tenant:

| Reader | Read | Scaling |
|---|---|---|
| `alert-notifier` cron (`loadCoreData`) | `alerts.json` full read | O(table size) |
| `alertsys` notify cron (`processAlerts`) | `alerts.json` full read | O(table size) |
| both crons | `users.json`, `shifts.json`, … | O(users) — small, bounded |

Back-of-envelope: at ~1 KB/alert JSON, a 100k-alert table is ~100 MB
downloaded **per worker per minute** ≈ 280 GB/day/tenant — far past any
sane Firebase bill and past worker memory comfort. At 10k alerts it is
~28 GB/day: workable but wasteful. The table must be kept bounded.

## Retention policy (the fix)

`cloudflare_backup_worker.js` enforces retention daily, immediately after the
full RTDB snapshot lands in R2 (so nothing is deleted that isn't already
backed up twice):

- **What**: alerts in a terminal state (`validee`, `cancelled`) older than
  `RETENTION_DAYS` (default **365**).
- **Never**: open (`disponible`) or in-progress (`en_cours`) alerts, or alerts
  with unparseable timestamps — regardless of age.
- **Where they go**: batched into R2 objects under `alerts_archive/` (same
  bucket as the daily snapshots), then removed from RTDB in one multi-path
  delete. History stays queryable offline; the live table stays bounded.
- **Rate**: at most `RETENTION_BATCH` (default 500) per daily run — a backlog
  drains gradually instead of hammering RTDB.
- **Config**: `wrangler.backup.toml` `[vars]` → `RETENTION_DAYS`,
  `RETENTION_BATCH`. `RETENTION_DAYS = "0"` disables.
- **Manual trigger**: `GET /retention?key=<WORKER_SHARED_SECRET>` on the
  backup worker. Health beacon: `workers/health/backup.retention`.
- 365 days keeps a full seasonal year live for the GBDT forecaster and stays
  comfortably above the statistical model's 180-day recency window, so
  predictive quality is unaffected.

Steady-state table size ≈ alerts/year. A plant producing 50 alerts/day holds
~18k live alerts (~18 MB/scan) — inside comfortable cron and billing budgets.
For plants above ~200 alerts/day, lower `RETENTION_DAYS` (the forecaster
trains from uploaded exports and the archive, not only the live table).

## CPU benchmark (secondary axis)

The CPU-bound hot paths that run on every assignment cron tick:
- `buildSupStats` - aggregates the full alert history into per-supervisor profiles.
- `scoreSupervisor` - ranks every candidate supervisor for an alert.

```bash
node tool/load_benchmark.mjs --sups=300 --alerts=10000 --decisions=2000
```

### Results (Node 22, single core)

| Plant profile | Supervisors | History alerts | buildSupStats | Per-alert decision (p50 / p95 / p99) | Throughput | Peak heap |
|---|---|---|---|---|---|---|
| Medium  | 300   | 10,000  | 30 ms  | 0.1 / 0.2 / 0.4 ms | 2.46M ops/s | 11 MB |
| Large   | 1,000 | 50,000  | 136 ms | 0.5 / 0.9 / 1.2 ms | 1.85M ops/s | 24 MB |
| Extreme | 2,000 | 100,000 | 308 ms | 1.4 / 2.2 / 3.0 ms | 1.30M ops/s | 51 MB |

Interpretation: compute is a rounding error next to the I/O axis. Note the
"Extreme" 100k-alert row is exactly the table size retention exists to
prevent — with retention at defaults, the steady-state profile is "Medium".

## End-to-end load test plan (I/O axis - run on STAGING only)
1. Provision a **staging** Firebase project (never production).
2. Seed history with `tool/generate_alerts.cjs` (point `service-account.json` at staging).
3. Measure the cron scan itself at several table sizes (1k / 10k / 50k alerts):
   - `workers/health/lastRun.durationMs` per tick
   - Firebase console → Usage → bytes downloaded per day
4. Drive synthetic new-alert bursts (10/s, 50/s, 100/s) and measure:
   - notify-worker push fan-out latency (`push_sent_at - timestamp`)
   - assignment latency (`aiAssignedAt - timestamp`)
   - cron lock contention / skipped runs (`workers/health`)
   - RTDB write throughput and any throttling
5. Run the retention sweep against the seeded table and verify:
   - archived alerts land in R2 `alerts_archive/` and disappear from RTDB
   - open alerts and recent alerts are untouched
   - cron `durationMs` drops proportionally after the sweep
6. Soak test: sustained load 2-4 h; watch worker health, memory, error rate.
7. Record results against the SLOs below.

## Recommended production SLOs (for the buyer SLA)
- New-alert push delivery: **p95 < 5 s, p99 < 15 s**
- AI assignment: **p95 < 10 s** after an alert becomes assignable
- Worker cron success rate: **> 99.5%** (no missed ticks)
- Cron tick duration: **p95 < 10 s** (alarm if trending up — retention is failing)
- Availability: **99.9% monthly** (composite of Firebase + Cloudflare)

## Regression guards
- Wire `node tool/load_benchmark.mjs` into CI to fail if p99 per-decision exceeds a
  threshold (e.g. 5 ms at 1,000 supervisors).
- `worker_test/retention.test.js` pins the retention selection policy (terminal-only,
  cutoff, batch cap, oldest-first).
- Watch `workers/health/lastRun.durationMs` in the Overview Monitor: a steady
  upward trend means the alerts table is growing faster than retention drains it.
