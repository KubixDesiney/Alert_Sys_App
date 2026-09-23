# SIAS Documentation Index

One line per document. Start with `../CLAUDE.md` (engineering source of truth)
and `../README.md` (product front door).

## Core

| Doc | Purpose |
|---|---|
| [SECURITY_WHITEPAPER.md](SECURITY_WHITEPAPER.md) | Buyer-facing security overview: isolation, auth matrix, data flows, encryption, backups, roadmap-honest assurance status |
| [PROVISIONING.md](PROVISIONING.md) | Per-customer dedicated-instance runbook + shared tenant web delivery, Android APK delivery, lifecycle tooling (provision, verify, teardown, registry, backup drill) |
| [BRANCH_PROTECTION.md](BRANCH_PROTECTION.md) | Required branch-protection settings for `main` |
| [DEPENDENCY_AUDIT.md](DEPENDENCY_AUDIT.md) | Dependency posture and audit policy |
| [PENTEST_SCOPE.md](PENTEST_SCOPE.md) | Scope prepared for the first external penetration test |
| [PILOT_READINESS_CHECKLIST.md](PILOT_READINESS_CHECKLIST.md) | Everything checked before a customer pilot starts |
| [SECRET_ROTATION.md](SECRET_ROTATION.md) | Credential rotation runbook + leaked-secret history status |
| [TRUST_CENTER.md](TRUST_CENTER.md) | Buyer-facing trust summary page |
| [../desktop/README.md](../desktop/README.md) | Desktop app (Tauri v2 shell): architecture, security model, build, code signing, release runbook |

## Sales (`sales/`)

| Doc | Purpose |
|---|---|
| [sales/ONE_PAGER.md](sales/ONE_PAGER.md) | Product one-pager |
| [sales/SECURITY_OVERVIEW_ONEPAGER.md](sales/SECURITY_OVERVIEW_ONEPAGER.md) | Security one-pager condensed from the whitepaper |
| [sales/RFP_ANSWER_BANK.md](sales/RFP_ANSWER_BANK.md) | 44 honest canned answers for RFPs and security questionnaires |
| [sales/DEMO_SCRIPT.md](sales/DEMO_SCRIPT.md) | The 25-minute demo (gateway simulator setup, wow moments, persona branches, objections) |
| [sales/AFTER_YOU_BUY.md](sales/AFTER_YOU_BUY.md) | Buyer onboarding journey: purchase → activation → first integration → Kubix |
| [sales/PRICING.md](sales/PRICING.md) | Pricing rationale and packaging |
| [sales/ROI.md](sales/ROI.md) | ROI framing for pilots |

## Security (`security/`) & compliance (`compliance/`)

| Doc | Purpose |
|---|---|
| [security/THREAT_MODEL.md](security/THREAT_MODEL.md) | STRIDE analysis over every trust boundary (app, workers, store, ingest/gateway, n8n) |
| [security/ASVS_CHECKLIST.md](security/ASVS_CHECKLIST.md) | OWASP ASVS-aligned control checklist |
| [compliance/SOC2_CONTROL_MATRIX.md](compliance/SOC2_CONTROL_MATRIX.md) | SOC 2 control mapping (roadmap prep, not a certification claim) |
| [compliance/ROPA.md](compliance/ROPA.md) | GDPR record of processing activities |
| [compliance/DPIA.md](compliance/DPIA.md) | Data protection impact assessment |
| [compliance/DPA_TEMPLATE.md](compliance/DPA_TEMPLATE.md) | DPA working template |
| [compliance/VENDOR_SECURITY_QUESTIONNAIRE.md](compliance/VENDOR_SECURITY_QUESTIONNAIRE.md) | Pre-answered vendor security questionnaire |
| [compliance/AUDIT_EVIDENCE_INDEX.md](compliance/AUDIT_EVIDENCE_INDEX.md) | Where audit evidence lives |

## Legal (`legal/`) — DRAFTS, counsel review pending

| Doc | Purpose |
|---|---|
| [legal/COUNSEL_BRIEF.md](legal/COUNSEL_BRIEF.md) | One page for the reviewing lawyer: context + every decision needed |
| [legal/MSA.md](legal/MSA.md) | Master Subscription Agreement (draft) |
| [legal/DPA.md](legal/DPA.md) | Data Processing Addendum (draft) |
| [legal/SLA.md](legal/SLA.md) | Enterprise SLA (draft) |
| [legal/EULA.md](legal/EULA.md) | End-user license (draft) |
| [legal/PRIVACY.md](legal/PRIVACY.md) | Privacy policy (draft) |

Consistency enforced by `npm run legal:lint`; web publication gated off until
counsel signs (`LEGAL_PUBLISH` flag on the store worker).

## Integrations (`integrations/`)

| Doc | Purpose |
|---|---|
| [integrations/SCADA_INTEGRATION.md](integrations/SCADA_INTEGRATION.md) | Full SCADA/PLC/historian integration contract + the reference edge gateway |
| [integrations/COMPETITIVE_POSITIONING.md](integrations/COMPETITIVE_POSITIONING.md) | Where SIAS sits vs. alternatives |

Also see [`../gateway/README.md`](../gateway/README.md) — the packaged edge
gateway (OPC-UA / Modbus / S7 / MQTT / Sparkplug B + plant simulator).

## Operations (`ops/`) & policies (`policies/`)

| Doc | Purpose |
|---|---|
| [ops/RUNBOOK.md](ops/RUNBOOK.md) | Operational runbook |
| [ops/AUTOMATIC_ORDER_PROVISIONING.md](ops/AUTOMATIC_ORDER_PROVISIONING.md) | Authoritative Accept/Paid state machine, automatic Firebase/Worker provisioning, PM + supervisor delivery, retries, and Growth adaptive-AI contract |
| [ops/sias_orders_schema.sql](ops/sias_orders_schema.sql) | Private Supabase order control-plane schema and legacy-status migration |
| [ops/SLO.md](ops/SLO.md) | Service-level objectives + error budgets |
| [ops/OBSERVABILITY.md](ops/OBSERVABILITY.md) | Monitoring/telemetry surfaces |
| [ops/MUTATION_TESTING.md](ops/MUTATION_TESTING.md) | Mutation-testing setup |
| [policies/](policies/README.md) | Information security, access control, change management, retention/privacy, incident response |

## External engagements (`external/`) & ADRs (`adr/`)

| Doc | Purpose |
|---|---|
| [external/](external/README.md) | Pentest RFP/remediation, pilot plan, SOC 2 kickoff + system description |
| [adr/](adr/README.md) | Architecture decision records (worker split, GBDT forecaster, dedicated instances, rules-as-authz, Guardian, data layer) |

## Prompt packs

`CLAUDE_CODE_TASK_PROMPTS.md` and `CLAUDE_CODE_MAXOUT_PROMPTS.md` are internal
engineering-agent work orders, not product docs.

Per-tenant app delivery is documented in [PROVISIONING.md](PROVISIONING.md): one
`sias-app` Worker serves the Flutter web bundle, injects each tenant's public
Firebase config from KV, and exposes the gated Android APK download flow.
