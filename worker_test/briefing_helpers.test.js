import { describe, test, expect } from '@jest/globals';
import {
  _briefingDateKey,
  _aggregateWeek,
  _typeName,
  notifTitle,
  base64UrlEncode,
  getFcmTokensForFactory,
} from '../cloudflare_worker.js';

describe('_briefingDateKey', () => {
  test('formats yyyy-mm-dd in UTC', () => {
    const d = new Date(Date.UTC(2026, 4, 3, 8));
    expect(_briefingDateKey(d)).toBe('2026-05-03');
  });

  test('zero-pads single-digit days and months', () => {
    const d = new Date(Date.UTC(2026, 0, 7, 0));
    expect(_briefingDateKey(d)).toBe('2026-01-07');
  });
});

describe('_typeName', () => {
  test('maps known alert types to human labels', () => {
    expect(_typeName('qualite')).toBe('Quality');
    expect(_typeName('maintenance')).toBe('Maintenance');
    expect(_typeName('defaut_produit')).toBe('Damaged Product');
    expect(_typeName('manque_ressource')).toBe('Resource Deficiency');
  });

  test('returns the raw value for unknown types', () => {
    expect(_typeName('something_new')).toBe('something_new');
  });
});

describe('_aggregateWeek', () => {
  const recent = (overrides) => ({
    type: 'qualite',
    usine: 'Usine A',
    timestamp: new Date(Date.now() - 86400000).toISOString(),
    ...overrides,
  });

  test('returns zero stats for empty input', () => {
    const s = _aggregateWeek({});
    expect(s.total).toBe(0);
    expect(s.solved).toBe(0);
    expect(s.avgResolutionMin).toBe(0);
  });

  test('separates solved / pending / in-progress counts', () => {
    const s = _aggregateWeek({
      a1: recent({ status: 'validee', elapsedTime: 10 }),
      a2: recent({ status: 'en_cours' }),
      a3: recent({ status: 'disponible' }),
    });
    expect(s.solved).toBe(1);
    expect(s.inProgress).toBe(1);
    expect(s.pending).toBe(1);
    expect(s.total).toBe(3);
  });

  test('records fastest and slowest resolutions', () => {
    const s = _aggregateWeek({
      a1: recent({ status: 'validee', elapsedTime: 5 }),
      a2: recent({ status: 'validee', elapsedTime: 30 }),
      a3: recent({ status: 'validee', elapsedTime: 10 }),
    });
    expect(s.fastestMin).toBe(5);
    expect(s.slowestMin).toBe(30);
    expect(s.avgResolutionMin).toBe(15);
  });

  test('counts critical and AI-assigned tags', () => {
    const s = _aggregateWeek({
      a1: recent({ status: 'validee', elapsedTime: 5, isCritical: true }),
      a2: recent({ status: 'validee', elapsedTime: 5, aiAssigned: true }),
    });
    expect(s.critical).toBe(1);
    expect(s.aiAssigned).toBe(1);
  });

  test('skips alerts older than a week', () => {
    const old = new Date(Date.now() - 30 * 86400000).toISOString();
    const s = _aggregateWeek({
      a1: recent({ status: 'validee', elapsedTime: 5, timestamp: old }),
    });
    expect(s.total).toBe(0);
  });
});

describe('notifTitle', () => {
  test('maps known types', () => {
    expect(notifTitle('ai_assigned')).toBe('AI Assignment');
    expect(notifTitle('collaboration_request')).toBe('Collaboration request');
    expect(notifTitle('help_request')).toBe('Help request');
    expect(notifTitle('alert_suspended')).toBe('Alert suspended');
  });

  test('groups all collaboration_* update variants', () => {
    expect(notifTitle('collaboration_approved')).toBe('Collaboration update');
    expect(notifTitle('collaboration_rejected')).toBe('Collaboration update');
    expect(notifTitle('collaboration_removed')).toBe('Collaboration update');
  });

  test('falls back to AlertSys for unknown / null', () => {
    expect(notifTitle('whatever')).toBe('AlertSys');
    expect(notifTitle(null)).toBe('AlertSys');
    expect(notifTitle(undefined)).toBe('AlertSys');
  });
});

describe('base64UrlEncode', () => {
  test('encodes byte arrays to URL-safe base64 (no padding)', () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const out = base64UrlEncode(bytes);
    expect(out).not.toContain('=');
    expect(out).not.toContain('+');
    expect(out).not.toContain('/');
  });

  test('encodes strings consistently', () => {
    const out = base64UrlEncode('hello');
    expect(typeof out).toBe('string');
    expect(out.length).toBeGreaterThan(0);
  });
});

describe('getFcmTokensForFactory', () => {
  const usersMap = {
    sup1: {
      role: 'supervisor',
      usine: 'Usine A',
      fcmToken: 'tok-sup1',
    },
    sup2: {
      role: 'supervisor',
      usine: 'Usine A',
      fcmToken: 'tok-sup2',
    },
    sup3: {
      role: 'supervisor',
      usine: 'Usine B',
      fcmToken: 'tok-sup3',
    },
    admin1: {
      role: 'admin',
      usine: 'Usine Z',
      fcmToken: 'tok-admin1',
    },
    op: {
      role: 'operator',
      usine: 'Usine A',
      fcmToken: 'tok-op',
    },
    noToken: {
      role: 'supervisor',
      usine: 'Usine A',
    },
  };

  test('routes to supervisors of the same factory plus all admins', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, {});
    expect(tokens).toEqual(expect.arrayContaining([
      'tok-sup1',
      'tok-sup2',
      'tok-admin1',
    ]));
    expect(tokens).not.toContain('tok-sup3');
  });

  test('excludes operators (any non-admin/supervisor role)', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, {});
    expect(tokens).not.toContain('tok-op');
  });

  test('excludes users without an fcmToken', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, {});
    expect(tokens.every((t) => typeof t === 'string' && t.length > 0)).toBe(
      true,
    );
  });

  test('skips supervisors actively handling another alert', () => {
    const alertsMap = {
      a1: { status: 'en_cours', superviseurId: 'sup1' },
    };
    const tokens = getFcmTokensForFactory('Usine A', usersMap, alertsMap);
    expect(tokens).not.toContain('tok-sup1');
    expect(tokens).toContain('tok-sup2');
  });

  test('returns admin tokens even when no supervisors match', () => {
    const tokens = getFcmTokensForFactory(
      'Some Other Factory',
      usersMap,
      {},
    );
    expect(tokens).toContain('tok-admin1');
  });
});
