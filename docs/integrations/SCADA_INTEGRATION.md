# SCADA / PLC / Historian Integration

SIA is an **alerting and coordination layer that sits on top of** an existing
automation estate — it does not replace SCADA, a DCS, or PLC control loops. This
guide shows how to feed SIA from the systems a plant already runs, so a customer
gets mobile dispatch, AI assignment, presence tracking, and forecasting **without
ripping anything out**.

## Architecture: coexistence, not replacement

```
  PLCs / sensors ──► SCADA / DCS ──► Historian (PI, Ignition, Wonderware, …)
        │                │                    │
        │  (control loops stay exactly where they are — SIA never touches them)
        │                │                    │
        └──────── edge gateway / broker rule / historian export ───────┐
                                                                        ▼
                                                  SIA ingestion worker (HTTPS)
                                                  cloudflare_ingest_worker.js
                                                                        │
                                                  normalize + threshold + dedup
                                                                        ▼
                                                  SIA alert  →  push / AI assign
                                                                / forecast / PDF
```

The gateway is the integration seam. Anything that can make an authenticated HTTPS
POST can drive SIA; you do not run SIA logic on the OT network.

## Supported sources

| Protocol / source | How it reaches SIA | Notes |
|---|---|---|
| **OPC-UA** | A small edge bridge subscribes to nodes and POSTs changes | The dominant industrial standard; any OPC-UA client (Node-OPCUA, Kepware, Ignition) can call the ingest endpoint. |
| **MQTT / Sparkplug B** | Broker rule (e.g. HiveMQ/EMQX rule engine) or a bridge subscribes to topics and POSTs | Sparkplug metric name → SIA metric mapping. |
| **Modbus TCP/RTU** | A poller reads registers on an interval, applies thresholds, POSTs | Register→metric map lives in the gateway. |
| **REST / webhook** | Any system POSTs JSON directly | MES, CMMS, quality systems, custom apps. |
| **Historian export** | Scheduled query → POST batch (`readings[]`) | Backfill or near-real-time tag exports. |

## Ingestion endpoint contract

`POST https://alertsys-ingest.<sub>.workers.dev`
Header: `x-alertsys-ingest: <INGEST_SHARED_SECRET>`

Body — a single reading, or `{ "readings": [ … ] }`, or a bare array. Fields are
flexible (synonyms accepted); the worker normalizes them:

```json
{
  "source": "opcua",
  "factory": "Plant 1",          // factory | site | usine
  "line": "Line 2",              // line | conveyor | convoyeur
  "station": "Station 3",        // station | poste | point
  "machine": "M-204",            // machine | asset | tag | node
  "metric": "bearing_temp",      // metric | signal | measurement
  "value": 95,
  "unit": "C",
  "thresholds": { "warn": 70, "critical": 90, "direction": "high" },
  "timestamp": "2026-06-16T09:30:00Z"  // ISO, epoch s, or epoch ms
}
```

Behavior:
- **Normal readings raise nothing.** An alert is created only when `value` crosses
  a threshold, or when `type` is set / `alert: true` is sent (e.g. a digital E-stop).
- **Severity → criticality.** `critical` threshold ⇒ `isCritical: true`. `direction: "low"` flips the comparison (e.g. low oil pressure).
- **Type inference.** The metric name maps to a canonical SIA type
  (Mechanical / Electrical / Quality / Safety); an explicit canonical `type` wins.
- **Storm control.** Identical machine/metric events inside the dedup window
  (default 60 s) collapse to one alert — a flapping sensor won't page the floor 600×.
- On success SIA creates the alert (minimal first-write shape permitted by
  `database.rules.json`) and triggers the notification worker for sub-second push.

### Example
```bash
curl -sS https://alertsys-ingest.<sub>.workers.dev \
  -H 'content-type: application/json' \
  -H "x-alertsys-ingest: $INGEST_SHARED_SECRET" \
  -d '{"source":"mqtt","factory":"Plant 1","line":"Line 2","station":"S3",
       "metric":"bearing_temp","value":95,"unit":"C",
       "thresholds":{"warn":70,"critical":90}}'
# => {"ok":true,"created":1,"skipped":0,"alertIds":["-Nx…"]}
```

## Security
- Inbound auth is a constant-time shared-secret check; rotate via `wrangler secret put`.
- Per-source sliding-window rate limit (default 240/min) protects against a runaway gateway.
- 32 KB body cap; control/zero-width characters stripped from all fields.
- The worker only ever **creates alerts** — it cannot read or modify other data.

## Where the boundary is (be explicit with buyers)
SIA does **not** issue setpoints, close loops, or guarantee hard-real-time
determinism — that stays in SCADA/PLC. SIA owns what those systems are weak at:
getting the right human to the right machine fast, on mobile, with AI assignment,
voice claim, presence, and predictive risk. See `COMPETITIVE_POSITIONING.md`.

## Deploy
`npx wrangler deploy --config wrangler.ingest.toml` (set `FB_DB_URL`,
`NOTIFY_WORKER_URL`, and the `INGEST_SHARED_SECRET` secret first). Tests:
`worker_test/ingest.test.js`.
