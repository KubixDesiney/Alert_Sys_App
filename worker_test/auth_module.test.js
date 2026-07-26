// Exercises worker/auth.js's real JWT-signing + token-caching logic with a
// throwaway generated RSA key (so the actual RS256 signing path executes,
// not a stub) and a mocked Google token endpoint. No live network.
import crypto from 'node:crypto';
import { afterEach, beforeEach, describe, expect, jest, test } from '@jest/globals';

const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const PRIVATE_KEY_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const SERVICE_ACCOUNT = JSON.stringify({ client_email: 'sa@fake.iam.gserviceaccount.com', private_key: PRIVATE_KEY_PEM });

const realFetch = globalThis.fetch;
function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function decodeJwtPayload(jwt) {
  const [, payloadB64] = jwt.split('.');
  const b64 = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
  return JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
}

afterEach(() => { globalThis.fetch = realFetch; });

describe('base64UrlEncode / importPrivateKey / createFirebaseAuthJWT (real crypto)', () => {
  let mod;
  beforeEach(async () => {
    jest.resetModules();
    mod = await import('../worker/auth.js');
  });

  test('base64UrlEncode strips padding and uses URL-safe characters', () => {
    expect(mod.base64UrlEncode('a')).toBe('YQ');
    expect(mod.base64UrlEncode(new Uint8Array([255, 254, 253]))).not.toMatch(/[+/=]/);
  });

  test('importPrivateKey parses a real PEM into a usable CryptoKey', async () => {
    const key = await mod.importPrivateKey(PRIVATE_KEY_PEM);
    expect(key.type).toBe('private');
    expect(key.algorithm.name).toBe('RSASSA-PKCS1-v1_5');
  });

  test('createFirebaseAuthJWT produces a three-part JWT with the expected claims, verifiable with the public key', async () => {
    const jwt = await mod.createFirebaseAuthJWT('sa@fake.iam.gserviceaccount.com', PRIVATE_KEY_PEM);
    const parts = jwt.split('.');
    expect(parts).toHaveLength(3);
    const payload = decodeJwtPayload(jwt);
    expect(payload).toMatchObject({
      iss: 'sa@fake.iam.gserviceaccount.com',
      sub: 'sa@fake.iam.gserviceaccount.com',
      uid: 'worker-escalation',
      claims: { role: 'admin' },
    });
    expect(payload.exp - payload.iat).toBe(3600);

    // Real signature verification with the matching public key proves the
    // signing path (not just the string plumbing) actually ran correctly.
    const { publicKey } = crypto.createPrivateKey(PRIVATE_KEY_PEM).export ? { publicKey: null } : {};
    const pub = crypto.createPublicKey(PRIVATE_KEY_PEM);
    const [h, p, s] = parts;
    const sigBuf = Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
    const verifier = crypto.createVerify('RSA-SHA256');
    verifier.update(`${h}.${p}`);
    expect(verifier.verify(pub, sigBuf)).toBe(true);
  });
});

describe('getFirebaseToken (service-account path, with caching)', () => {
  beforeEach(() => { jest.resetModules(); });

  test('signs in with a custom token minted from the service account and caches the result', async () => {
    const mod = await import('../worker/auth.js');
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init) => {
      calls.push(String(url));
      expect(String(url)).toContain('accounts:signInWithCustomToken');
      const body = JSON.parse(init.body);
      expect(body.returnSecureToken).toBe(true);
      expect(body.token.split('.')).toHaveLength(3);
      return response({ idToken: 'minted-id-token' });
    });
    const env = { FIREBASE_SERVICE_ACCOUNT: SERVICE_ACCOUNT, FB_API_KEY: 'key123' };
    const tok = await mod.getFirebaseToken(env);
    expect(tok).toBe('minted-id-token');

    // Second call within the cache window must not hit the network again.
    const tok2 = await mod.getFirebaseToken(env);
    expect(tok2).toBe('minted-id-token');
    expect(calls).toHaveLength(1);
  });

  test('falls back to anonymous signUp when there is no service account', async () => {
    const mod = await import('../worker/auth.js');
    globalThis.fetch = jest.fn(async (url) => {
      expect(String(url)).toContain('accounts:signUp');
      return response({ idToken: 'anon-token' });
    });
    const tok = await mod.getFirebaseToken({ FB_API_KEY: 'key123' });
    expect(tok).toBe('anon-token');
  });

  test('falls back to anonymous signUp when the service-account sign-in request fails', async () => {
    const mod = await import('../worker/auth.js');
    globalThis.fetch = jest.fn(async (url) => {
      if (String(url).includes('signInWithCustomToken')) return new Response('nope', { status: 401 });
      return response({ idToken: 'anon-fallback' });
    });
    const env = { FIREBASE_SERVICE_ACCOUNT: SERVICE_ACCOUNT, FB_API_KEY: 'key123' };
    const tok = await mod.getFirebaseToken(env);
    expect(tok).toBe('anon-fallback');
  });

  test('falls back to anonymous signUp when the service account JSON is malformed', async () => {
    const mod = await import('../worker/auth.js');
    globalThis.fetch = jest.fn(async (url) => {
      expect(String(url)).toContain('accounts:signUp');
      return response({ idToken: 'anon-token-2' });
    });
    const tok = await mod.getFirebaseToken({ FIREBASE_SERVICE_ACCOUNT: '{not json', FB_API_KEY: 'key123' });
    expect(tok).toBe('anon-token-2');
  });
});

describe('getFcmAccessToken (OAuth JWT-bearer flow, with caching)', () => {
  beforeEach(() => { jest.resetModules(); });

  test('mints an FCM access token via the JWT-bearer grant and caches it', async () => {
    const mod = await import('../worker/auth.js');
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init) => {
      calls.push(String(url));
      expect(String(url)).toBe('https://oauth2.googleapis.com/token');
      expect(init.body).toContain('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer'.replace(/%3A/g, ':').replace(/%2F/g, '/') || '');
      expect(init.body).toContain('grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer');
      return response({ access_token: 'fcm-access-token', expires_in: 3600 });
    });
    const env = { FIREBASE_SERVICE_ACCOUNT: SERVICE_ACCOUNT };
    const tok = await mod.getFcmAccessToken(env);
    expect(tok).toBe('fcm-access-token');
    const tok2 = await mod.getFcmAccessToken(env);
    expect(tok2).toBe('fcm-access-token');
    expect(calls).toHaveLength(1); // second call served from cache
  });

  test('throws a descriptive error when the token endpoint returns no access_token', async () => {
    const mod = await import('../worker/auth.js');
    globalThis.fetch = jest.fn(async () => response({ error: 'invalid_grant' }));
    await expect(mod.getFcmAccessToken({ FIREBASE_SERVICE_ACCOUNT: SERVICE_ACCOUNT })).rejects.toThrow(/FCM token failed/);
  });
});
