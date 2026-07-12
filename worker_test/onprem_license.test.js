// Privacy-preserving licensing: signing, verification, expiry, renewal,
// offline grace, air-gapped licence files, plan feature flags, and the
// privacy whitelist on BOTH the token and the licence server.
import { describe, test, expect, beforeEach, afterEach } from '@jest/globals';
import { mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  generateLicenseKeyPair, signLicense, verifyLicense, sanitizeLicensePayload,
  featuresForPlan, ALLOWED_FIELDS,
} from '../deploy/onprem/license/license.mjs';
import { LicenseGuard, SAFETY_FLOOR } from '../deploy/onprem/license/license_guard.mjs';
import { handleValidate } from '../deploy/onprem/license/license-server/index.mjs';

const NOW = Date.UTC(2026, 6, 11);
const DAY = 24 * 60 * 60 * 1000;
const { privateKeyPem, publicKeyPem } = generateLicenseKeyPair();
const other = generateLicenseKeyPair();

const basePayload = (over = {}) => ({
  companyId: 'acme-industries',
  plan: 'industrial',
  status: 'active',
  expiresAt: new Date(NOW + 30 * DAY).toISOString(),
  installationId: 'inst-001',
  version: '1.2.1',
  ...over,
});

let dir;
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), 'sias-license-test-')); });
afterEach(() => { rmSync(dir, { recursive: true, force: true }); });

describe('token sign/verify', () => {
  test('valid round trip preserves the whitelisted payload', () => {
    const token = signLicense(basePayload(), privateKeyPem);
    const res = verifyLicense(token, publicKeyPem, { now: NOW });
    expect(res.valid).toBe(true);
    expect(res.payload.companyId).toBe('acme-industries');
    expect(res.payload.plan).toBe('industrial');
    expect(res.payload.features).toContain('gateway.modbus');
  });

  test('tampered payloads fail signature verification', () => {
    const token = signLicense(basePayload({ plan: 'standard' }), privateKeyPem);
    const [prefix, body, sig] = token.split('.');
    const hacked = JSON.parse(Buffer.from(body, 'base64url').toString());
    hacked.plan = 'industrial';
    const forged = `${prefix}.${Buffer.from(JSON.stringify(hacked)).toString('base64url')}.${sig}`;
    expect(verifyLicense(forged, publicKeyPem, { now: NOW }))
      .toMatchObject({ valid: false, reason: 'invalid signature' });
  });

  test('a token signed by another key is rejected', () => {
    const token = signLicense(basePayload(), other.privateKeyPem);
    expect(verifyLicense(token, publicKeyPem, { now: NOW }).valid).toBe(false);
  });

  test('expired tokens are rejected; renewal (a fresh token) restores validity', () => {
    const expired = signLicense(basePayload({ expiresAt: new Date(NOW - DAY).toISOString() }), privateKeyPem);
    expect(verifyLicense(expired, publicKeyPem, { now: NOW }))
      .toMatchObject({ valid: false, expired: true, reason: 'licence expired' });

    const renewed = signLicense(basePayload({ expiresAt: new Date(NOW + 365 * DAY).toISOString() }), privateKeyPem);
    expect(verifyLicense(renewed, publicKeyPem, { now: NOW }).valid).toBe(true);
  });

  test('suspended licences are invalid even before expiry', () => {
    const token = signLicense(basePayload({ status: 'suspended' }), privateKeyPem);
    expect(verifyLicense(token, publicKeyPem, { now: NOW }).reason).toContain('suspended');
  });

  test('malformed tokens are handled gracefully', () => {
    expect(verifyLicense('garbage', publicKeyPem).valid).toBe(false);
    expect(verifyLicense('SIAS1.only-two', publicKeyPem).valid).toBe(false);
    expect(verifyLicense('', publicKeyPem).valid).toBe(false);
  });
});

describe('privacy whitelist', () => {
  test('the allowed field list is exactly the documented contract', () => {
    expect([...ALLOWED_FIELDS].sort()).toEqual([
      'companyId', 'expiresAt', 'features', 'installationId', 'issuedAt', 'plan', 'status', 'version',
    ]);
  });

  test('payloads carrying operational data cannot be signed', () => {
    expect(() => signLicense(basePayload({ alerts: [{ id: 1 }] }), privateKeyPem))
      .toThrow(/disallowed field/);
    expect(() => signLicense(basePayload({ machineData: 'MACH-1:97C' }), privateKeyPem))
      .toThrow(/disallowed field/);
    expect(() => sanitizeLicensePayload({ users: ['a@b.c'] })).toThrow(/disallowed/);
  });

  test('the licence server rejects requests smuggling extra fields', () => {
    const registry = { 'inst-001': basePayload() };
    const bad = handleValidate(
      { installationId: 'inst-001', plcReadings: [1, 2, 3] },
      registry, privateKeyPem, NOW,
    );
    expect(bad.status).toBe(400);
    expect(bad.body.error).toContain('disallowed');
  });

  test('the licence server issues valid tokens for known active installations', () => {
    const registry = { 'inst-001': basePayload() };
    const ok = handleValidate({ installationId: 'inst-001', version: '1.2.1' }, registry, privateKeyPem, NOW);
    expect(ok.status).toBe(200);
    const res = verifyLicense(ok.body.token, publicKeyPem, { now: NOW });
    expect(res.valid).toBe(true);
    expect(res.payload.version).toBe('1.2.1');

    expect(handleValidate({ installationId: 'nope' }, registry, privateKeyPem, NOW).status).toBe(404);
    expect(handleValidate(
      { installationId: 'inst-001' },
      { 'inst-001': basePayload({ status: 'suspended' }) },
      privateKeyPem, NOW,
    ).status).toBe(403);
  });
});

describe('plan feature flags', () => {
  test('standard vs industrial gates the protocol adapters and AI extras', () => {
    const std = featuresForPlan('standard');
    const ind = featuresForPlan('industrial');
    expect(std).toContain('alerts.core');
    expect(std).toContain('gateway.http');
    expect(std).not.toContain('gateway.opcua');
    expect(std).not.toContain('forecaster.gbdt');
    expect(ind).toEqual(expect.arrayContaining(['gateway.mqtt', 'gateway.opcua', 'gateway.modbus', 'forecaster.gbdt']));
    expect(featuresForPlan('unknown-plan')).toEqual(std); // fail to the smaller plan
  });
});

describe('LicenseGuard', () => {
  const guardWith = (over = {}) => new LicenseGuard({
    publicKeyPem,
    installationId: 'inst-001',
    softwareVersion: '1.2.1',
    cachePath: join(dir, 'cache.json'),
    now: () => NOW,
    ...over,
  });

  test('offline annual licence file: valid without any network', async () => {
    const file = join(dir, 'license.sias');
    writeFileSync(file, signLicense(basePayload(), privateKeyPem));
    const guard = guardWith({
      licenseFile: file,
      fetchImpl: () => { throw new Error('network must not be touched'); },
    });
    const state = await guard.check();
    expect(state).toMatchObject({ status: 'active', source: 'file', plan: 'industrial' });
    expect(guard.isEnabled('gateway.modbus')).toBe(true);
  });

  test('a tampered offline file is invalid but keeps the safety floor', async () => {
    const file = join(dir, 'license.sias');
    writeFileSync(file, signLicense(basePayload(), other.privateKeyPem));
    const state = await guardWith({ licenseFile: file }).check();
    expect(state.status).toBe('invalid');
    expect(state.features).toEqual([...SAFETY_FLOOR]);
  });

  test('server path caches the token for later grace use', async () => {
    const token = signLicense(basePayload(), privateKeyPem);
    const guard = guardWith({
      serverUrl: 'http://license.sias.dev',
      fetchImpl: async () => ({ ok: true, json: async () => ({ token }) }),
    });
    const state = await guard.check();
    expect(state).toMatchObject({ status: 'active', source: 'server' });
    expect(existsSync(join(dir, 'cache.json'))).toBe(true);
  });

  test('unreachable server + cached token => grace inside the 7-day window', async () => {
    const token = signLicense(basePayload(), privateKeyPem);
    writeFileSync(join(dir, 'cache.json'), JSON.stringify({
      token, validatedAt: new Date(NOW - 3 * DAY).toISOString(),
    }));
    const guard = guardWith({
      serverUrl: 'http://license.sias.dev',
      graceDays: 7,
      fetchImpl: async () => { throw new Error('offline'); },
    });
    const state = await guard.check();
    expect(state.status).toBe('grace');
    expect(state.source).toBe('cache');
    expect(state.graceUntil).toBe(new Date(NOW + 4 * DAY).toISOString());
    expect(guard.isEnabled('gateway.opcua')).toBe(true); // features stay on in grace
  });

  test('grace window over => expired, features fall to the safety floor', async () => {
    const token = signLicense(basePayload(), privateKeyPem);
    writeFileSync(join(dir, 'cache.json'), JSON.stringify({
      token, validatedAt: new Date(NOW - 10 * DAY).toISOString(),
    }));
    const guard = guardWith({
      serverUrl: 'http://license.sias.dev',
      graceDays: 7,
      fetchImpl: async () => { throw new Error('offline'); },
    });
    const state = await guard.check();
    expect(state.status).toBe('expired');
    expect(state.features).toEqual([...SAFETY_FLOOR]);
    expect(guard.isEnabled('alerts.core')).toBe(true);      // never brick safety
    expect(guard.isEnabled('gateway.modbus')).toBe(false);  // paid extras off
  });

  test('14-day grace is honoured when configured', async () => {
    const token = signLicense(basePayload(), privateKeyPem);
    writeFileSync(join(dir, 'cache.json'), JSON.stringify({
      token, validatedAt: new Date(NOW - 10 * DAY).toISOString(),
    }));
    const guard = guardWith({
      serverUrl: 'http://license.sias.dev',
      graceDays: 14,
      fetchImpl: async () => { throw new Error('offline'); },
    });
    expect((await guard.check()).status).toBe('grace');
  });

  test('no configuration at all => missing, with the safety floor only', async () => {
    const state = await guardWith().check();
    expect(state.status).toBe('missing');
    expect(state.features).toEqual([...SAFETY_FLOOR]);
  });
});
