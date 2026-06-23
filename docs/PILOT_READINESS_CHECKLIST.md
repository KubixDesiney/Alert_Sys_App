# SIA — Pilot Readiness Checklist

Use this checklist to confirm a Smart Industrial Alert (SIA) instance is ready
for a **controlled enterprise pilot**. Work top to bottom; every item should be
checked (or explicitly marked N/A with a note) before a sponsor relies on SIA
for operational alert coordination.

- **Instance:** `__________________________`
- **Sponsor / plant / line:** `__________________________`
- **Pilot administrator (SuperAdmin):** `__________________________`
- **Pilot window:** `__________ → __________`
- **Date reviewed:** `__________`  **Reviewer:** `__________`

> Scope reminder: SIA is a supervisory alert and operations layer. It does not
> run control loops and is not a safety-instrumented system. Existing SCADA/PLC
> safety functions remain authoritative and must stay in place during the pilot.

## 1. Instance provisioning

- [ ] Dedicated Firebase project created for the customer (Auth + Realtime
      Database + Cloud Messaging enabled).
- [ ] Dedicated Cloudflare account/subdomain available (Workers + R2).
- [ ] Backend deployed (automated `deploy_instance` workflow, or manual per
      `INSTALLATION.md`).
- [ ] Realtime Database security rules deployed and current.
- [ ] All required Cloudflare workers deployed (AI/security, notifications,
      GitHub proxy, ingestion, monitor, SCIM if used, backup).
- [ ] Client app built with this instance's worker URLs and distributed to
      pilot devices.

## 2. Secrets & configuration (names only — no values in repo)

- [ ] `WORKER_SHARED_SECRET` set in CI and on the relevant workers.
- [ ] `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` set in CI.
- [ ] `FIREBASE_SERVICE_ACCOUNT`, `FB_DB_URL`, `FB_API_KEY` set where required.
- [ ] `SCIM_TOKEN` set if IdP provisioning is enabled.
- [ ] `INGEST_SHARED_SECRET` / per-connector ingest keys set if connectors are
      enabled.
- [ ] AI-provider API keys (if a non-default model is used) entered via the
      SuperAdmin Model Engine panel, not committed anywhere.
- [ ] No secret values appear in the repository, workflow files, or logs.
- [ ] Any previously exposed credential has been rotated at its provider
      (`docs/SECRET_ROTATION.md`).

## 3. Identity & access

- [ ] SuperAdmin account created and verified (`users/{uid}/role = "SuperAdmin"`).
- [ ] MFA enforcement confirmed for required roles.
- [ ] Production Manager account(s) provisioned.
- [ ] Supervisor accounts provisioned and assigned to the correct factory/line.
- [ ] SCIM provisioning tested end to end (if used): create, update, deactivate.
- [ ] Least-privilege confirmed: `security/*` and `workers/*` not readable by
      non-SuperAdmin roles.

## 4. Core alerting

- [ ] Test alert created; push delivered to a supervisor device within a few
      seconds (foreground and background).
- [ ] Lock-screen / full-screen alert verified on Android pilot devices.
- [ ] Claim → resolve → validate lifecycle works for a real supervisor.
- [ ] Escalation path verified for an unclaimed/critical alert.
- [ ] Offline behavior checked (device loses connectivity, then reconnects and
      syncs).

## 5. AI agents (enable only what the pilot needs)

- [ ] Each enabled agent reviewed; disabled agents confirmed off.
- [ ] Assignment (Shift Commander) reasons and confidence reviewed on sample
      assignments.
- [ ] If a non-default model is used, **Test this model** shows "better" or
      "similar" versus the built-in default before deploy.
- [ ] Model-drift alerting enabled and routed to the monitoring webhook.
- [ ] Predictive forecaster trained on representative history (if used) and the
      Production Manager dashboard shows live risk.
- [ ] Guardian automatic deploy mode is **off** unless explicitly agreed for the
      pilot.

## 6. Industrial integration (if in scope)

- [ ] Connectors configured (SCADA / PLC / Historian / MQTT / REST) with the
      correct mode (cloud-pull or edge-push).
- [ ] **Verify link** handshake passes for each connector.
- [ ] A known reading produces the expected alert (and a normal reading does
      not).
- [ ] Integration confirmed to be read-only/supervisory — SIA does not write to
      control systems.

## 7. Monitoring, reliability & data

- [ ] Reliability monitor enabled with the agreed checks.
- [ ] Alert webhook delivers to the team channel (Slack / Teams / Discord /
      Telegram / generic) — verified with a test event.
- [ ] Application crash-free / error-budget signal visible and SLO set.
- [ ] Backups running and writing to R2; a restore path is understood.
- [ ] Data residency / ownership confirmed with the customer (customer owns the
      Firebase project and data).

## 8. Documentation & operations

- [ ] `RELEASE_NOTES.md` scope statement shared with the sponsor.
- [ ] Trust documentation (`docs/TRUST_CENTER.md`, dependency audit, pentest
      scope) shared as required.
- [ ] Support channel and response expectations agreed and documented.
- [ ] Rollback / disable plan documented (how to revert to existing alerting).
- [ ] Test suites green in CI (`flutter test`, `npm test`).

## 9. Sponsor sign-off

By signing, the sponsor acknowledges that SIA is being used for a **controlled
pilot and operational alert coordination**, that it is a supervisory layer (not
a control or safety-instrumented system), and that existing safety and control
systems remain authoritative throughout the pilot.

- Pilot sponsor: `__________________________`  Date: `__________`
- SIA administrator: `__________________________`  Date: `__________`
