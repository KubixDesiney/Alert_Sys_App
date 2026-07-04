import { describe, test, expect } from '@jest/globals';
import {
  _validateIdTokenClaims,
  _constantTimeEquals,
  _workerAuthCheck,
} from '../cloudflare_ai_worker.js';
import {
  _validateIdTokenClaims as validateClaimsNotify,
  _workerAuthCheck as workerAuthCheckNotify,
} from '../cloudflare_notify_worker.js';

const NOW = 1_700_000_000;
const PROJECT = 'alertappsys';

const claims = (overrides = {}) => ({
  aud: PROJECT,
  iss: `https://securetoken.google.com/${PROJECT}`,
  exp: NOW + 3600,
  iat: NOW - 60,
  sub: 'user-1',
  ...overrides,
});

const requestWith = (headers = {}) => ({
  headers: { get: (k) => headers[k.toLowerCase()] ?? headers[k] ?? null },
});

describe('_validateIdTokenClaims', () => {
  test('accepts a valid Firebase ID token payload', () => {
    expect(_validateIdTokenClaims(claims(), PROJECT, NOW)).toEqual({
      ok: true,
      uid: 'user-1',
    });
  });

  test.each([
    ['expired', claims({ exp: NOW - 1 })],
    ['bad_aud', claims({ aud: 'other-project' })],
    ['bad_iss', claims({ iss: 'https://securetoken.google.com/other' })],
    ['no_uid', claims({ sub: '', user_id: '' })],
    ['issued_in_future', claims({ iat: NOW + 3600 })],
  ])('rejects %s', (error, payload) => {
    expect(_validateIdTokenClaims(payload, PROJECT, NOW)).toEqual({ ok: false, error });
  });

  test('rejects null payload and missing project', () => {
    expect(_validateIdTokenClaims(null, PROJECT, NOW).ok).toBe(false);
    expect(_validateIdTokenClaims(claims(), '', NOW).ok).toBe(false);
  });

  test('both workers share identical claim validation', () => {
    for (const payload of [claims(), claims({ exp: NOW - 1 }), claims({ aud: 'x' })]) {
      expect(validateClaimsNotify(payload, PROJECT, NOW)).toEqual(
        _validateIdTokenClaims(payload, PROJECT, NOW),
      );
    }
  });
});

describe('_constantTimeEquals', () => {
  test('matches equal non-empty strings only', () => {
    expect(_constantTimeEquals('secret-1', 'secret-1')).toBe(true);
    expect(_constantTimeEquals('secret-1', 'secret-2')).toBe(false);
    expect(_constantTimeEquals('secret-1', 'secret-10')).toBe(false);
    expect(_constantTimeEquals('', '')).toBe(false); // empty never authenticates
  });
});

describe('_workerAuthCheck modes', () => {
  const env = { WORKER_SHARED_SECRET: 's3cret', FB_DB_URL: 'https://alertappsys-default-rtdb.firebaseio.com/' };

  test("mode 'off' (default) allows everything", async () => {
    const res = await _workerAuthCheck(requestWith({}), { ...env });
    expect(res).toEqual({ ok: true, mode: 'off', method: 'none' });
  });

  test("mode 'required' accepts the legacy shared secret", async () => {
    const res = await _workerAuthCheck(
      requestWith({ 'x-worker-secret': 's3cret' }),
      { ...env, WORKER_AUTH_MODE: 'required' },
    );
    expect(res.ok).toBe(true);
    expect(res.method).toBe('secret');
  });

  test("mode 'required' rejects a caller with no credentials", async () => {
    const res = await _workerAuthCheck(requestWith({}), { ...env, WORKER_AUTH_MODE: 'required' });
    expect(res).toMatchObject({ ok: false, error: 'no_credentials' });
  });

  test("mode 'required' rejects a malformed bearer token", async () => {
    const res = await _workerAuthCheck(
      requestWith({ authorization: 'Bearer not.a.jwt.at.all' }),
      { ...env, WORKER_AUTH_MODE: 'required' },
    );
    expect(res.ok).toBe(false);
  });

  test("mode 'log' lets unauthenticated callers through but flags them", async () => {
    const res = await _workerAuthCheck(requestWith({}), { ...env, WORKER_AUTH_MODE: 'log' });
    expect(res.ok).toBe(true);
    expect(res.method).toBe('unauthenticated_logged');
  });

  test('notify worker enforces the same decisions', async () => {
    const denied = await workerAuthCheckNotify(requestWith({}), { ...env, WORKER_AUTH_MODE: 'required' });
    expect(denied.ok).toBe(false);
    const allowed = await workerAuthCheckNotify(
      requestWith({ 'x-worker-secret': 's3cret' }),
      { ...env, WORKER_AUTH_MODE: 'required' },
    );
    expect(allowed.ok).toBe(true);
  });
});
