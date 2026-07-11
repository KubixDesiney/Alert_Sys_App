// Privacy-preserving SIAS licensing — shared library (pure functions).
//
// PRIVACY CONTRACT: a licence describes ONLY the subscription. The whitelist
// below is the complete universe of fields a licence token / licence server
// may ever carry. Alerts, users, machine data and PLC readings are
// structurally impossible to smuggle in: extra fields make a payload invalid
// on BOTH ends (server refuses to sign, client refuses to accept).
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';

export const TOKEN_PREFIX = 'SIAS1';

export const ALLOWED_FIELDS = Object.freeze([
  'companyId',
  'plan',
  'status',
  'expiresAt',
  'features',
  'installationId',
  'version',
  'issuedAt',
]);

/** Words that indicate telemetry/operational data trying to sneak in. */
const FORBIDDEN_HINTS = /alert|machine|plc|reading|user|email|sensor|telemetry|gps|location/i;

export const PLAN_FEATURES = Object.freeze({
  standard: Object.freeze([
    'alerts.core',          // intake, claim, resolve, escalate
    'notifications.lan',    // SSE fan-out
    'gateway.http',         // ESP32 + REST webhook adapters
    'backups.local',
  ]),
  industrial: Object.freeze([
    'alerts.core',
    'notifications.lan',
    'gateway.http',
    'backups.local',
    'gateway.mqtt',
    'gateway.opcua',
    'gateway.modbus',
    'forecaster.gbdt',      // on-device predictive model
    'shifts.ai_commander',
    'audit.extended',
  ]),
});

export function featuresForPlan(plan) {
  return [...(PLAN_FEATURES[String(plan || '').toLowerCase()] || PLAN_FEATURES.standard)];
}

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const unb64u = (s) => Buffer.from(s, 'base64url');

/**
 * Whitelist enforcement. Throws on unknown fields — the privacy boundary.
 */
export function sanitizeLicensePayload(input = {}) {
  const extra = Object.keys(input).filter((k) => !ALLOWED_FIELDS.includes(k));
  if (extra.length) {
    throw new Error(
      `licence payload contains disallowed field(s): ${extra.join(', ')} — ` +
      'the licence service must never receive operational data',
    );
  }
  for (const [k, v] of Object.entries(input)) {
    if (k === 'features') continue;
    if (typeof v === 'object' && v !== null) {
      throw new Error(`licence field "${k}" must be a scalar`);
    }
    if (FORBIDDEN_HINTS.test(String(v)) && k !== 'companyId' && k !== 'installationId') {
      // company/installation ids are opaque; other fields must not embed data
      throw new Error(`licence field "${k}" looks like operational data`);
    }
  }
  if (input.features && !Array.isArray(input.features)) {
    throw new Error('features must be a string array');
  }
  return {
    companyId: String(input.companyId || ''),
    plan: String(input.plan || 'standard').toLowerCase(),
    status: String(input.status || 'active').toLowerCase(),
    expiresAt: String(input.expiresAt || ''),
    features: (input.features || featuresForPlan(input.plan)).map(String),
    installationId: String(input.installationId || ''),
    version: String(input.version || ''),
    issuedAt: String(input.issuedAt || new Date().toISOString()),
  };
}

export function generateLicenseKeyPair() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  return {
    privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    publicKeyPem: publicKey.export({ type: 'spki', format: 'pem' }).toString(),
  };
}

/** Signs a (whitelisted) payload into a `SIAS1.<payload>.<sig>` token. */
export function signLicense(payload, privateKeyPem) {
  const clean = sanitizeLicensePayload(payload);
  if (!clean.companyId) throw new Error('companyId is required');
  if (!clean.expiresAt || Number.isNaN(Date.parse(clean.expiresAt))) {
    throw new Error('expiresAt must be a valid ISO date');
  }
  const body = b64u(JSON.stringify(clean));
  const sig = sign(null, Buffer.from(body), createPrivateKey(privateKeyPem));
  return `${TOKEN_PREFIX}.${body}.${b64u(sig)}`;
}

/**
 * Verifies a token: signature, whitelist, status and (optionally) expiry.
 * @returns {{valid:boolean, reason?:string, payload?:object, expired?:boolean}}
 */
export function verifyLicense(token, publicKeyPem, { now = Date.now(), allowExpired = false } = {}) {
  const parts = String(token || '').trim().split('.');
  if (parts.length !== 3 || parts[0] !== TOKEN_PREFIX) {
    return { valid: false, reason: 'malformed token' };
  }
  const [, body, sig] = parts;
  let ok = false;
  try {
    ok = verify(null, Buffer.from(body), createPublicKey(publicKeyPem), unb64u(sig));
  } catch (_) {
    ok = false;
  }
  if (!ok) return { valid: false, reason: 'invalid signature' };

  let payload;
  try {
    payload = sanitizeLicensePayload(JSON.parse(unb64u(body).toString('utf8')));
  } catch (err) {
    return { valid: false, reason: `invalid payload: ${err.message}` };
  }
  if (payload.status !== 'active') {
    return { valid: false, reason: `licence status is "${payload.status}"`, payload };
  }
  const exp = Date.parse(payload.expiresAt);
  const expired = Number.isNaN(exp) || exp <= now;
  if (expired && !allowExpired) {
    return { valid: false, reason: 'licence expired', payload, expired: true };
  }
  return { valid: true, payload, expired };
}
