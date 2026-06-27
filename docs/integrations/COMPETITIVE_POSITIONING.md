# Competitive Positioning — SIAS vs SCADA / IIoT

An honest map of where SIAS wins, where it complements, and where it deliberately
does not compete. Use this to frame deals correctly — the fastest way to lose an
industrial sale is to claim you replace a control system when you don't.

## One-line positioning
**SIAS is the mobile alerting, dispatch, and predictive-intelligence layer for the
factory floor — it makes an existing SCADA/IIoT estate act on its own data faster.**

## The category, precisely
SIAS is **not** a SCADA/DCS (no control loops, no PLC programming, no hard-real-time
determinism) and **not** a historian. It is closest to a *connected-worker / alert
management / mobile CMMS-adjacent* product, with an AI assignment + forecasting
engine and a voice/lock-screen claim flow that those products generally lack.

## Where SIAS wins (vs the alerting features bundled into SCADA/IIoT suites)

| Capability | Typical SCADA/IIoT alarm module | SIAS |
|---|---|---|
| Mobile-first dispatch | HMI-bound; SMS/email bolt-ons | Native app, push + full-screen lock-screen buzz |
| Getting the *right* person | Static on-call lists | AI assignment scored on workload, skill, proximity, history |
| Hands-busy claim | None | Voice + lock-screen voice claim with speaker verification |
| Coordination | Ticket hand-off | Collaboration, help requests, shift commander, presence |
| Prediction | Threshold alarms | On-device GBDT next-24h machine risk, self-grading |
| Offline floor | Assumes connected HMI | Offline-aware startup, cached roles, queued triggers |
| Time-to-deploy | Months of SI work | Dedicated instance stood up in hours |
| Self-healing ops | Vendor support contract | Guardian CI pipeline (configurable AI, gated) |

## Where SIAS complements (and must integrate, not fight)

| Incumbent | Relationship |
|---|---|
| **SCADA/DCS** (Ignition, Wonderware, FactoryTalk, WinCC) | They own control + visualization; SIAS ingests their alarms/tags (`SCADA_INTEGRATION.md`) and runs the human response. |
| **Historian** (PI, Ignition Historian) | Source of telemetry/backfill for the forecaster; SIAS does not store time-series at historian scale. |
| **CMMS/EAM** (Maximo, Fiix, UpKeep) | SIAS handles the real-time alert→claim→resolve loop; a work order can be opened from a resolved alert. SIAS is faster at the live incident, weaker at long-horizon asset lifecycle. |
| **MES/quality** | POST quality excursions to SIAS as Quality alerts. |

## Where SIAS does **not** compete (say so plainly)
- Closed-loop process **control** / setpoint management — stays in PLC/DCS.
- Safety-instrumented systems (SIS), functional-safety SIL loops — SIAS is not a
  safety-rated control path; it is a notification aid alongside them.
- High-frequency time-series storage/analytics at historian scale.
- Sub-millisecond deterministic response.

## Honest scorecard inputs (what bounds the rating)
- **Strength:** breadth of human-response features + integration path is best-in-class for this niche; the connector makes the "works with your SCADA" claim real and testable.
- **Ceiling:** as a category, SIAS competes as a *complement*, so the dimension tops out below a hypothetical "replaces SCADA" 10 — that 10 isn't a product SIAS is trying to be. The realistic max is "the default alerting/dispatch layer bolted onto any SCADA estate," which the integration connector + positioning now support.

## Objection handling (quick)
- *"We already have SCADA alarms."* → Those alarm the control room; SIAS gets the
  right technician to the machine on mobile, with AI routing and voice claim, and
  predicts the next failure. Feed it from your existing alarms in an afternoon.
- *"Is this another rip-and-replace?"* → No. SIAS reads from your stack and changes
  nothing on the OT network. Start with one line.
- *"Data residency / isolation?"* → Dedicated instance on your own Firebase/cloud;
  no shared data plane (ADR-0003).
