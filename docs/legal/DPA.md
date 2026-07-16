> **DRAFT v1 — requires review by qualified counsel before use.**

# Data Processing Addendum (DPA)

**Controller:** the Customer identified on the applicable Order Form under the
Master Subscription Agreement (`MSA.md`) ("**Controller**", "**Customer**")
**Processor:** KubixDesiney ("**Processor**", "**KubixDesiney**")
**Service:** SIAS — Smart Industrial Alert System

This Data Processing Addendum ("**DPA**") supplements and is incorporated into
the MSA. It applies where KubixDesiney processes personal data on Customer's
behalf as a processor in the course of providing the Service, and is intended
to meet the requirements of Article 28 of the EU General Data Protection
Regulation ("**GDPR**") and analogous data protection laws (e.g. UK GDPR).
Where this DPA conflicts with the MSA on data protection matters, this DPA
controls.

---

## 1. Roles of the parties

1.1 As between the parties, Customer is the **controller** and KubixDesiney is
the **processor** with respect to personal data processed through the
Service. Customer is responsible for the lawfulness of the personal data it
submits to the Service and for any instructions it gives KubixDesiney.

1.2 KubixDesiney processes personal data only (a) on Customer's documented
instructions, including as set out in the MSA, the Order Form, and Customer's
configuration of the Service, or (b) as required by applicable law, in which
case KubixDesiney will inform Customer of that legal requirement before
processing, unless the law prohibits such notice.

## 2. Subject matter, duration, nature, and purpose

The subject matter, duration, nature, purpose, and categories of personal
data and data subjects are as described in `PRIVACY.md` and, in more detail,
in the Record of Processing Activities (`docs/compliance/ROPA.md`): principally,
account/identity data, authentication metadata, operational alert and
coordination records, device push tokens, and, only where the Customer
enables the relevant feature, GPS location and voiceprint biometric data —
each scoped to the roles that need it. Processing continues for the
duration of the Service Agreement.

## 3. Confidentiality

KubixDesiney ensures that persons authorized to process personal data
(employees, contractors) are subject to a duty of confidentiality, whether
contractual or statutory.

## 4. Sub-processors

4.1 Customer authorizes KubixDesiney to engage the following sub-processors
in connection with the Service:

| Sub-processor | Role |
|---|---|
| Google (Firebase: Authentication, Realtime Database, Cloud Messaging, Hosting; and the Gemini model family for select AI features) | Application data store, authentication, push delivery, hosting, AI inference |
| Cloudflare | Edge compute (Workers), networking, and security enforcement |
| Supabase | Supplementary application data/services (see current sub-processor detail on request) |
| Brevo | Transactional email delivery, including Owner activation emails |
| n8n | Workflow orchestration for the Kubix Copilot chat agent |

4.2 KubixDesiney imposes data protection obligations on each sub-processor
that are no less protective than this DPA, and remains liable to Customer for
each sub-processor's performance of its obligations.

4.3 KubixDesiney will give Customer at least [[PLACEHOLDER: sub-processor
change notice period, e.g. 30 days]] prior notice of the addition or
replacement of a sub-processor (for example, by posting an update to this
document or by direct notice), during which Customer may object on reasonable
data-protection grounds. If the parties cannot resolve the objection,
Customer may terminate the affected portion of the Service as its sole
remedy.

## 5. International transfers

Where personal data is transferred outside the jurisdiction in which it was
collected (for example, because Customer selects a Firebase project region
outside that jurisdiction, or because a sub-processor operates
internationally), the parties will rely on an applicable adequacy decision or
execute Standard Contractual Clauses (or an equivalent transfer mechanism)
[[PLACEHOLDER: SCCs / transfer mechanism to be incorporated by reference —
module to be selected based on Controller/Processor relationship]]. The
Firebase project region is selected by Customer at provisioning time (see
`docs/PROVISIONING.md`).

## 6. Technical and organizational measures (TOMs)

KubixDesiney maintains the following technical and organizational measures,
reflecting the actual architecture described in the product's engineering
documentation:

- **Tenant isolation.** Each Customer instance is a dedicated Firebase project
  and dedicated set of Cloudflare Workers — there is no shared, multi-tenant
  data store, removing an entire class of cross-tenant data-leak risk.
- **Access control.** Deny-by-default Realtime Database security rules with
  role-based access (supervisor / admin / superadmin), self-or-admin write
  scoping, and worker-service-token authentication for edge functions.
- **PII scoping.** Sensitive fields (email, phone, precise location) are
  separated from broadly-readable operational records and scoped to the
  record owner and administrative roles.
- **Encryption.** TLS in transit; encryption at rest via the underlying cloud
  providers' managed encryption (Google Cloud / Firebase, Cloudflare).
- **Edge security controls.** Per-endpoint rate limiting, prompt-injection
  detection and input sanitization on AI-facing endpoints, and security event
  logging with anomaly detection.
- **Backups and retention.** Automated daily encrypted backups of the
  Realtime Database to object storage, and an alert-retention policy that
  archives and removes terminal operational records after a default of 365
  days (configurable by Customer).
- **Change management and testing.** Automated test suites gating deploys,
  dependency and secret scanning in CI.
- **Incident response.** A documented incident response process (see
  `docs/policies/incident_response_plan.md`).

A detailed control mapping is available at `docs/COMPLIANCE.md` on request. As
of this draft, KubixDesiney does **not** hold SOC 2 or ISO 27001 certification
— formal certification is a roadmap item, not a current attestation, and no
part of the Service marketing or this DPA should be read to claim otherwise.

## 7. Assistance with data subject rights

Taking into account the nature of the processing, KubixDesiney will provide
Customer with reasonable assistance (via the Service's export and account
management functions, or by direct request) to respond to data subject
requests to access, correct, delete, restrict, or port their personal data,
and to respond to data protection authority inquiries, consistent with
`docs/policies/data_retention_privacy_policy.md`.

## 8. Personal data breach notification

KubixDesiney will notify Customer **without undue delay, and in any event
within 72 hours** of becoming aware of a personal data breach affecting
Customer's instance, with the information reasonably available to
KubixDesiney at the time (nature of the breach, categories and approximate
number of data subjects/records affected, likely consequences, and measures
taken or proposed) so that Customer can meet its own regulatory and
data-subject notification obligations. KubixDesiney will cooperate with
Customer's reasonable investigation and remediation requests.

## 9. Return and deletion of data on termination

On termination or expiry of the Service Agreement, KubixDesiney will, at
Customer's choice, make Customer's data available for export or delete it
(and instruct sub-processors to do the same), within [[PLACEHOLDER: return/
deletion period, e.g. 30 days]] of termination, except to the extent
retention is required by applicable law. Because each Customer instance is
dedicated infrastructure, decommissioning an instance destroys its data
stores in their entirety.

## 10. Audits

KubixDesiney will make available to Customer information reasonably necessary
to demonstrate compliance with this DPA (including the control mapping in
`docs/COMPLIANCE.md` and, once available, any third-party audit report), and
will permit and contribute to audits, including inspections, conducted by
Customer or an auditor mandated by Customer, subject to reasonable
confidentiality, scope, and frequency limits, and subject to
[[PLACEHOLDER: audit cost allocation / notice period]].

## 11. Liability

Each party's liability arising out of this DPA is subject to the limitation
of liability set out in the MSA.

## 12. Governing law

This DPA is governed by the same governing law as the MSA.
[[PLACEHOLDER: governing law — anticipated Republic of Tunisia, to be
confirmed by counsel; note that GDPR-subject Controllers may separately
require EU member-state law/SCCs for the transfer mechanism in Section 5]].

---

Signatures: Controller [[PLACEHOLDER: name / title / date]] · Processor
[[PLACEHOLDER: name / title / date]].

*Related documents: `MSA.md` (incorporates this DPA by reference), `SLA.md`
(Enterprise plan only), `PRIVACY.md` (public-facing description of the same
processing), `EULA.md` (end-user terms), `docs/compliance/ROPA.md` (detailed
record of processing activities), `docs/COMPLIANCE.md` (control mapping).*
