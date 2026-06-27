# ADR-0003: Dedicated per-customer instances

Status: Accepted — 2026-06

## Context
SIAS is sold to industrial companies that have strict data-residency, isolation,
and procurement requirements, and that often already own Firebase/cloud accounts.
A shared multi-tenant backend would concentrate risk (one breach exposes all
customers), complicate data-residency promises, and make the historical leaked
dev credential a cross-customer liability.

## Decision
Each customer runs a **dedicated instance**: their own Firebase project (Auth +
RTDB), their own Cloudflare Worker deployment, and their own secrets, provisioned
through the SuperAdmin console / `deploy-instance.yml` (`tool/provision_company.mjs`).
No shared data plane exists between customers. Credentials are supplied by the
customer and stored only in their instance's secret store.

## Consequences
**Positive:** blast radius of any single compromise is one customer; data residency
is whatever the customer's Firebase region is; the accepted historical dev-key risk
never reaches customer instances (it lives only on the reference/demo instance);
billing and quotas are naturally per-customer.

**Negative:** no central fleet dashboard by default; upgrades must roll out per
instance (mitigated by the provisioning workflow and Guardian per-instance CI);
onboarding requires a provisioning step rather than just creating a tenant row.

## Related
THREAT_MODEL.md (blast-radius reasoning), PROVISIONING.md, ONPREM.md, ADR-0006.
