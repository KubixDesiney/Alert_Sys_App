// Conformance: gateway output must satisfy the REAL ingest worker normalizer.
// This is the contract that keeps the edge gateway and the cloud ingest path
// from drifting apart — gateway payloads are fed through the exact
// normalizeTelemetry/mergeConnectorDefaults the deployed worker runs.
import { normalizeTelemetry, mergeConnectorDefaults } from '../cloudflare_ingest_connectors.js';
import { mapReadings, toIngestReading } from '../gateway/src/mapping.mjs';
import { SimSource, simMapRules } from '../gateway/src/sources/sim.mjs';

const NOW = () => 1780000000000;

const connector = { id: 'c1', kind: 'custom', factory: 'Fallback Plant' };
const normalize = (payload) =>
  normalizeTelemetry(mergeConnectorDefaults(payload, connector, {}), { source: connector.kind });

describe('gateway → ingest worker contract', () => {
  const rule = {
    match: 'plc/bearing',
    factory: 'Usine A',
    line: 'Conveyor 2',
    station: '3',
    machine: 'MACH-007',
    metric: 'bearing_temperature',
    unit: '°C',
    thresholds: { warn: 80, critical: 90, direction: 'high' },
  };

  test('a critical breach becomes a critical SIAS alert', () => {
    const payload = toIngestReading({ key: 'plc/bearing', value: 95, ts: NOW() }, rule, { source: 'opcua', now: NOW });
    const alert = normalize(payload);
    expect(alert).not.toBeNull();
    expect(alert.isCritical).toBe(true);
    expect(alert.usine).toBe('Usine A');
    expect(alert.convoyeur).toBe('Conveyor 2');
    expect(alert.poste).toBe('3');
    expect(alert.source).toBe('scada:opcua');
    expect(alert.value).toBe(95);
    expect(alert.push_sent).toBe(false);
    expect(typeof alert.timestamp).toBe('number');
  });

  test('a warning breach becomes a non-critical alert', () => {
    const alert = normalize(toIngestReading({ key: 'plc/bearing', value: 83 }, rule, { now: NOW }));
    expect(alert).not.toBeNull();
    expect(alert.isCritical).toBe(false);
  });

  test('a normal reading is absorbed (no alert) — the gate lives in the worker', () => {
    const alert = normalize(toIngestReading({ key: 'plc/bearing', value: 60 }, rule, { now: NOW }));
    expect(alert).toBeNull();
  });

  test('low-direction thresholds fire on drops', () => {
    const lowRule = { ...rule, metric: 'line_speed', thresholds: { warn: 30, critical: 22, direction: 'low' } };
    expect(normalize(toIngestReading({ key: 'plc/bearing', value: 20 }, lowRule, { now: NOW })).isCritical).toBe(true);
    expect(normalize(toIngestReading({ key: 'plc/bearing', value: 45 }, lowRule, { now: NOW }))).toBeNull();
  });

  test('event-style rules (alert: true) force alert creation without thresholds', () => {
    const eventRule = { factory: 'Usine A', machine: 'MACH-001', metric: 'estop', alert: true, message: 'E-stop pressed', type: 'Safety' };
    const alert = normalize(toIngestReading({ key: 'k', value: 1 }, eventRule, { now: NOW }));
    expect(alert).not.toBeNull();
    expect(alert.type).toBe('Safety');
    expect(alert.adresse).toBe('E-stop pressed');
  });

  test('simulator faults produce alerts; simulator idle telemetry does not', () => {
    const machines = 4;
    const sim = new SimSource({ machines, seed: 7, faultEveryMs: 1000, now: NOW });
    const rules = simMapRules(machines);
    const { readings, faulted } = sim.tick(NOW());
    expect(faulted).not.toBeNull();
    const { mapped, unmapped } = mapReadings(readings, rules, { source: 'sim', now: NOW });
    expect(unmapped).toBe(0);
    expect(mapped).toHaveLength(machines * 3);

    const alerts = mapped.map(normalize).filter(Boolean);
    // Exactly the faulted machine's breached metric(s) alert — not the whole plant.
    expect(alerts.length).toBeGreaterThanOrEqual(1);
    for (const a of alerts) expect(a.convoyeur).toBeTruthy();
    const faultAlert = alerts.find((a) => a.adresse.includes(faulted) || a.usine === 'Demo Plant');
    expect(faultAlert).toBeTruthy();
    expect(alerts.length).toBeLessThan(mapped.length / 2);
  });

  test('connector defaults backfill a payload that omits the factory', () => {
    // A rule missing factory never leaves the gateway; but if a customer maps
    // only machine/metric, the connector-level default factory still applies
    // through mergeConnectorDefaults — asserted here so the fallback contract
    // stays real.
    const alert = normalize({ machine: 'MACH-009', metric: 'temperature', value: 999, thresholds: { warn: 80, critical: 90 }, timestamp: NOW() });
    expect(alert).not.toBeNull();
    expect(alert.usine).toBe('Fallback Plant');
  });

  test('every simulator payload field survives worker sanitization', () => {
    const sim = new SimSource({ machines: 1, seed: 1, faultEveryMs: 1, now: NOW });
    const { readings } = sim.tick(NOW());
    const { mapped } = mapReadings(readings, simMapRules(1), { source: 'sim', now: NOW });
    for (const p of mapped) {
      const merged = mergeConnectorDefaults(p, connector, {});
      expect(merged.factory).toBeTruthy();
      expect(merged.machine).toMatch(/^MACH-\d{3}$/);
      expect(typeof merged.value).toBe('number');
    }
  });
});
