# Service Level Agreement — Alert Delivery (DRAFT)

**Product:** SIAS — Smart Industrial Alert System
**Provider:** KubixDesiney
**Status:** DRAFT — the numeric targets below are *proposed defaults*. Confirm or adjust before this is attached to any contract.
**Positioning:** SIAS is an **advisory** notification layer. It accelerates human response; it does **not** replace the customer's certified safety systems, alarms, or emergency procedures (see `TERMS.md`). This SLA covers delivery *performance*, not safety guarantees.

---

## 1. What this SLA covers

The end-to-end path from the moment an alert is created in SIAS (`alerts/{id}`, field `timestamp`) to the moment it is delivered to an eligible supervisor's device. It does **not** cover the customer's own SCADA/PLC layer, device connectivity, or the upstream FCM/APNs networks (see Exclusions).

## 2. Definitions

- **Created** — the alert is written to the database (`timestamp`).
- **Accepted** — the notify worker has handed the push to FCM (`push_sent_at`). Measures the part of the path fully under our control.
- **Received** — the first eligible device acknowledges receipt (`alerts/{id}/received_at`, written first-wins by the app). True end-to-end, and matches the "delivered alert" success definition below.
- **Delivered alert** — at least one eligible recipient device reaches *Received* within the success window.
- **Eligible recipient** — a supervisor with a registered device token in the alert's factory scope, per the recipient rules in `cloudflare_notify_worker.js`.

## 3. Service commitments (proposed — confirm)

| Metric | Target | Window | Source of truth |
|---|---|---|---|
| Accepted latency (created → push accepted) | p95 ≤ 5s, p99 ≤ 15s | rolling 30 days | `push_sent_at − timestamp` |
| Received latency (created → device ack) | p95 ≤ 10s, p99 ≤ 30s | rolling 30 days | `received_at − timestamp` |
| Delivery success rate | ≥ 99.5% delivered within 60s | calendar month | passive harvest + canary |
| Intake & notify availability | ≥ 99.9% | calendar month | worker reachability + cron freshness |
| Synthetic canary | a test alert every 5 min, ≤ 15s | continuous | dedicated canary path |

Measurement is computed by the pure, unit-tested functions in `slo_delivery.js` (mirrors the existing `crashFreeBreach` SLO check). Targets live in `DEFAULT_TARGETS` and are also editable at runtime from the SuperAdmin → Reliability tab (`monitoring_config`).

## 4. How we measure (transparency for the customer's auditors)

1. **Passive harvest** — every real alert contributes a latency sample when the notify worker finalizes its push. No synthetic load, no sampling bias: the SLO reflects real production traffic.
2. **Synthetic canary** — every 5 minutes the monitor worker injects a test alert into a reserved synthetic factory (no real supervisors are paged), measures it through the full pipeline, and records the result. This is the dead-man's switch: it catches a broken pipeline *before* a real alert is missed.
3. **Aggregation** — daily percentiles and success rate are written to `slo/delivery/{date}` and surfaced in the SuperAdmin Reliability tab and the public status page.
4. **Breach alerting** — a target breach or two consecutive canary misses pages the on-call operator via the existing monitor webhook (Slack / Teams / PagerDuty), alerting only on state transition.

## 5. Exclusions

This SLA does not apply to delay or loss caused by: the customer's device being offline, in battery-saver, or with notifications disabled; the customer's LAN/Wi-Fi or cellular network; FCM/APNs platform outages or throttling; the customer's own SCADA/PLC/gateway layer upstream of SIAS; scheduled maintenance announced ≥ 48h in advance; or force majeure.

## 6. Reporting

A monthly delivery report (latency percentiles, success rate, canary uptime, any breaches and their cause) is generated from `slo/` and made available to the customer. Raw measurement data is retained for 13 months.

## 7. Service credits (commercial — to be set)

Service credits for missed monthly targets are a commercial decision and will be defined in the order form (a common structure: a percentage of the monthly fee per increment below target, capped at a monthly maximum). This section is intentionally left open pending pricing.

## 8. Review

Targets are reviewed quarterly and after any Sev-1 delivery incident. Changes require written agreement from both parties.

---

*Draft prepared as part of the alert-delivery reliability workstream. The measurement engine (`slo_delivery.js`) is implemented and unit-tested; instrumentation and the canary are being wired into the notify and monitor workers.*
