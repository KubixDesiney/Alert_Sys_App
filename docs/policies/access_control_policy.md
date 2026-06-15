# Access control policy

Version 1.0 - 2026-06-15 - Owner: SuperAdmin - Review: quarterly

## 1. Principle
Least privilege. Every identity gets the minimum access required for its role, enforced
technically in `database.rules.json` and Firebase Auth.

## 2. Roles (RBAC)
| Role | Grants |
|------|--------|
| `superadmin` | platform: users, `security/*`, `workers/*`, `ai_forecast`, `bugs`; provisions Production Managers |
| `admin` (Production Manager) | own company/factory: alerts, hierarchy, shifts, collaborations, supervisor management |
| `supervisor` | own work: claim/resolve alerts, collaboration/help, own location, shift readiness |
| unauthenticated | `auth_config` (SSO discovery) + constrained first-write alert create only |

## 3. Authentication
- Firebase Auth for all accounts.
- Enterprise **SSO** (OIDC/SAML) and **MFA** available via Identity Platform (`MFA_SSO.md`).
- **MFA is required for `admin` and `superadmin`** accounts.

## 4. Provisioning & deprovisioning
- Production Managers are provisioned via the SuperAdmin console (secondary Firebase app,
  so the SuperAdmin session is never replaced).
- On role change or offboarding, revoke the account and rotate any shared secrets.
- New tenants follow `PROVISIONING.md` (isolated project + SuperAdmin seed).

## 5. Secrets & keys
- Worker secrets via Cloudflare secrets; service-account credential injected at runtime.
- Firebase client API keys are public by design and MUST carry Google Cloud API-key
  restrictions (app + API allow-lists).
- No secret is ever committed; `gitleaks` enforces this in CI.

## 6. Access reviews
Quarterly review of all `admin`/`superadmin` accounts and active supervisors. Remove
stale access. Record the review date and reviewer.
