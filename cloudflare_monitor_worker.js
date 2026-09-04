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

import { harvestSamples, summarize, deliveryBreaches, deliveryLatencyMs, DEFAULT_TARGETS } from './slo_delivery.js';

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
  if (on('deliveryLatency')) {
    // Passive harvest: read the last hour of alerts and measure created -> push_sent_at
    // latency. No change to the delivery hot path; reuses fields already written.
    const sinceMs = Date.now() - 60 * 60 * 1000;
    const sinceIso = new Date(sinceMs).toISOString();
    const recent = await rtdbQuery(base, token, 'alerts', 'timestamp', sinceIso);
    const h = harvestSamples(recent || {}, sinceMs, 'push_sent_at');
    const sum = summarize(h.samples);
    const nowIso = new Date().toISOString();
    const snapshot = {
      at: nowIso,
      windowMin: 60,
      profile: 'accepted',
      count: sum.count,
      p50Ms: sum.p50,
      p95Ms: sum.p95,
      p99Ms: sum.p99,
      maxMs: sum.maxMs,
      total: h.total,
      delivered: h.delivered,
      successRate: h.successRate == null ? null : Math.round(h.successRate * 10000) / 10000,
    };
    const day = nowIso.slice(0, 10);
    const hour = nowIso.slice(11, 13);
    await rtdbPut(base, token, 'slo/delivery/latest', snapshot);
    await rtdbPut(base, token, `slo/delivery/byHour/${day}/${hour}`, snapshot);
    for (const b of deliveryBreaches(sum, h.successRate, DEFAULT_TARGETS, 'accepted')) problems.push(b);

    // True end-to-end: created -> received_at (first device ack, written by the
    // app in phase 2). Empty until clients ship the new build -> no false breach.
    const hr = harvestSamples(recent || {}, sinceMs, 'received_at');
    const sumr = summarize(hr.samples);
    await rtdbPut(base, token, 'slo/delivery/received/latest', {
      at: nowIso,
      windowMin: 60,
      profile: 'received',
      count: sumr.count,
      p50Ms: sumr.p50,
      p95Ms: sumr.p95,
      p99Ms: sumr.p99,
      maxMs: sumr.maxMs,
      total: hr.total,
      delivered: hr.delivered,
      successRate: hr.successRate == null ? null : Math.round(hr.successRate * 10000) / 10000,
    });
    for (const b of deliveryBreaches(sumr, hr.successRate, DEFAULT_TARGETS, 'received')) problems.push(b);
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
  if (on('canary')) {
    // Synthetic-alert dead-man's switch. Two-phase across runs: measure the
    // previous probe, then launch a fresh one through the REAL notify path.
    // The reserved '__canary__' factory has no supervisors, so nobody is paged.
    const CANARY_ID = '__canary__';
    const nowIso2 = new Date().toISOString();
    const pending = await rtdbGet(base, token, 'slo/canary/pending');
    if (pending && pending.createdAt) {
      const cur = (await rtdbGet(base, token, `alerts/${CANARY_ID}`)) || {};
      const done = cur.received_at || cur.push_sent_at;
      let rec;
      if (done) {
        const latencyMs = deliveryLatencyMs(pending.createdAt, done);
        const ok = latencyMs != null && latencyMs <= DEFAULT_TARGETS.canaryMs;
        rec = {
          at: nowIso2,
          ok,
          latencyMs,
          createdAt: pending.createdAt,
          reason: ok ? 'ok' : `delivered in ${(latencyMs / 1000).toFixed(1)}s > ${(DEFAULT_TARGETS.canaryMs / 1000).toFixed(0)}s target`,
        };
      } else {
        rec = { at: nowIso2, ok: false, latencyMs: null, createdAt: pending.createdAt, reason: 'not delivered — alert pipeline may be down' };
      }
      await rtdbPut(base, token, 'slo/canary/latest', rec);
      await rtdbPut(base, token, `slo/canary/history/${nowIso2.slice(0, 10)}/${nowIso2.slice(11, 16).replace(':', '-')}`, rec);
      if (!rec.ok) problems.push(`Alert canary: ${rec.reason}`);
    }
    // Launch the next probe: a fresh synthetic alert through the real trigger.
    await rtdbPut(base, token, `alerts/${CANARY_ID}`, {
      synthetic: true,
      usine: '__canary__',
      factoryId: '__canary__',
      adresse: 'canary',
      convoyeur: 0,
      poste: 0,
      type: 'canary',
      timestamp: nowIso2,
      status: 'disponible',
      push_sent: false,
    });
    await rtdbPut(base, token, 'slo/canary/pending', { id: CANARY_ID, createdAt: nowIso2 });
    if (env.NOTIFY_WORKER_URL) {
      try {
        const headers = { 'Content-Type': 'application/json' };
        // Notify worker runs WORKER_AUTH_MODE=required; authenticate the
        // worker-to-worker canary trigger with the shared secret.
        const secret = env.WORKER_SHARED_SECRET || env.ALERTSYS_WORKER_SHARED_SECRET || '';
        if (secret) headers['x-worker-secret'] = secret;
        await fetch(env.NOTIFY_WORKER_URL, {
          method: 'POST',
          headers,
          body: JSON.stringify({ alertId: CANARY_ID }),
        });
      } catch (_) {}
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

// Public, sanitized status summary for the customer-facing status page.
// Reads SLO + monitor health via the service account; returns no PII or secrets.
async function buildStatus(env) {
  const token = await getAccessToken(env);
  const base = env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/';
  const [mon, acc, rec, can] = await Promise.all([
    rtdbGet(base, token, 'workers/health/monitor'),
    rtdbGet(base, token, 'slo/delivery/latest'),
    rtdbGet(base, token, 'slo/delivery/received/latest'),
    rtdbGet(base, token, 'slo/canary/latest'),
  ]);
  const round = (v) => (typeof v === 'number' ? Math.round(v) : null);
  const canOk = !can || can.ok !== false;
  const monState = (mon && mon.state) || 'unknown';
  const state = (monState === 'degraded' || !canOk) ? 'degraded' : (monState === 'ok' ? 'operational' : 'unknown');
  const slim = (s) => (s ? { p95Ms: round(s.p95Ms), p99Ms: round(s.p99Ms), successRate: s.successRate ?? null, count: s.count ?? 0 } : null);
  return {
    service: 'Alert delivery',
    state,
    updatedAt: new Date().toISOString(),
    accepted: slim(acc),
    received: slim(rec),
    canary: can ? { ok: can.ok !== false, latencyMs: round(can.latencyMs), at: can.at || null } : null,
  };
}

function statusHtml(s) {
  const color = s.state === 'operational' ? '#1a7f37' : (s.state === 'degraded' ? '#9a6700' : '#6e7781');
  const label = s.state === 'operational' ? 'All systems operational' : (s.state === 'degraded' ? 'Degraded performance' : 'Status unknown');
  const ms = (v) => (v == null ? '—' : `${(v / 1000).toFixed(1)}s`);
  const pct = (v) => (v == null ? '—' : `${(v * 100).toFixed(2)}%`);
  const tile = (t, v) => `<div style="flex:1;min-width:130px;background:#f6f8fa;border-radius:10px;padding:14px 16px"><div style="font-size:12px;color:#57606a">${t}</div><div style="font-size:22px;font-weight:500;margin-top:4px">${v}</div></div>`;
  const acc = s.accepted || {};
  const rec = s.received || {};
  const can = s.canary || {};
  const success = rec.successRate != null ? rec.successRate : acc.successRate;
  return '<!doctype html><html><head><meta charset="utf-8">'
    + '<meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<meta http-equiv="refresh" content="60"><title>SIAS status</title></head>'
    + '<body style="margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#1f2328;background:#fff">'
    + '<div style="max-width:720px;margin:0 auto;padding:32px 20px">'
    + `<div style="display:flex;align-items:center;gap:12px"><span style="width:14px;height:14px;border-radius:50%;background:${color};display:inline-block"></span>`
    + `<h1 style="font-size:22px;font-weight:500;margin:0">${label}</h1></div>`
    + `<p style="color:#57606a;font-size:14px;margin:8px 0 24px">SIAS — alert delivery · updated ${new Date(s.updatedAt).toUTCString()}</p>`
    + '<div style="display:flex;gap:12px;flex-wrap:wrap">'
    + tile('Accepted p95', ms(acc.p95Ms))
    + tile('Received p95', ms(rec.p95Ms))
    + tile('Delivery success', pct(success))
    + tile('Canary', can.ok === false ? 'Failing' : (can.latencyMs != null ? ms(can.latencyMs) : 'OK'))
    + '</div>'
    + '<p style="color:#8c959f;font-size:12px;margin-top:24px">Advisory notification layer. Latency is measured from alert creation to device delivery. Page refreshes every 60 seconds.</p>'
    + '</div></body></html>';
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runChecks(env).catch((e) => console.error('monitor failed:', e.message)));
  },
  async fetch(req, env) {
    const path = new URL(req.url).pathname;
    if (path === '/check') {
      try {
        return Response.json(await runChecks(env));
      } catch (e) {
        // Never echo the exception: these routes are public and a failed
        // fetch() puts the whole request URL in e.message -- including the
        // ?access_token= of the Firebase service account. Log it, return a
        // generic body. (See the /status HTML branch, which already did this.)
        console.error('monitor /check failed:', (e && e.message) || e);
        return Response.json({ error: 'check_failed' }, { status: 500 });
      }
    }
    if (path === '/status.json') {
      try {
        return new Response(JSON.stringify(await buildStatus(env)), { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
      } catch (e) {
        console.error('monitor /status.json failed:', (e && e.message) || e);
        return new Response(JSON.stringify({ state: 'unknown', error: 'status_unavailable' }), { status: 500, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
      }
    }
    if (path === '/status' || path === '/') {
      try {
        return new Response(statusHtml(await buildStatus(env)), { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Access-Control-Allow-Origin': '*' } });
      } catch (e) {
        return new Response('status unavailable', { status: 500 });
      }
    }
    return new Response('alertsys monitor worker');
  },
};
