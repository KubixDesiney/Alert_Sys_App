const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-firebase-auth',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};
const FIREBASE_DB = 'https://alertappsys-default-rtdb.firebaseio.com';

function bearer(header) {
  const value = String(header || '');
  return value.toLowerCase().startsWith('bearer ') ? value.slice(7).trim() : '';
}

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS, ...extra },
  });
}

function decodeJwtPayload(token) {
  const [, payload] = String(token || '').split('.');
  if (!payload) return {};
  const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  try {
    return JSON.parse(atob(padded));
  } catch (_) {
    return {};
  }
}

async function superadminFromFirebaseToken(token) {
  const payload = decodeJwtPayload(token);
  const uid = String(payload.user_id || payload.sub || '');
  if (!uid) return false;

  const response = await fetch(
    `${FIREBASE_DB}/users/${encodeURIComponent(uid)}/role.json?auth=${encodeURIComponent(token)}`,
    { headers: { Accept: 'application/json' } },
  );
  if (!response.ok) return false;
  const role = String(await response.json() || '');
  return role === 'superadmin' || role === 'SuperAdmin';
}

function upstreamRequest(request) {
  const source = new URL(request.url);
  const path = source.pathname.replace(/^\/github-proxy/, '') || '/config';
  const upstream = new URL(`${path}${source.search}`, 'https://alertsys-github.internal');
  const headers = new Headers(request.headers);
  headers.delete('host');
  return new Request(upstream, {
    method: request.method,
    headers,
    body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
    redirect: 'manual',
  });
}

function withCors(response) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS)) headers.set(key, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export async function onRequest({ request, env }) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

  const token = bearer(request.headers.get('x-firebase-auth'));
  if (!token) return json({ error: 'unauthorized' }, 401, { 'WWW-Authenticate': 'Bearer' });
  if (!(await superadminFromFirebaseToken(token))) return json({ error: 'forbidden' }, 403);

  const response = await env.GITHUB_INTERNAL.fetchBypass(upstreamRequest(request));
  return withCors(response);
}
