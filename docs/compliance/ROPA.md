# Records of Processing Activities (ROPA) — GDPR Article 30

Template + reference record for a SIA instance. Because SIA is sold as a dedicated
instance, the **customer is the data controller** and the SIA operator is typically
a **processor**. Each customer completes/owns their ROPA; this is the starting point.

Last reviewed 2026-06-16. Maintainer: Data Protection point of contact.

## Roles
- **Controller:** the customer (industrial company deploying SIA for its staff).
- **Processor:** the SIA operator running/maintaining the dedicated instance.
- **Sub-processors:** see table at the bottom.

## Processing activities

### PA-1 — Supervisor/operator account management
- **Purpose:** authentication, role-based access, shift assignment.
- **Categories of data subjects:** employees (supervisors, production managers, superadmins).
- **Personal data:** name, email, phone, role, factory assignment, FCM token, auth UID.
- **Lawful basis:** legitimate interest / performance of employment-related duties (controller determines).
- **Retention:** for account lifetime + per `data_retention_privacy_policy.md`; deleted on offboarding.
- **Location:** customer's Firebase project region.

### PA-2 — Alert lifecycle & coordination
- **Purpose:** dispatch, claim, resolve, escalate, collaborate on factory alerts.
- **Data subjects:** employees handling alerts.
- **Personal data:** UID/name on assignment/claim/resolution, comments authored, timestamps.
- **Lawful basis:** legitimate interest (operational safety/efficiency).
- **Retention:** operational; archival/anonymization per retention policy.

### PA-3 — Location tracking (supervisors)
- **Purpose:** proximity-based AI assignment and locator routing.
- **Data subjects:** supervisors with tracking enabled.
- **Personal data:** GPS coordinates (`users/{uid}/currentLocation`), timestamps.
- **Lawful basis:** legitimate interest; **requires worker notice/consent per local law** — controller responsibility. Sensitive; minimize and time-box.
- **Retention:** last-known only; not retained as a history trail by default.

### PA-4 — Voice claim & speaker verification
- **Purpose:** hands-free alert claim with anti-spoofing.
- **Personal data:** voiceprint embedding (`users/{uid}/voiceprint`), short audio at capture.
- **Special category risk:** biometric data → **explicit consent / DPIA required** (see `DPIA.md`).
- **Retention:** embedding stored until enrollment is removed; raw audio not persisted server-side.

### PA-5 — Telemetry-driven alerts (SCADA ingestion)
- **Purpose:** create alerts from machine telemetry.
- **Personal data:** generally none (machine/line/metric); incidental only.
- **Lawful basis:** legitimate interest. Source: `docs/integrations/SCADA_INTEGRATION.md`.

### PA-6 — Operational logging & security
- **Purpose:** reliability, abuse prevention, audit.
- **Personal data:** UIDs in `ai_decisions`; hashed fingerprints in `security/*`; dedup-hashed client errors in `bugs/client` (scrubbed).
- **Retention:** in-memory app logs are ephemeral; security/health retained per policy.

## Data subject rights
DSAR (access, rectification, erasure, portability) handled per
`docs/policies/data_retention_privacy_policy.md`. Erasure removes the user record,
voiceprint, location, and de-identifies authored content where feasible.

## International transfers
Determined by the customer's chosen Firebase/Cloudflare regions. SCCs apply where a
sub-processor transfers data outside the controller's jurisdiction (controller to assess).

## Sub-processors

| Sub-processor | Function | Data exposed | Safeguard |
|---|---|---|---|
| Google Firebase | Auth, RTDB, FCM | account, alert, token data | DPA + region selection |
| Cloudflare | Workers/edge compute | request data in transit, fingerprints | DPA |
| Model provider(s) (configurable, optional) | AI assist/Guardian | operational prompt text (no secrets) | DPA; disable-able per agent |
| GitHub (Guardian, optional) | CI/self-healing | source/CI metadata | customer-supplied token, server-side vault |

Customers must execute a DPA with the SIA operator (`DPA_TEMPLATE.md`) and confirm
sub-processor DPAs for their region.
