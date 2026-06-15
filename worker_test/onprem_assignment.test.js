import { describe, test, expect } from '@jest/globals';
import { buildSupStats, scoreSupervisor } from '../cloudflare_worker.js';
import { MemoryStore } from '../deploy/onprem/worker-runner/store.mjs';
import {
  isActiveSupervisor, eligibleSupervisors, runAssignmentCycle,
} from '../deploy/onprem/worker-runner/assignment.mjs';

const scoring = { buildSupStats, scoreSupervisor };
const NOW = Date.UTC(2026, 5, 15, 9, 0, 0);

describe('isActiveSupervisor', () => {
  test('accepts active supervisors, rejects admins/inactive', () => {
    expect(isActiveSupervisor({ uid: 'a', role: 'supervisor', active: true })).toBe(true);
    expect(isActiveSupervisor({ uid: 'b', role: 'supervisor', status: 'online' })).toBe(true);
    expect(isActiveSupervisor({ uid: 'c', role: 'admin', active: true })).toBe(false);
    expect(isActiveSupervisor({ uid: 'd', role: 'supervisor' })).toBe(false);
  });
});

describe('eligibleSupervisors', () => {
  const users = [
    { uid: 's1', role: 'supervisor', usine: 'A', active: true },
    { uid: 's2', role: 'supervisor', usine: 'B', active: true },
    { uid: 's3', role: 'supervisor', usine: 'A', active: true },
  ];
  test('filters by factory and excludes busy supervisors', () => {
    expect(eligibleSupervisors({ usine: 'A' }, users, { s3: 1 }).map((u) => u.uid)).toEqual(['s1']);
  });
});

describe('runAssignmentCycle', () => {
  test('assigns an available alert to an eligible same-factory supervisor', async () => {
    const store = new MemoryStore({
      users: [
        { uid: 's1', role: 'supervisor', usine: 'A', active: true, firstName: 'Sam', lastName: 'One' },
        { uid: 's2', role: 'supervisor', usine: 'B', active: true },
      ],
      alerts: [{ id: 'al1', status: 'disponible', usine: 'A', type: 'qualite', convoyeur: 1, poste: 1 }],
    });
    const res = await runAssignmentCycle(store, scoring, NOW);
    expect(res.assigned).toBe(1);
    const a = (await store.listAlerts())[0];
    expect(a.superviseurId).toBe('s1');
    expect(a.status).toBe('en_cours');
  });

  test('assigns nothing when no eligible supervisor in the factory', async () => {
    const store = new MemoryStore({
      users: [{ uid: 's2', role: 'supervisor', usine: 'B', active: true }],
      alerts: [{ id: 'al1', status: 'disponible', usine: 'A', type: 'qualite', convoyeur: 1, poste: 1 }],
    });
    expect((await runAssignmentCycle(store, scoring, NOW)).assigned).toBe(0);
  });

  test('one supervisor is not double-assigned within a cycle', async () => {
    const store = new MemoryStore({
      users: [{ uid: 's1', role: 'supervisor', usine: 'A', active: true }],
      alerts: [
        { id: 'al1', status: 'disponible', usine: 'A', type: 'qualite', convoyeur: 1, poste: 1 },
        { id: 'al2', status: 'disponible', usine: 'A', type: 'maintenance', convoyeur: 2, poste: 2 },
      ],
    });
    expect((await runAssignmentCycle(store, scoring, NOW)).assigned).toBe(1);
  });
});
