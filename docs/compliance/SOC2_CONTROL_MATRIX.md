# SOC 2 Control Matrix — SIAS

Maps the AICPA Trust Services Criteria (TSC, 2017 incl. 2022 points of focus) to
SIAS's implemented controls and the evidence an auditor can pull. Target: **SOC 2
Type I** first (design at a point in time), then **Type II** (operating
effectiveness over a 3–6 month window).

Status: ✅ implemented · 🟡 partial/compensating · 🔜 process-dependent (needs an
observation window or external party). Last reviewed 2026-06-16.

> This matrix makes the audit **turnkey**: each control names where it lives and
> what artifact proves it. The remaining gap to a signed report is the auditor
> engagement + Type II observation window — see "Roadmap" at the bottom.

## Common Criteria (Security) — required for every SOC 2

| TSC | Control | Implementation | Evidence | Status |
|---|---|---|---|---|
| CC1.x Control environment | Governance, roles, policies | Policy set, ownership | `docs/policies/*`, `.github/CODEOWNERS` | ✅ |
| CC2.x Communication | Documented architecture & responsibilities | Living docs | `ARCHITECTURE.md`, `.claude/CLAUDE.md`, `docs/adr/*` | ✅ |
| CC3.x Risk assessment | Threat model + risk rating | STRIDE per boundary | `docs/security/THREAT_MODEL.md` | ✅ |
| CC4.x Monitoring | Continuous health + synthetic checks | Worker health, smoke test, uptime | `docs/ops/OBSERVABILITY.md`, `tool/smoke_test.mjs`, `.github/workflows/uptime.yml` | ✅ |
| CC5.x Control activities | Change mgmt + review gates | Branch protection, CODEOWNERS, CI | `docs/policies/change_management_policy.md`, `docs/BRANCH_PROTECTION.md` | ✅ |
| CC6.1 Logical access | AuthN + deny-by-default authz | Firebase Auth, RTDB rules | `database.rules.json`, `docs/policies/access_control_policy.md` | ✅ |
| CC6.2/6.3 Provisioning | Least-privilege role grant | SuperAdmin provisioning, RBAC | `superadmin_service.dart`, ASVS V4 | ✅ |
| CC6.6 Boundary protection | Edge guard, rate limit, headers | Worker `_securityGuard`, CSP/HSTS | `docs/security/ASVS_CHECKLIST.md`, `firebase.json` | ✅ |
| CC6.7 Data in transit | TLS everywhere | Firebase/Cloudflare/FCM | ASVS V9 | ✅ |
| CC6.8 Malicious code | SAST + secret + dep scanning | CodeQL, gitleaks, Dependabot | `.github/workflows/{codeql,security}.yml`, `.github/dependabot.yml` | ✅ |
| CC7.1/7.2 Detection | Anomaly scan + security logs | Worker anomaly scan | `security/logs`, `security/actions` | ✅ |
| CC7.3/7.4 Incident response | Documented IR + runbook | Severity, comms, procedures | `docs/policies/incident_response_plan.md`, `docs/ops/RUNBOOK.md` | ✅ |
| CC7.5 Recovery | DR plan + backups | DR doc, R2 backup worker | `DISASTER_RECOVERY.md` | ✅ |
| CC8.1 Change management | Tested, reviewed, gated changes | CI + Guardian dual-AI/test gate | `.github/workflows/ci.yml`, ADR-0005 | ✅ |
| CC9.x Risk mitigation / vendors | Vendor due diligence | Subprocessor list, questionnaire | `VENDOR_SECURITY_QUESTIONNAIRE.md`, `ROPA.md` | 🟡 |

## Availability (A)

| TSC | Control | Implementation | Evidence | Status |
|---|---|---|---|---|
| A1.1 Capacity | Load benchmarked | Benchmark tool + report | `LOAD_TESTING.md`, `tool/load_benchmark.mjs` | ✅ |
| A1.2 Backup/recovery/SLO | SLOs, error budgets, DR | Targets + runbook | `docs/ops/SLO.md`, `DISASTER_RECOVERY.md` | ✅ |
| A1.3 Recovery testing | DR drill cadence | DR doc procedure | `DISASTER_RECOVERY.md` | 🔜 (needs drill records) |

## Confidentiality (C)

| TSC | Control | Implementation | Evidence | Status |
|---|---|---|---|---|
| C1.1 Identify confidential data | Data classes documented | ROPA | `ROPA.md` | ✅ |
| C1.2 Protect/dispose | Retention + deletion | Retention policy | `docs/policies/data_retention_privacy_policy.md` | ✅ |

## Processing Integrity (PI)

| TSC | Control | Implementation | Evidence | Status |
|---|---|---|---|---|
| PI1.x Complete/accurate processing | Validators, transactions, prediction grading | RTDB validators, claim transactions, forecaster self-eval | `database.rules.json`, `ai_forecast/accuracy/*` | ✅ |

## Privacy (P) — if in scope for the customer

| TSC | Control | Implementation | Evidence | Status |
|---|---|---|---|---|
| P1–P8 | Notice, choice, access, retention, disposal | Privacy policy, DSAR path, retention | `docs/policies/data_retention_privacy_policy.md`, `DPIA.md` | 🟡 |

## Roadmap to a signed report
1. Engage a SOC 2 auditor; select TSC scope (Security mandatory; +Availability/Confidentiality recommended for this product).
2. Type I readiness review against this matrix (most controls are ✅ by design).
3. Collect operating evidence over the Type II window (CI logs, security/health pulses, incident/DR drill records, access reviews).
4. Close 🔜 items: DR drill records, periodic access reviews, signed subprocessor agreements.
