// SIAS on-prem worker-runner.
// Runs assignment + escalation on a timer against the on-prem PocketBase backend
// (cloud-parity scoring is vendored), and pushes events to LAN devices over SSE.
import http from 'node:http';
import { PocketBaseStore } from './store.mjs';
import { runAssignmentCycle } from './assignment.mjs';
import { runEscalationCycle } from './escalation.mjs';
import { SseHub, recipientsForAssignment, recipientsForEscalation } from './notifications.mjs';

const PB_URL = process.env.PB_URL || 'http://pocketbase:8090';
const PB_TOKEN = process.env.PB_TOKEN || '';
const INTERVAL = Number(process.env.CRON_INTERVAL_MS || 60000);
const hub = new SseHub();

let scoring = null;
try {
  scoring = await import('./vendor/cloudflare_worker.js');
  console.log('[worker-runner] scoring bundle loaded (cloud-parity assignment)');
} catch (_) {
  console.warn('[worker-runner] scoring bundle not vendored; heartbeat-only mode');
}

let lastTick = null;
let ticks = 0;
let lastSummary = null;
let lastError = null;

async function tick() {
  ticks++;
  lastTick = new Date().toISOString();
  if (!scoring) return;
  try {
    const store = new PocketBaseStore(PB_URL, PB_TOKEN);
    const now = Date.now();
    const users = await store.listUsers();
    const a = await runAssignmentCycle(store, scoring, now);
    for (const d of a.decisions) {
      hub.broadcast(recipientsForAssignment({ superviseurId: d.uid }), { type: 'assignment', alertId: d.alertId });
    }
    const e = await runEscalationCycle(store, now);
    if (e.escalated) {
      const byId = Object.fromEntries((await store.listAlerts()).map((x) => [x.id, x]));
      for (const it of e.items) {
        hub.broadcast(recipientsForEscalation(byId[it.id] || { id: it.id }, users), { type: 'escalation', alertId: it.id, reason: it.reason });
      }
    }
    lastSummary = { assigned: a.assigned, pending: a.pending, escalated: e.escalated, connected: hub.connectedCount() };
    lastError = null;
    console.log(`[worker-runner] tick ${ticks}: assigned ${a.assigned}/${a.pending}, escalated ${e.escalated}, clients ${hub.connectedCount()}`);
  } catch (err) {
    lastError = String((err && err.message) || err);
    console.error(`[worker-runner] tick ${ticks} error: ${lastError}`);
  }
}

setInterval(tick, INTERVAL);
tick();

// The SSE endpoint is fail-closed: it needs the deployment-wide shared secret
// AND the requested uid must be bound to a PocketBase-authenticated identity.
// A deployment-wide token alone does not authorize a per-user stream — otherwise
// any LAN client could subscribe to another supervisor/admin's uid and read
// their assignment/escalation events.
function tokenOk(url) {
  const secret = process.env.WORKER_SHARED_SECRET || '';
  if (!secret) return false; // fail closed: no configured secret => deny
  const t = new URL(url, 'http://x').searchParams.get('token') || '';
  if (t.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < t.length; i++) diff |= t.charCodeAt(i) ^ secret.charCodeAt(i);
  return diff === 0;
}

// Bind the requested uid to the caller's PocketBase session. The client passes
// its PocketBase auth token (query `pb` or Authorization header); we refresh it
// against PocketBase and require the resulting record id to equal uid — admins
// may subscribe to any uid. No valid session => 403.
async function authorizedForUid(pbToken, uid) {
  if (!pbToken || !uid) return false;
  try {
    const r = await fetch(`${PB_URL.replace(/\/+$/, '')}/api/collections/users/auth-refresh`, {
      method: 'POST',
      headers: { Authorization: pbToken },
    });
    if (!r.ok) return false;
    const j = await r.json();
    const rec = j && j.record;
    if (!rec || !rec.id) return false;
    const role = String(rec.role || '').toLowerCase();
    return rec.id === uid || role === 'admin' || role === 'superadmin';
  } catch (_) {
    return false;
  }
}

http
  .createServer(async (req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: !lastError, ticks, lastTick, lastSummary, lastError, scoring: !!scoring, backend: PB_URL }));
      return;
    }
    if (req.url.startsWith('/events')) {
      if (!tokenOk(req.url)) { res.writeHead(401); res.end(); return; }
      const parsed = new URL(req.url, 'http://x');
      const uid = parsed.searchParams.get('uid');
      if (!uid) { res.writeHead(400); res.end(); return; }
      const pbToken = parsed.searchParams.get('pb') || req.headers['authorization'] || '';
      if (!(await authorizedForUid(pbToken, uid))) { res.writeHead(403); res.end(); return; }
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
      res.write('retry: 5000\n\n');
      hub.connect(uid, res);
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(8787, () => console.log('[worker-runner] health on :8787/health, SSE on :8787/events?uid='));

export { tokenOk, authorizedForUid };
