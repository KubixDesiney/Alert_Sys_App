# Autonomous Bug-Fix Agent

`tool/autonomous_bugfix_agent.mjs` is an operational runner for the Smart Industrial Alert repo. It detects production and CI failures, gathers repo/runtime context, asks Gemini for a code fix, validates the fix locally, asks OpenAI for an independent review gate, then pushes the approved commit directly to `main` and deploys Firebase Hosting.

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

## Detected Issue Conditions

- UI URL request fails, times out, or returns a non-2xx/3xx status.
- UI HTML contains failure markers such as `flutter initialization failed`, `failed to load`, `uncaught`, or `fatal error`.
- AI worker `/config` fails.
- AI worker `/security-status` fails.
- Notification worker `/config` fails.
- Recent log files contain error markers such as `error`, `exception`, `fatal`, `failed`, `uncaught`, or `unhandled`.
- Configured detection commands exit non-zero, for example `npm test`.
- Firebase RTDB context collection fails when credentials are configured.
- `workers/health` is missing in RTDB.
- `workers/health/lastRun` or `workers/health/notifyLastRun` is missing.
- AI or notification cron health timestamps are unreadable.
- AI or notification cron health timestamps are older than `AGENT_WORKER_STALE_MINUTES`.
- AI or notification cron health records include non-empty `errors`.

## Fix And Gate Flow

1. Stop if no actionable issue is detected, unless `AGENT_FORCE=1`.
2. Create an isolated `agent/autofix-*` branch.
3. Send structured context to Gemini using `GEMINI_API_KEY`.
4. Apply only safe text file writes inside the repo.
5. Run `AGENT_VALIDATION_COMMANDS`.
6. Send the diff and validation output to OpenAI using `OPENAI_API_KEY` and `OPENAI_REVIEW_MODEL` (`o3` by default).
7. Retry up to `AGENT_MAX_ATTEMPTS` times with validation/review feedback.
8. If approved, commit on `main`, push `HEAD:main`, build Flutter web, and deploy Firebase Hosting.
9. If all attempts fail, write the rejection context to `.dart_tool/autofix-agent` and fail the workflow. There is no Slack/email human escalation path.

## Required Secrets

- `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `FIREBASE_TOKEN`
- `AUTOFIX_GITHUB_TOKEN` recommended for direct `main` pushes; falls back to `GITHUB_TOKEN` in Actions when branch protection allows it.

## Runtime Context Secrets

- `FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS`
- `WORKER_SHARED_SECRET`
- `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are needed only when `AGENT_DEPLOY_WORKERS=1`.

## Safety Notes

- The runner refuses active fixes in a dirty worktree unless `AGENT_ALLOW_DIRTY=1`.
- It refuses writes outside the repository and ignores binary/build/cache paths.
- Generated artifacts are written under `.dart_tool/autofix-agent` and uploaded by the workflow.
- Direct pushes to `main` still depend on repository branch protection allowing the configured token to push.

