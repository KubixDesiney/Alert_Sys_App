# Incident response plan

Version 1.0 - 2026-06-15 - Owner: security lead - Review: annual + after every incident

## 1. Roles
- **Incident commander**: SuperAdmin / security lead - coordinates the response.
- **Engineering on-call**: investigates and remediates.
- **Comms owner**: handles customer/authority notification.

## 2. Severity levels
| Sev | Definition | Target response |
|-----|------------|-----------------|
| SEV1 | Data breach, auth bypass, or full outage | < 1 hour |
| SEV2 | Partial outage, failed push/assignment at scale | < 4 hours |
| SEV3 | Degraded feature, elevated error rate | < 1 business day |

## 3. Detection sources
- `security/logs` + `security/actions` (rate-limit, injection, anomaly events).
- `bugs/client` deduplicated client errors.
- `workers/health` cron freshness + monitor worker alerts.
- CI security workflow (`gitleaks`, `npm audit`) failures.

## 4. Response steps
1. **Declare** severity and assign an incident commander.
2. **Contain**: revoke compromised credentials, rotate secrets, disable affected agent
   via the AI Agent Fleet toggle, or take the worker offline if needed.
3. **Eradicate**: deploy a fix through the change-management process (hotfix allowed for SEV1).
4. **Recover**: restore data from backups if required (`DISASTER_RECOVERY.md`); verify
   against SLOs (`LOAD_TESTING.md`).
5. **Communicate**: notify affected customers; for personal-data breaches, follow the
   applicable breach-notification timeline for the jurisdiction.

## 5. Post-incident review
Within 5 business days: timeline, root cause, what worked, action items with owners and
dates. Feed fixes back into tests/rules/policies. Record in an incident log.

## 6. Contacts
Security reports: chefbriotemendez@gmail.com (see `SECURITY.md`). Sub-processors:
Google (Firebase), Cloudflare (Workers).
