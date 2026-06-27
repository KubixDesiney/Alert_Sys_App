# Information security policy

Version 1.0 - 2026-06-15 - Owner: SuperAdmin / security lead - Review: annual

## 1. Purpose & scope
Defines how SIAS protects the confidentiality, integrity, and availability of customer
and operational data. Applies to all code, infrastructure (Firebase, Cloudflare),
contributors, and connected services.

## 2. Roles & responsibilities
- **SuperAdmin / security lead**: owns this policy, access reviews, incident response.
- **Production Managers (admin)**: manage factory operations within their tenant only.
- **Engineering**: follow change-management and secure-coding practices.

## 3. Data classification
- **Confidential**: user PII, FCM tokens, credentials, RTDB exports.
- **Internal**: alerts, shifts, AI decisions, operational metrics.
- **Public**: marketing content, Firebase client config (public by design).

## 4. Controls (in force)
- **Encryption**: TLS 1.2+ in transit; AES-256 at rest (Google-managed) in Firebase.
- **Access**: RBAC enforced in `database.rules.json`; MFA/SSO via Identity Platform.
- **Secrets**: none in source; Cloudflare secrets + runtime service-account injection;
  CI secret scanning (`gitleaks`) and dependency auditing (`npm audit`, Dependabot).
- **Isolation**: dedicated Firebase project + workers per company (`PROVISIONING.md`).
- **Logging**: security enforcement (`security/logs`, `security/actions`), AI decisions,
  and client errors (`bugs/client`) are persisted and timestamped.
- **Backup/DR**: automated + on-demand RTDB backup/restore (`DISASTER_RECOVERY.md`).

## 5. Acceptable use
Access only the data required for your role. No sharing of credentials. No copying of
confidential data to unmanaged locations. RTDB exports stay in git-ignored `backups/`.

## 6. Exceptions & enforcement
Exceptions require written SuperAdmin approval with an expiry. Violations may result in
revoked access. This policy is reviewed annually and after any major incident.
