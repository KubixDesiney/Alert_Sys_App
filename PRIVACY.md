# Privacy Notice

**SIAS - Smart Industrial Alert System** — operated by KubixDesiney ("we", "us")

Last updated: 2026-06-23

This notice explains what data SIAS processes, why, and how it is protected. SIAS is
a business-to-business industrial alerting platform used by factory operators. It
is delivered as a **dedicated instance per customer**: each customer's data lives
in that customer's own Firebase project and is served by Cloudflare Workers
deployed for that customer. There is no shared, cross-customer data store.

In most deployments the customer is the **data controller** and KubixDesiney acts
as a **data processor** on the customer's instructions. A Data Processing
Agreement is available (`docs/compliance/DPA_TEMPLATE.md`).

## 1. Data we process

- **User account and identity:** first/last name, email, phone, role
  (supervisor, admin/Production Manager, superadmin), and factory assignment.
- **Authentication data:** Firebase Authentication identifiers and, where enabled,
  MFA/SSO metadata. We do not store account passwords; authentication is handled by
  the identity provider.
- **Operational data:** alerts, claims, resolutions, escalations, collaboration and
  shift records, and related comments.
- **Device and messaging:** Firebase Cloud Messaging (FCM) push tokens.
- **Optional location:** supervisor GPS coordinates, only when location features are
  enabled, used for proximity-based assignment and the plant locator.
- **Optional voice biometrics:** a voiceprint embedding for speaker verification,
  only when voice claim is enabled and the user has enrolled.
- **AI and telemetry:** assignment decisions and reasons, predictive/forecast
  outputs, security enforcement logs, worker health metrics, and de-duplicated
  client error reports.

A detailed Record of Processing Activities is maintained in
`docs/compliance/ROPA.md`.

## 2. Why we process it

To deliver core functionality (alert intake, assignment, coordination,
notification, forecasting), to secure the service, to provide support, and to meet
contractual and legal obligations. We do **not** sell personal data and we do not
use customer operational data for advertising.

## 3. Legal basis

Processing is carried out to perform the contract with the customer, on the basis
of the customer's instructions as controller, for our legitimate interest in
securing and operating the service, and to comply with applicable law. Special
categories such as voice biometrics are processed only with the appropriate basis
and, where required, the user's consent.

## 4. Sharing and subprocessors

We use the following infrastructure subprocessors, each operating within the
customer's dedicated instance configuration:

- **Google Firebase** (Authentication, Realtime Database, Hosting, Cloud
  Messaging) — application data store and delivery.
- **Cloudflare** (Workers) — edge orchestration, notifications, security, and
  integrations.

Optional integrations (for example external forecasting endpoints or industrial
connectors) are enabled only at the customer's direction. We do not share personal
data with third parties except as needed to provide the service or as required by
law.

## 5. Data location and isolation

Each customer's data is stored within that customer's own cloud tenancy
(dedicated Firebase project and dedicated Workers). Access is least-privilege and
role-based, enforced by Firebase security rules and the worker service identity.

## 6. Retention

Data is retained for as long as the customer's instance is active and as needed
for the purposes above, then deleted or anonymized in line with
`docs/policies/data_retention_privacy_policy.md`. Customers may request export or
deletion of their instance data.

## 7. Security

Data is encrypted in transit (TLS) and at rest (provider-managed). Technical and
organizational measures are summarized in `docs/TRUST_CENTER.md` and the
information security policy (`docs/policies/information_security_policy.md`). No
security measure is perfect; we work to reduce risk on an ongoing basis.

## 8. Your rights

Depending on applicable law, individuals may have rights to access, correct,
delete, or restrict processing of their personal data, or to object or request
portability. Because the customer is usually the controller, we will refer
individual requests to the relevant customer and assist them in responding.

## 9. Children

SIAS is a workplace tool and is not directed to children. We do not knowingly
process data of children.

## 10. Changes

We may update this notice; material changes will be communicated to customers.

## 11. Contact

Privacy inquiries: <chefbriotemendez@gmail.com>

> This notice describes current practices and does not itself assert any
> third-party certification or audit attestation.
