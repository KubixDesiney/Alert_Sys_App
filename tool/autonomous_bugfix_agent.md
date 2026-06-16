# Autonomous Bug-Fix Agent

`tool/autonomous_bugfix_agent.mjs` is an operational runner for the Smart
Industrial Alert repo. It detects production and CI failures, gathers
repo/runtime context, asks Claude for a candidate fix, validates the fix
locally, asks OpenAI for an independent review gate, then opens a draft pull
request for human review and normal CI.

The safe default is reviewable automation. Direct pushes to `main` and
production deploys are disabled unless an operator explicitly sets both
`AGENT_PUBLISH_MODE=direct` and `AGENT_DIRECT_MAIN_PUSH_ALLOWED=1` in an
isolated emergency environment.

## Entry Points

```bash
npm run agent:bugfix:dry-run
npm run agent:bugfix
```

The GitHub Actions workflow is `.github/workflows/autonomous-bugfix-agent.yml`.
It runs hourly and can also be started manually.

## Detection Sources

- Deployed UI URLs from `AGENT_UI_HEALTH_URLS`, defaulting to `https://alertappsys.web.app`.
- Cloudflare worker probes:
  - `GET /config` on the AI worker.
  - `GET /security-status` on the AI worker.
  - `GET /config` on the notification worker.
- Recent local/GitHub-run logs matching `*.log`, with stale logs ignored by age.
- RTDB state when `FIREBASE_SERVICE_ACCOUNT` is present.
- Optional detection commands from `AGENT_DETECTION_COMMANDS`.

## Fix And Gate Flow

1. Stop if no actionable issue is detected, unless `AGENT_FORCE=1`.
2. Reset an agent-owned branch from `origin/main`.
3. Send structured context to Claude using `ANTHROPIC_API_KEY` and `CLAUDE_FIX_MODEL`.
4. Apply only safe text file writes inside the repo.
5. Run `AGENT_VALIDATION_COMMANDS`.
6. Send the diff and validation output to OpenAI using `OPENAI_API_KEY` and `OPENAI_REVIEW_MODEL`.
7. Retry up to `AGENT_MAX_ATTEMPTS` times with validation/review feedback.
8. If approved, commit to an `autofix/*` branch and open a draft PR against `main`.
9. If all attempts fail, write the rejection context to `.dart_tool/autofix-agent`, open an escalation issue when possible, and fail the workflow.

## Required Secrets

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` or `GH_TOKEN` with permission to push the autofix branch and open a PR.

## Runtime Context Secrets

- `FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS`
- `WORKER_SHARED_SECRET`

Cloudflare and Firebase deploy credentials are not used by the default workflow.
They are only needed for explicit direct emergency publish mode.

## Safety Notes

- The runner refuses active fixes in a dirty worktree unless `AGENT_ALLOW_DIRTY=1`.
- It refuses writes outside the repository and ignores binary/build/cache paths.
- Generated artifacts are written under `.dart_tool/autofix-agent` and uploaded by the workflow.
- Merging an autofix PR requires the same protected-branch checks and human review as any other production change.
