# Operations Runbook — SIA

On-call procedures for the most likely production incidents. Each entry follows
**Symptom → Detect → Diagnose → Mitigate → Verify → Prevent**. Pair with
`docs/ops/SLO.md` (targets/budgets) and `docs/policies/incident_response_plan.md`
(severity, comms, roles). Times in UTC.

## Severity quick reference
- **SEV1** — alerts not reaching supervisors (push pipeline down) or RTDB unavailable. Page immediately.
- **SEV2** — AI assignment / escalation / cron degraded; alerts still flow manually.
- **SEV3** — supporting feature (forecaster, briefing, Guardian, console) degraded.

---

## RB-1 · New-alert push not arriving (SEV1)

- **Detect:** SLI-1/2 breach; `tool/smoke_test.mjs` red; users report no buzz; `workers/health/notifyLastRun` stale; alerts stuck `push_sent: false`.
- **Diagnose:**
  1. Check notify worker health: `GET https://<notify>/config` and `workers/health/notifyLastRun` age.
  2. Check `cron_lock/notify` — a stuck lock blocks cron. Lock older than `NOTIFICATION_LOCK_TTL_MS` (2 min) should self-clear; if not, it's stale.
  3. Inspect a stuck alert's `push_last_error_at` / `push_skip_reason`.
  4. Confirm supervisors have valid `fcmToken` and aren't all `busy`.
- **Mitigate:**
  - Stale lock: delete `cron_lock/notify` (admin/worker token).
  - Manual flush: `POST https://<notify>/notify?sync=1` (returns counts/errors).
  - Single alert: `POST /notify` with `{ "alertId": "<id>" }` (fast path).
  - FCM/credential failure: verify `FIREBASE_SERVICE_ACCOUNT` secret; re-deploy notify worker.
- **Verify:** target alert flips to `push_sent: true`; smoke test green.
- **Prevent:** cron fallback already covers missed producer triggers; ensure `uptime.yml` is active so this is caught within 15 min.

## RB-2 · Worker cron stalled / lock held (SEV2)

- **Detect:** SLI-4 breach; `workers/health/lastRun` age > 2 min; health shows `{ skipped: true, reason: 'lock_held' }`.
- **Diagnose:** read `cron_lock/ai`; check Cloudflare worker logs for exceptions before lock release.
- **Mitigate:** delete the stale `cron_lock/ai` node; redeploy the AI worker if it's crashing mid-run (`npm run deploy:ai`). The lock TTL design means deletion is safe.
- **Verify:** next minute `lastRun` refreshes with assignment/security counters.
- **Prevent:** lock TTL + awaited DELETE in `finally` already guard this; keep them.

## RB-3 · RTDB rules denial spike (SEV1/2)

- **Detect:** `bugs/client` area=database surge; users see permission errors; `security/logs` auth_surge.
- **Diagnose:** recent `database.rules.json` deploy? New field written by app/worker not covered by validators? Check the offending path in the error.
- **Mitigate:** roll back rules: `firebase deploy --only database` from the last good `database.rules.json` (git). For a new field, add its validator and redeploy.
- **Verify:** denials stop; `worker_test/database_rules_security.test.js` still green.
- **Prevent:** every new alert/user field must land in rules validators in the same PR (see `CONTRIBUTING.md`).

## RB-4 · Worker 5xx / latency breach (SEV2)

- **Detect:** SLI-5/6 breach; smoke test latency red.
- **Diagnose:** Cloudflare dashboard error rate; check for a bad deploy, model-provider timeout, or rate-limit feedback loop.
- **Mitigate:** roll back the worker (`wrangler deploy` previous version / `wrangler rollback`); if a model provider is down, disable that AI agent from the SuperAdmin AI Agents console (fails open to fallback).
- **Verify:** 5xx returns to baseline; `/security-status` healthy.

## RB-5 · AI worker model/provider failure (SEV2/3)

- **Detect:** assignment counter flat in `workers/health`; AI suggest returns fallback.
- **Diagnose:** provider key invalid/quota; Workers AI binding error in logs.
- **Mitigate:** toggle the affected agent off (console) — assignment falls back to statistical scoring; rotate/replace the provider key in the secret vault.
- **Verify:** assignments resume; agent stats increment.

## RB-6 · Guardian pipeline runaway / bad auto-fix (SEV2/3)

- **Detect:** unexpected commits/PRs on `main`; CI churn; `bugs/agent` shows repeated runs.
- **Mitigate:** disable the Guardian agent toggle in the AI Agents console (gates the pipeline); set deploy mode to "human review required"; revert the offending commit. Guardian never bypasses the test + independent-review gate, so impact is bounded.
- **Verify:** no new auto-commits; branch protection intact (`docs/BRANCH_PROTECTION.md`).
- **Prevent:** keep customer instances on "human review required" by default.

## RB-7 · Forecaster degraded (SEV3)

- **Detect:** SLI-9 stale; console shows NOT-LEARNING or Brier rising.
- **Mitigate:** non-urgent — retrain from the SuperAdmin AI Training tab on fresh history; adaptation continues opportunistically. No floor-safety impact.

---

## Rollback cheat-sheet
- Rules: `firebase deploy --only database` from last-good `database.rules.json`.
- Worker: `wrangler rollback --config wrangler.<svc>.toml` or redeploy prior commit.
- Web app: redeploy prior `build/web` (Firebase Hosting keeps release history; `firebase hosting:rollback`).
- App binary: Shorebird patch revert / store rollback.

## After every SEV1/SEV2
File a post-incident review (blameless) within 48 h: timeline, root cause, budget
impact, and the prevention item added to the backlog. Template in
`docs/policies/incident_response_plan.md`.
