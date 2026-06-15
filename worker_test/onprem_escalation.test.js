import { describe, test, expect } from '@jest/globals';
import { MemoryStore } from '../deploy/onprem/worker-runner/store.mjs';
import { findEscalations, minutesSince, runEscalationCycle } from '../deploy/onprem/worker-runner/escalation.mjs';
import {
  recipientsForNewAlert, recipientsForEscalation, recipientsForAssignment, SseHub,
} from '../deploy/onprem/worker-runner/notifications.mjs';

const NOW = 1_000_000_000_000;
const minsAgo = (m) => NOW - m * 60000;
const settings = { qualite: { unclaimedMinutes: 15, claimedMinutes: 60 }, default: { unclaimedMinutes: 30 } };

describe('minutesSince', () => {
  test('handles epoch ms, ISO strings, and junk', () => {
    expect(minutesSince(minsAgo(10), NOW)).toBeCloseTo(10, 5);
    expect(minutesSince(new Date(minsAgo(10)).toISOString(), NOW)).toBeCloseTo(10, 0);
    expect(minutesSince('not-a-date', NOW)).toBeNull();
    expect(minutesSince(undefined, NOW)).toBeNull();
  });
});

describe('findEscalations', () => {
  test('escalates an unclaimed alert past its threshold', () => {
    const r = findEscalations([{ id: 'a', status: 'disponible', type: 'qualite', timestamp: minsAgo(20) }], settings, NOW);
    expect(r).toEqual([{ id: 'a', reason: 'Unclaimed for 20 minutes' }]);
  });
  test('does not escalate before the threshold', () => {
    expect(findEscalations([{ id: 'a', status: 'disponible', type: 'qualite', timestamp: minsAgo(5) }], settings, NOW)).toEqual([]);
  });
  test('escalates a claimed-but-unresolved alert', () => {
    const r = findEscalations([{ id: 'b', status: 'en_cours', type: 'qualite', takenAtTimestamp: minsAgo(90) }], settings, NOW);
    expect(r[0].id).toBe('b');
    expect(r[0].reason).toMatch(/Claimed but not resolved/);
  });
  test('uses default threshold when type has none', () => {
    expect(findEscalations([{ id: 'c', status: 'disponible', type: 'unknown', timestamp: minsAgo(31) }], settings, NOW).length).toBe(1);
  });
  test('skips already-escalated and resolved alerts', () => {
    expect(findEscalations([
      { id: 'd', status: 'disponible', type: 'qualite', timestamp: minsAgo(99), isEscalated: true },
      { id: 'e', status: 'validee', type: 'qualite', timestamp: minsAgo(99) },
    ], settings, NOW)).toEqual([]);
  });
});

describe('runEscalationCycle', () => {
  test('marks escalated alerts in the store', async () => {
    const store = new MemoryStore({
      escalationSettings: settings,
      alerts: [{ id: 'a', status: 'disponible', type: 'qualite', timestamp: minsAgo(40) }],
    });
    const res = await runEscalationCycle(store, NOW);
    expect(res.escalated).toBe(1);
    expect((await store.listAlerts())[0].isEscalated).toBe(true);
  });
});

describe('notification targeting', () => {
  const users = [
    { uid: 's1', role: 'supervisor', usine: 'A', active: true },
    { uid: 's2', role: 'supervisor', usine: 'A', active: true },
    { uid: 's3', role: 'supervisor', usine: 'B', active: true },
    { uid: 'a1', role: 'admin', usine: 'A', active: true },
  ];
  test('new alert -> active same-factory supervisors, excluding busy', () => {
    expect(recipientsForNewAlert({ usine: 'A' }, users, { s2: 1 })).toEqual(['s1']);
  });
  test('escalation -> admins + the assigned supervisor', () => {
    expect(recipientsForEscalation({ usine: 'A', superviseurId: 's1' }, users).sort()).toEqual(['a1', 's1']);
  });
  test('assignment -> the assigned supervisor only', () => {
    expect(recipientsForAssignment({ superviseurId: 's2' })).toEqual(['s2']);
  });
});

describe('SseHub', () => {
  const mockRes = () => ({ writes: [], write(s) { this.writes.push(s); }, on() {} });
  test('delivers to a connected uid and broadcasts to many', () => {
    const hub = new SseHub();
    const r1 = mockRes(); const r2 = mockRes();
    hub.connect('s1', r1); hub.connect('s2', r2);
    expect(hub.deliver('s1', { type: 'assignment' })).toBe(1);
    expect(r1.writes[0]).toContain('"type":"assignment"');
    expect(hub.broadcast(['s1', 's2'], { type: 'escalation' })).toBe(2);
    expect(hub.connectedCount()).toBe(2);
  });
  test('returns 0 for an unknown uid', () => {
    expect(new SseHub().deliver('nobody', {})).toBe(0);
  });
});
