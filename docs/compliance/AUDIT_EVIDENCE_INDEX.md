# Audit Evidence Index — SIAS

A single map from "what an auditor/buyer asks for" to "where the evidence lives,"
so an assessment doesn't turn into a scavenger hunt. Pair with
`SOC2_CONTROL_MATRIX.md` (control-by-control) — this is the document-finder view.

Last reviewed 2026-06-16.

## Policies & governance
- Information security policy — `docs/policies/information_security_policy.md`
- Access control policy — `docs/policies/access_control_policy.md`
- Change management policy — `docs/policies/change_management_policy.md`
- Incident response plan — `docs/policies/incident_response_plan.md`
- Data retention & privacy policy — `docs/policies/data_retention_privacy_policy.md`
- Policy index — `docs/policies/README.md`

## Security design & verification
- Threat model (STRIDE) — `docs/security/THREAT_MODEL.md`
- OWASP ASVS L2 checklist — `docs/security/ASVS_CHECKLIST.md`
- Authorization rules (deny-by-default) — `database.rules.json`
- Rules/authorization tests — `worker_test/database_rules_security.test.js`
- Edge security guard (rate limit, injection, sanitize) — `cloudflare_ai_worker.js` (`_securityGuard`)
- Security headers (CSP/HSTS/…) — `firebase.json`
- SAST — `.github/workflows/codeql.yml`
- Secret scanning — `.gitleaks.toml`, `.github/workflows/security.yml`
- Dependency management — `.github/dependabot.yml`
- Secret rotation procedure — `docs/SECRET_ROTATION.md`
- Penetration test scope — `docs/PENTEST_SCOPE.md`

## Reliability & operations
- SLOs / error budgets — `docs/ops/SLO.md`
- Operations runbook — `docs/ops/RUNBOOK.md`
- Observability map — `docs/ops/OBSERVABILITY.md`
- Synthetic monitoring — `tool/smoke_test.mjs`, `.github/workflows/uptime.yml`
- Disaster recovery — `DISASTER_RECOVERY.md`
- Load/capacity testing — `LOAD_TESTING.md`, `tool/load_benchmark.mjs`
- Live health evidence (runtime) — `workers/health/*`, `security/logs`, `security/actions`, `bugs/client`

## Change management & SDLC
- Branch protection — `docs/BRANCH_PROTECTION.md`, `.github/branch-protection-main.json`
- Code ownership — `.github/CODEOWNERS`
- CI pipeline — `.github/workflows/ci.yml`, `quality.yml`
- Contribution standards — `CONTRIBUTING.md`
- Self-healing pipeline (gated) — `tool/autonomous_bugfix_agent.mjs`, ADR-0005
- Architecture decisions — `docs/adr/*`, `ARCHITECTURE.md`

## Privacy & data
- Records of processing (Art. 30) — `docs/compliance/ROPA.md`
- DPIA (biometric/location) — `docs/compliance/DPIA.md`
- DPA template (Art. 28) — `docs/compliance/DPA_TEMPLATE.md`
- Vendor security questionnaire — `docs/compliance/VENDOR_SECURITY_QUESTIONNAIRE.md`

## Compliance status
- SOC 2 control matrix — `docs/compliance/SOC2_CONTROL_MATRIX.md`
- Compliance overview — `COMPLIANCE.md`

## Items pending external action (transparent gaps)
| Item | Owner | Blocker |
|---|---|---|
| SOC 2 Type I/II report | Auditor | Engagement + observation window |
| Executed penetration test | Pentest vendor | Scheduling (scope ready) |
| DR drill records | Operator | Run the documented drill, capture results |
| Periodic access reviews | Operator | Establish cadence + log reviews |
| Signed sub-processor DPAs | Operator/customer | Counter-signatures |
