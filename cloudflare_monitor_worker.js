/**
 * System monitor / deadman switch.
 *
 * Runs every 5 minutes, checks the worker fleet + cron freshness + backup
 * freshness, and posts to a webhook (Slack / Teams / Discord / PagerDuty-
 * compatible) the moment the system changes state — so you hear about a stalled
 * cron or a failed backup before a customer does. State is recorded at
 * workers/health/monitor; alerts fire only on transition (no every-5-min spam).
 *
 * Deploy:  npx wrangler deploy --config wrangler.monitor.toml
 * Secrets: wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.monitor.toml
 *          wrangler secret put FB_DB_URL --config wrangler.monitor.toml
 *          wrangler secret put ALERT_WEBHOOK_URL --config wrangler.monitor.toml  (incoming webhook)
 * Vars:    AI_WORKER_URL, NOTIFY_WORKER_URL (in wrangler.monitor.toml)
 * Manual:  GET https://<worker>/check
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
    'pkcs8', pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
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

async function rtdbGet(base, token, path) {
  const r = await fetch(`${base}${path}.json?access_token=${token}`);
  return r.ok ? await r.json() : null;
}
async function rtdbPut(base, token, path, val) {
  await fetch(`${base}${path}.json?access_token=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(val),
  });
}

// "reachable" = the edge responded at all (even a 4xx). Only a thrown fetch
// (DNS / connection refused) counts as down.
async function reachable(url) {
  try { await fetch(url, { method: 'GET' }); return true; } catch { return false; }
}
function ageMin(iso) {
  if (!iso) return Infinity;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? Infinity : (Date.now() - t) / 60000;
}

async function rtdbQuery(base, token, path, orderBy, startAt) {
  const url = `${base}${path}.json?access_token=${token}`
    + `&orderBy=${encodeURIComponent('"' + orderBy + '"')}`
    + `&startAt=${encodeURIComponent('"' + startAt + '"')}`;
  const r = await fetch(url);
  return r.ok ? await r.json() : null;
}

// Sends the alert via the IT-configured webhook (SuperAdmin → Reliability),
// formatted for the chosen provider; falls back to the env secret.
async function sendAlert(env, cfg, text, state, problems) {
  const w = (cfg && cfg.webhook) || {};
  const url = (w.enabled && w.url) ? w.url : env.ALERT_WEBHOOK_URL;
  if (!url) return;
  const format = (w.enabled && w.format) ? w.format : 'slack';
  let body;
  if (format === 'discord') body = { content: text };
  else if (format === 'telegram') body = { chat_id: w.chatId || '', text };
  else if (format === 'generic') body = { text, state, problems };
  else body = { text }; // slack / teams / google chat / mattermost / rocket.chat
  await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

// Pure SLO check on a daily telemetry record. Returns a problem string or null.
export function crashFreeBreach(daily, sloPercent = 99, minSessions = 20) {
  const sessions = Number((daily && daily.sessions) || 0);
  const errorSessions = Number((daily && daily.errorSessions) || 0);
  if (sessions < minSessions) return null; // not enough signal yet
  const free = Math.max(0, sessions - errorSessions) / sessions;
  const slo = (Number(sloPercent) || 99) / 100;
  if (free < slo) {
    return `Crash-free ${(free * 100).toFixed(1)}% < SLO ${sloPercent}% ` +
      `(${errorSessions}/${sessions} sessions hit errors today)`;
  }
  return null;
}

async function runChecks(env) {
  const token = await getAccessToken(env);
  const base = env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/';

  // Live config from SuperAdmin (webhook + which checks are enabled).
  const cfg = (await rtdbGet(base, token, 'monitoring_config')) || {};
  const checks = cfg.checks || {};
  const on = (k) => checks[k] !== false; // default on

  const problems = [];

  if (on('aiWorker') && env.AI_WORKER_URL && !(await reachable(`${env.AI_WORKER_URL}/config`))) {
    problems.push('AI worker unreachable');
  }
  if (on('notifyWorker') && env.NOTIFY_WORKER_URL && !(await reachable(`${env.NOTIFY_WORKER_URL}/config`))) {
    problems.push('Notify worker unreachable');
  }
  if (on('cron')) {
    const lastRun = await rtdbGet(base, token, 'workers/health/lastRun');
    const cronAge = ageMin(lastRun && (lastRun.at || lastRun.finishedAt));
    if (cronAge > 10) problems.push(`Cron stale (${Number.isFinite(cronAge) ? Math.round(cronAge) + ' min' : 'no pulse'})`);
  }
  if (on('backup')) {
    const backup = await rtdbGet(base, token, 'workers/health/backup');
    if (!backup) problems.push('No backup yet');
    else if (backup.ok === false) problems.push('Last backup FAILED: ' + (backup.error || ''));
    else if (ageMin(backup.at) > 26 * 60) problems.push(`Backup stale (${Math.round(ageMin(backup.at) / 60)} h)`);
  }
  if (on('errorSpike')) {
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const recent = await rtdbQuery(base, token, 'bugs/client', 'lastSeenAt', since);
    const n = recent ? Object.keys(recent).length : 0;
    if (n > 15) problems.push(`Error spike: ${n} distinct errors in the last hour`);
  }
  if (on('notificationBacklog')) {
    const notify = await rtdbGet(base, token, 'workers/health/notifyLastRun');
    const age = ageMin(notify && (notify.at || notify.finishedAt));
    if (age > 12) problems.push(`Notification worker stale (${Number.isFinite(age) ? Math.round(age) + ' min' : 'no pulse'})`);
  }
  if (on('appErrorBudget')) {
    const today = new Date().toISOString().slice(0, 10);
    const daily = await rtdbGet(base, token, `telemetry/daily/${today}`);
    const breach = crashFreeBreach(daily, cfg.crashFreeSlo, cfg.minSessions);
    if (breach) problems.push(breach);
  }
  if (on('modelDrift')) {
    for (const agent of ['assist', 'briefing', 'shift']) {
      const ds = await rtdbGet(base, token, `ai_model_evals/${agent}/driftStatus`);
      if (ds && ds.drift === true) {
        problems.push(`Model drift · ${agent}: ${ds.reason || 'quality regressed'}`);
      }
    }
  }

  const now = new Date().toISOString();
  const state = problems.length ? 'degraded' : 'ok';
  const prev = await rtdbGet(base, token, 'workers/health/monitor');
  const prevState = prev && prev.state;

  await rtdbPut(base, token, 'workers/health/monitor', { at: now, state, problems });

  // Alert only on transition (degraded<->ok) so we never spam every 5 minutes.
  if (state !== prevState) {
    const msg = state === 'degraded'
      ? `[ALERT] SIAS platform DEGRADED:\n- ${problems.join('\n- ')}`
      : '[OK] SIAS platform RECOVERED (all checks passing).';
    await sendAlert(env, cfg, msg, state, problems).catch(() => {});
  }
  return { state, problems };
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runChecks(env).catch((e) => console.error('monitor failed:', e.message)));
  },
  async fetch(req, env) {
    if (new URL(req.url).pathname === '/check') {
      try {
        return Response.json(await runChecks(env));
      } catch (e) {
        return Response.json({ error: e.message }, { status: 500 });
      }
    }
    return new Response('alertsys monitor worker');
  },
};
