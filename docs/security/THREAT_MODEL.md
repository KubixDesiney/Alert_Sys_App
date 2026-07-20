# SIAS - Smart Industrial Alert System — Threat Model

Status: living document. Last reviewed 2026-06-16. Owner: Security Lead.
Methodology: STRIDE per trust boundary, scored with a lightweight DREAD-style
likelihood × impact rating (Low / Medium / High). This model is reviewed on every
change-management cycle (see `docs/policies/change_management_policy.md`) and before
each release (see `RELEASE.md`).

## 1. System overview & trust boundaries

SIAS is a dedicated-instance product: each customer runs their own Firebase project
and provisions their own Cloudflare Worker secrets through the SuperAdmin console.
There is no shared multi-tenant data plane, which bounds the blast radius of any
single compromise to one customer instance.

```
[ Mobile / Web client (Flutter) ]
        |  Firebase Auth (ID token)        TRUST BOUNDARY 1 (client ↔ Firebase)
        v
[ Firebase Realtime Database ]  <----+    enforced by database.rules.json
        ^                            |
        |  service-account JWT       |    TRUST BOUNDARY 2 (worker ↔ Firebase)
        |                            |
[ Cloudflare Workers ]---------------+
   - alert-notifier (AI/security)         TRUST BOUNDARY 3 (internet ↔ worker)
   - alertsys (notifications)             guarded by _securityGuard + shared secret
   - alertsys-github (GitHub proxy)
        |  OAuth / FCM / GitHub token      TRUST BOUNDARY 4 (worker ↔ 3rd party)
        v
[ FCM ]  [ GitHub API ]  [ optional model providers ]
```

Assets in priority order: (1) customer alert/operational data in RTDB, (2) Firebase
service-account credentials, (3) GitHub repo write access via the Guardian pipeline,
(4) model-provider API keys, (5) supervisor PII (name, email, phone, GPS).

## 2. STRIDE analysis

### Boundary 1 — Client ↔ Firebase

| STRIDE | Threat | Likelihood × Impact | Mitigation |
|---|---|---|---|
| Spoofing | Forged user identity / stolen session | M × H | Firebase Auth ID tokens; no anonymous writes except the constrained alert-create shape; role read from `users/{uid}/role` server-side in rules. |
| Tampering | Client writes outside its scope (e.g. another user's claim) | M × H | `database.rules.json` scopes writes to self/admin; claim exclusivity via RTDB transactions; `worker_test/database_rules_security.test.js` asserts `security/*` and `workers/*` are closed to plain `admin`. |
| Repudiation | User denies an action | L × M | `ai_decisions`, `security/logs`, `bugs/client`, and alert lifecycle timestamps form an append-only-ish audit trail. |
| Info disclosure | Reading data above role | M × H | Field-level rules; superadmin-only `security/*`, `workers/*`; PII limited to authenticated factory scope. |
| DoS | Client floods alert creation | M × M | Worker anomaly scan flags alert flood (>40/min); rate limits on worker endpoints; RTDB quota alarms. |
| Elevation | Escalate to superadmin via client write | L × H | Rules reject role self-escalation; role grant only via secondary-app provisioning (`superadmin_service.dart`). |

### Boundary 2 — Worker ↔ Firebase

| STRIDE | Threat | L × I | Mitigation |
|---|---|---|---|
| Spoofing | Stolen service-account JSON used elsewhere | L × H | Secret stored per-instance in Cloudflare secrets, never in client/repo; rotation runbook in `docs/SECRET_ROTATION.md`; dedicated-instance model contains blast radius. |
| Tampering | Malicious model output writes bad assignments | L × M | Worker validates/clamps scores; assignment writes are bounded fields; predictions graded against reality (`validatePredictions`). |
| Info disclosure | Over-broad RTDB read by worker | L × M | Workers read only required roots via `loadCoreData`; least-privilege parsing. |

### Boundary 3 — Internet ↔ Worker

| STRIDE | Threat | L × I | Mitigation |
|---|---|---|---|
| Spoofing | Unauthorized caller hits protected endpoints | M × H | Optional `WORKER_SHARED_SECRET` on protected routes; fingerprint = CF IP + SHA-256(UA). |
| Tampering | Prompt injection via alert text / feedback | M × M | `_securityDetectPromptInjection` 10-pattern bank; input sanitization; 8 KB prompt clamp. |
| Repudiation | Attacker hides their requests | L × M | `security/actions` + `security/logs` fire-and-forget audit with fingerprint + endpoint. |
| Info disclosure | Error messages leak secrets/URLs | L × M | Patterns block `firebase_url` / `cloudflare_token` exfil attempts; generic error responses. |
| DoS | Endpoint flooding | M × M | Per-endpoint sliding-window rate limits; 64 KB body cap; soft fingerprint eviction at 5000. |
| Elevation | Reach admin-only data via worker | L × H | `/security-status` admin-only; worker enforces guard before handler. |

### Boundary 4 — Worker ↔ third parties (FCM, GitHub, model providers)

| STRIDE | Threat | L × I | Mitigation |
|---|---|---|---|
| Spoofing | Forged GitHub webhook / response | L × M | GitHub proxy reads token server-side from the RTDB vault; HMAC `timingSafeEqual` on shared secret. |
| Tampering | Guardian deploys a malicious patch | L × H | Two-AI gate (fix provider → independent review provider) + `flutter analyze`/tests before any push; "human review required" mode opens a PR instead of pushing to `main`. |
| Info disclosure | Model provider logs sensitive prompts | M × M | Provider keys per-instance; prompts carry operational text only, no secrets; provider is configurable/disable-able per agent. |
| Elevation | Leaked GitHub token grants repo write | L × H | Fine-grained PAT (least scope) recommended in `docs/security/ASVS_CHECKLIST.md`; token stored superadmin-only in `ai_agent_secrets`. |

### Boundary 5 — Internet ↔ Store worker (`sias-store`) & n8n webhooks

The storefront is deliberately **outside the product data plane**: it holds no
customer instance credentials and cannot reach any customer Firebase project.

| STRIDE | Threat | L × I | Mitigation |
|---|---|---|---|
| Spoofing | Forged Stripe webhook triggers provisioning | M × H | HMAC signature verification (`verifyStripeSignature`, constant-time compare, 5-min timestamp tolerance); unsigned events rejected 400. |
| Spoofing | Replayed ClicToPay return URL double-provisions | M × M | Server-side `getOrderStatusExtended.do` re-verification per hit; n8n dedupes on `eventId` (`ctp_<orderId>`). |
| Tampering | XSS via chat replies or intake fields | M × H | Escape-first markdown renderer on /copilot; strict CSP (nonce'd scripts, no `unsafe-inline` script-src); all intake clipped + validated server-side. |
| Info disclosure | n8n webhook URLs / bearer leak to the browser | L × M | `N8N_*` URLs are worker secrets; the browser only ever talks to `/api/kubix*` and `/api/quote` same-origin proxies. |
| Info disclosure | Quote/checkout intake PII exposure | L × M | No storefront datastore — intake rides Stripe metadata / n8n payloads only; `quotes/` output dir git-ignored; security.txt published for reports. |
| DoS | Checkout/chat/feedback flooding | M × L | Per-IP sliding-window rate limits on `/api/checkout`, `/api/quote`, `/api/kubix` (20/min), `/api/kubix-feedback` (20/min); Stripe/n8n are the real backstops. |
| Elevation | Legal drafts published prematurely | L × M | `/legal` routes hard-404 unless `LEGAL_PUBLISH="true"`; `npm run legal:lint` blocks forbidden claims from ever entering the drafts. |

### Boundary 6 — Plant estate ↔ Ingest worker & edge gateway

| STRIDE | Threat | L × I | Mitigation |
|---|---|---|---|
| Spoofing | Forged telemetry creates fake alerts | M × M | Per-connector ingest key (`x-alertsys-ingest`, constant-time compare); disabled connectors rejected 403; unknown connectors 404. |
| Tampering | Malicious payload shapes poison alert data | M × M | `normalizeTelemetry` sanitizes/clips every field, drops rows without location context; alert-shape validation before RTDB write. |
| Info disclosure | Connector credentials replayed to attacker hosts | L × H | Credential host-binding (`credentialsAllowedForUrl`) — secrets only travel to the connector's registered host. |
| DoS | Telemetry flood | M × M | Per-connector rate limit, 100-item batch cap, body-size cap, dedup window drops repeats. |
| Elevation | Gateway host compromise pivots to SIAS | L × M | Gateway is push-only with a single scoped ingest key; it holds no Firebase credentials; SIAS never opens connections into the plant (edge-push model). |

## 3. Top residual risks & decisions

1. **Historical leaked dev credential (accepted).** A development Firebase key was
   committed historically. Decision (owner-accepted): not rotated for the reference
   instance because every paying customer provisions their own DB + secrets via the
   SuperAdmin console, so the leak never reaches customer instances. Do **not** store
   sensitive data on the reference/demo instance. Rotation procedure remains documented
   in `docs/SECRET_ROTATION.md` and `tool/purge_leaked_secret.sh` should the policy change.
2. **Guardian auto-deploy.** Mitigated by the dual-AI review gate + test gate; default
   to "human review required" (PR) for any customer-facing instance.
3. **Supply chain.** Mitigated by Dependabot, gitleaks (current-tree blocking), CodeQL
   SAST, and least-privilege workflow `permissions:` blocks.

## 4. Re-evaluation triggers

Re-run this model when: a new external endpoint is added, a new trust boundary appears,
a new data class is stored, the auth model changes, or a dependency with a known CVE is
introduced. Pair every change with the ASVS checklist (`docs/security/ASVS_CHECKLIST.md`).
