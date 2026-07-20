# Counsel Brief — SIAS Legal Pack Review

One page for the reviewing lawyer. The five documents in this folder (`MSA.md`,
`DPA.md`, `SLA.md`, `EULA.md`, `PRIVACY.md`) are **DRAFT v1, written in-house,
never published, never signed**. Nothing goes live until you sign off; the
website routes that would serve them are hard-gated off in code.

## What the product is

**SIAS — Smart Industrial Alert System**, operated by **KubixDesiney**
(Tunisia), is a B2B SaaS platform for industrial factory alert supervision:
real-time alerts from plant equipment (SCADA/PLC/sensors), AI-assisted dispatch
to human supervisors, mobile apps with voice claiming, and failure forecasting.
It is an **advisory coordination layer** — it never controls machinery and is
explicitly positioned as not replacing certified safety systems (see `SLA.md`
"Positioning" and `EULA.md` §6). That safety disclaimer is the single most
important clause in the pack.

## Deployment and data model (relevant to the DPA)

- Every customer gets a **dedicated, isolated instance**: their own Google
  Firebase project (database + authentication) and their own set of Cloudflare
  edge services. No shared multi-tenant data store.
- KubixDesiney operates the infrastructure (updates, backups, monitoring); the
  customer administers their own users and data. In GDPR terms we drafted
  customer = controller, KubixDesiney = processor.
- Sub-processors as drafted: Google (Firebase), Cloudflare (edge/compute/
  storage), Supabase (ancillary storage), Brevo (transactional email),
  n8n (workflow automation for onboarding/support chat).
- Personal data in the product is limited: employee names, work emails/phones,
  GPS location of supervisors while on shift (a point to confirm is handled
  correctly for employee-monitoring rules), voice-print embeddings for voice
  authentication (biometric-adjacent — flag if this needs explicit treatment),
  and operational alert history.
- Daily encrypted backups to Cloudflare R2; alert retention default 365 days,
  customer-controllable.

## Commercial motion

- Seller: KubixDesiney, Tunisia. Buyers: international B2B (EU, MENA, beyond).
- Current sales motion is **invoice-led**: buyer requests a quote on the
  website, we invoice (bank transfer, USD/TND/EUR, net-15 drafted). Card
  checkout rails (Stripe international; ClicToPay/SMT for Tunisian cards) exist
  in code but are parked; they may be re-enabled later.
- Plans: Starter / Growth (self-serve pricing), Enterprise (custom, with SLA).
- A 30-day money-back clause on the first payment is drafted in `MSA.md` §…
  ("Money-back guarantee") — confirm enforceability/wording.

## What we deliberately did NOT claim

No SOC 2 / ISO 27001 certification is claimed anywhere (both are roadmap
items). A repo linter (`npm run legal:lint`) mechanically blocks any such claim
from entering these documents, enforces naming consistency, and lists the
placeholders below.

## Decisions we need from you ([[PLACEHOLDER]] markers in the drafts)

1. **Governing law + venue** — Tunisian seller, international buyers. Your
   recommendation (Tunisian law? English law? Swiss?) and dispute forum
   (courts vs. arbitration; if arbitration: institution, seat, language) —
   `MSA.md`, `EULA.md`.
2. **Company registration block** — legal form, registration number,
   registered address for KubixDesiney — `MSA.md` header.
3. **GDPR representation** — whether KubixDesiney (non-EU processor serving EU
   controllers) needs an Article 27 EU representative, and SCCs/transfer
   mechanics for the DPA — `DPA.md`.
4. **Notice/cure periods** — renewal notice, breach cure period, SLA claim
   window, maintenance notice — `MSA.md`, `SLA.md`.
5. **Currency and Tunisian specifics** — invoicing currency clause, TN
   export/foreign-currency invoice constraints, local consumer/B2B mandatory
   provisions — `MSA.md`.
6. **Legal contact email** — the address to publish for legal notices —
   `MSA.md`, `EULA.md`.
7. **Audit clause economics** — who pays for controller audits under the DPA
   and on what notice — `DPA.md`.

## Questions beyond the placeholders

- Is the liability cap structure (12-month fees, standard carve-outs) right
  for an industrial-adjacent product, given the safety disclaimer?
- Does supervisor GPS tracking + voice-print verification trigger
  employee-consent or works-council style obligations we should push onto the
  customer as controller obligations in the DPA?
- Anything about the AI features (assignment decisions about employees,
  logged with reasons) that needs a dedicated clause under EU AI Act
  timelines?

## Logistics

Redlines directly on the markdown files are ideal (or any format — we will
transcribe). When you sign off, publication is a one-variable flip on the
website; the documents themselves remain versioned in this repository.
