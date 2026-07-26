# SIAS Security Whitepaper

**SIAS — Smart Industrial Alert System · KubixDesiney**
Buyer-facing technical security overview. Last updated: 2026-07-20.

> **Honesty note up front:** SIAS is not SOC 2 or ISO 27001 certified. Both are
> roadmap items (SOC 2 Type II engagement material is prepared in
> `docs/external/SOC2_KICKOFF.md`). Everything below describes controls that
> exist in the product today, verifiable in the codebase and in your own
> instance — we would rather you audit us than take our word for it.

---

## 1. Architecture and isolation model

SIAS is delivered as a **dedicated instance per customer**. When you buy, we
provision for your company:

- A dedicated **Google Firebase project**: Realtime Database (operational
  data) and Firebase Authentication (your users, your auth realm).
- A dedicated set of **Cloudflare Workers** (edge services): AI dispatch +
  security agent, push notification fan-out, industrial ingestion, SCIM
  provisioning, synthetic monitoring, daily backups, and a GitHub proxy for
  the self-healing pipeline.
- Dedicated **mobile/web app builds** pointed only at your instance.

There is **no shared multi-tenant database**. Cross-customer data exposure is
prevented by construction, not by row-level filters: another customer's
credentials simply do not exist in your project. The commercial storefront
(pricing, quotes, the pre-sales Kubix chat) runs on separate infrastructure
that holds **no customer instance credentials** and cannot reach any
customer's Firebase project.

An **on-premise deployment option** exists for air-gapped estates (PocketBase
+ worker-runner + edge gateway; see `ONPREM.md`).

## 2. Authentication and authorization

### Human roles (per instance)

| Role | Surface | Authority |
|---|---|---|
| SuperAdmin (Owner) | Command console | Platform config, alert-type registry, ML training, account provisioning, hardware lab, security telemetry, connectors |
| Production Manager (`admin`) | Admin dashboard | Alerts, hierarchy, shifts, supervisors, collaborations, escalation policy |
| Supervisor | Mobile-first dashboard | Claim/resolve/escalate own-factory alerts, collaboration, voice actions |

- Sign-in is Firebase Authentication; **MFA** is supported, and **SCIM 2.0**
  (Okta, Microsoft Entra) automates joiner/leaver sync on Enterprise.
- Authorization is enforced **server-side in Firebase security rules** — not
  in app code. Highlights (all regression-tested in
  `worker_test/database_rules_security.test.js`, including adversarial cases):
  - Users cannot change their own role or factory assignment (no
    self-escalation path).
  - Supervisors can only claim alerts in their own factory and can never
    delete an alert.
  - PII (email, phone, GPS) is structurally separated into an access-scoped
    node (`users_private`) that other supervisors cannot read.
  - Credential vaults (connector secrets, AI provider keys, GitHub token) are
    readable by **no** client principal — the edge services read them via
    OAuth service credentials.

### Service-to-service

| Caller → Callee | Mechanism |
|---|---|
| Apps → AI/notify workers | Firebase **ID token** verified against Google JWKS (enforcement mode: `required`) |
| Worker → worker triggers | Shared-secret header, constant-time comparison |
| Workers → Firebase | Service-account JWT minted at the edge; secrets held in Cloudflare, never in clients or the repository |
| Plant gateway → ingest worker | Per-connector ingest key; credential host-binding stops replays to foreign hosts |
| Stripe → storefront | HMAC-verified webhook signatures (timestamped, constant-time) |

## 3. Data flows — what leaves your instance

Your operational data stays in your Firebase project and your Cloudflare
account. The complete list of what crosses that boundary:

1. **Push notifications** → Firebase Cloud Messaging (delivery metadata +
   alert title/body to Google, the platform push channel).
2. **AI features** → the configured model provider receives operational
   prompt text only (alert descriptions, shift context) — never credentials,
   never your database. Every AI agent has an off switch in your console, and
   the failure forecaster is **pure on-device Dart** (trains and infers inside
   your instance; no external ML service).
3. **Kubix Copilot chat** → the chat text you type (plus your tenant code and
   company name for context) is forwarded to the agent runtime to generate a
   reply. Nothing else — no alert data, no user directory, no credentials.
4. **Daily backups** → encrypted snapshots to Cloudflare R2 in your instance's
   account (that's a copy, not a departure).

## 4. Encryption

- **In transit:** TLS 1.2+ everywhere (Cloudflare edge, Firebase, FCM); HSTS
  on web surfaces.
- **At rest:** Google Firebase and Cloudflare R2 encrypt all stored data at
  rest (AES-256 class, managed by the platforms).
- **Secrets:** Cloudflare Worker secrets (encrypted at rest, never readable
  back via API); in-product credential vaults are client-unreadable by rule.

## 5. Backups, retention, disaster recovery

- **Daily automated snapshots** of the full database to R2 object storage
  (02:00 UTC), with restore tooling (`tool/restore_rtdb.mjs`) and a documented
  recovery runbook (`DISASTER_RECOVERY.md`).
- **Alert retention policy:** terminal alerts older than a configurable window
  (default 365 days) are archived to object storage and pruned from the live
  database — bounded live data, unbounded auditable history.
- You can export your data at any time; on termination, data handling follows
  the DPA.

## 6. Application security controls

- **Edge security agent** on the AI worker: per-endpoint rate limits,
  prompt-injection detection, input sanitization, anomaly scans, and an
  append-only security audit trail (`security/logs`, `security/actions`)
  visible in your SuperAdmin console.
- **Storefront hardening:** strict Content-Security-Policy (nonce-based
  scripts, no inline handlers), HSTS, X-Frame-Options DENY, escape-first
  rendering of all user/AI-generated text.
- **Supply chain CI:** secret scanning (gitleaks, blocking on current tree),
  dependency audit (`npm audit`, high severity blocking), CodeQL SAST, and a
  CycloneDX **SBOM** generated on every run (`.github/workflows/security.yml`)
  — the SBOM artifact is available to customers on request.
- **Self-healing pipeline (Guardian):** any automated fix passes a dual-AI
  review gate plus the full test suite; customer-facing instances default to
  human-approved pull requests, never direct deploys.

## 7. Vulnerability handling

- **Reporting:** `/.well-known/security.txt` (RFC 9116) is published on the
  storefront; `SECURITY.md` in the repository describes the disclosure
  process. Reports are acknowledged and triaged by a human.
- **Independent review:** an external buyer-driven security scan (July 2026)
  was fully triaged; 15/16 findings remediated, 1 documented-accepted — the
  remediation log is `SECURITY_REMEDIATION_2026-07-09.md` and we share it
  under NDA.
- A full **penetration-test RFP scope** is prepared
  (`docs/PENTEST_SCOPE.md`); the first external pentest report will be shared
  with Enterprise customers under NDA when complete.

## 8. Sub-processors

| Sub-processor | Purpose |
|---|---|
| Google (Firebase) | Database, authentication, push delivery |
| Cloudflare | Edge compute, object storage (backups), network security |
| Supabase | Ancillary storage services |
| Brevo | Transactional email (activation, notifications) |
| n8n | Onboarding/support workflow automation (Kubix runtime) |
| AI model provider (configurable) | AI feature inference — operational text only |

The DPA (`docs/legal/DPA.md`, counsel review pending) governs sub-processor
commitments, notice of changes, and GDPR processor obligations.

## 9. Roadmap (stated as roadmap, not as claims)

- SOC 2 Type II audit engagement (kickoff pack prepared).
- ISO 27001 alignment following SOC 2.
- External penetration test (scope prepared, vendor selection pending).

## 10. Verify us

The fastest due-diligence path: ask for a demo instance and read the code.
The security rules, worker auth enforcement, CSP, webhook verification, and
every control named above are in the repository and covered by automated
tests that run on every commit. STRIDE analysis: `docs/security/THREAT_MODEL.md`.
Questions → the contact in `/.well-known/security.txt`.
