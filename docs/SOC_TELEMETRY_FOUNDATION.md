# SOC telemetry foundation

Status: draft branch for the first SIAS monitoring exercise.

This document defines the smallest useful security telemetry contract for SIAS. It is designed for a private Wazuh lab and a separate Splunk learning lab. It does not change runtime behavior or deploy anything.

## Scope

The first phase covers:

- authentication and session outcomes;
- account provisioning, revocation, and role changes;
- configuration and AI-agent changes;
- alert lifecycle and escalation actions;
- worker, cron, notification, and backup health;
- collector liveness and delivery failures.

The first phase intentionally excludes industrial payloads, customer message contents, passwords, access tokens, Firebase service-account material, OTP values, payment data, and full request bodies.

## Event envelope

Every forwarded event should be newline-delimited JSON with these fields:

| Field | Requirement |
| --- | --- |
| schema_version | Fixed value such as `1` |
| event_id | Stable unique ID; the collector must deduplicate it |
| event_time | UTC ISO-8601 timestamp generated server-side |
| source | `sias` |
| environment | `development`, `staging`, or `production` |
| event_type | Stable category such as `auth`, `access`, `config`, `alert`, or `health` |
| action | Existing SIAS action identifier where one exists |
| outcome | `success`, `failure`, `denied`, or `unknown` |
| severity | `info`, `low`, `medium`, `high`, or `critical` |
| actor_id | Firebase UID or `system`; never an email unless a later policy explicitly permits it |
| actor_role | Role at the time of the event, when known |
| target_type | Optional resource class |
| target_id | Optional non-secret resource identifier |
| request_id | Correlation ID when available |
| reason | Short, redacted explanation |
| collector_cursor | Added locally by the collector, not by the app |

Example:

```json
{"schema_version":1,"event_id":"audit:abc123","event_time":"2026-09-13T12:00:00Z","source":"sias","environment":"development","event_type":"access","action":"account.role_change","outcome":"success","severity":"high","actor_id":"uid-admin","actor_role":"admin","target_type":"user","target_id":"uid-test","request_id":"req-123","reason":"role changed from supervisor to admin"}
```

## Existing SIAS sources

- `lib/services/audit_service.dart` already records append-only `audit_log` events for alert lifecycle, authentication, account access, settings, and AI governance.
- `database.rules.json` protects the audit node and indexes it for time, actor, action, and target searches.
- `cloudflare_monitor_worker.js` already checks worker reachability, cron freshness, notification health, backup freshness, error spikes, delivery latency, and model drift.
- `workers/health/*` and the audit node are the first records the collector should read.

These existing events should be normalized into the envelope above by a trusted collector or server-side adapter. Browser code must never receive Wazuh or Splunk credentials.

## Collection design

The home collector will:

1. read only the selected SIAS paths over an outbound HTTPS connection;
2. authenticate with a narrowly scoped credential stored outside the repository;
3. keep a durable cursor and a local deduplication state;
4. redact fields before writing JSONL;
5. rotate local files and report its own liveness;
6. expose the files only to the local Wazuh agent.

The initial retention target is 30 days of selected security events. Raw archives are disabled until volume and privacy have been measured.

## Validation exercise

Use a disposable development account and perform one authorized role change.

Expected evidence:

1. the SIAS audit record is created with the correct actor and target;
2. the collector reads it exactly once;
3. Wazuh receives one normalized event;
4. the event is searchable by actor, action, target, and time;
5. the collector liveness event remains healthy;
6. no password, token, OTP, customer content, or request body appears in the forwarded record.

After this trace works, add a failed-login sequence and a worker-health failure as the next two detection exercises.

## Coverage limits

This phase covers application events emitted by SIAS and the health signals it already writes. It does not automatically provide Cloudflare account audit logs, all WAF events, Firebase provider-side logs, or network traffic. Those sources will be added only after their plan and export capabilities are verified.
