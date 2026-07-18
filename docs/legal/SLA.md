> **DRAFT v1 — requires review by qualified counsel before use.**

# Service Level Agreement (SLA) — Enterprise Plan

**Provider:** KubixDesiney
**Service:** SIAS — Smart Industrial Alert System
**Applies to:** **Enterprise** plan Customers only, for the duration their
subscription is active. Starter and Growth plan Customers receive the support
response targets in Section 4 but not the uptime commitment or service
credits in Sections 1–3.

This SLA is incorporated into, and forms part of, the Master Subscription
Agreement (`MSA.md`) between KubixDesiney and Customer. Capitalized terms not
defined here have the meaning given in the MSA.

**Positioning:** SIAS is an advisory alerting and coordination layer. It
accelerates human response to industrial alerts; it does not replace
Customer's own certified safety systems, alarms, or emergency procedures (see
`EULA.md` Section 6 and `MSA.md` Section 8.4). This SLA covers the
availability of the alert pipeline, not safety outcomes.

---

## 1. Uptime commitment

KubixDesiney will use commercially reasonable efforts to achieve **99.9%
monthly uptime** on the alert pipeline — the path from an alert being created
in Customer's dedicated instance to it being made available for delivery to
an eligible supervisor's device, and the availability of the core Service
endpoints (alert intake, assignment, notification dispatch).

## 2. Measurement method

Uptime is measured by a **synthetic monitor**: a dedicated monitoring worker
injects a test transaction into a reserved synthetic path on a fixed interval
and records success/failure and latency, without paging real supervisors.
Monthly uptime percentage is calculated as:

```
Uptime % = (total scheduled monitoring checks − failed checks) / total scheduled monitoring checks × 100
```

A "failed check" is a synthetic check that does not complete successfully
within the timeout KubixDesiney publishes for that check type. Results are
aggregated daily and reported monthly per Section 6.

## 3. Service credits

If measured monthly uptime falls below the commitment in Section 1, and the
shortfall is not subject to an Exclusion (Section 5), Customer may request
the following service credit, applied against the following month's Service
fees:

| Monthly uptime | Service credit |
|---|---|
| 99.5% – < 99.9% | 5% of that month's Service fees |
| 99.0% – < 99.5% | 10% of that month's Service fees |
| 95.0% – < 99.0% | 20% of that month's Service fees |
| < 95.0% | 30% of that month's Service fees |

**How to claim:** Customer must request a service credit in writing within
[[PLACEHOLDER: claim window, e.g. 30 days]] of the end of the affected month,
with reasonable detail of the incidents relied on. Service credits are
Customer's **sole and exclusive remedy** for a failure to meet the uptime
commitment. Total service credits in any month will not exceed 30% of that
month's Service fees.

## 4. Support response targets

| Plan | Support channel | First-response target |
|---|---|---|
| Starter | Email | 48 hours |
| Growth | Priority queue | 8 business hours |
| Enterprise | Priority queue + designated contact | 4 hours |

Targets apply to KubixDesiney's first substantive response to a support
request, not to resolution time. Business hours are [[PLACEHOLDER: support
business hours and timezone]]. Response targets apply to requests submitted
through KubixDesiney's designated support channel for the applicable plan.

## 5. Exclusions

This SLA does not apply to unavailability or degradation caused by, or
attributable to:

- Customer's own operational technology (OT) network, SCADA/PLC/gateway
  layer, or industrial connectors upstream of the Service;
- Customer's devices, local network, or internet connectivity;
- third-party platform outages or throttling outside KubixDesiney's control
  (for example, push notification platform outages);
- scheduled maintenance for which KubixDesiney gives at least
  [[PLACEHOLDER: maintenance notice period, e.g. 48 hours]] advance notice;
- force majeure events as defined in the MSA;
- Customer's breach of the MSA, or use of the Service other than as
  documented;
- beta, preview, or evaluation features not designated as generally
  available.

## 6. Reporting

KubixDesiney will make a monthly uptime report available to Enterprise
Customers on request, covering measured uptime, any incidents, and their
root cause where known. Raw monitoring data is retained for at least 13
months.

## 7. Review

The commitments in this SLA are reviewed [[PLACEHOLDER: review cadence, e.g.
annually]] and after any Severity-1 availability incident. Changes require
written agreement between the parties, except that KubixDesiney may improve
(but not reduce) the commitments in this SLA by notice.

---

*Related documents: `MSA.md` (incorporates this SLA for Enterprise Customers),
`DPA.md`, `EULA.md`, `PRIVACY.md`.*
