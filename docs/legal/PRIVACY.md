> **DRAFT v1 — requires review by qualified counsel before use.**

# Privacy Policy

**SIAS — Smart Industrial Alert System**, operated by KubixDesiney ("we",
"us", "KubixDesiney")

This policy covers two things: (1) the **storefront** at KubixDesiney's
marketing site, including the Kubix Copilot pre-sales chat, and (2) the
**product** — the dedicated SIAS instance a Customer organization uses day to
day. It explains what we collect, why, and how it is protected in each case.

SIAS is delivered as a **dedicated instance per customer**: each customer's
product data lives in that customer's own Firebase project and is served by
Cloudflare Workers deployed for that customer specifically. There is no
shared, cross-customer product data store. In most product deployments the
Customer organization is the **data controller** and KubixDesiney acts as a
**data processor** on the Customer's instructions — see the Data Processing
Addendum (`DPA.md`).

---

## 1. Storefront: what we collect when you visit or buy

When you visit KubixDesiney's marketing site, or purchase a plan:

- **Purchase/contact information** — the name, work email, company name, and
  billing details you provide when requesting a plan or completing a
  purchase. Payment card details are handled directly by our payment
  processor and are not stored on KubixDesiney's own systems.
- **Kubix Copilot pre-sales chat** — if you chat with Kubix before or during
  a purchase (for example from the `/copilot` page), we process your
  messages, an anonymous session identifier, and any tenant/company/plan
  context in the page URL, in order to generate a reply and, where the
  conversation is escalated, to route it to a human for follow-up by email.
- **Basic site analytics** — standard web request metadata (e.g. page
  requested, timestamp) via our hosting/edge provider, used to operate and
  secure the site.

We use this information to respond to your inquiry, provision your
instance, process payment, and — where you've agreed to be contacted — to
follow up about your evaluation or purchase. We do not sell this
information.

## 2. Product: what SIAS stores about your organization's users

Once an instance is provisioned, the following categories of data may be
processed on behalf of the Customer organization (as controller):

- **Account and identity** — first/last name, email, phone, role (supervisor,
  admin/Production Manager, superadmin), and factory assignment.
- **Authentication** — Firebase Authentication identifiers and, where
  enabled, MFA/SSO metadata. We do not store account passwords ourselves;
  authentication is handled by the identity provider, and Owner accounts are
  activated via a single-use link rather than an emailed password.
- **Operational records** — alerts, claims, resolutions, escalations,
  collaboration and shift records, and related comments.
- **Device and messaging** — push notification tokens.
- **Optional GPS presence** — a supervisor's device location, collected
  **only** where the Customer enables location features, used for
  proximity-based assignment and the in-app plant locator. This data is
  **role-scoped**: it is readable only by the supervisor themselves and by
  administrative roles, not broadly across the organization.
- **Optional voiceprints** — where the Customer enables voice claim and a
  supervisor enrolls, a voiceprint embedding used for **on-device** speaker
  verification (confirming it is really that supervisor claiming an alert,
  including from a lock screen). Enrollment is optional and, where required
  by applicable law, subject to the individual's consent. Like GPS presence,
  voiceprint data is role-scoped to the individual and administrative roles.
- **Kubix Copilot chat logs (in-product)** — once a Customer is live, its
  users may also chat with their dedicated Kubix agent from within the
  product. As with the pre-sales chat, messages and session context are
  processed to generate replies and, where escalated, routed to a human
  engineer.
- **AI and telemetry** — assignment decisions and reasons, predictive/
  forecast outputs, security enforcement logs, worker health metrics, and
  de-duplicated client error reports.

We do not use a Customer's operational data for advertising, and we do not
sell personal data.

## 3. Legal basis

Product-side processing is carried out to perform KubixDesiney's contract
with the Customer, on the Customer's instructions as controller, for our
legitimate interest in securing and operating the Service, and to comply
with applicable law. Storefront-side processing is carried out to respond
to your inquiry, to perform a contract with you (if you are purchasing), and
based on consent where applicable (for example, marketing follow-up).
Special categories of data such as voiceprints are processed only with an
appropriate legal basis and, where required, the individual's consent.

## 4. Sharing and sub-processors

We use the following sub-processors, each operating within the relevant
dedicated instance or storefront configuration:

- **Google** — Firebase (Authentication, Realtime Database, Hosting, Cloud
  Messaging) for product data storage and delivery, and the Gemini model
  family for select AI features.
- **Cloudflare** — edge compute (Workers), networking, and security
  enforcement for both the storefront and the product.
- **Supabase** — supplementary application data/services.
- **Brevo** — transactional email delivery, including purchase confirmations
  and Owner activation emails.
- **n8n** — workflow orchestration for the Kubix Copilot chat agent (both
  pre-sales and in-product).

We do not share personal data with third parties beyond these sub-processors
except as needed to provide the Service or as required by law.

## 5. Data location and isolation

Each Customer's product data is stored within that Customer's own cloud
tenancy (a dedicated Firebase project and dedicated Workers), with a region
selected at provisioning time. Access is least-privilege and role-based,
enforced by Firebase security rules and the Workers' service identity.
Storefront data (purchase/contact records, pre-sales chat) is processed by
KubixDesiney directly, not within a Customer's dedicated instance.

## 6. Retention

- **Product operational data** (e.g. alerts and related records) is retained
  under a default **365-day retention policy**: terminal records older than
  365 days are archived to encrypted backup storage and removed from the
  live database, unless the Customer configures a different period. Backups
  themselves are retained on the Customer's backup schedule (daily,
  encrypted).
- **Account/identity, GPS, and voiceprint data** is retained for as long as
  the relevant instance is active and the feature remains enabled, then
  deleted or anonymized in line with
  `docs/policies/data_retention_privacy_policy.md`.
- **Storefront purchase/contact records** are retained for as long as
  needed for the business relationship and applicable legal (e.g. tax,
  accounting) requirements.
- **Chat logs (pre-sales and in-product Kubix Copilot)** are retained for a
  limited period to support quality review and, where escalated, human
  follow-up, then deleted or anonymized.

Customers may request export or deletion of their instance's data at any
time; see Section 9 (return/deletion) of `DPA.md`.

## 7. Security

Data is encrypted in transit (TLS) and at rest (provider-managed encryption).
Technical and organizational measures are summarized in `docs/TRUST_CENTER.md`,
`docs/COMPLIANCE.md`, and `DPA.md` Section 6. **KubixDesiney does not
currently hold SOC 2 or ISO 27001 certification** — these are roadmap items,
not present attestations. No security measure is perfect; we work to reduce
risk on an ongoing basis.

## 8. Your rights

Depending on applicable law, individuals may have rights to access, correct,
delete, or restrict processing of their personal data, or to object or
request portability. For product data, KubixDesiney is typically a
processor acting for the Customer organization as controller — if you are an
employee of a Customer, please contact your organization first; we will
assist the Customer in responding to your request. For storefront data
where KubixDesiney is the controller, contact us using the details below.

## 9. Children

SIAS is a workplace and business tool and is not directed to children. We do
not knowingly collect personal data from children, on the storefront or in
the product.

## 10. Changes to this policy

We may update this policy; material changes will be communicated on the
storefront and, for product data, to affected Customers.

## 11. Contact

Data protection / privacy inquiries: [[PLACEHOLDER: DPO or privacy contact
email and, if applicable, registered postal address]] (interim contact:
<chefbriotemendez@gmail.com>).

---

*Related documents: `DPA.md` (the controller/processor terms with Customer
organizations), `MSA.md`, `EULA.md`, `SLA.md` (Enterprise plan only),
`docs/compliance/ROPA.md` (detailed record of processing activities).*
