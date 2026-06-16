# OWASP ASVS L2 Conformance Checklist — SIA

Maps the Smart Industrial Alert platform against OWASP Application Security
Verification Standard (ASVS) v4.0.3, target **Level 2** (the standard bar for
applications handling sensitive business data). Status legend: ✅ met,
🟡 partial / compensating control, ⬜ not applicable, 🔜 planned.

Last reviewed 2026-06-16. Re-verify each release (`RELEASE.md`).

## V1 Architecture, Design & Threat Modeling
- ✅ 1.1.2 Threat model maintained — `docs/security/THREAT_MODEL.md`.
- ✅ 1.4.x Trust boundaries documented and enforced at each tier.
- ✅ 1.14 Dedicated-instance isolation; no shared multi-tenant data plane.

## V2 Authentication
- ✅ 2.1 Firebase Auth; no anonymous access except the constrained alert-create shape.
- ✅ 2.2 MFA/SSO available — see `MFA_SSO.md`.
- 🟡 2.5 Credential rotation: documented (`docs/SECRET_ROTATION.md`); historical dev key accepted-risk per dedicated-instance model.

## V3 Session Management
- ✅ 3.2 Firebase-managed tokens; short-lived ID tokens, refresh handled by SDK.
- ✅ 3.3 Sign-out clears cached role/usine (`OfflineAccountCache`) and stops location tracking.

## V4 Access Control
- ✅ 4.1 Deny-by-default RTDB rules; role checked server-side.
- ✅ 4.2 `security/*`, `workers/*`, `ai_forecast` write, `ai_agent_secrets` are superadmin/worker-only — asserted by `worker_test/database_rules_security.test.js`.
- ✅ 4.3 No client path to role self-escalation; provisioning via secondary app only.

## V5 Validation, Sanitization & Encoding
- ✅ 5.1 Worker `_securityGuard`: JSON shape validation, 64 KB body cap, 8 KB prompt clamp.
- ✅ 5.2 Prompt-injection pattern bank (10 signatures) + control-char stripping.
- ✅ 5.3 RTDB rule validators enforce types (booleans stay boolean, timestamps stay strings).

## V7 Error Handling & Logging
- ✅ 7.1 No secrets in error responses; exfil patterns (`firebase_url`, `cloudflare_token`) blocked.
- ✅ 7.2 Security events logged to `security/logs` + `security/actions` with fingerprint/endpoint.
- ✅ 7.3 Client errors deduplicated into `bugs/client`; worker health to `workers/health`.

## V8 Data Protection
- ✅ 8.1 PII (name/email/phone/GPS) scoped to authenticated factory context.
- ✅ 8.2 Data retention & privacy — `docs/policies/data_retention_privacy_policy.md`.
- 🟡 8.3 At-rest encryption provided by Firebase/Cloudflare platforms; customer-managed keys 🔜 for on-prem (`ONPREM.md`).

## V9 Communications
- ✅ 9.1 TLS everywhere (Firebase, Cloudflare, FCM, GitHub).
- ✅ 9.2 HSTS + security headers served by Firebase Hosting (`firebase.json`).

## V10 Malicious Code
- ✅ 10.2 CodeQL SAST (`.github/workflows/codeql.yml`); Dependabot; gitleaks secret scanning.
- ✅ 10.3 Guardian auto-fix gated by independent review AI + tests before any merge/deploy.

## V12 Files & Resources
- ✅ 12.1 Skill/instruction `.md` uploads sanitized and size-capped (8 KB) before storage.

## V13 API & Web Service
- ✅ 13.1 Per-endpoint sliding-window rate limits; shared-secret on protected routes.
- ✅ 13.2 GitHub token held server-side in worker vault; never shipped to clients.

## V14 Configuration
- ✅ 14.1 Least-privilege GitHub Actions `permissions:` on all workflows.
- ✅ 14.2 Third-party actions reviewed; secrets via CI secret store, never committed.
- ✅ 14.4 Security headers (CSP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy) set.

## Supply-chain hardening summary
| Control | Tool | Gate |
|---|---|---|
| Secret scanning | gitleaks | Blocking on current tree, informational on history |
| Dependency CVEs | Dependabot | Weekly PRs |
| SAST | CodeQL | PR + push to main |
| Least privilege | workflow `permissions:` | All workflows |
| Review gate | Guardian dual-AI + tests | Before deploy/merge |

## Known gaps / roadmap to full L2 sign-off
1. Independent penetration test execution (scope ready: `docs/PENTEST_SCOPE.md`).
2. Customer-managed encryption keys for on-prem deployments.
3. SOC 2 Type I attestation (policies authored under `docs/policies/`; auditor engagement pending).
