# Data Processing Agreement (DPA) — Template

> **Template, not legal advice.** This is a starting point for the agreement between
> the Customer (**Controller**) and the SIA operator (**Processor**) under GDPR
> Art. 28 (and analogous laws, e.g. UK GDPR, CCPA service-provider terms). Have it
> reviewed by counsel before execution. Bracketed `[…]` fields are filled per deal.

**Parties:** `[Customer legal entity]` ("Controller") and `[SIA operator entity]` ("Processor").
**Effective date:** `[date]`. **Term:** coterminous with the Service Agreement.

## 1. Subject matter & duration
The Processor processes personal data solely to provide and maintain the Customer's
dedicated SIA instance, for the duration of the Service Agreement.

## 2. Nature & purpose of processing
Hosting/operation of an industrial alert-management platform: account management,
alert lifecycle, optional location/voice features, telemetry-driven alerting, and
operational logging. Detailed in `ROPA.md`.

## 3. Categories of data & data subjects
Data subjects: Customer's employees (supervisors, managers, admins). Data:
identifiers, contact details, role/assignment, device tokens, optional GPS and
voiceprint, authored operational content. Special-category (biometric voiceprint)
only where the Customer enables voice claim and has a lawful basis (see `DPIA.md`).

## 4. Controller instructions
The Processor processes personal data only on the Controller's documented
instructions, including transfers, unless required by law (with prior notice where
permitted).

## 5. Confidentiality
Personnel authorized to process data are bound by confidentiality obligations.

## 6. Security measures (Art. 32)
The Processor maintains technical and organizational measures including: deny-by-
default access control (`database.rules.json`), TLS in transit, edge security guard
(rate limiting, prompt-injection detection, input sanitization), SAST/secret/dependency
scanning, security logging and anomaly detection, documented incident response, and
backups/DR. Detail: `docs/security/THREAT_MODEL.md`, `docs/security/ASVS_CHECKLIST.md`,
`docs/policies/information_security_policy.md`. The **dedicated-instance model** means
the Customer's data is isolated in the Customer's own project with no shared data plane.

## 7. Sub-processors
The Controller authorizes the sub-processors listed in `ROPA.md`. The Processor
imposes Art. 28-equivalent terms on each, gives `[30]` days' notice of additions/
changes, and remains liable for their performance. The Controller may object on
reasonable data-protection grounds.

## 8. Data subject rights
The Processor assists the Controller (insofar as possible, given the nature of
processing) in responding to access/rectification/erasure/portability/objection
requests, via the DSAR procedures in `docs/policies/data_retention_privacy_policy.md`.

## 9. Personal data breach
The Processor notifies the Controller without undue delay and within `[48 hours]` of
becoming aware of a personal-data breach, with the information needed for the
Controller's regulator/data-subject notifications. Procedure: `docs/ops/RUNBOOK.md`,
`docs/policies/incident_response_plan.md`.

## 10. International transfers
Where data is transferred outside the Controller's jurisdiction, the parties rely on
an adequacy decision or Standard Contractual Clauses, incorporated by reference.
Region is selected at provisioning (`PROVISIONING.md`).

## 11. Audit & compliance
The Processor makes available information necessary to demonstrate Art. 28 compliance
and allows for audits, including the SOC 2 report (when available) and the control
matrix (`SOC2_CONTROL_MATRIX.md`), subject to reasonable confidentiality/frequency limits.

## 12. Return/deletion on termination
On termination, the Processor deletes or returns all personal data within `[30]` days,
except as required by law, and deletes existing copies. For dedicated instances,
decommissioning destroys the instance's data stores.

## 13. Liability & governing law
As set out in the Service Agreement. Governing law: `[jurisdiction]`.

---
Signatures: Controller `[name/title/date]` · Processor `[name/title/date]`.
Annexes: Annex 1 = ROPA (`ROPA.md`); Annex 2 = security measures (`docs/security/`);
Annex 3 = sub-processor list (`ROPA.md`).
