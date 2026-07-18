> **DRAFT v1 — requires review by qualified counsel before use.**

# Master Subscription Agreement (MSA)

**Provider:** KubixDesiney, [[PLACEHOLDER: company registration details —
legal form, registration number, registered address (Tunisia)]] ("**Provider**",
"**KubixDesiney**")
**Customer:** the organization identified on the applicable Order Form
("**Customer**")
**Service:** SIAS — Smart Industrial Alert System (the "**Service**")

This Master Subscription Agreement ("**Agreement**"), together with each Order
Form, the Data Processing Addendum (`DPA.md`), and, for Enterprise plan
Customers, the Service Level Agreement (`SLA.md`), governs Customer's
subscription to and use of the Service. Each of those documents is
incorporated into this Agreement by reference. Capitalized terms not defined
here have the meaning given in the referenced document.

---

## 1. The Service

1.1 **Delivery model.** The Service is delivered as a dedicated,
KubixDesiney-operated instance for Customer: its own Firebase (Realtime
Database + Authentication) project and its own set of Cloudflare edge
services, provisioned and operated by KubixDesiney. There is no shared,
multi-tenant data store between customers.

1.2 **Plans.** The Service is offered on three plans — **Starter**, **Growth**,
and **Enterprise** — as described on the Order Form and at KubixDesiney's
then-current plan description. Enterprise plan Customers additionally receive
the service levels in `SLA.md`. Features, limits, and support response targets
differ by plan; the Order Form and `SLA.md` control.

1.3 **Kubix Copilot.** Customer's users may access Kubix Copilot, an
AI assistant dedicated to Customer's instance, as described in the product
documentation. Kubix Copilot is decision support only; see the AI-output
disclaimer in `EULA.md` Section 6 and this Agreement Section 8.4.

## 2. Term and renewal

2.1 **Initial term.** The subscription term begins on the Order Form's start
date and continues for the period stated on the Order Form (the "**Initial
Term**").

2.2 **Renewal.** Unless either party gives the other written notice of
non-renewal at least [[PLACEHOLDER: renewal notice period, e.g. 30 days]]
before the end of the then-current term, the Agreement renews automatically
for successive terms of the same length as the Initial Term, at KubixDesiney's
then-current fees for the applicable plan.

## 3. Fees and payment

3.1 **Fees.** Customer will pay the fees set out on the Order Form. Unless
stated otherwise, fees are quoted and payable in [[PLACEHOLDER: currency]] and
are exclusive of applicable taxes, which Customer is responsible for (other
than taxes on KubixDesiney's net income).

3.2 **Invoicing.** Fees are invoiced in advance on the billing cycle stated on
the Order Form (monthly or annual) and are due within [[PLACEHOLDER: payment
terms, e.g. 15 days]] of the invoice date.

3.3 **30-day money-back guarantee.** If Customer is dissatisfied with the
Service, Customer may request a full refund of its **first** payment within
30 days of that payment, by written notice to KubixDesiney. This guarantee
applies once per Customer and only to the first payment made under the
Order Form; it does not apply to renewal payments or to Enterprise
professional-services fees, if any. On a timely refund request under this
Section, KubixDesiney will process the refund within [[PLACEHOLDER: refund
processing period, e.g. 14 days]] and may deprovision Customer's instance.

3.4 **Late payment.** Amounts not disputed in good faith and not paid when due
may accrue interest at the lesser of [[PLACEHOLDER: late-payment interest
rate]] per month or the maximum rate permitted by law, and KubixDesiney may
suspend the Service per Section 6 for non-payment that remains uncured after
notice.

## 4. Customer responsibilities

Customer is responsible for: (a) provisioning and de-provisioning its own
users and roles within the Service; (b) the accuracy and lawfulness of data
it submits, and obtaining any consents needed for optional features such as
location tracking or voice enrollment; (c) safeguarding its users'
credentials and enabling MFA/SSO for privileged roles where available; (d)
its own safety systems, emergency procedures, and regulatory compliance
independent of the Service (see Section 8.4); and (e) compliance with the
acceptable-use restrictions in `EULA.md` by its authorized users.

## 5. Sub-processors

KubixDesiney uses the sub-processors listed in `DPA.md` (currently: Google,
for Firebase and the Gemini AI model family; Cloudflare, for edge
compute/networking; Supabase; Brevo, for transactional email; and n8n, for
the Kubix Copilot agent workflow). KubixDesiney will provide advance notice of
sub-processor changes as set out in `DPA.md`.

## 6. Suspension

KubixDesiney may suspend Customer's access to the Service, in whole or in
part, on reasonable notice (or without notice in an emergency) if: (a)
Customer's payment is overdue and not cured within [[PLACEHOLDER: cure
period, e.g. 10 days]] of notice; (b) Customer's use poses a security risk to
the Service or another party; (c) Customer materially breaches the acceptable
use provisions of `EULA.md`; or (d) suspension is required to comply with
law. KubixDesiney will restore access promptly once the underlying issue is
resolved.

## 7. Confidentiality

Each party will protect the other's non-public information disclosed under
this Agreement with at least the same degree of care it uses for its own
similar confidential information (and no less than reasonable care), and will
use it only to perform under this Agreement. This Section does not apply to
information that is or becomes public through no fault of the receiving
party, was already known to it without confidentiality obligation, or is
independently developed. A party may disclose the other's confidential
information where required by law, provided it gives reasonable notice where
legally permitted.

## 8. Warranties and disclaimers

8.1 **Mutual authority warranty.** Each party warrants it has the authority to
enter into this Agreement.

8.2 **Service warranty.** KubixDesiney warrants it will provide the Service
using commercially reasonable care and skill, materially in accordance with
the applicable plan description and, for Enterprise Customers, `SLA.md`.

8.3 **Disclaimer.** EXCEPT AS EXPRESSLY STATED IN THIS AGREEMENT, THE SERVICE
IS PROVIDED "AS IS" AND "AS AVAILABLE." TO THE MAXIMUM EXTENT PERMITTED BY
LAW, KUBIXDESINEY DISCLAIMS ALL OTHER WARRANTIES, WHETHER EXPRESS, IMPLIED, OR
STATUTORY, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
NON-INFRINGEMENT.

8.4 **Industrial-safety disclaimer.** SIAS is a supervisory and coordination
aid. It does not monitor, control, or actuate Customer's machinery, and it is
not a safety instrumented system. AI-assisted assignments, predictions,
forecasts, and Kubix Copilot outputs are decision support and may be
incomplete or incorrect. Customer remains solely responsible for its own
safety systems, emergency procedures, and regulatory compliance, and for any
operational decisions made using the Service.

8.5 **No certification claims.** KubixDesiney does not represent that the
Service holds SOC 2 or ISO 27001 certification. These are roadmap items (see
`docs/COMPLIANCE.md`); current status is available on request.

## 9. Indemnification

9.1 **By KubixDesiney.** KubixDesiney will defend Customer against a
third-party claim alleging that the Service, as provided by KubixDesiney and
used in accordance with this Agreement, infringes that third party's
intellectual property rights, and will indemnify Customer against damages
finally awarded (or agreed in settlement), subject to prompt notice,
cooperation, and KubixDesiney's control of the defense. KubixDesiney may, at
its option, procure a license, modify the Service to avoid infringement, or
terminate the affected Service and refund prepaid unused fees.

9.2 **By Customer.** Customer will defend and indemnify KubixDesiney against a
third-party claim arising from Customer's data, Customer's use of the Service
in violation of this Agreement or applicable law, or Customer's failure to
maintain its own safety systems and procedures as required by Section 8.4.

## 10. Limitation of liability

10.1 **Exclusion of certain damages.** TO THE MAXIMUM EXTENT PERMITTED BY LAW,
NEITHER PARTY IS LIABLE TO THE OTHER FOR INDIRECT, INCIDENTAL, SPECIAL,
CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, REVENUE, OR DATA,
ARISING OUT OF OR RELATED TO THIS AGREEMENT, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

10.2 **Cap.** EXCEPT FOR (A) A PARTY'S INDEMNIFICATION OBLIGATIONS UNDER
SECTION 9, (B) A PARTY'S BREACH OF SECTION 7 (CONFIDENTIALITY), OR (C)
LIABILITY THAT CANNOT BE LIMITED BY LAW, EACH PARTY'S TOTAL AGGREGATE
LIABILITY ARISING OUT OF OR RELATED TO THIS AGREEMENT WILL NOT EXCEED THE
FEES PAID OR PAYABLE BY CUSTOMER TO KUBIXDESINEY IN THE TWELVE (12) MONTHS
PRECEDING THE EVENT GIVING RISE TO THE CLAIM.

## 11. Force majeure

Neither party is liable for delay or failure to perform caused by
circumstances beyond its reasonable control, including natural disaster, war,
labor dispute, internet or telecommunications failure, or failure of a
third-party service KubixDesiney relies on to deliver the Service (see
`DPA.md` sub-processor list), provided the affected party gives prompt notice
and uses reasonable efforts to mitigate.

## 12. Term, termination, and effect of termination

12.1 Either party may terminate this Agreement for the other's uncured
material breach on [[PLACEHOLDER: cure period, e.g. 30 days]] written notice.

12.2 On termination or expiry: Customer's access to the Service ends;
Customer's data is handled per `PRIVACY.md` and `DPA.md` (return/deletion on
termination); and each party remains liable for obligations accrued before
termination. Sections 3 (fees accrued), 7 (confidentiality), 8.3–8.5
(disclaimers), 9 (indemnification), 10 (limitation of liability), and 13
(governing law) survive termination.

## 13. Governing law and dispute resolution

[[PLACEHOLDER: governing law — anticipated Republic of Tunisia, to be
confirmed by counsel]]. [[PLACEHOLDER: venue / arbitration forum and rules,
if the parties prefer arbitration over courts]]. [[PLACEHOLDER: language of
the Agreement if executed in a language other than English]].

## 14. General

14.1 **Order of precedence.** In case of conflict on a matter a document
expressly addresses, the order is: the applicable Order Form, this Agreement,
`DPA.md`, `SLA.md` (Enterprise only), then `EULA.md`.

14.2 **Assignment.** Neither party may assign this Agreement without the
other's consent, except to a successor in a merger, acquisition, or sale of
substantially all assets, on notice.

14.3 **Notices.** Legal notices must be in writing to the addresses on the
Order Form or to [[PLACEHOLDER: legal contact email]] (interim contact:
<chefbriotemendez@gmail.com>).

14.4 **Entire agreement.** This Agreement, the Order Form, `DPA.md`, and (for
Enterprise Customers) `SLA.md` are the entire agreement between the parties
on their subject matter and supersede prior discussions on that subject.

---

*Related documents: `EULA.md` (end-user terms for Customer's authorized
users), `DPA.md` (data processing terms, incorporated by reference),
`SLA.md` (Enterprise plan only, incorporated by reference), `PRIVACY.md`
(how KubixDesiney describes its processing publicly).*
