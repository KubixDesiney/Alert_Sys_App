/**
 * Serverless daily backup of the Realtime Database to Cloudflare R2.
 *
 * Runs on a cron (default 02:00 UTC), exports the whole RTDB via a short-lived
 * Google access token minted from the service account, and writes a timestamped
 * object to the R2 bucket, keeping the newest `BACKUP_KEEP` snapshots.
 *
 * Deploy:  npx wrangler deploy --config wrangler.backup.toml
 * Secrets: wrangler secret put FIREBASE_SERVICE_ACCOUNT  (the SA JSON)
 *          wrangler secret put FB_DB_URL                  (https://<proj>-default-rtdb.firebaseio.com/)
 *          wrangler secret put WORKER_SHARED_SECRET       (optional; guards the manual /backup trigger)
 * R2:      create the bucket named in wrangler.backup.toml (e.g. alertsys-backups).
 *
 * Manual run:  GET https://<worker>/backup?key=<WORKER_SHARED_SECRET>
 */

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
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const jwt = `${header}.${claim}.${b64urlFromBytes(new Uint8Array(sig))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('token error: ' + JSON.stringify(j));
  return j.access_token;
}

async function runBackup(env) {
  const token = await getAccessToken(env);
  const base = env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/';
  try {
    const res = await fetch(`${base}.json?access_token=${token}`);
    if (!res.ok) throw new Error('RTDB export failed: ' + res.status);
    const body = await res.text();
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
    const objKey = `rtdb/${stamp}.json`;
    await env.BACKUPS.put(objKey, body, {
      httpMetadata: { contentType: 'application/json' },
    });
    await prune(env, Number(env.BACKUP_KEEP || 30));
    // Health beacon so the monitor / SuperAdmin console can see backups happen.
    await writeBeacon(base, token, {
      at: new Date().toISOString(), ok: true, key: objKey, bytes: body.length,
    });
    return { key: objKey, bytes: body.length };
  } catch (e) {
    await writeBeacon(base, token, {
      at: new Date().toISOString(), ok: false, error: String((e && e.message) || e),
    }).catch(() => {});
    throw e;
  }
}

async function writeBeacon(base, token, payload) {
  await fetch(`${base}workers/health/backup.json?access_token=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

async function prune(env, keep) {
  const list = await env.BACKUPS.list({ prefix: 'rtdb/' });
  const keys = list.objects.map((o) => o.key).sort().reverse(); // newest first
  for (const k of keys.slice(keep)) await env.BACKUPS.delete(k);
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      runBackup(env).catch((e) => console.error('backup failed:', e.message)),
    );
  },
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === '/backup') {
      if (env.WORKER_SHARED_SECRET &&
          url.searchParams.get('key') !== env.WORKER_SHARED_SECRET) {
        return new Response('forbidden', { status: 403 });
      }
      try {
        const r = await runBackup(env);
        return Response.json({ ok: true, ...r });
      } catch (e) {
        return Response.json({ ok: false, error: e.message }, { status: 500 });
      }
    }
    return new Response('alertsys backup worker');
  },
};
