# Edge Gateway configuration examples

Copy one (or merge several) into `gateway.config.json` next to `index.mjs`
(or point `GATEWAY_CONFIG` at it). Every adapter is **read-only**: the gateway
never writes values or setpoints to PLC/SCADA systems — the Modbus frame
builder physically lacks write function codes and the OPC UA adapter only
creates monitored-item subscriptions.

| File | Protocol | Transport |
|------|----------|-----------|
| `esp32.json` | ESP32 / microcontroller HTTP | board POSTs to `/esp32` |
| `webhook.json` | Generic REST webhook | third party POSTs to `/webhook/<id>` |
| `mqtt.json` | MQTT subscribe | gateway connects to your broker |
| `opcua.json` | OPC UA monitored items | gateway connects to the server |
| `modbus.json` | Modbus TCP polling (FC3/FC4 only) | gateway polls the PLC |

Common sections (all files):
- `ingestUrl` — worker-runner `/ingest` endpoint (compose default works).
- `apiKeys` — per-caller API keys for the HTTP adapters (`X-Api-Key` or
  `Authorization: Bearer`). Generate long random values; one key per device
  fleet / integration, never shared between vendors.
- `rateLimit` — token bucket per caller (`capacity`, `refillPerSec`).
- Thresholds: a rule fires when ANY configured comparison matches
  (`gt`, `gte`, `lt`, `lte`, `eq`, `notEq`). A rule without thresholds fires on
  every reading (event-style inputs). `scale`/`offset` convert raw units
  (e.g. Modbus tenths-of-°C -> °C) *before* thresholds are applied.

MQTT / OPC UA / Modbus adapters require the **Industrial** plan — on Standard
licences the gateway skips them at boot (logged) while HTTP ingestion keeps
working.

> **Honesty note:** the protocol logic is covered by unit tests against
> simulated data (bytes/frames/payloads). **No real PLC, OPC UA server or
> production broker has been tested against this gateway.** Commission it
> against your own equipment in a safe, non-production window first.
