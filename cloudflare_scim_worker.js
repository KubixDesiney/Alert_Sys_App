/**
 * SCIM 2.0 provisioning endpoint for the dedicated-instance deployment model.
 *
 * The customer's identity provider (Okta / Microsoft Entra / OneLogin / …) points
 * its SCIM connector at this worker to AUTO-PROVISION and AUTO-DEPROVISION users.
 * We govern the *authorization* layer; the customer's SSO handles *authentication*:
 *
 *   - Create / update  → writes provisioning/{emailKey} = { role, factory, active,
 *     names, externalId, scimId }. When the user signs in (SSO or email/pw) the
 *     app's RoleRouter reads this and grants the mapped role with no manual step.
 *   - Deactivate / delete → sets active:false. The app denies access on the next
 *     role load, and flips users/{uid}/active:false once the uid is known.
 *
 * This split means we never mint Firebase credentials from the edge (auth stays
 * with the IdP/SSO), so the worker only needs RTDB access.
 *
 * Deploy:  npx wrangler deploy --config wrangler.scim.toml
 * Secrets: FIREBASE_SERVICE_ACCOUNT  (SA JSON, RTDB access)
 *          FB_DB_URL                  (https://<proj>-default-rtdb.firebaseio.com/)
 *          SCIM_TOKEN                  (bearer token the IdP authenticates with)
 *          SCIM_DEFAULT_ROLE          (optional; default "supervisor")
 *          SCIM_GRANTABLE_ROLES       (optional CSV; default "admin,supervisor")
 *          SCIM_DEFAULT_FACTORY       (optional)
 *
 * IdP base URL:  https://<worker>/scim/v2
 */

const CORE_USER = 'urn:ietf:params:scim:schemas:core:2.0:User';
const ENTERPRISE = 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User';
const LIST_RESPONSE = 'urn:ietf:params:scim:api:messages:2.0:ListResponse';
const PATCH_OP = 'urn:ietf:params:scim:api:messages:2.0:PatchOp';
const ERROR = 'urn:ietf:params:scim:api:messages:2.0:Error';

// ── crypto / Google token (RTDB REST) ────────────────────────────────────────
function b64urlFromString(s) {
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlFromBytes(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function pemToArrayBuffer(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}
async function getAccessToken(env) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlFromString(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64urlFromString(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.${b64urlFromBytes(new Uint8Array(sig))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt,
    }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('token error: ' + JSON.stringify(j));
  return j.access_token;
}

// ── RTDB REST helpers ─────────────────────────────────────────────────────────
function dbBase(env) {
  return env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/';
}
async function rtdbGet(env, token, path) {
  const r = await fetch(`${dbBase(env)}${path}.json?access_token=${token}`);
  if (!r.ok) throw new Error(`RTDB GET ${path}: ${r.status}`);
  return r.json();
}
async function rtdbPut(env, token, path, value) {
  const r = await fetch(`${dbBase(env)}${path}.json?access_token=${token}`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(value),
  });
  if (!r.ok) throw new Error(`RTDB PUT ${path}: ${r.status}`);
  return r.json();
}
async function rtdbPatch(env, token, path, value) {
  const r = await fetch(`${dbBase(env)}${path}.json?access_token=${token}`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(value),
  });
  if (!r.ok) throw new Error(`RTDB PATCH ${path}: ${r.status}`);
  return r.json();
}

// ── pure mapping helpers (exported for tests) ─────────────────────────────────
export function emailKey(email) {
  return String(email || '').trim().toLowerCase().replace(/[.#$\[\]/]/g, '_');
}

export function grantableRoles(env) {
  const csv = (env && env.SCIM_GRANTABLE_ROLES) || 'admin,supervisor';
  return csv.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
}

/** Map an incoming SCIM User payload → our internal record. */
export function scimToRecord(body, env) {
  const ent = body[ENTERPRISE] || {};
  const emails = Array.isArray(body.emails) ? body.emails : [];
  const primary = emails.find((e) => e && e.primary) || emails[0] || {};
  const email = (primary.value || body.userName || '').trim().toLowerCase();
  const name = body.name || {};

  // Role: explicit custom attr → enterprise.department → default. Clamp to the
  // grantable set so SCIM can never escalate to e.g. superadmin.
  const allowed = grantableRoles(env);
  const fallback = ((env && env.SCIM_DEFAULT_ROLE) || 'supervisor').toLowerCase();
  let role = (body.role || ent.department || fallback).toString().trim().toLowerCase();
  if (!allowed.includes(role)) role = allowed.includes(fallback) ? fallback : allowed[0];

  const factory = (body.factory || body.usine || ent.division ||
    (env && env.SCIM_DEFAULT_FACTORY) || '').toString().trim();

  return {
    email,
    firstName: (name.givenName || '').trim(),
    lastName: (name.familyName || '').trim(),
    active: body.active !== false, // SCIM defaults active when omitted
    externalId: (body.externalId || '').toString(),
    role,
    factory,
  };
}

/** Render our stored resource → a SCIM User JSON for IdP responses. */
export function recordToScim(id, rec, location) {
  const r = rec || {};
  return {
    schemas: [CORE_USER],
    id,
    externalId: r.externalId || undefined,
    userName: r.email,
    name: {
      givenName: r.firstName || undefined,
      familyName: r.lastName || undefined,
      formatted: [r.firstName, r.lastName].filter(Boolean).join(' ') || undefined,
    },
    emails: r.email ? [{ value: r.email, primary: true }] : [],
    active: r.active !== false,
    meta: {
      resourceType: 'User',
      created: r.createdAt || undefined,
      lastModified: r.updatedAt || undefined,
      location,
    },
  };
}

/** Parse a SCIM filter like `userName eq "x@y.com"`. Returns {attr, value} or null. */
export function parseFilter(filter) {
  if (!filter) return null;
  const m = String(filter).match(/^\s*(\S+)\s+eq\s+"([^"]*)"\s*$/i);
  if (!m) return null;
  return { attr: m[1].toLowerCase(), value: m[2] };
}

/** Apply a SCIM PatchOp body to our record. Handles Okta/Azure shapes. */
export function applyPatch(rec, patchBody) {
  const out = { ...rec };
  const ops = (patchBody && patchBody.Operations) || [];
  for (const op of ops) {
    if (!op) continue;
    const verb = (op.op || '').toLowerCase();
    if (verb !== 'replace' && verb !== 'add') continue;
    const path = (op.path || '').toLowerCase();
    const val = op.value;
    if (path === 'active') {
      out.active = val === true || val === 'True' || val === 'true';
    } else if (path === 'name.givenname') {
      out.firstName = String(val || '');
    } else if (path === 'name.familyname') {
      out.lastName = String(val || '');
    } else if (path === 'username') {
      out.email = String(val || '').trim().toLowerCase();
    } else if (!op.path && val && typeof val === 'object') {
      // Pathless replace: a partial resource object.
      if ('active' in val) out.active = val.active !== false;
      if (val.name && val.name.givenName != null) out.firstName = String(val.name.givenName);
      if (val.name && val.name.familyName != null) out.lastName = String(val.name.familyName);
      if (val.userName) out.email = String(val.userName).trim().toLowerCase();
    }
  }
  return out;
}

// ── SCIM responses ────────────────────────────────────────────────────────────
function scimJson(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { 'Content-Type': 'application/scim+json' },
  });
}
function scimError(status, detail) {
  return scimJson({ schemas: [ERROR], detail, status: String(status) }, status);
}
function serviceProviderConfig() {
  return {
    schemas: ['urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig'],
    documentationUri: 'https://docs',
    patch: { supported: true },
    bulk: { supported: false, maxOperations: 0, maxPayloadSize: 0 },
    filter: { supported: true, maxResults: 200 },
    changePassword: { supported: false },
    sort: { supported: false },
    etag: { supported: false },
    authenticationSchemes: [{
      type: 'oauthbearertoken', name: 'OAuth Bearer Token',
      description: 'Authentication via the SCIM_TOKEN bearer.',
    }],
  };
}

async function provisionLocation(req, id) {
  return new URL(req.url).origin + '/scim/v2/Users/' + id;
}

async function writeUser(env, token, id, rec) {
  const stamp = new Date().toISOString();
  const stored = { ...rec, scimId: id, updatedAt: stamp };
  await rtdbPut(env, token, `scim/Users/${id}`, stored);
  if (rec.email) {
    const key = emailKey(rec.email);
    await rtdbPut(env, token, `scim/byUserName/${key}`, id);
    // The authorization record the app consumes on login.
    await rtdbPut(env, token, `provisioning/${key}`, {
      scimId: id, externalId: rec.externalId || '', email: rec.email,
      role: rec.role, factory: rec.factory || '', active: rec.active !== false,
      firstName: rec.firstName || '', lastName: rec.lastName || '',
      updatedAt: stamp,
    });
    // If this person has already logged in, flip their live account too.
    try {
      const uid = await rtdbGet(env, token, `provisioning/${key}/uid`);
      if (uid) {
        await rtdbPatch(env, token, `users/${uid}`, { active: rec.active !== false });
      }
    } catch (_) { /* best-effort */ }
  }
  return stored;
}

async function beacon(env, op, ok) {
  try {
    const token = await getAccessToken(env);
    await rtdbPut(env, token, 'workers/health/scim',
      { at: new Date().toISOString(), lastOp: op, ok });
  } catch (_) { /* non-fatal */ }
}

// ── router ──────────────────────────────────────────────────────────────────
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, '');

    if (!path.startsWith('/scim/v2')) {
      return new Response('alertsys SCIM worker');
    }
    // Bearer auth.
    const auth = req.headers.get('authorization') || '';
    if (!env.SCIM_TOKEN || auth !== `Bearer ${env.SCIM_TOKEN}`) {
      return scimError(401, 'Unauthorized');
    }

    const sub = path.slice('/scim/v2'.length); // e.g. '', '/Users', '/Users/{id}'
    try {
      if (sub === '/ServiceProviderConfig') return scimJson(serviceProviderConfig());
      if (sub === '/ResourceTypes' || sub === '/Schemas') {
        return scimJson({ schemas: [LIST_RESPONSE], totalResults: 0, Resources: [] });
      }

      const token = await getAccessToken(env);
      const usersMatch = sub.match(/^\/Users(?:\/(.+))?$/);
      if (!usersMatch) return scimError(404, 'Not found');
      const id = usersMatch[1] ? decodeURIComponent(usersMatch[1]) : null;

      // ── collection ──
      if (!id) {
        if (req.method === 'GET') {
          const f = parseFilter(url.searchParams.get('filter'));
          const Resources = [];
          if (f && (f.attr === 'username' || f.attr === 'emails.value' || f.attr === 'externalid')) {
            const key = emailKey(f.value);
            const foundId = await rtdbGet(env, token, `scim/byUserName/${key}`);
            if (foundId) {
              const rec = await rtdbGet(env, token, `scim/Users/${foundId}`);
              if (rec) Resources.push(recordToScim(foundId, rec, await provisionLocation(req, foundId)));
            }
          } else {
            const all = (await rtdbGet(env, token, 'scim/Users')) || {};
            for (const [uid, rec] of Object.entries(all)) {
              Resources.push(recordToScim(uid, rec, await provisionLocation(req, uid)));
            }
          }
          return scimJson({
            schemas: [LIST_RESPONSE], totalResults: Resources.length,
            startIndex: 1, itemsPerPage: Resources.length, Resources,
          });
        }
        if (req.method === 'POST') {
          const body = await req.json();
          const rec = scimToRecord(body, env);
          if (!rec.email) return scimError(400, 'userName/email is required');
          // De-dupe by userName.
          const existing = await rtdbGet(env, token, `scim/byUserName/${emailKey(rec.email)}`);
          if (existing) return scimError(409, 'User already exists');
          const newId = crypto.randomUUID();
          rec.createdAt = new Date().toISOString();
          const stored = await writeUser(env, token, newId, rec);
          ctx.waitUntil(beacon(env, 'create', true));
          return scimJson(recordToScim(newId, stored, await provisionLocation(req, newId)), 201);
        }
        return scimError(405, 'Method not allowed');
      }

      // ── single resource ──
      const current = await rtdbGet(env, token, `scim/Users/${id}`);
      if (req.method === 'GET') {
        if (!current) return scimError(404, 'User not found');
        return scimJson(recordToScim(id, current, await provisionLocation(req, id)));
      }
      if (!current) return scimError(404, 'User not found');

      if (req.method === 'PUT') {
        const body = await req.json();
        const rec = { ...current, ...scimToRecord(body, env), createdAt: current.createdAt };
        const stored = await writeUser(env, token, id, rec);
        ctx.waitUntil(beacon(env, 'replace', true));
        return scimJson(recordToScim(id, stored, await provisionLocation(req, id)));
      }
      if (req.method === 'PATCH') {
        const body = await req.json();
        const rec = applyPatch(current, body);
        const stored = await writeUser(env, token, id, rec);
        ctx.waitUntil(beacon(env, 'patch', true));
        return scimJson(recordToScim(id, stored, await provisionLocation(req, id)));
      }
      if (req.method === 'DELETE') {
        // Soft delete: deactivate (keeps an audit trail; revokes app access).
        const stored = await writeUser(env, token, id, { ...current, active: false });
        await rtdbPatch(env, token, `scim/Users/${id}`, { deletedAt: new Date().toISOString() });
        ctx.waitUntil(beacon(env, 'delete', true));
        return new Response(null, { status: 204 });
      }
      return scimError(405, 'Method not allowed');
    } catch (e) {
      ctx.waitUntil(beacon(env, 'error', false));
      return scimError(500, String((e && e.message) || e));
    }
  },
};
