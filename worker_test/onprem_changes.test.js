// ChangeWatcher: the on-prem replacement for the Firebase-client notification
// side effects — the runner diffs data snapshots and emits lifecycle events.
import { describe, test, expect } from '@jest/globals';
import { ChangeWatcher } from '../deploy/onprem/worker-runner/changes.mjs';

const a = (over = {}) => ({
  id: 'al1', status: 'disponible', isCritical: false, superviseurId: '', ...over,
});

describe('ChangeWatcher', () => {
  test('first snapshot is a baseline — no event storm on boot', () => {
    const w = new ChangeWatcher();
    expect(w.diff([a(), a({ id: 'al2', isCritical: true })])).toEqual([]);
  });

  test('a new alert emits new_alert (and critical_update when born critical)', () => {
    const w = new ChangeWatcher();
    w.diff([a()]);
    const events = w.diff([a(), a({ id: 'al2', isCritical: true })]);
    expect(events.map((e) => e.type)).toEqual(['new_alert', 'critical_update']);
    expect(events[0].alert.id).toBe('al2');
  });

  test('critical flag flip emits critical_update once', () => {
    const w = new ChangeWatcher();
    w.diff([a()]);
    expect(w.diff([a({ isCritical: true })]).map((e) => e.type)).toEqual(['critical_update']);
    // steady state -> no repeat
    expect(w.diff([a({ isCritical: true })])).toEqual([]);
  });

  test('en_cours -> disponible emits alert_suspended with the previous supervisor', () => {
    const w = new ChangeWatcher();
    w.diff([a({ status: 'en_cours', superviseurId: 's1' })]);
    const events = w.diff([a({ status: 'disponible', superviseurId: '' })]);
    expect(events[0].type).toBe('alert_suspended');
    expect(events[0].previousSupervisorId).toBe('s1');
  });

  test('claim and resolve transitions are detected', () => {
    const w = new ChangeWatcher();
    w.diff([a()]);
    expect(w.diff([a({ status: 'en_cours', superviseurId: 's1' })]).map((e) => e.type))
      .toEqual(['alert_claimed']);
    expect(w.diff([a({ status: 'validee', superviseurId: 's1' })]).map((e) => e.type))
      .toEqual(['alert_resolved']);
  });
});
