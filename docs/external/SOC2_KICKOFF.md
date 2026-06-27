# SOC 2 — Audit Kickoff Brief

What an auditor needs to start, and how we get to a signed report fast. Built on
the control matrix (`docs/compliance/SOC2_CONTROL_MATRIX.md`), the system
description (`docs/external/SOC2_SYSTEM_DESCRIPTION.md`), and the policy set
(`docs/policies/`). Fill `[...]` per engagement.

## 1. Scope we propose
- **Report type:** Type I first (design of controls at a point in time), then Type II (operating effectiveness over a window).
- **Trust Services Criteria:** **Security (Common Criteria) — required**, plus **Availability** and **Confidentiality** (strongly recommended for this product). Privacy optional per customer demand.
- **System boundary:** the SIAS platform — Flutter client, Firebase (Auth + RTDB), Cloudflare Workers, CI/CD (GitHub Actions), and the dedicated-instance provisioning path. Customer-owned cloud accounts are the customer's responsibility (shared-responsibility split documented).
- **Type II observation window:** `[3 or 6 months]`.

## 2. Why this should be efficient
Most controls are already designed and evidenced (see the control matrix — the
majority are marked implemented). We maintain: documented policies, a STRIDE threat
model, deny-by-default authorization with rule tests, SAST/secret/dependency
scanning, SLOs + runbook + DR, and an audit-evidence index. The auditor's job is to
test what we've built, not help us build it.

## 3. Evidence sources (where the auditor pulls proof)
| Control area | Evidence | Location |
|---|---|---|
| Policies/governance | Policy set + ownership | `docs/policies/*`, `.github/CODEOWNERS` |
| Access control | Rules + role tests | `database.rules.json`, `worker_test/database_rules_security.test.js` |
| Change management | PR reviews, branch protection, CI logs | `docs/BRANCH_PROTECTION.md`, GitHub Actions history |
| Vulnerability mgmt | CodeQL/gitleaks/Dependabot runs | `.github/workflows/*`, Security tab |
| Monitoring | Worker health, security logs, synthetic checks | `workers/health`, `security/*`, `docs/ops/OBSERVABILITY.md` |
| Availability/DR | SLOs, runbook, DR, backups | `docs/ops/SLO.md`, `docs/ops/RUNBOOK.md`, `DISASTER_RECOVERY.md` |
| Risk/threat | Threat model, ASVS, pentest report | `docs/security/*`, `docs/external/PENTEST_*` |
| Privacy | ROPA, DPA, DPIA | `docs/compliance/*` |

## 4. Pre-audit readiness checklist (close before Type II)
- [ ] Pentest executed + Critical/High findings remediated (`docs/external/PENTEST_REMEDIATION.md`).
- [ ] Quarterly access review performed and logged.
- [ ] DR drill performed and results captured.
- [ ] Security-awareness training completed by staff with access.
- [ ] Vendor/sub-processor DPAs counter-signed (`docs/compliance/ROPA.md`).
- [ ] Incident-response tabletop exercise run once.
- [ ] Change-management evidence accumulating (PRs, approvals, CI) across the window.

## 5. Roles
- Audit sponsor / point of contact: `[name]`
- Control owners: per the matrix (Security lead, Reliability lead, Eng lead).
- Auditor: `[firm]` — selection criteria: SaaS/cloud SOC 2 experience, fixed-fee Type I, clear evidence portal, reasonable Type II cadence.

## 6. Timeline (typical)
1. Kickoff + readiness review — `[2–3 weeks]` (gap list against the matrix).
2. Type I report — `[~4–8 weeks]` from kickoff.
3. Type II observation — `[3–6 months]` collecting operating evidence.
4. Type II report — at window close.

## 7. Output we share with prospects
The SOC 2 report (under NDA), plus the always-shareable control matrix and the
pre-answered vendor questionnaire (`docs/compliance/VENDOR_SECURITY_QUESTIONNAIRE.md`).
