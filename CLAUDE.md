# AlertSys Architecture Notes

## Cloudflare Workers

AlertSys now uses two separate Cloudflare Workers so push delivery is not competing with AI, prediction, and security work inside one Free-plan invocation.

### AI & Security Worker

- Worker name: `alert-notifier`
- URL: `https://alert-notifier.aziz-nagati01.workers.dev`
- Main file: `cloudflare_ai_worker.js`
- Wrangler config: `wrangler.ai.toml`
- Cron: `* * * * *`

Responsibilities:

- AI assignment runs and shift AI actions.
- Escalation checks and escalation push sends.
- Predictive model and briefing endpoints: `/predict`, `/briefing`, `/predict-lstm`.
- AI suggestion endpoints: `/ai-suggest`, `/suggest-assignee`, `/ai-proxy`, `/auto-fix`, `/auto-fix-full`.
- Security guard, prompt-injection detection, anomaly scanning, and `/security-status`.
- Worker health pulse for AI/security work.

### Notifications Worker

- Worker name: `alertsys`
- URL: `https://alertsys.aziz-nagati01.workers.dev`
- Main file: `cloudflare_notify_worker.js`
- Wrangler config: `wrangler.notify.toml`
- Cron: `* * * * *`

Responsibilities:

- New-alert push fan-out via `processAlerts`.
- Queued notification fan-out via `fanOutPendingNotifications`.
- `/notify` HTTP endpoint.
- Default manual trigger at `/`.
- Notification worker health pulse at `workers/health/notifyLastRun`.

The notification worker keeps only the Firebase auth helpers, FCM sender, FCM token cleanup, active/free supervisor gates, basic rate limiting, and notification-specific Firebase reads/writes.

### Deprecated Fallback

- `cloudflare_workerV2.js` is kept only as a deprecated monolithic fallback.
- Do not deploy it for normal production operation.
- `wrangler.toml` is retained as a legacy config; active deployments should use the split configs.

## Deployment

Deploy both workers manually or from CI:

```bash
npx wrangler deploy --config wrangler.ai.toml
npx wrangler deploy --config wrangler.notify.toml
```

Both workers need the same Firebase secrets configured in Cloudflare. Set them per worker with `wrangler secret put` and do not commit secret values:

- `FB_DB_URL`
- `FB_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT`
- `FB_DB_Secret` if still used by operational scripts
- Any optional AI/provider secrets used by the AI worker

## Flutter Worker URLs

`lib/config/app_config.dart` defines separate URLs:

- `AppConfig.aiWorkerBase`
- `AppConfig.notifyWorkerBase`

AI calls use the AI worker. Notification triggers use the notification worker.

## File-to-Responsibility Index

- `cloudflare_ai_worker.js`: AI, predictions, briefings, escalation, security, and AI-related HTTP endpoints.
- `cloudflare_notify_worker.js`: new-alert pushes, queued notification pushes, `/notify`, and manual notification trigger.
- `wrangler.ai.toml`: Cloudflare deployment config for `alert-notifier`.
- `wrangler.notify.toml`: Cloudflare deployment config for `alertsys`.
- `.github/workflows/ci.yml`: tests and deploys both workers.
- `.github/workflows/deploy.yml`: builds Flutter web with split worker URLs.
- `lib/config/app_config.dart`: central Flutter URLs for AI and notification workers.
- `lib/services/worker_trigger_queue.dart`: routes `/notify` to the notification worker and `/ai-retry` to the AI worker.
- `lib/services/alert_service.dart`: triggers the notification worker after creating alerts.
- `lib/services/predictive_repository.dart`: reads predictions, briefings, and assignee suggestions from the AI worker.
