# Reference Pilot — Plan & Statement of Work

A 2–4 week pilot on one production line that produces **defensible before/after
numbers**. Those numbers are what convert "9.x in theory" into a referenceable 10 on
Reliability, SCADA competitive fit, and Deploy/sales — and they replace the
estimates in `docs/sales/ROI.md` with the customer's real data. Fill `[...]`.

## 1. Objective
Prove SIAS measurably shortens alert response time and improves coordination on one
line, integrated with the customer's existing alarms/telemetry — with no change to
their SCADA/PLC control.

## 2. Scope (deliberately small)
- One production line / area: `[line]` at `[site]`.
- `[N]` supervisors + `[1]` production manager onboarded.
- Integration: feed SIAS from the line's existing alarms via the ingestion connector
  (OPC-UA / MQTT / Modbus / webhook — `docs/integrations/SCADA_INTEGRATION.md`).
- Out of scope: other lines, control-loop changes, custom development.

## 3. Success metrics (agree the targets up front)
| Metric | How measured | Baseline | Target | Source |
|---|---|---|---|---|
| Mean time to acknowledge (alert → claimed) | SIAS alert timestamps vs current radio/log baseline | `[__]` | ≥ 30% faster | alert lifecycle fields |
| Mean time to resolve | `resolvedAt − timestamp` | `[__]` | ≥ 20% faster | alert records |
| Missed/late alerts | count beyond SLA | `[__]` | → ~0 | SLI-1/2 (`docs/ops/SLO.md`) |
| Push delivery latency (p95) | `push_sent_at − timestamp` | n/a | ≤ 5 s | notify worker |
| Supervisor adoption | % alerts claimed via app/voice | n/a | ≥ 80% | alert records |
| Prediction signal (upside) | forecast accuracy (Brier/precision) | n/a | trending up | `ai_forecast/accuracy` |

Baselines are captured in week 0 from the customer's current process (their incident
log + a stopwatch sample). Keep it conservative — defendable beats impressive.

## 4. Measurement plan
- **Week 0 (baseline):** instrument the line, record current MTTA/MTTR from `[N]`
  recent incidents (or a 1-week observation), confirm a downtime cost/min with finance.
- **Weeks 1–N (live):** SIAS in use; the same metrics auto-collected from alert records.
- **Reporting:** the shift/alert exports + the SLO dashboard produce the numbers; the
  ROI model (`docs/sales/ROI.md`) converts them to annualized value.

## 5. Timeline
| Phase | Duration |
|---|---|
| Setup + integration + onboarding | `[3–5 days]` |
| Baseline capture | `[1 week]` |
| Live pilot | `[2–3 weeks]` |
| Readout + ROI report | `[2 days]` |

## 6. Roles & responsibilities
- KubixDesiney: stand up the dedicated instance (`make deploy-all` / `deploy-instance.yml`), wire the connector, train supervisors, run the readout.
- Customer: name a sponsor, provide line access + alarm/telemetry feed, ensure supervisors install the app, supply baseline incident data.

## 7. Entry / exit criteria
- **Entry:** dedicated instance healthy (`make smoke` green), connector delivering test alerts, supervisors enrolled.
- **Exit (success):** the agreed metric targets met or exceeded; signed off in the readout. Conversion path + pricing in `docs/sales/PRICING.md` (pilot fee credited).
- **Exit (no-go):** targets not met → customer walks, no obligation. We keep the learnings.

## 8. What we get from a successful pilot
- A named reference + a quote.
- Real uptime/latency/response numbers for the SLO and ROI stories.
- Evidence that the SCADA integration works on a real floor — the proof behind the
  "works alongside your SCADA" claim (`docs/integrations/COMPETITIVE_POSITIONING.md`).

## 9. Data handling during the pilot
Dedicated instance in the customer's chosen region; DPA executed
(`docs/compliance/DPA_TEMPLATE.md`); data deleted or retained per the customer's
instruction at pilot end.
