# SIAS Demo Script (25 minutes: 15-min core + persona deep-dives)

Goal: prove SIAS is faster than their current process, smarter (AI + prediction),
and uniquely self-healing — then land the pilot. Run on a seeded demo instance.

## 0. Setup (before the call)
- Demo instance with a few factories, supervisors, and seeded alert history.
- Two phones (or emulators) signed in as supervisors; one as Production Manager.
- A forecaster model trained on the seeded history (Predictive cards live).
- The Guardian agent visible in the SuperAdmin console.
- **Start the plant simulator** against the demo instance's ingest connector —
  it keeps a believable live plant humming for the whole call and injects a
  real fault every 90 seconds:

  ```bash
  SIAS_INGEST_URL=https://<ingest>/ingest/<connectorId> SIAS_INGEST_KEY=<key> \
    node gateway/bin/sias-gateway.mjs --sim 6 --fault-every 90s
  ```

  (Rehearsal without a network: `node gateway/bin/sias-gateway.mjs --sim 3 --dry-run`
  prints the exact payloads.) Time your section 2 so a simulator fault lands
  the alert for you — nothing beats "we didn't touch anything, the plant did."

## 1. The hook (1 min)
"Your SCADA already knows a machine is in trouble. The question is how fast the
right person is standing in front of it — and whether you saw it coming. Watch."

## 2. Instant dispatch + voice claim (3 min)
1. Trigger an alert (or POST telemetry via the SCADA connector live — see below).
2. Both supervisor phones buzz with a full-screen alert in ~1-2s.
3. AI has already picked the best supervisor (show the reason: skill + proximity + workload).
4. The chosen supervisor **claims by voice from the lock screen**. Timer stops.
5. Talking point: "From machine fault to claimed, hands-free, in seconds."

## 3. Real SCADA integration (2 min)
```bash
curl -s https://alertsys-ingest.<sub>.workers.dev -H "x-alertsys-ingest: $S" \
  -d '{"source":"opcua","factory":"Plant 1","line":"Line 2","station":"S3",
       "metric":"bearing_temp","value":95,"thresholds":{"warn":70,"critical":90}}'
```
"That's an OPC-UA/MQTT-style reading from your existing estate becoming a dispatched,
AI-routed alert. We sit on top of SCADA — we don't replace it."

## 4. Prediction (2 min)
Open the Production Manager Overview. Show the **Predictive Failure** card and
**Next-24h risk heatmap** ("AI · LIVE"), and the accuracy badge.
"The model runs on-device, trains in seconds on your history, and grades its own
forecasts against what actually happened."

## 5. The Guardian — the jaw-drop (4 min)
In SuperAdmin → AI Agents → Guardian:
1. Show the deploy mode (automatic vs human-review) and the two configurable AIs (Fix + Review).
2. Hit **Simulate**. It triggers a real GitHub Actions run that **injects a genuine fault, has two independent AIs fix + review it, validates, and (in automatic mode) ships the fix** — with a guaranteed auto-restore if anything fails.
3. Watch the live terminal + Actions/PR feed.
"Most vendors give you a support ticket. This platform repairs and redeploys itself,
with an independent AI reviewing every change. No lock-in — pick Claude, GPT, Qwen,
DeepSeek, whatever your security team approves."

## 6. Trust close (1 min)
Flash the compliance pack: SOC 2 control matrix, GDPR ROPA/DPA/DPIA, threat model,
SLOs/runbook, pre-answered security questionnaire. "Your procurement team's homework
is already done."

## 7. The ask (1 min)
"Two-week pilot on one line. We integrate to your alarms, your supervisors install
the app, and we measure response-time and downtime deltas together. If the numbers
aren't there, you walk." → schedule the pilot kickoff.

## Per-persona deep-dives (pick ONE based on who's in the room, ~8 min)

**Plant IT / OT engineer** — go deeper on integration + security:
- Open `gateway/README.md` live: one config file, exact/wildcard mapping rules,
  on-disk retry queue ("a network blip loses nothing"), Docker one-liner.
- Show the connector **Verify link test** handshake in the console.
- Close with the trust surface: enforced worker auth, server-side security
  rules with adversarial tests, CSP'd storefront, SBOM in CI, threat model
  (`docs/SECURITY_WHITEPAPER.md` is their leave-behind).
- Their fear is a second system to babysit → "the gateway is 300 lines of
  config-driven Node you can read in one sitting, and SIAS never writes to
  your PLCs."

**Maintenance manager** — go deeper on the day-2 workflow:
- Claim → resolve → validate on the phone; comments; help requests;
  collaboration across factories; escalation timers.
- Shift view: AI shift commander, presence tracking, handover summaries, the
  shift PDF report ("your morning meeting, pre-written").
- Their fear is technician adoption → voice claiming from a locked phone in
  work gloves is the moment; let THEM claim one.

**Ops leadership** — go deeper on numbers and control:
- Overview analytics: response-time trends, per-type breakdowns, per-supervisor
  performance, export.
- The forecaster's self-graded accuracy ledger ("it tells you when it's wrong").
- The one real number we cite: an export workflow that took ~30 minutes of
  manual collation now takes ~1–2 minutes, with 100% of actions logged (AMEC).
  Everything else we prove live on their own pilot data, not on slides.

## Objection one-liners
- *"We have SCADA alarms."* → Those alarm the room; we get the right tech to the machine, with prediction. Feed us from your alarms in an afternoon.
- *"Rip-and-replace?"* → No. We read your stack, change nothing on the OT network. Start with one line.
- *"Data residency?"* → Dedicated instance in your own cloud; no shared data plane.
- *"Are you certified?"* → SOC 2 is on the roadmap, not claimed. What we have today: dedicated instances, enforced auth, tested security rules, daily backups, a published threat model — and the code to audit.
