# SIA Trust Center

**Smart Industrial Alert (SIA)** — operated by KubixDesiney

Last updated: 2026-06-23

This page summarizes the security, privacy, and reliability controls in place for
SIA. It is written for prospective and early-pilot enterprise customers and links
to the underlying source-of-truth documents in this repository. It describes
controls **as they exist today** and intentionally does not assert any
certification the project has not earned (see *Compliance posture* below).

---

## 1. Architecture and tenant isolation

SIA is delivered as a **dedicated instance per customer**. Each customer's data
resides in that customer's own Firebase project and is served by Cloudflare
Workers deployed for that customer. There is no shared, multi-tenant data store
across customers, which removes a large class of cross-tenant data-leak risk.

- Design rationale: `docs/adr/0003-dedicated-instance-model.md`
- Per-instance provisioning is automated via `.github/workflows/deploy-instance.yml`.

## 2. Access control (RBAC)

Access is role-based and deny-by-default:

- **Supervisor** — alert handling, collaboration, voice claim, location.
- **Admin (Production Manager)** — factory operations within their own tenant.
- **SuperAdmin** — platform configuration and observability (operator role).

Roles are enforced at the data layer by Firebase Realtime Database security rules,
not only in the UI. Sensitive nodes (security telemetry, worker health,
configuration vaults) are restricted to the SuperAdmin role and the worker service
identity; ordinary admin accounts are deliberately excluded. Privileged accounts
support MFA/SSO via Firebase Identity Platform.

- Policy: `docs/policies/access_control_policy.md`

## 3. SuperAdmin configuration

A dedicated SuperAdmin console centralizes configuration with least-privilege
boundaries: AI agent enable/disable controls, security defense toggles, model
training/deployment, Production Manager provisioning (through an isolated secondary
auth app so the operator session is never replaced), industrial connector setup,
and platform observability. Configuration changes are constrained by the same
Firebase rules that govern all other access.

## 4. Application and data security

- **Authorization as code:** `database.rules.json` enforces field-level validation
  and least-privilege reads/writes. Rationale in
  `docs/adr/0004-rtdb-rules-as-authorization.md`.
- **Rules are tested:** `worker_test/database_rules_security.test.js` asserts that
  security/worker/forecast nodes reject non-privileged access.
- **Encryption:** TLS in transit; provider-managed encryption at rest in Firebase.
- **Secrets handling:** no secrets are committed to source. Worker secrets are
  injected via Cloudflare secrets and the Firebase service-account credential is
  provided at runtime only. Firebase client API keys are public by design and are
  locked down with Google Cloud API-key restrictions plus rule enforcement. See
  `SECURITY.md` and `docs/SECRET_ROTATION.md`.

## 5. Edge and infrastructure (Cloudflare Workers)

Edge logic is split across purpose-scoped Workers so notification delivery does not
compete with AI/security processing, and so credentials are held server-side:

- AI/security worker, notifications worker, GitHub proxy, and SCADA/industrial
  ingestion worker.
- A runtime security guard provides per-endpoint rate limiting, prompt-injection
  detection, input sanitization, and anomaly scanning.
- Design rationale: `docs/adr/0001-dual-worker-split.md`.

## 6. Secure development and CI/CD

Every change to `main` and every pull request runs automated gates in GitHub
Actions:

| Control | Where | What it does |
|---|---|---|
| Static analysis (SAST) | `.github/workflows/codeql.yml` | CodeQL `security-extended` on JS/TS, on push, PR, and weekly |
| Secret scanning | `.github/workflows/security.yml` | `gitleaks` blocking scan of the current tree (`.gitleaks.toml`) |
| Dependency audit | `.github/workflows/security.yml` | `npm audit` (high) for root, functions, and secondary codebase |
| Dependency updates | `.github/dependabot.yml` | Automated dependency update PRs |
| Build/test | `.github/workflows/ci.yml` | `flutter analyze`, Flutter tests, worker Jest tests |
| Coverage + perf guard | `.github/workflows/quality.yml` | Enforced Jest coverage threshold and an assignment performance guard |
| Code review | `.github/CODEOWNERS` + branch protection | Required review before merge (`docs/BRANCH_PROTECTION.md`) |

The Guardian self-heal pipeline additionally requires an independent review model
and passing tests before any automated change can merge or deploy
(`docs/adr/0005-guardian-self-healing-pipeline.md`).

## 7. Logging, monitoring, and audit trail

- **Security audit logs:** enforcement events are persisted and timestamped under
  `security/logs` and `security/actions`.
- **Operational decision logs:** AI assignment decisions (`ai_decisions`) and shift
  commander actions (`shift_ai_logs`) are recorded with reasons.
- **Error pipeline:** de-duplicated client errors are captured in `bugs/client`;
  autonomous agent runs in `bugs/agent`.
- **Health and uptime:** Workers write per-run health pulses; synthetic uptime
  checks run via `.github/workflows/uptime.yml`.
- **Observability reference:** `docs/ops/OBSERVABILITY.md`,
  service levels in `docs/ops/SLO.md`.

## 8. Incident response

A documented incident response process covers detection, triage, severity,
communication, and blameless postmortems:

- `docs/policies/incident_response_plan.md`
- Operational runbook: `docs/ops/RUNBOOK.md`

## 9. Data privacy and retention

- Privacy notice: `PRIVACY.md`
- Retention/disposal: `docs/policies/data_retention_privacy_policy.md`
- Record of Processing Activities: `docs/compliance/ROPA.md`
- Data Processing Agreement (template): `docs/compliance/DPA_TEMPLATE.md`

Customer data stays within the customer's own cloud tenancy (dedicated instance),
and customers may request export or deletion of their instance data.

## 10. Subprocessors

- **Google Firebase** — Authentication, Realtime Database, Hosting, Cloud
  Messaging.
- **Cloudflare** — Workers (edge orchestration, notifications, security,
  integrations).

Optional integrations are enabled only at the customer's direction.

## 11. Compliance posture (what we claim and what we do not)

- SIA is **not** currently certified or attested under SOC 2, ISO 27001, or any
  other framework, and this document makes no such claim.
- We maintain **readiness materials** mapped to common control frameworks to support
  future audits and customer due diligence — for example a SOC 2 control matrix and
  system description (`docs/compliance/`, `docs/external/`), a threat model and ASVS
  checklist (`docs/security/`), and written security policies (`docs/policies/`).
  These are internal artifacts, not certifications.
- Penetration testing scope and remediation tracking are documented in
  `docs/PENTEST_SCOPE.md` and `docs/external/PENTEST_*`.

We are happy to walk pilot customers through any control and to complete a security
questionnaire (`docs/compliance/VENDOR_SECURITY_QUESTIONNAIRE.md`).

## 12. Reporting a vulnerability

Please report suspected vulnerabilities privately per `SECURITY.md`. Do not open
public issues for security reports.

## 13. Contact

Security, privacy, and trust inquiries: <chefbriotemendez@gmail.com>
