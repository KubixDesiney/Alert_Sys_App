// SIAS licence server — reference implementation.
//
// Stores ONLY: company ID, plan, licence status, expiry, enabled features,
// installation ID, current software version. `handleValidate` rejects any
// request that carries other fields, so a misbehaving client cannot push
// operational data here even by accident. No alerts, users, machine data or
// PLC readings ever transit this service — see worker_test/onprem_license.
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { signLicense, ALLOWED_FIELDS } from '../license.mjs';

const REQUEST_FIELDS = ['installationId', 'version', 'companyId'];

/**
 * Pure request handler (unit-tested directly).
 * @param {object} body           parsed JSON request
 * @param {object} registry       { [installationId]: {companyId, plan, status, expiresAt, features?} }
 * @param {string} privateKeyPem  Ed25519 signing key
 */
export function handleValidate(body, registry, privateKeyPem, now = Date.now()) {
  const extra = Object.keys(body || {}).filter((k) => !REQUEST_FIELDS.includes(k));
  if (extra.length) {
    return {
      status: 400,
      body: {
        error: `request contains disallowed field(s): ${extra.join(', ')}`,
        hint: 'the licence service accepts only installationId, version, companyId',
      },
    };
  }
  const installationId = String(body?.installationId || '');
  if (!installationId) return { status: 400, body: { error: 'installationId required' } };

  const entry = registry[installationId];
  if (!entry) return { status: 404, body: { error: 'unknown installation' } };
  if (String(entry.status).toLowerCase() !== 'active') {
    return { status: 403, body: { error: `licence ${entry.status}` } };
  }

  const token = signLicense({
    companyId: entry.companyId,
    plan: entry.plan,
    status: entry.status,
    expiresAt: entry.expiresAt,
    features: entry.features,
    installationId,
    version: String(body?.version || ''),
    issuedAt: new Date(now).toISOString(),
  }, privateKeyPem);

  return { status: 200, body: { token } };
}

// ── standalone runtime ───────────────────────────────────────────────────────
if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, '/')}`) {
  const PORT = Number(process.env.PORT || 8791);
  const registry = JSON.parse(readFileSync(process.env.LICENSE_REGISTRY || './licenses.json', 'utf8'));
  const keyPem = readFileSync(process.env.LICENSE_PRIVATE_KEY || './license_ed25519.pem', 'utf8');

  http.createServer((req, res) => {
    const respond = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.method === 'GET' && req.url === '/health') return respond(200, { ok: true });
    if (req.method === 'POST' && req.url === '/license/validate') {
      let raw = '';
      req.on('data', (c) => {
        raw += c;
        if (raw.length > 4096) req.destroy(); // identity payloads are tiny
      });
      req.on('end', () => {
        try {
          const out = handleValidate(JSON.parse(raw || '{}'), registry, keyPem);
          respond(out.status, out.body);
        } catch (_) {
          respond(400, { error: 'invalid JSON' });
        }
      });
      return undefined;
    }
    return respond(404, { error: 'not found' });
  }).listen(PORT, () => console.log(JSON.stringify({
    ts: new Date().toISOString(), service: 'license-server', msg: `listening on :${PORT}`,
  })));

  void ALLOWED_FIELDS; // documented contract, re-exported for operators
}
