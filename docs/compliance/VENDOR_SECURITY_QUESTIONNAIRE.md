# Vendor Security Questionnaire (pre-answered)

Buyers' procurement/security teams send SIG-lite / CAIQ / bespoke questionnaires.
This is a pre-filled response covering the common domains, so a deal isn't stalled
for weeks. Answers reflect the dedicated-instance architecture (each customer's data
is isolated in their own Firebase/Cloudflare project; no shared multi-tenant plane).

Last reviewed 2026-06-16. Format: **Q — A — Evidence.**

## A. Governance & risk
- **Documented information security policy?** — Yes. — `docs/policies/information_security_policy.md`.
- **Risk assessment / threat modeling?** — Yes, STRIDE per trust boundary, reviewed each release. — `docs/security/THREAT_MODEL.md`.
- **Secure SDLC?** — Yes: PR review, CODEOWNERS, branch protection, CI gates, conventional commits. — `CONTRIBUTING.md`, `docs/BRANCH_PROTECTION.md`.

## B. Access control
- **Authentication?** — Firebase Auth; MFA/SSO supported. — `MFA_SSO.md`.
- **Authorization model?** — Deny-by-default RBAC enforced in `database.rules.json`; superadmin/worker-only on sensitive nodes; tested. — `worker_test/database_rules_security.test.js`.
- **Least privilege in CI?** — Yes, `permissions:` blocks on every workflow; GitHub token held server-side in a worker vault. — `.github/workflows/*`, `cloudflare_github_worker.js`.
- **Privileged access?** — SuperAdmin tier; account provisioning via isolated secondary app.

## C. Data protection
- **Encryption in transit?** — TLS across Firebase/Cloudflare/FCM. — ASVS V9.
- **Encryption at rest?** — Platform-managed (Firebase/Cloudflare); customer-managed keys on the on-prem roadmap. — `ONPREM.md`.
- **Data classification & retention?** — Documented; DSAR + erasure supported. — `docs/policies/data_retention_privacy_policy.md`, `ROPA.md`.
- **Multi-tenancy isolation?** — None required: dedicated instance per customer, no shared data plane. — ADR-0003.
- **Biometric/location data?** — Opt-in, DPIA-covered, consent-gated, minimized. — `DPIA.md`.

## D. Application & infrastructure security
- **SAST / secret / dependency scanning?** — CodeQL (security-extended), gitleaks, Dependabot. — `.github/workflows/{codeql,security}.yml`, `.github/dependabot.yml`.
- **Input validation / injection defense?** — Edge guard: rate limits, 10-pattern prompt-injection bank, sanitization, body caps. — `docs/security/ASVS_CHECKLIST.md` V5/V13.
- **Security headers?** — CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP/CORP. — `firebase.json`.
- **Penetration testing?** — Scope & rules of engagement prepared; execution pending. — `docs/PENTEST_SCOPE.md`.

## E. Operations, monitoring & resilience
- **Logging & monitoring?** — Worker health pulses, security logs/actions, client-error pipeline, synthetic uptime checks. — `docs/ops/OBSERVABILITY.md`.
- **SLAs / SLOs?** — Defined with error budgets. — `docs/ops/SLO.md`.
- **Incident response?** — Documented IR plan + operational runbook with severities and breach notification. — `docs/policies/incident_response_plan.md`, `docs/ops/RUNBOOK.md`.
- **Backup & DR?** — Backup worker + documented DR. — `DISASTER_RECOVERY.md`.
- **Change management?** — Tested, reviewed, gated; optional AI self-healing with dual-AI + test gate. — `docs/policies/change_management_policy.md`, ADR-0005.

## F. Compliance & privacy
- **SOC 2?** — Control matrix complete; auditor engagement pending (Type I → Type II). — `SOC2_CONTROL_MATRIX.md`.
- **GDPR?** — ROPA, DPA template, DPIA available; processor role under dedicated-instance model. — `ROPA.md`, `DPA_TEMPLATE.md`, `DPIA.md`.
- **Sub-processors disclosed?** — Yes. — `ROPA.md`.
- **Secret management / rotation?** — Per-instance secrets; rotation runbook. — `docs/SECRET_ROTATION.md`.

## G. Known limitations (stated honestly)
- SOC 2 report and executed penetration test are **not yet complete** (artifacts/scope ready).
- At-rest customer-managed keys are on-prem-roadmap, not yet GA.
- SIA is an alerting/coordination layer, not a safety-rated control system. — `docs/integrations/COMPETITIVE_POSITIONING.md`.
