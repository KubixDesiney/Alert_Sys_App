// Integration tests for the on-prem ingestion pipeline:
// canonical payload -> validation -> dedup/storm guard -> PocketBase-shaped
// store -> assignment cycle -> LAN SSE notification delivery.
import { describe, test, expect, jest } from '@jest/globals';
import { buildSupStats, scoreSupervisor } from '../cloudflare_worker.js';
import { MemoryStore } from '../deploy/onprem/worker-runner/store.mjs';
import { DedupGuard, dedupKeyFor } from '../deploy/onprem/worker-runner/dedup.mjs';
import {
  validateCanonicalAlert, canonicalToAlertRecord, ingestAlert, nextAlertNumber,
} from '../deploy/onprem/worker-runner/ingest.mjs';
import { runAssignmentCycle } from '../deploy/onprem/worker-runner/assignment.mjs';
import { runEscalationCycle } from '../deploy/onprem/worker-runner/escalation.mjs';
import {
  SseHub, recipientsForNewAlert,
} from '../deploy/onprem/worker-runner/notifications.mjs';

const scoring = { buildSupStats, scoreSupervisor };
const NOW = Date.UTC(2026, 6, 11, 9, 0, 0);

const payload = (over = {}) => ({
  factory: 'Usine A',
  line: 2,
  station: 3,
  machine: 'MACH-007',
  metric: 'temperature',
  value: 92.5,
  severity: 'critical',
  type: 'maintenance',
  description: 'Bearing temp above threshold',
  timestamp: new Date(NOW).toISOString(),
  source: 'edge-gateway',
  ...over,
});

/** Minimal fake SSE response object accepted by SseHub. */
function fakeClient() {
  const written = [];
  return {
    written,
    handlers: {},
    write(chunk) { written.push(String(chunk)); },
    on(ev, fn) { this.handlers[ev] = fn; },
  };
}

describe('validateCanonicalAlert', () => {
  test('normalizes a full payload', () => {
    const v = validateCanonicalAlert(payload());
    expect(v.ok).toBe(true);
    expect(v.normalized).toMatchObject({
      factory: 'Usine A', line: 2, station: 3, machine: 'MACH-007',
      severity: 'critical', type: 'maintenance', source: 'edge-gateway',
    });
  });

  test('rejects missing factory/type and bad timestamps', () => {
    expect(validateCanonicalAlert({ type: 'x' }).ok).toBe(false);
    expect(validateCanonicalAlert({ factory: 'A' }).ok).toBe(false);
    const bad = validateCanonicalAlert(payload({ timestamp: 'yesterday-ish' }));
    expect(bad.ok).toBe(false);
    expect(bad.errors.join(' ')).toContain('ISO-8601');
  });

  test('accepts firebase-style field aliases (usine/convoyeur/poste)', () => {
    const v = validateCanonicalAlert({
      usine: 'Usine B', convoyeur: 1, poste: 4, type: 'qualite',
    });
    expect(v.ok).toBe(true);
    expect(v.normalized.factory).toBe('Usine B');
    expect(v.normalized.line).toBe(1);
    expect(v.normalized.station).toBe(4);
  });
});

describe('canonicalToAlertRecord', () => {
  test('produces the same field shape the Flutter app writes', () => {
    const rec = canonicalToAlertRecord(
      validateCanonicalAlert(payload()).normalized,
      { alertNumber: 7, now: new Date(NOW) },
    );
    expect(rec).toMatchObject({
      type: 'maintenance',
      usine: 'Usine A',
      convoyeur: 2,
      poste: 3,
      alertNumber: 7,
      adresse: 'Usine_A_C2_P3',
      assetId: 'MACH-007',
      source: 'edge-gateway',
      status: 'disponible',
      isCritical: true,
    });
    expect(rec.comments).toEqual([]);
  });
});

describe('DedupGuard', () => {
  test('same signal within the window is a duplicate; different station is not', () => {
    const g = new DedupGuard({ dedupWindowMs: 60_000 });
    const a = { usine: 'A', convoyeur: 1, poste: 1, type: 'qualite', source: 's' };
    expect(g.check(a, NOW).action).toBe('accept');
    expect(g.check(a, NOW + 10_000).action).toBe('duplicate');
    expect(g.check({ ...a, poste: 2 }, NOW + 10_000).action).toBe('accept');
    // window elapsed -> accepted again
    expect(g.check(a, NOW + 61_000).action).toBe('accept');
  });

  test('per-source storm suppression reports the transition exactly once', () => {
    const g = new DedupGuard({ dedupWindowMs: 1, maxPerMinutePerSource: 3, maxPerMinuteGlobal: 100 });
    for (let i = 0; i < 3; i++) {
      expect(g.check({ usine: 'A', poste: i, type: 't', source: 'plc1' }, NOW + i * 10).action).toBe('accept');
    }
    const fourth = g.check({ usine: 'A', poste: 99, type: 't', source: 'plc1' }, NOW + 40);
    expect(fourth.action).toBe('suppress');
    expect(fourth.stormStarted).toBe('plc1');
    const fifth = g.check({ usine: 'A', poste: 98, type: 't', source: 'plc1' }, NOW + 50);
    expect(fifth.action).toBe('suppress');
    expect(fifth.stormStarted).toBeUndefined();
    // other sources are unaffected
    expect(g.check({ usine: 'A', poste: 1, type: 'x', source: 'plc2' }, NOW + 60).action).toBe('accept');
  });

  test('global ceiling suppresses regardless of source', () => {
    const g = new DedupGuard({ dedupWindowMs: 1, maxPerMinuteGlobal: 2, maxPerMinutePerSource: 100 });
    expect(g.check({ usine: 'A', poste: 1, type: 't', source: 'a' }, NOW).action).toBe('accept');
    expect(g.check({ usine: 'A', poste: 2, type: 't', source: 'b' }, NOW + 1).action).toBe('accept');
    const third = g.check({ usine: 'A', poste: 3, type: 't', source: 'c' }, NOW + 2);
    expect(third.action).toBe('suppress');
    expect(third.stormStarted).toBe('');
  });

  test('dedupKeyFor is case/whitespace insensitive', () => {
    expect(dedupKeyFor({ usine: ' Usine A ', convoyeur: 1, poste: 2, type: 'QUALITE' }))
      .toBe(dedupKeyFor({ usine: 'usine a', convoyeur: '1', poste: '2', type: 'qualite' }));
  });
});

describe('ingestAlert end-to-end', () => {
  test('creates the alert, allocates a number and audits', async () => {
    const store = new MemoryStore({ alerts: [{ id: 'old', alertNumber: 41, status: 'validee' }] });
    const audits = [];
    const result = await ingestAlert(store, new DedupGuard(), payload(), {
      now: NOW,
      audit: async (action, fields) => audits.push({ action, ...fields }),
    });
    expect(result.status).toBe('created');
    const created = (await store.listAlerts()).find((a) => a.id === result.id);
    expect(created.alertNumber).toBe(42);
    expect(created.isCritical).toBe(true);
    expect(audits.map((a) => a.action)).toContain('ingest.created');
  });

  test('invalid payloads are rejected without touching the store', async () => {
    const store = new MemoryStore();
    const result = await ingestAlert(store, new DedupGuard(), { type: 'x' }, { now: NOW });
    expect(result.status).toBe('invalid');
    expect(result.errors.length).toBeGreaterThan(0);
    expect((await store.listAlerts()).length).toBe(0);
  });

  test('duplicates are absorbed', async () => {
    const store = new MemoryStore();
    const guard = new DedupGuard();
    expect((await ingestAlert(store, guard, payload(), { now: NOW })).status).toBe('created');
    expect((await ingestAlert(store, guard, payload(), { now: NOW + 1000 })).status).toBe('duplicate');
    expect((await store.listAlerts()).length).toBe(1);
  });

  test('a storm creates ONE critical meta-alert then suppresses silently', async () => {
    const store = new MemoryStore();
    const guard = new DedupGuard({ dedupWindowMs: 1, maxPerMinutePerSource: 2, maxPerMinuteGlobal: 100 });
    await ingestAlert(store, guard, payload({ station: 1 }), { now: NOW });
    await ingestAlert(store, guard, payload({ station: 2 }), { now: NOW + 1 });
    const r3 = await ingestAlert(store, guard, payload({ station: 3 }), { now: NOW + 2 });
    const r4 = await ingestAlert(store, guard, payload({ station: 4 }), { now: NOW + 3 });

    expect(r3.status).toBe('suppressed');
    expect(r3.stormAlertId).toBeDefined();
    expect(r4.status).toBe('suppressed');
    expect(r4.stormAlertId).toBeUndefined();

    const alerts = await store.listAlerts();
    expect(alerts.length).toBe(3); // 2 real + 1 storm meta-alert
    const storm = alerts.find((a) => a.id === r3.stormAlertId);
    expect(storm.isCritical).toBe(true);
    expect(storm.description).toContain('ALERT STORM');
    expect(storm.source).toBe('worker-runner');
  });

  test('nextAlertNumber survives an empty store', async () => {
    expect(await nextAlertNumber(new MemoryStore())).toBe(1);
  });
});

describe('full pipeline: ingest -> assign -> escalate -> notify', () => {
  test('an ingested alert is assigned to the right supervisor and the SSE client hears about it', async () => {
    const store = new MemoryStore({
      users: [
        { uid: 's1', role: 'supervisor', usine: 'Usine A', active: true, firstName: 'Sam', lastName: 'One' },
        { uid: 's2', role: 'supervisor', usine: 'Usine B', active: true },
        { uid: 'pm', role: 'production_manager', active: true },
      ],
    });
    const hub = new SseHub();
    const supClient = fakeClient();
    hub.connect('s1', supClient);

    // 1. ingest
    const ingest = await ingestAlert(store, new DedupGuard(), payload({ severity: 'normal' }), { now: NOW });
    expect(ingest.status).toBe('created');

    // 2. new-alert fan-out goes to free same-factory supervisors only
    const users = await store.listUsers();
    const created = (await store.listAlerts()).find((a) => a.id === ingest.id);
    const recipients = recipientsForNewAlert(created, users, await store.activeCounts());
    expect(recipients).toEqual(['s1']);
    expect(hub.broadcast(recipients, { type: 'new_alert', alertId: created.id })).toBe(1);
    expect(supClient.written.join('')).toContain('"new_alert"');

    // 3. assignment picks the same supervisor (cloud-parity scoring)
    const assignment = await runAssignmentCycle(store, scoring, NOW + 60_000);
    expect(assignment.assigned).toBe(1);
    expect(assignment.decisions[0].uid).toBe('s1');

    // 4. escalation: nothing yet (just claimed) — then it fires after the SLA
    const settings = { default: { claimedMinutes: 30 } };
    store.escalationSettings = settings;
    const claimed = (await store.listAlerts()).find((a) => a.id === ingest.id);
    claimed.takenAtTimestamp = new Date(NOW + 60_000).toISOString();
    expect((await runEscalationCycle(store, NOW + 5 * 60_000)).escalated).toBe(0);
    const late = await runEscalationCycle(store, NOW + 40 * 60_000);
    expect(late.escalated).toBe(1);
    expect((await store.listAlerts()).find((a) => a.id === ingest.id).isEscalated).toBe(true);
  });

  test('SSE heartbeat pings connected clients and stops cleanly', () => {
    jest.useFakeTimers();
    try {
      const hub = new SseHub();
      const client = fakeClient();
      hub.connect('u1', client);
      hub.startHeartbeat(1000);
      jest.advanceTimersByTime(3500);
      expect(client.written.filter((w) => w.includes(': ping')).length).toBe(3);
      hub.stopHeartbeat();
      jest.advanceTimersByTime(5000);
      expect(client.written.filter((w) => w.includes(': ping')).length).toBe(3);
    } finally {
      jest.useRealTimers();
    }
  });
});
