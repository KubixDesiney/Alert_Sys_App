import { describe, test, expect } from '@jest/globals';
import {
  rtdbAlertToRecord, rtdbUserToRecord, rtdbActiveToRecords,
  rtdbNotificationsToRecords, rtdbEscalationToRecord, migrate,
} from '../deploy/onprem/pocketbase/migrate_rtdb_to_pocketbase.mjs';

describe('rtdbAlertToRecord', () => {
  test('coerces types and maps fields', () => {
    const r = rtdbAlertToRecord({
      alertNumber: '42', type: 'qualite', usine: 'A', convoyeur: '3', poste: 7,
      status: 'en_cours', superviseurId: 'u1', isCritical: 'true', timestamp: 1717230000000,
      reason: 'belt', elapsedTime: '15',
    });
    expect(r.alertNumber).toBe(42);
    expect(r.convoyeur).toBe(3);
    expect(r.poste).toBe(7);
    expect(r.isCritical).toBe(true);
    expect(r.timestamp).toBe('1717230000000');
    expect(r.resolutionReason).toBe('belt');
    expect(r.elapsedTime).toBe(15);
  });
});

describe('rtdbUserToRecord', () => {
  test('lowercases role and derives active', () => {
    expect(rtdbUserToRecord({ email: 'a@b.com', role: 'Admin', isActive: true }))
      .toMatchObject({ email: 'a@b.com', role: 'admin', active: true });
    expect(rtdbUserToRecord({ status: 'active' }).active).toBe(true);
    expect(rtdbUserToRecord({}).active).toBe(false);
  });
});

describe('rtdbActiveToRecords / notifications', () => {
  test('flattens supervisor_active_alerts', () => {
    expect(rtdbActiveToRecords({ u1: { alertId: 'al1', status: 'en_cours' } }))
      .toEqual([{ supervisorId: 'u1', alertId: 'al1', status: 'en_cours' }]);
  });
  test('flattens nested notifications', () => {
    const r = rtdbNotificationsToRecords({ u1: { n1: { notifType: 'new_alert', alertId: 'al1', pushSent: true } } });
    expect(r).toEqual([{ recipientId: 'u1', notifType: 'new_alert', alertId: 'al1', pushSent: true, createdAt: '' }]);
  });
});

describe('rtdbEscalationToRecord', () => {
  test('wraps settings in a record', () => {
    const s = { qualite: { unclaimedMinutes: 15 } };
    expect(rtdbEscalationToRecord(s)).toEqual({ settings: s });
  });
});

describe('migrate (dry-run)', () => {
  test('counts every node without network calls', async () => {
    const input = {
      alerts: { a1: { type: 'qualite' }, a2: { type: 'maintenance' } },
      users: { u1: { email: 'a@b.com' }, u2: { firstName: 'NoEmail' } },
      supervisor_active_alerts: { u1: { alertId: 'a1' } },
      notifications: { u1: { n1: { notifType: 'new_alert' } } },
      escalation_settings: { default: { unclaimedMinutes: 30 } },
    };
    const counts = await migrate(input, 'http://pb', 'T', { dryRun: true, log: () => {} });
    expect(counts.alerts).toBe(2);
    expect(counts.users).toBe(1); // u2 skipped (no email)
    expect(counts.supervisor_active_alerts).toBe(1);
    expect(counts.notifications).toBe(1);
    expect(counts.escalation_settings).toBe(1);
  });
});
