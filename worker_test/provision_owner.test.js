import { describe, test, expect } from '@jest/globals';
import {
  parseArgs,
  validateFlags,
  parseFullName,
  buildUserRecord,
  buildPrivateRecord,
  generatePassword,
  buildSummary,
  planLines,
} from '../tool/provision_owner.mjs';

describe('parseArgs', () => {
  test('parses space-separated values', () => {
    expect(parseArgs(['--email', 'a@b.c', '--name', 'A B'])).toEqual({
      email: 'a@b.c',
      name: 'A B',
    });
  });

  test('parses --key=value form', () => {
    expect(parseArgs(['--tenant=NSW#7K2F'])).toEqual({ tenant: 'NSW#7K2F' });
  });

  test('treats a trailing flag with no value as boolean true', () => {
    expect(parseArgs(['--email', 'a@b.c', '--dry-run'])).toEqual({
      email: 'a@b.c',
      'dry-run': true,
    });
  });

  test('a flag immediately followed by another flag is boolean true', () => {
    expect(parseArgs(['--dry-run', '--email', 'a@b.c'])).toEqual({
      'dry-run': true,
      email: 'a@b.c',
    });
  });

  test('ignores non-flag tokens', () => {
    expect(parseArgs(['positional', '--email', 'a@b.c'])).toEqual({ email: 'a@b.c' });
  });
});

describe('validateFlags', () => {
  test('reports all required flags missing on empty input', () => {
    expect(validateFlags({})).toEqual(['email', 'name', 'company', 'tenant']);
  });

  test('reports nothing missing when all required flags have values', () => {
    expect(
      validateFlags({ email: 'a@b.c', name: 'A B', company: 'Co', tenant: 'C#AAAA' })
    ).toEqual([]);
  });

  test('a valueless boolean flag counts as missing', () => {
    expect(
      validateFlags({ email: true, name: 'A B', company: 'Co', tenant: 'C#AAAA' })
    ).toEqual(['email']);
  });
});

describe('parseFullName', () => {
  test('splits first and last name', () => {
    expect(parseFullName('Amine Nagati')).toEqual({ firstName: 'Amine', lastName: 'Nagati' });
  });

  test('keeps middle names in lastName', () => {
    expect(parseFullName('Amine Ben Nagati')).toEqual({ firstName: 'Amine', lastName: 'Ben Nagati' });
  });

  test('single-token name has empty lastName', () => {
    expect(parseFullName('Amine')).toEqual({ firstName: 'Amine', lastName: '' });
  });

  test('collapses extra whitespace', () => {
    expect(parseFullName('  Amine   Nagati  ')).toEqual({ firstName: 'Amine', lastName: 'Nagati' });
  });

  test('empty/undefined input is safe', () => {
    expect(parseFullName('')).toEqual({ firstName: '', lastName: '' });
    expect(parseFullName(undefined)).toEqual({ firstName: '', lastName: '' });
  });
});

describe('buildUserRecord', () => {
  test('shapes the RTDB users/{uid} record WITHOUT email (PII split)', () => {
    expect(
      buildUserRecord({ name: 'Amine Nagati', company: 'Nagati Steel', tenantCode: 'NSW#7K2F' })
    ).toEqual({
      role: 'SuperAdmin',
      firstName: 'Amine',
      lastName: 'Nagati',
      active: true,
      tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel',
    });
  });

  test('email is confined to the users_private record', () => {
    expect(buildPrivateRecord({ email: 'a@b.c' })).toEqual({ email: 'a@b.c' });
    expect(buildUserRecord({ name: 'A B', company: 'C', tenantCode: 'T#1111' })).not.toHaveProperty('email');
  });
});

describe('generatePassword', () => {
  test('returns a long, url-safe random string', () => {
    const pw = generatePassword();
    expect(typeof pw).toBe('string');
    expect(pw.length).toBeGreaterThanOrEqual(24);
    expect(pw).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  test('is different on every call', () => {
    expect(generatePassword()).not.toBe(generatePassword());
  });
});

describe('buildSummary', () => {
  test('shapes exactly the documented summary fields', () => {
    expect(
      buildSummary({
        uid: 'uid123',
        email: 'a@b.c',
        tenantCode: 'NSW#7K2F',
        activationLink: 'https://example.com/activate',
        expiresNote: 'expires soon',
      })
    ).toEqual({
      uid: 'uid123',
      email: 'a@b.c',
      tenantCode: 'NSW#7K2F',
      activationLink: 'https://example.com/activate',
      expiresNote: 'expires soon',
    });
  });
});

describe('planLines', () => {
  test('includes the parsed name and falls back db-url note when unset', () => {
    const lines = planLines({ email: 'a@b.c', name: 'Amine Nagati', company: 'Co', tenant: 'C#AAAA' });
    expect(lines.some((l) => l.includes('a@b.c'))).toBe(true);
    expect(lines.some((l) => l.includes('firstName="Amine"'))).toBe(true);
    expect(lines.some((l) => l.includes('(not set)'))).toBe(true);
  });

  test('shows the provided --db-url', () => {
    const lines = planLines({ name: 'A B', 'db-url': 'https://x-default-rtdb.firebaseio.com' });
    expect(lines.some((l) => l.includes('https://x-default-rtdb.firebaseio.com'))).toBe(true);
  });
});
