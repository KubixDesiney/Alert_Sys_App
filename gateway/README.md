# sias-gateway — SIAS Reference Edge Gateway

Bridges your plant's automation estate — **OPC-UA, Modbus TCP, Siemens S7,
MQTT (incl. Sparkplug B)** — into your SIAS instance's ingest endpoint, in one
command. It also ships a **built-in plant simulator** for demos and dry runs.

- **Zero required dependencies.** The core runs on Node 20 built-ins only.
  Each protocol lazy-loads its library and tells you exactly what to install
  if it's missing.
- **Push-only and credential-light.** The gateway holds a single scoped
  connector ingest key. It never receives credentials *from* SIAS, and SIAS
  never opens connections *into* your plant.
- **Loses nothing on network blips.** Readings batch (max 20 per POST / 2s),
  failures land in an on-disk queue (`gateway/queue/`, capped at 10,000
  readings, oldest dropped with a warning) and retry with exponential backoff.
- **Observe-only.** It reads telemetry. It cannot write to your PLCs.

## 60-second quickstart

1. In your SIAS console: **Infrastructure → Connectors → Add** (pick your
   protocol's edge-push connector). Copy the **ingest URL** and **ingest key**.
2. On any box that can reach both the plant network and the internet:

```bash
cp gateway.config.example.json gateway.config.json   # fill in ingestUrl + ingestKey + your sources
node bin/sias-gateway.mjs --config gateway.config.json
```

3. Watch the status line: `sent=… alerts=… queued=0`. Fire the **Verify link
   test** in the console — the connector flips to *linked*.

No hardware handy? Demo against your instance with the simulator:

```bash
SIAS_INGEST_URL=https://…/ingest/<id> SIAS_INGEST_KEY=… \
  node bin/sias-gateway.mjs --sim 6 --fault-every 90s
```

Or fully offline — print the exact payloads that would be sent and exit:

```bash
node bin/sias-gateway.mjs --sim 3 --dry-run
```

## Per-protocol quickstart

Only install the library for protocols you actually use:

| Protocol | Install | Source config |
|---|---|---|
| OPC-UA | `npm install node-opcua` | `{ "type": "opcua", "endpoint": "opc.tcp://plc:4840", "map": [...] }` — subscribes to the map rules' nodeIds (or an explicit `nodeIds` list) |
| Modbus TCP | `npm install modbus-serial` | `{ "type": "modbus", "host": "…", "registers": [{ "register": 40001, "kind": "uint16\|int16\|uint32\|float32" }], "map": [...] }` — keys are `modbus/<unitId>/<register>` |
| Siemens S7 | `npm install nodes7` | `{ "type": "s7", "host": "…", "rack": 0, "slot": 1, "map": [...] }` — keys are S7 addresses (`DB10,REAL4`) |
| MQTT | `npm install mqtt` | `{ "type": "mqtt", "url": "mqtt://broker:1883", "topics": [...], "map": [...] }` — plain numeric or `{value, ts}` JSON payloads |
| Sparkplug B | `npm install mqtt sparkplug-payload` | add `"sparkplug": true` to the MQTT source — metrics map as `<topic>/<metric name>` |
| Simulator | *(built in)* | `{ "type": "sim", "machines": 6 }` or the `--sim` flag |

## Mapping rules

Every source carries a `map` array binding reading keys (exact, or MQTT-style
`+`/`#` wildcards) to your plant model and thresholds:

```json
{
  "match": "ns=2;s=Line2.Station3.BearingTemp",
  "factory": "Usine A", "line": "Conveyor 2", "station": "3", "machine": "MACH-007",
  "metric": "bearing_temperature", "unit": "°C",
  "scale": 0.1, "offset": 0,
  "thresholds": { "warn": 80, "critical": 90, "direction": "high" },
  "type": "maintenance"
}
```

The SIAS ingest worker makes the alert decision: readings below `warn` are
absorbed as telemetry; `warn`/`critical` breaches become real alerts routed by
AI dispatch. Rules with `"alert": true` force alert creation (event-style
signals). `direction: "low"` inverts the comparison (e.g. line-speed drops).
Contract note: the worker treats an explicit `type` as *forced* alert
creation, so the gateway attaches a threshold rule's `type` only to readings
that actually breach — idle telemetry never floods your alert queue.

## Running it for real

- **Docker** (recommended on plant servers):

  ```bash
  docker build --build-arg PROTOCOL_DEPS="mqtt sparkplug-payload" -t sias-gateway gateway/
  docker run -d --restart unless-stopped \
    -v /opt/sias/gateway.config.json:/app/gateway.config.json:ro \
    -v sias-gateway-queue:/app/queue \
    sias-gateway
  ```

  Runs as the non-root `node` user; persist the queue volume so an outage
  survives container restarts.

- **systemd**: `ExecStart=/usr/bin/node /opt/sias-gateway/bin/sias-gateway.mjs
  --config /etc/sias/gateway.config.json`, `Restart=always`.

## Air-gapped / restricted plants

- The gateway needs **one outbound HTTPS destination**: your instance's ingest
  endpoint. Allow-list that hostname on the plant firewall; no inbound rules.
- For fully air-gapped estates, use the **on-prem SIAS deployment**
  (`deploy/onprem/`) — this same mapping grammar applies to its local gateway.
- Install protocol libraries offline with `npm pack` on a connected machine,
  then `npm install ./<pkg>.tgz` inside.

## Operational notes

- One status line per cycle:
  `sent=1240 alerts=3 queued=0 requeued=40 dropped=0 unmapped=12` —
  `unmapped` counts readings with no matching map rule (fix the rule, not the
  plant).
- Rotating the connector key in the console: update `ingestKey`, restart.
  During the rotation window 401s are queued, not lost.
- Payload contract is covered by `worker_test/gateway_contract.test.js`, which
  runs gateway output through the real ingest worker normalizer — gateway and
  cloud cannot silently drift apart.
