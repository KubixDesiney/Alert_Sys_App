# Data retention & privacy policy

Version 1.0 - 2026-06-15 - Owner: SuperAdmin / security lead - Review: annual

## 1. Purpose & scope
How SIA collects, processes, retains, and deletes personal and operational data, and how
data-subject rights are honored. Applies to every SIA instance.

## 2. Controller / processor model
In the dedicated-instance model (`PROVISIONING.md`) each customer runs its own Firebase
project, so the **customer is the data controller** and sets final retention and consent;
SIA provides the software and the defaults below. Sub-processors: Google (Firebase),
Cloudflare (Workers). On-prem deployments (`ONPREM.md`) have no third-party processors.

## 3. Data we process
| Category | Examples | Sensitivity |
|----------|----------|-------------|
| Account PII | firstName, lastName, email, phone | Personal |
| Location | `users/{uid}/currentLocation` (GPS lat/lng) | Sensitive |
| Biometric | `users/{uid}/voiceprint` (speaker embedding) | **Special category - explicit consent** |
| Operational | alerts, shifts, collaborations, AI decisions | Internal |
| Device | `fcmToken` | Personal (pseudonymous) |
| Security / audit | `security/logs`, `security/actions`, `bugs/client` | Internal |
| Backups | RTDB exports in `backups/` | Mirrors the above |

## 4. Consent & legal basis
- **Voice biometric** (`voiceprint`) is **opt-in only**. Supervisors may decline and use
  manual claim. Opting out (`aiOptOut` / disabling voice) deletes the stored voiceprint.
- **Location** is written only while the supervisor is on an active shift/role, limited to
  numeric lat/lng, and stops on sign-out.
- No analytics SDKs, ad trackers, or data sales.

## 5. Retention schedule (defaults; the controller may adjust)
| Data | Retention | Deletion mechanism |
|------|-----------|--------------------|
| Account PII | life of account; <= 30 days after offboarding | account revoke + `tool/migrate_user_pii.mjs` |
| Voiceprint (biometric) | until opt-out or offboarding | cleared on opt-out / account delete |
| Location (GPS) | 90 days rolling | scheduled purge |
| Alerts / operational | 24 months, then anonymize | archive / anonymize job |
| AI decisions & feedback | 12 months | rolling purge |
| Security / audit logs | >= 12 months (SOC 2) | rolling purge after retention |
| `bugs/client` errors | 90 days | dedup + age-out |
| FCM tokens | cleared on logout / unregister | notify-worker token cleanup |
| RTDB backups | 30-90 days rolling | backup rotation (`DISASTER_RECOVERY.md`) |

## 6. Data minimization
Collect only what operations require. Firebase client API keys are public configuration,
not personal data.

## 7. Data-subject rights (DSR)
Supports access, rectification, erasure, restriction, and portability. Process: request to
the controller -> verify identity -> fulfil within the statutory window (e.g. 30 days under
GDPR). Erasure = account revoke + `tool/migrate_user_pii.mjs` + backup purge after the
backup-retention window.

## 8. Deletion & offboarding
- **User offboarding**: revoke auth, delete `users/{uid}`, clear `voiceprint` and `fcmToken`.
- **Company decommissioning**: per `PROVISIONING.md` (delete the project / purge the instance).
- Deletions propagate into backups within the backup-retention window.

## 9. Cross-border & residency
Each instance's Firebase project region is chosen at provisioning; data remains in that
region. On-prem keeps all data on customer hardware.

## 10. Breach handling & review
Personal-data breaches follow `docs/policies/incident_response_plan.md`, including
notification within the applicable statutory timeline. Reviewed annually.
