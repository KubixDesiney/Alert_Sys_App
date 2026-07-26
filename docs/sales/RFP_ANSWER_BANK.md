# RFP / Security Questionnaire Answer Bank

Honest canned answers for the questions industrial buyers actually ask.
Copy verbatim or adapt tone; **never** upgrade a "roadmap" to a "yes".
Anything marked *(confirm with engineering)* needs a check before it goes in a
binding document. Companion docs: `SECURITY_OVERVIEW_ONEPAGER.md`,
`docs/SECURITY_WHITEPAPER.md`, `docs/compliance/VENDOR_SECURITY_QUESTIONNAIRE.md`.

## Company & product

1. **Who is the vendor?** KubixDesiney, an industrial software company based in
   Tunisia, building SIAS — Smart Industrial Alert System, a supervisory alert
   and operations platform for factories.
2. **What does SIAS do?** Real-time factory alert intake, AI-assisted dispatch
   to human supervisors, mobile apps with voice claiming, shift coordination,
   and on-device failure forecasting. It sits on top of the existing
   automation estate and never executes control loops.
3. **Is SIAS a safety system?** No. SIAS is an advisory coordination layer. It
   does not replace certified safety systems, alarms, or emergency procedures,
   and our agreements say so explicitly.
4. **Customer references?** We are in the controlled-pilot stage. The one
   citable production metric today: an export/reporting workflow that took
   ~30 minutes of manual collation now takes ~1–2 minutes, with 100% of
   actions logged (AMEC Export). We propose measured pilots over slideware.

## Hosting, architecture & data residency

5. **Where is the service hosted?** On Google Firebase (database,
   authentication, push) and Cloudflare (edge compute, object storage). Each
   customer runs a dedicated instance in its own Firebase project and
   Cloudflare worker set.
6. **Is it multi-tenant?** No shared data plane. One customer = one isolated
   instance (own database, own auth realm, own edge services).
7. **Can we choose the data region?** The database region is selected at
   provisioning (e.g. `europe-west1`). Cloudflare compute is edge-global;
   data at rest lives in the selected Firebase region and the backup bucket.
   Custom residency arrangements are an Enterprise conversation.
8. **On-premise option?** Yes — an on-prem deployment (local database, local
   workers, edge gateway) exists for air-gapped estates. Feature parity is
   narrower than cloud; scope it with engineering. *(confirm with engineering
   for your specific feature list)*
9. **Do you access our production data?** KubixDesiney operates the
   infrastructure (updates, backups, monitoring). Operational data belongs to
   the customer, is exportable at any time, and is handled per the DPA.

## Identity & access

10. **SSO?** Firebase Authentication is the identity layer; MFA is supported.
    SCIM 2.0 provisioning (Okta, Microsoft Entra) automates joiner/leaver
    sync on Enterprise. SAML federation: *(confirm with engineering)*.
11. **RBAC?** Three product roles (Owner/SuperAdmin, Production Manager,
    Supervisor) with authorization enforced server-side in database security
    rules — including no self-escalation and factory-scoped access.
12. **Least privilege for your staff?** Access to a customer instance is
    limited to the operations needed to run it, using per-instance
    credentials; customer admins control their own user base entirely.
13. **Password policy?** Passwords are never transmitted by us — account
    activation uses a single-use, short-lived link and the user sets their
    own password + MFA. Password rules follow Firebase Auth policy.

## Data protection

14. **Encryption in transit?** TLS 1.2+ on every hop; HSTS on web surfaces.
15. **Encryption at rest?** Yes — platform-managed (Firebase, Cloudflare R2),
    AES-256 class.
16. **What personal data is processed?** Employee names, work emails/phones,
    supervisor GPS while on shift, voice-print embeddings for voice
    authentication, operational alert history. Detailed records: the ROPA in
    `docs/compliance/ROPA.md`.
17. **Is PII segregated?** Yes — contact PII and location live in an
    access-scoped node readable only by the user themselves and admin roles;
    coworkers cannot enumerate it.
18. **GDPR posture?** Customer = controller, KubixDesiney = processor; DPA
    with sub-processor commitments (drafted, counsel review pending — shared
    on request). DPIA and ROPA templates are prepared.
19. **Sub-processors?** Google (Firebase), Cloudflare, Supabase, Brevo
    (email), n8n (workflow automation), plus the customer-configurable AI
    model provider.
20. **Data deletion on termination?** Instance teardown removes the compute;
    database/backup deletion follows the DPA's retention terms and is
    executed deliberately (documented, not automatic).

## AI

21. **What AI runs in the product?** Assignment scoring, shift automation,
    briefings, suggestion generation (via a configurable LLM provider), and a
    pure on-device gradient-boosted failure forecaster (no external ML
    service).
22. **What data reaches the AI provider?** Operational prompt text only
    (alert descriptions, shift context) — never credentials or bulk data. The
    provider is configurable per instance; every agent has an off switch.
23. **Are AI decisions explainable?** Yes — every assignment records its
    reason and confidence, visible in the console; the forecaster grades its
    own accuracy daily against realized alerts.
24. **Does AI act on machines?** Never. AI routes people; it has no path to
    control systems.

## Integrations & OT security

25. **How do you connect to our SCADA/PLCs?** Cloud-pull (REST, PI, Ignition)
    or edge-push via the packaged gateway (OPC-UA, Modbus TCP, Siemens S7,
    MQTT incl. Sparkplug B). The gateway is push-only, read-only toward the
    plant, and holds a single scoped ingest key.
26. **Inbound connections to our network?** None. The gateway makes one
    outbound HTTPS connection to your instance; SIAS never connects into the
    plant.
27. **What happens on network loss?** The gateway queues readings on disk
    (bounded) and retries with backoff; mobile apps are offline-aware with
    durable sync.
28. **Can telemetry be spoofed?** Ingest requires a per-connector key
    (constant-time compared); payloads are sanitized and rate-limited;
    connector credentials are host-bound so they cannot be replayed
    elsewhere.

## Reliability & support

29. **Uptime commitment?** 99.9% SLA with service credits on Enterprise;
    Starter/Growth get the support response targets without the credit
    scheme. Architecture is serverless edge + managed database (no single VM
    to die).
30. **Backups?** Daily automated encrypted snapshots to object storage,
    30 kept, restore tooling + documented DR runbook, plus an automated
    "backups are actually happening" drill.
31. **RPO/RTO?** Design targets: RPO ≤ 24h (daily snapshots), RTO measured in
    hours via documented restore. *(confirm with engineering before binding
    numbers in an MSA)*
32. **Monitoring?** Synthetic probes + SLO/error-budget alerting run per
    instance; customers see live status and worker health in their own
    console.
33. **Incident response?** Documented IR plan (`docs/policies/`), security
    contact via RFC 9116 security.txt, customer notification obligations per
    the DPA.
34. **Support tiers?** Email support (Starter), priority support (Growth),
    dedicated onboarding engineer + SLA (Enterprise). Kubix Copilot gives
    24/7 first-line answers with human escalation.

## Development & supply chain

35. **SDLC controls?** Protected main branch, CI with full test suites
    (worker + app), secret scanning (blocking), dependency audits, CodeQL
    SAST, CycloneDX SBOM per run.
36. **Do you pentest?** An independent buyer-driven security scan (July 2026)
    was remediated (15/16 fixed, 1 documented-accepted). A formal external
    pentest is scoped; the report will be shared with Enterprise customers
    under NDA when complete.
37. **SBOM available?** Yes — CycloneDX, generated in CI, on request.
38. **Vulnerability disclosure?** security.txt + SECURITY.md process; reports
    triaged by a human.
39. **The self-healing pipeline sounds risky — who approves changes?** Every
    automated fix passes an independent AI review plus the full test suite;
    customer-facing instances default to human-approved pull requests. The
    automation can be disabled entirely per instance.

## Certifications & legal

40. **SOC 2 / ISO 27001?** Not certified today — both are roadmap items
    (SOC 2 engagement pack prepared). We say this plainly in every document.
41. **Insurance (cyber/E&O)?** *(confirm with management — jurisdiction
    dependent)*
42. **Contract stack?** MSA + DPA + SLA (Enterprise) + EULA + Privacy Policy —
    drafted, under counsel review; signature-ready versions follow counsel
    sign-off.
43. **Escrow / continuity?** Customer data is exportable at any time; on-prem
    deployment reduces vendor-dependency risk. Source escrow: an Enterprise
    negotiation point.
44. **Billing terms?** Invoice-led: bank transfer in USD/TND/EUR, net-15
    (drafted). Card rails (Stripe / ClicToPay) exist and can be enabled for
    self-serve.
