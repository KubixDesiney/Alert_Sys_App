# External Validation Pack

The remaining gap between SIA's 9.4 and a legitimate 10 is **external validation** —
proof from third parties that no amount of code can manufacture. These documents are
the kickoff artifacts so each process starts in days, not months. Writing them does
not raise the score; **completing the work they describe does.**

## What's here → what it unlocks

| Document | Purpose | Pillar(s) it moves toward 10 |
|---|---|---|
| `PENTEST_RFP.md` | Vendor-ready penetration-test engagement request | Security |
| `PENTEST_REMEDIATION.md` | Findings → fix tracker with SLAs | Security |
| `SOC2_KICKOFF.md` | Auditor engagement brief + evidence plan + timeline | Compliance |
| `SOC2_SYSTEM_DESCRIPTION.md` | Draft SOC 2 Section III system description | Compliance |
| `PILOT_PLAN.md` | Reference-pilot SOW with measured success metrics | Reliability, SCADA fit, Deploy/sales |

## Suggested order
1. **Pilot first** — fastest signal, produces the numbers that sell, and exercises the SCADA integration on a real floor. (Weeks.)
2. **Penetration test** — schedule against staging; scope is already written. (Weeks once booked.)
3. **SOC 2** — engage an auditor; Type I is quick given the control matrix, Type II runs a 3–6 month window. (Months.)

## How each closes its pillar
- **Security → 10:** executed pentest with Critical/High findings remediated + retested (tracker proves closure).
- **Compliance → 10:** signed SOC 2 (Type I then Type II) + counter-signed sub-processor DPAs.
- **Reliability / SCADA fit / Deploy & sales → 10:** a completed reference pilot with real uptime/latency/response numbers, a named reference, and a closed conversion.

## Companion artifacts already in the repo
Threat model + ASVS (`docs/security/`), control matrix + ROPA/DPA/DPIA + vendor
questionnaire (`docs/compliance/`), SLOs/runbook/observability/DR (`docs/ops/`,
`DISASTER_RECOVERY.md`), and the sales pack (`docs/sales/`). The kickoff docs above
point into these so an auditor/vendor/prospect has a single thread to pull.
