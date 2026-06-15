# Compliance & security control map

Buyer-facing summary of the security and reliability controls in Smart Industrial
Alert (SIA), mapped to the SOC 2 Trust Services Criteria and common industrial
procurement questionnaires. Honest status: **Done / Partial / Gap**.

## Deployment & tenancy
SIA supports a **dedicated-instance per company** model (see `PROVISIONING.md`): each
customer runs an isolated Firebase project + isolated Cloudflare workers, with its own
data store, secrets, and SuperAdmin. There is no shared multi-tenant database, which
removes an entire class of cross-tenant data-leak risk.

## Role-based access control (RBAC)
| Role | Scope | Reads | Writes | MFA |
|------|-------|-------|--------|-----|
| `superadmin` | platform | users, `security/*`, `workers/*`, `ai_forecast`, `bugs` | provision PMs, forecaster, agent config | required (recommended) |
| `admin` (Production Manager) | company/factory | alerts, hierarchy, shifts, collaborations | hierarchy, supervisors, settings, shifts | required (recommended) |
| `supervisor` | own work | alerts, collaborations, help | claim/resolve/comment, own location, shift readiness | optional |
| unauthenticated | minimal | `auth_config` (SSO discovery pre-login) | constrained first-write alert create only | n/a |

Enforced in `database.rules.json` (self-or-admin patterns; `security/*` and `workers/*`
restricted to superadmin + worker service token).

## Control map (SOC 2 Trust Services Criteria)
| Criterion | SIA control | Status |
|-----------|-------------|--------|
| CC6 Access control | RBAC + RTDB rules; MFA/SSO via Identity Platform (`MFA_SSO.md`) | Done (enforce MFA = recommended) |
| CC6.7 Encryption | TLS in transit; Firebase at-rest encryption (Google-managed keys) | Done (documented) |
| CC7 Monitoring | `security/logs` + `security/actions` audit trail; monitor worker; `bugs/client`; `workers/health` | Partial (add retention + SIEM export) |
| CC7.1 Vulnerability mgmt | `gitleaks` secret scan + `npm audit` + Dependabot (CI) | Done |
| CC8 Change mgmt | CI gates (analyze/test/coverage/perf/security), release runbook (`RELEASE.md`) | Partial (add branch protection + required review) |
| A1 Availability | DR + backups (`DISASTER_RECOVERY.md`), monitoring, load proof + SLOs (`LOAD_TESTING.md`) | Partial (run tested DR + uptime monitor) |
| C1 Confidentiality | Per-tenant isolation; secret handling (no secrets in source) | Done |
| PI1 Processing integrity | RTDB transactions/locks, rules validation, 188 worker + Flutter tests | Done |
| P (Privacy) | PII migration tooling (`tool/migrate_user_pii.mjs`); minimal data model | Partial (document retention + deletion) |

## Security questionnaire — quick answers
- **Where is data stored?** Customer's own Firebase (Google Cloud) project; region selectable at project creation.
- **Encryption?** TLS 1.2+ in transit; AES-256 at rest (Google-managed).
- **Authentication?** Firebase Auth with optional enterprise SSO (OIDC/SAML) and MFA.
- **Secrets?** None in source; Cloudflare secrets + runtime service-account injection; CI secret scanning (`gitleaks`).
- **Audit trail?** Security enforcement actions, AI decisions, and client errors are persisted and timestamped.
- **Backups / DR?** Automated + on-demand RTDB backup and restore; documented DR runbook.
- **Pen test?** Planned (see open items).
- **Sub-processors?** Google (Firebase) and Cloudflare (Workers).

## Open items to reach SOC 2 / certification
1. Write formal policies: information security, access control, incident response, change management.
2. Enable GitHub branch protection on `main` with required PR review + required status checks.
3. Centralize audit-log retention (>= 1 year) and wire SIEM export.
4. Commission a third-party penetration test; remediate findings.
5. Publish sub-processor list + sign DPAs (Google, Cloudflare).
6. Document data retention, deletion, and data-subject-request (DSR) handling.
7. Engage a SOC 2 auditor (e.g. via Vanta/Drata) for a Type I, then a Type II observation window.
