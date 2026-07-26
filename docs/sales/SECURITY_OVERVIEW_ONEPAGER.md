# SIAS Security Overview — One Pager

**SIAS — Smart Industrial Alert System · KubixDesiney** · condensed from
`docs/SECURITY_WHITEPAPER.md` (full detail there). Updated 2026-07-20.

**The honest headline first:** SIAS is not SOC 2 / ISO 27001 certified — both
are roadmap items. Everything below exists in the product today and is
verifiable in code and in your own instance.

## Isolation: one customer, one instance

Every customer gets a **dedicated instance**: their own Firebase project
(database + auth realm) and their own set of Cloudflare edge services. No
shared multi-tenant database — cross-customer exposure is prevented by
construction. The storefront/pre-sales chat runs on separate infrastructure
holding **zero** customer-instance credentials. An on-prem option exists for
air-gapped estates.

## Authentication & authorization

- Firebase Authentication with **MFA**; **SCIM 2.0** (Okta/Entra) on Enterprise.
- Authorization enforced **server-side in database security rules**, not app
  code: no role self-escalation, factory-scoped supervisor access, PII
  structurally separated, credential vaults unreadable by any client.
  Regression-tested, including adversarial attacker cases.
- Service-to-service: Firebase ID-token verification on the workers
  (**enforcement: required**), constant-time shared-secret worker-to-worker
  triggers, HMAC-verified Stripe webhooks, per-connector ingest keys with
  credential host-binding for plant telemetry.

## What leaves your instance

1. Push notifications → Firebase Cloud Messaging (platform push channel).
2. AI features → operational prompt text only to the configured model
   provider; every agent has an off switch; the failure forecaster is fully
   on-device (no external ML service).
3. Kubix Copilot chat → only the chat text + tenant/company context.
4. Daily encrypted backups → object storage in the instance's own account.

Nothing else. No credentials, no user directory, no bulk data.

## Encryption, backups, retention

- TLS 1.2+ in transit everywhere; HSTS on web surfaces.
- Platform-managed AES-256-class encryption at rest (Firebase, R2).
- **Daily automated snapshots** with restore tooling + a documented DR
  runbook; a verification drill (`backup drill`) checks snapshots are fresh.
- Alert retention: configurable (default 365 days), archive-then-prune.

## Application & supply-chain controls

- Edge security agent: rate limits, prompt-injection detection, input
  sanitization, anomaly scans, append-only audit trail in your console.
- Storefront: strict CSP (nonce-based scripts), HSTS, frame-deny,
  escape-first rendering; RFC 9116 `security.txt` published.
- CI: secret scanning (blocking), dependency audit, CodeQL SAST, **CycloneDX
  SBOM on every run** (available on request).
- Self-healing pipeline changes pass a dual-AI review + full test suite;
  customer instances default to human-approved PRs.

## Assurance status (no inflation)

| Item | Status |
|---|---|
| Independent buyer-driven security scan | Done (July 2026) — 15/16 remediated, 1 documented-accepted; log shareable under NDA |
| STRIDE threat model | Published (`docs/security/THREAT_MODEL.md`) |
| External penetration test | Scoped, vendor selection pending; report to Enterprise customers under NDA |
| SOC 2 Type II | Roadmap — kickoff pack prepared |
| ISO 27001 | Roadmap — after SOC 2 |

**Sub-processors:** Google (Firebase), Cloudflare, Supabase, Brevo, n8n, and
the configurable AI model provider. Governed by the DPA.

**Report a vulnerability:** `/.well-known/security.txt` on the storefront —
a human answers.
