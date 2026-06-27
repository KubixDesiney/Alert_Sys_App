#!/usr/bin/env node
// Synthetic smoke test for a SIAS instance.
//
// Probes the worker liveness + security endpoints and verifies the cron health
// pulses in RTDB are fresh. Exits non-zero on any breach so it can gate CI /
// uptime monitoring (see docs/ops/OBSERVABILITY.md, .github/workflows/uptime.yml).
//
// Zero dependencies — Node 18+ global fetch only.
//
// Config (env):
//   ALERTSYS_AI_WORKER_URL       e.g. https://alert-notifier.<sub>.workers.dev
//   ALERTSYS_NOTIFY_WORKER_URL   e.g. https://alertsys.<sub>.workers.dev
//   FB_DB_URL                    e.g. https://<proj>-default-rtdb.firebaseio.com
//   WORKER_SHARED_SECRET         optional; sent as x-alertsys-secret on protected routes
//   FB_DB_ACCESS_TOKEN           optional; bearer/?access_token for protected RTDB reads
//   SMOKE_MAX_PULSE_AGE_S        max acceptable health-pulse age, default 120
//   SMOKE_TIMEOUT_MS             per-request timeout, default 8000

const AI = trimSlash(process.env.ALERTSYS_AI_WORKER_URL || '');
const NOTIFY = trimSlash(process.env.ALERTSYS_NOTIFY_WORKER_URL || '');
const DB = trimSlash(process.env.FB_DB_URL || '');
const SECRET = process.env.WORKER_SHARED_SECRET || '';
const DB_TOKEN = process.env.FB_DB_ACCESS_TOKEN || '';
const MAX_PULSE_AGE_S = Number(process.env.SMOKE_MAX_PULSE_AGE_S || 120);
const TIMEOUT_MS = Number(process.env.SMOKE_TIMEOUT_MS || 8000);

const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail: detail || '' });
}

function trimSlash(u) {
  return u.replace(/\/+$/, '');
}

async function fetchWithTimeout(url, opts = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...opts, signal: ctrl.signal });
  } finally {
    clearTimeout(t);
  }
}

async function checkEndpoint(label, base, path, { secret = false } = {}) {
  if (!base) {
    record(label, true, 'skipped (no URL configured)');
    return;
  }
  const headers = {};
  if (secret && SECRET) headers['x-alertsys-secret'] = SECRET;
  const started = Date.now();
  try {
    const res = await fetchWithTimeout(base + path, { headers });
    const ms = Date.now() - started;
    const ok = res.status >= 200 && res.status < 500; // 4xx (e.g. auth) still = alive
    record(label, ok, `HTTP ${res.status} in ${ms} ms`);
  } catch (e) {
    record(label, false, `request failed: ${String(e.message || e)}`);
  }
}

async function checkPulse(label, node) {
  if (!DB) {
    record(label, true, 'skipped (no FB_DB_URL)');
    return;
  }
  let url = `${DB}/${node}.json`;
  if (DB_TOKEN) url += `?access_token=${encodeURIComponent(DB_TOKEN)}`;
  try {
    const res = await fetchWithTimeout(url);
    if (res.status === 401 || res.status === 403) {
      record(label, true, `skipped (RTDB read protected: HTTP ${res.status})`);
      return;
    }
    if (!res.ok) {
      record(label, false, `HTTP ${res.status}`);
      return;
    }
    const data = await res.json();
    if (!data) {
      record(label, false, 'no pulse written yet');
      return;
    }
    const at = data.at || data.ts || data.lastRunAt || data.time;
    const ageS = at ? Math.round((Date.now() - new Date(at).getTime()) / 1000) : null;
    if (ageS == null) {
      record(label, true, 'pulse present (no timestamp field)');
    } else {
      record(label, ageS <= MAX_PULSE_AGE_S, `age ${ageS}s (max ${MAX_PULSE_AGE_S}s)`);
    }
  } catch (e) {
    record(label, false, `request failed: ${String(e.message || e)}`);
  }
}

async function main() {
  await Promise.all([
    checkEndpoint('AI worker /config', AI, '/config'),
    checkEndpoint('AI worker /security-status', AI, '/security-status', { secret: true }),
    checkEndpoint('Notify worker /config', NOTIFY, '/config'),
  ]);
  await Promise.all([
    checkPulse('AI cron freshness', 'workers/health/lastRun'),
    checkPulse('Notify cron freshness', 'workers/health/notifyLastRun'),
  ]);

  const pad = Math.max(...results.map((r) => r.name.length));
  let failed = 0;
  for (const r of results) {
    if (!r.ok) failed++;
    const mark = r.ok ? 'PASS' : 'FAIL';
    console.log(`[${mark}] ${r.name.padEnd(pad)}  ${r.detail}`);
  }
  console.log(`\n${results.length - failed}/${results.length} checks passed.`);
  if (failed > 0) {
    console.error(`SMOKE TEST FAILED: ${failed} check(s) breached.`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('smoke test crashed:', e);
  process.exit(2);
});
