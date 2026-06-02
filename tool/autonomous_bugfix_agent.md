# Autonomous Bug-Fix Agent

`tool/autonomous_bugfix_agent.mjs` is an operational runner for the Smart Industrial Alert repo. It detects production and CI failures, gathers repo/runtime context, asks the ChatGPT/OpenAI code fixer for a patch, validates the fix locally, asks OpenAI for an independent review gate, then opens a PR and can auto-merge it after required checks pass.

## Entry Points

```bash
npm run agent:bugfix:dry-run
npm run agent:bugfix
```

The GitHub Actions workflow is `.github/workflows/autonomous-bugfix-agent.yml`. It runs hourly and can also be started manually.

## Detection Sources

- Deployed UI URLs from `AGENT_UI_HEALTH_URLS`, defaulting to `https://alertappsys.web.app`.
- Cloudflare worker probes:
  - `GET /config` on the AI worker.
  - `GET /security-status` on the AI worker.
  - `GET /config` on the notification worker.
- Recent local/GitHub-run logs matching `*.log`, with stale logs ignored by age.
- RTDB state when `FIREBASE_SERVICE_ACCOUNT` is present:
  - `workers/health`
  - `cron_lock`
  - `ai_runtime/lastAttemptAt`
  - `ai_runtime/lastAssignedAt`
  - `ai_predictions/performance/latest`
  - recent `alerts`
  - recent `security/logs`
- Optional detection commands from `AGENT_DETECTION_COMMANDS`.

## Fix And Gate Flow

1. Stop if no actionable issue is detected, unless `AGENT_FORCE=1`.
2. Create an isolated `agent/autofix-*` branch.
3. Send structured context to the ChatGPT/OpenAI code fixer using `OPENAI_API_KEY` and `OPENAI_CODE_FIX_MODEL`.
4. Apply only safe text file writes inside the repo.
5. Run `AGENT_VALIDATION_COMMANDS`.
6. Send the diff and validation output to OpenAI using `OPENAI_API_KEY` and `OPENAI_REVIEW_MODEL` (`o3` by default).
7. Retry up to `AGENT_MAX_ATTEMPTS` times with validation/review feedback.
8. If approved, open a PR with `gh`, wait for required checks, auto-merge when `AGENT_AUTOMERGE=1`, and trigger `deploy.yml` when `AGENT_TRIGGER_DEPLOY=1`.
9. If all attempts fail, notify Slack and/or email.

## Required Secrets

- `OPENAI_API_KEY`
- `AUTOFIX_GITHUB_TOKEN` recommended; falls back to `GITHUB_TOKEN` in Actions.

## Runtime Context Secrets

- `FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS`
- `WORKER_SHARED_SECRET`
- `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are still needed by existing CI worker deploy jobs.

## Human Alerts

Configure at least one:

- `SLACK_WEBHOOK_URL`
- `RESEND_API_KEY` plus `ALERT_EMAIL_FROM` and `ALERT_EMAIL_TO`
- SMTP: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `ALERT_EMAIL_FROM`, `ALERT_EMAIL_TO`

## Safety Notes

- The runner refuses active fixes in a dirty worktree unless `AGENT_ALLOW_DIRTY=1`.
- It refuses writes outside the repository and ignores binary/build/cache paths.
- Generated artifacts are written under `.dart_tool/autofix-agent` and uploaded by the workflow.
- Auto-merge still depends on repository branch protection and required checks.
