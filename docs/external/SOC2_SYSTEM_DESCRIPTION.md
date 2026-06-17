# SOC 2 — System Description (Section III draft)

Draft of the "Description of the System" an auditor includes as Section III of a
SOC 2 report. Written for the dedicated-instance architecture. Review with the
auditor and counsel before issuance. `[...]` = fill per company.

## A. Overview of services
`[Company]` provides Smart Industrial Alert (SIA), a SaaS platform for industrial
alert intake, AI-assisted dispatch, supervisor coordination, on-device failure
forecasting, and self-healing operations. SIA is delivered as a **dedicated
instance per customer**: each customer's data resides in that customer's own
Firebase project and is served by Cloudflare Workers deployed for that customer.
There is no shared multi-tenant data store across customers.

## B. Principal service commitments & system requirements
- **Security:** access is role-based and deny-by-default; only authorized users and
  the worker service identity can access data; secrets are isolated per instance.
- **Availability:** alert delivery and core workflows meet the targets in
  `docs/ops/SLO.md` (e.g. push success ≥ 99.5%, worker availability ≥ 99.9%).
- **Confidentiality:** customer/operational data and PII are restricted to
  authorized roles and the customer's own cloud tenancy.
These commitments are met through the controls summarized in Section D and detailed
in `docs/compliance/SOC2_CONTROL_MATRIX.md`.

## C. Components of the system
- **Infrastructure:** Cloudflare Workers (AI/security, notifications, GitHub proxy,
  SCADA ingestion); Firebase Authentication and Realtime Database; Firebase Hosting;
  FCM. All run in the customer's cloud accounts (dedicated instance).
- **Software:** the Flutter client application; the worker source; Firebase security
  rules; CI/CD pipelines (GitHub Actions); the Guardian self-heal tooling.
- **People:** `[Company]` engineering and operations (SuperAdmin role); customer
  Production Managers (admin) and Supervisors. Access is least-privilege by role.
- **Procedures:** documented in `docs/policies/*` (information security, access
  control, change management, incident response, data retention/privacy) and the
  operational runbook (`docs/ops/RUNBOOK.md`).
- **Data:** supervisor identity/PII (name, email, phone, optional GPS/voiceprint),
  alert lifecycle records, AI decisions, security/health telemetry. Classified and
  governed per `docs/compliance/ROPA.md` and the retention policy.

## D. Control environment (mapped to TSC)
- **Logical access (CC6):** Firebase Auth; deny-by-default rules with field-level
  validation; superadmin/worker-only on sensitive nodes; provisioning via an
  isolated secondary app. Tested by `worker_test/database_rules_security.test.js`.
- **Change management (CC8):** PR review + CODEOWNERS + branch protection + CI gates
  (analyze, tests, coverage, mutation, CodeQL); the Guardian pipeline requires an
  independent review AI + passing tests before any merge/deploy.
- **Vulnerability management (CC7):** CodeQL SAST, gitleaks, Dependabot, anomaly
  scanning + security logging; penetration testing (`docs/external/PENTEST_*`).
- **Monitoring (CC4/CC7):** worker health pulses, security logs/actions, client
  error pipeline, synthetic uptime checks (`docs/ops/OBSERVABILITY.md`).
- **Availability (A1):** SLOs + error budgets, runbook, DR + backups.
- **Confidentiality (C1):** per-instance isolation, role scoping, retention/disposal.

## E. Boundaries
The system boundary includes the SIA application, its workers, Firebase rules, and
CI/CD. It excludes the customer's broader cloud environment, the customer's SCADA/OT
network, and the internal operations of subservice organizations.

## F. Subservice organizations (carve-out method)
SIA relies on Google Firebase and Cloudflare as subservice organizations for
infrastructure. Their SOC 2 reports are relied upon for the controls they operate
(physical security, environmental, host hardening, platform availability). See
"Complementary Subservice Organization Controls" below.

### Complementary Subservice Organization Controls (CSOCs)
- Google/Cloudflare maintain physical and environmental security of data centers.
- They maintain platform-level availability, patching, and network controls.
- They provide encryption-at-rest for stored data.

## G. Complementary User Entity Controls (CUECs)
Because each customer runs a dedicated instance, the customer is responsible for:
1. Provisioning and safeguarding their Firebase project + Cloudflare account credentials and secrets.
2. Managing user lifecycle (onboarding/offboarding) and enforcing MFA/SSO where available.
3. Obtaining lawful basis/consent for location and voiceprint features (`docs/compliance/DPIA.md`).
4. Choosing the data-residency region and configuring backups/retention to their policy.
5. Reviewing access and reacting on alerts/notifications in a timely manner.

## H. Significant changes during the period
`[List any material changes to the system during the review window, or "none".]`
