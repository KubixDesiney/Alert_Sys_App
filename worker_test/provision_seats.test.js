import { describe, test, expect } from '@jest/globals';
import {
  parseArgs,
  validateFlags,
  parseFullName,
  collectSeats,
  validateDeliveryPair,
  buildUserRecord,
  buildPrivateRecord,
  generatePassword,
  buildSeatSummary,
  buildDeliverySummary,
  redactSeatSummary,
  postActivationPayload,
  planLines,
  SEAT_TYPES,
  DEFAULT_USINE,
} from '../tool/provision_seats.mjs';

const seatFlags = {
  tenant: 'NSW#7K2F',
  company: 'Nagati Steel Works',
  'owner-email': 'owner@nsw.tn',
  'owner-name': 'Amine Ben Salah',
  'pm-email': 'pm@nsw.tn',
  'pm-name': 'Sonia Trabelsi',
  'supervisor-email': 'sup@nsw.tn',
  'supervisor-name': 'Karim Aloui',
};

describe('parseArgs', () => {
  test('parses space-separated values', () => {
    expect(parseArgs(['--tenant', 'NSW#7K2F', '--company', 'Nagati Steel Works'])).toEqual({
      tenant: 'NSW#7K2F',
      company: 'Nagati Steel Works',
    });
  });

  test('parses --key=value form', () => {
    expect(parseArgs(['--pm-email=pm@nsw.tn'])).toEqual({ 'pm-email': 'pm@nsw.tn' });
  });

  test('treats a trailing flag with no value as boolean true', () => {
    expect(parseArgs(['--execute'])).toEqual({ execute: true });
  });

  test('treats a flag followed by another flag as boolean true', () => {
    expect(parseArgs(['--execute', '--tenant', 'X'])).toEqual({ execute: true, tenant: 'X' });
  });
});

describe('validateFlags', () => {
  test('accepts tenant + company', () => {
    expect(validateFlags({ tenant: 'T', company: 'C' })).toEqual([]);
  });

  test('reports every missing required flag', () => {
    expect(validateFlags({})).toEqual(['tenant', 'company']);
  });

  test('a boolean-only flag counts as missing (no value supplied)', () => {
    expect(validateFlags({ tenant: true, company: 'C' })).toEqual(['tenant']);
  });
});

describe('parseFullName', () => {
  test('splits first and last name', () => {
    expect(parseFullName('Amine Ben Salah')).toEqual({ firstName: 'Amine', lastName: 'Ben Salah' });
  });

  test('single word becomes firstName only', () => {
    expect(parseFullName('Karim')).toEqual({ firstName: 'Karim', lastName: '' });
  });

  test('empty input yields empty parts', () => {
    expect(parseFullName('   ')).toEqual({ firstName: '', lastName: '' });
  });
});

describe('SEAT_TYPES', () => {
  test('maps the three delivered seats to the roles database.rules.json enforces', () => {
    expect(SEAT_TYPES.map((s) => [s.key, s.role])).toEqual([
      ['owner', 'SuperAdmin'],
      ['pm', 'admin'],
      ['supervisor', 'supervisor'],
    ]);
  });
});

describe('collectSeats', () => {
  test('collects all three seats when fully specified', () => {
    const { seats, errors } = collectSeats(seatFlags);
    expect(errors).toEqual([]);
    expect(seats.map((s) => s.key)).toEqual(['owner', 'pm', 'supervisor']);
    expect(seats.find((s) => s.key === 'pm')).toMatchObject({
      role: 'admin', email: 'pm@nsw.tn', name: 'Sonia Trabelsi',
    });
  });

  test('supports provisioning a subset', () => {
    const { seats, errors } = collectSeats({
      tenant: 'T', company: 'C', 'supervisor-email': 'sup@nsw.tn', 'supervisor-name': 'Karim Aloui',
    });
    expect(errors).toEqual([]);
    expect(seats.map((s) => s.key)).toEqual(['supervisor']);
  });

  test('rejects half a seat rather than silently skipping it', () => {
    const { seats, errors } = collectSeats({ tenant: 'T', company: 'C', 'pm-email': 'pm@nsw.tn' });
    expect(seats).toEqual([]);
    expect(errors[0]).toMatch(/pm: needs both/);
  });

  test('reports when no seats were requested at all', () => {
    const { seats, errors } = collectSeats({ tenant: 'T', company: 'C' });
    expect(seats).toEqual([]);
    expect(errors[0]).toMatch(/no seats requested/);
  });

  test('rejects reusing one Auth email for multiple roles', () => {
    const { errors } = collectSeats({
      ...seatFlags,
      'supervisor-email': 'PM@NSW.TN',
    });
    expect(errors.join(' ')).toMatch(/already assigned/i);
  });

  test('automatic delivery requires both PM and supervisor', () => {
    expect(validateDeliveryPair(collectSeats(seatFlags).seats)).toEqual([]);
    expect(validateDeliveryPair(collectSeats({
      tenant: 'T',
      company: 'C',
      'pm-email': 'pm@nsw.tn',
      'pm-name': 'PM User',
    }).seats).join(' ')).toMatch(/supervisor/);
  });
});

describe('buildUserRecord', () => {
  test('writes the role, names, tenant and usine — and never the email', () => {
    const rec = buildUserRecord({
      name: 'Sonia Trabelsi', company: 'Nagati Steel Works', tenantCode: 'NSW#7K2F',
      role: 'admin', usine: 'Usine B',
    });
    expect(rec).toEqual({
      role: 'admin',
      firstName: 'Sonia',
      lastName: 'Trabelsi',
      active: true,
      tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel Works',
      usine: 'Usine B',
    });
    expect(rec.email).toBeUndefined();
  });

  test('falls back to the default usine', () => {
    const rec = buildUserRecord({ name: 'A B', company: 'C', tenantCode: 'T', role: 'supervisor' });
    expect(rec.usine).toBe(DEFAULT_USINE);
  });
});

describe('buildPrivateRecord', () => {
  test('carries the email only', () => {
    expect(buildPrivateRecord({ email: 'pm@nsw.tn' })).toEqual({ email: 'pm@nsw.tn' });
  });
});

describe('generatePassword', () => {
  test('is long and url-safe', () => {
    const pw = generatePassword();
    expect(pw.length).toBeGreaterThanOrEqual(30);
    expect(pw).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  test('is different every time', () => {
    expect(generatePassword()).not.toEqual(generatePassword());
  });
});

describe('buildSeatSummary', () => {
  test('keeps the WF3-compatible fields and adds seat metadata', () => {
    const seat = SEAT_TYPES.find((s) => s.key === 'pm');
    const summary = buildSeatSummary({
      seat, uid: 'uid-1', email: 'pm@nsw.tn', tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel Works', activationLink: 'https://link', consoleUrl: 'https://console',
    });
    expect(summary).toMatchObject({
      seat: 'pm',
      role: 'admin',
      seatLabel: 'Production Manager',
      uid: 'uid-1',
      email: 'pm@nsw.tn',
      tenantCode: 'NSW#7K2F',
      activationLink: 'https://link',
      consoleUrl: 'https://console',
    });
    expect(summary.expiresNote).toMatch(/single-use/i);
  });
});

describe('buildDeliverySummary', () => {
  test('counts the seats and timestamps the delivery', () => {
    const out = buildDeliverySummary({
      tenantCode: 'NSW#7K2F', company: 'Nagati Steel Works', seats: [{ seat: 'owner' }, { seat: 'pm' }],
    });
    expect(out.seatCount).toBe(2);
    expect(out.tenantCode).toBe('NSW#7K2F');
    expect(Date.parse(out.generatedAt)).not.toBeNaN();
  });

  test('redacted delivery artifacts never contain email or activation links', () => {
    const safe = redactSeatSummary({
      seat: 'pm',
      role: 'admin',
      seatLabel: 'Production Manager',
      uid: 'uid-1',
      email: 'pm@nsw.tn',
      tenantCode: 'T#1',
      company: 'Company',
      activationLink: 'https://secret-link',
      consoleUrl: 'https://tenant.example',
    });
    expect(safe.activationDelivered).toBe(true);
    expect(JSON.stringify(safe)).not.toContain('pm@nsw.tn');
    expect(JSON.stringify(safe)).not.toContain('secret-link');
  });
});

describe('planLines', () => {
  test('lists every seat with its role, and never leaks a secret', () => {
    const lines = planLines(seatFlags).join('\n');
    expect(lines).toContain('tenantCode:  NSW#7K2F');
    expect(lines).toContain('role=SuperAdmin');
    expect(lines).toContain('role=admin');
    expect(lines).toContain('role=supervisor');
    expect(lines).not.toContain('owner@nsw.tn');
    expect(lines).not.toMatch(/password/i);
  });

  test('surfaces collection errors in the plan', () => {
    const lines = planLines({ tenant: 'T', company: 'C', 'pm-name': 'Only Name' }).join('\n');
    expect(lines).toMatch(/ERROR: pm: needs both/);
  });
});

describe('activation delivery', () => {
  test('retries non-2xx responses and authenticates the webhook', async () => {
    const requests = [];
    const statuses = [503, 202];
    const result = await postActivationPayload('https://n8n.example/activate', { activationLink: 'secret' }, {
      authToken: 'token',
      fetchImpl: async (_url, init) => {
        requests.push(init);
        return { ok: statuses[0] < 300, status: statuses.shift() };
      },
      sleep: async () => {},
    });
    expect(result).toMatchObject({ ok: true, status: 202, attempts: 2 });
    expect(requests[0].headers.Authorization).toBe('Bearer token');
  });

  test('returns a hard failure after bounded attempts', async () => {
    const result = await postActivationPayload('https://n8n.example/activate', {}, {
      fetchImpl: async () => ({ ok: false, status: 500 }),
      sleep: async () => {},
      attempts: 2,
    });
    expect(result.ok).toBe(false);
    expect(result.attempts).toBe(2);
  });
});
