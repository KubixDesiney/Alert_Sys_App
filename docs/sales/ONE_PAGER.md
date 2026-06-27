# SIAS - Smart Industrial Alert System — One-Pager

**The mobile, AI-driven alerting and dispatch layer for the factory floor — it makes
your existing SCADA/IIoT estate act on its own data in seconds, on the right
person's phone.**

## The problem
Plant alarms fire in the control room, but getting the *right* technician to the
*right* machine fast is still manual: radios, static on-call lists, supervisors
hunting for who's free. Minutes of downtime per incident add up to real money, and
nothing predicts the next failure.

## What SIAS does
- **Instant mobile dispatch** — push + full-screen lock-screen buzz; claim by voice.
- **AI assignment** — routes each alert to the best supervisor by skill, workload, proximity, and history.
- **Coordination** — collaboration, help requests, shift commander, live presence.
- **Prediction** — on-device gradient-boosted model forecasts next-24h machine risk and self-grades its accuracy.
- **Self-healing ops** — a two-AI "Guardian" pipeline detects, fixes, reviews, and ships platform fixes automatically.
- **Works with your stack** — ingests OPC-UA / MQTT / Modbus / webhook / historian telemetry; it does not replace SCADA/PLC control.

## Why it wins
| | Bundled SCADA alarms | Generic CMMS | **SIAS** |
|---|---|---|---|
| Mobile-first dispatch | weak | partial | **native + voice** |
| Right-person AI routing | no | no | **yes** |
| Next-failure prediction | no | no | **on-device, self-grading** |
| Time-to-deploy | months | weeks | **hours (dedicated instance)** |
| Self-healing platform | no | no | **yes (Guardian)** |

## How it's delivered
A **dedicated instance per customer** — your own Firebase project, your own
Cloudflare workers, your own secrets. No shared data plane, so your data stays
isolated and resident where you choose. Stood up in hours, not months.

## Trust & compliance
Threat-modeled (STRIDE), OWASP ASVS L2-mapped, CodeQL + dependency + secret
scanning, documented SLOs/runbook/DR, and an audit-ready SOC 2 control matrix +
GDPR pack (ROPA, DPA, DPIA). Pre-answered vendor security questionnaire on file.

## Get started
A 2-week pilot on one production line. We integrate to your alarms/telemetry, your
supervisors install the app, and you measure response-time and downtime deltas.
See `docs/sales/PRICING.md` and `docs/sales/DEMO_SCRIPT.md`.
