// SIAS on-prem worker-runner.
// Replaces the Cloudflare workers for air-gapped sites: assignment,
// escalation, alert ingestion (dedup + storm protection), LAN SSE fan-out,
// retention, local backups, audit trail, licence validation and health.
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { PocketBaseStore } from './store.mjs';
import { runAssignmentCycle } from './assignment.mjs';
import { runEscalationCycle } from './escalation.mjs';
import {
  SseHub, recipientsForAssignment, recipientsForEscalation, recipientsForNewAlert,
} from './notifications.mjs';
import { DedupGuard } from './dedup.mjs';
import { ingestAlert } from './ingest.mjs';
import { ChangeWatcher } from './changes.mjs';
import { runRetentionCycle } from './retention.mjs';
import { runBackup, makeArchiveSink } from './backup.mjs';
import { AuditTrail } from './audit.mjs';
import { makeLogger } from './logger.mjs';
import { LicenseGuard } from '../license/license_guard.mjs';

const PB_URL = process.env.PB_URL || 'http://pocketbase:8090';
const PB_TOKEN = process.env.PB_TOKEN || '';
const INTERVAL = Number(process.env.CRON_INTERVAL_MS || 60000);
const BACKUP_DIR = process.env.BACKUP_DIR || '/backups';
const RETENTION_DAYS = Number(process.env.RETENTION_DAYS || 365);
const BACKUP_KEEP = Number(process.env.BACKUP_KEEP || 14);
const AUDIT_FILE = process.env.AUDIT_FILE || `${BACKUP_DIR}/audit.jsonl`;

const log = makeLogger('worker-runner');
const hub = new SseHub();
hub.startHeartbeat(25000);

const store = new PocketBaseStore(PB_URL, PB_TOKEN);
const audit = new AuditTrail(store, { file: AUDIT_FILE, log });
const guard = new DedupGuard({
  maxPerMinuteGlobal: Number(process.env.STORM_MAX_PER_MIN || 60),
  maxPerMinutePerSource: Number(process.env.STORM_MAX_PER_MIN_PER_SOURCE || 20),
  dedupWindowMs: Number(process.env.DEDUP_WINDOW_MS || 5 * 60_000),
});
const watcher = new ChangeWatcher();

const license = new LicenseGuard({
  publicKeyPem: process.env.LICENSE_PUBLIC_KEY_FILE && existsSync(process.env.LICENSE_PUBLIC_KEY_FILE)
    ? readFileSync(process.env.LICENSE_PUBLIC_KEY_FILE, 'utf8')
    : (process.env.LICENSE_PUBLIC_KEY || ''),
  licenseFile: process.env.LICENSE_FILE || null,
  serverUrl: process.env.LICENSE_SERVER_URL || null,
  installationId: process.env.INSTALLATION_ID || 'unregistered',
  softwareVersion: process.env.SIAS_VERSION || 'dev',
  graceDays: Number(process.env.LICENSE_GRACE_DAYS || 7),
  cachePath: process.env.LICENSE_CACHE || `${BACKUP_DIR}/.license-cache.json`,
  log,
});

let scoring = null;
try {
  scoring = await import('./vendor/cloudflare_worker.js');
  log.info('scoring bundle loaded (cloud-parity assignment)');
} catch (_) {
  log.warn('scoring bundle not vendored; assignment runs in heartbeat-only mode');
}

let lastTick = null;
let ticks = 0;
let lastSummary = null;
let lastError = null;
let lastRetention = null;
let lastBackup = null;
let lastMaintenanceDay = '';
const ingestStats = { created: 0, duplicates: 0, suppressed: 0, invalid: 0 };

async function fanOutEvents(events, users) {
  for (const ev of events) {
    const a = ev.alert || {};
    let recipients = [];
    if (ev.type === 'new_alert') {
      recipients = recipientsForNewAlert(a, users);
    } else if (ev.type === 'critical_update') {
      recipients = users
        .filter((u) => !String(u.role || '').toLowerCase().startsWith('vendor'))
        .map((u) => u.uid);
    } else if (ev.type === 'alert_suspended') {
      recipients = users
        .filter((u) => ['company_owner', 'production_manager', 'admin']
          .includes(String(u.role || '').toLowerCase()))
        .map((u) => u.uid);
    } else if (ev.type === 'alert_claimed' || ev.type === 'alert_resolved') {
      recipients = recipientsForAssignment(a);
    }
    if (!recipients.length) continue;
    hub.broadcast(recipients, { type: ev.type, alertId: a.id, usine: a.usine, isCritical: !!a.isCritical });
    // Persist rows so devices that were offline still catch up in-app.
    for (const uid of recipients) {
      try {
        await store.addNotification({
          recipientId: uid,
          notifType: ev.type,
          alertId: a.id,
          title: ev.type.replace(/_/g, ' '),
          body: a.description || '',
          pushSent: true,
          createdAt: new Date().toISOString(),
        });
      } catch (err) {
        log.warn('notification row write failed', { err: String((err && err.message) || err) });
      }
    }
  }
}

async function tick() {
  ticks++;
  lastTick = new Date().toISOString();
  try {
    await license.check();
    const users = await store.listUsers();

    let assignment = { assigned: 0, pending: 0, decisions: [] };
    if (scoring) {
      assignment = await runAssignmentCycle(store, scoring, Date.now());
      for (const d of assignment.decisions) {
        hub.broadcast(recipientsForAssignment({ superviseurId: d.uid }), { type: 'assignment', alertId: d.alertId });
        await audit.record('ai.assignment', { targetType: 'alert', targetId: d.alertId, detail: `assigned to ${d.uid}` });
      }
    }

    const escalation = await runEscalationCycle(store, Date.now());
    const alerts = await store.listAlerts();
    if (escalation.escalated) {
      const byId = Object.fromEntries(alerts.map((x) => [x.id, x]));
      for (const it of escalation.items) {
        hub.broadcast(recipientsForEscalation(byId[it.id] || { id: it.id }, users), { type: 'escalation', alertId: it.id, reason: it.reason });
        await audit.record('alert.escalate', { targetType: 'alert', targetId: it.id, detail: it.reason });
      }
    }

    // Lifecycle fan-out from data changes (new/critical/suspend/resolve),
    // replacing the Firebase-client-side notification paths.
    await fanOutEvents(watcher.diff(alerts), users);

    // Daily maintenance (retention + backup) after 02:00 local.
    const today = new Date().toISOString().slice(0, 10);
    if (lastMaintenanceDay !== today && new Date().getHours() >= 2) {
      lastMaintenanceDay = today;
      try {
        lastRetention = await runRetentionCycle(store, {
          retentionDays: RETENTION_DAYS,
          archive: makeArchiveSink(BACKUP_DIR),
          audit: audit.bind(),
        });
        lastBackup = await runBackup(store, BACKUP_DIR, { keep: BACKUP_KEEP, audit: audit.bind() });
      } catch (err) {
        log.error('maintenance failed', { err: String((err && err.message) || err) });
      }
    }

    lastSummary = {
      assigned: assignment.assigned,
      pending: assignment.pending,
      escalated: escalation.escalated,
      connected: hub.connectedCount(),
      license: license.state.status,
    };
    lastError = null;
    log.info('tick', { n: ticks, ...lastSummary });
  } catch (err) {
    lastError = String((err && err.message) || err);
    log.error('tick failed', { n: ticks, err: lastError });
  }
}

setInterval(tick, INTERVAL);
tick();

// ── HTTP auth helpers ────────────────────────────────────────────────────────

// The SSE endpoint is fail-closed: it needs the deployment-wide shared secret
// AND the requested uid must be bound to a PocketBase-authenticated identity.
function timingSafeEq(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function tokenOk(url) {
  const secret = process.env.WORKER_SHARED_SECRET || '';
  if (!secret) return false; // fail closed: no configured secret => deny
  const t = new URL(url, 'http://x').searchParams.get('token') || '';
  return timingSafeEq(t, secret);
}

const MANAGING_ROLES = new Set(['admin', 'superadmin', 'company_owner', 'production_manager']);

// Bind the requested uid to the caller's PocketBase session; managing roles
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
    if (!rec || !rec.id || rec.disabled === true) return false;
    const role = String(rec.role || '').toLowerCase();
    return rec.id === uid || MANAGING_ROLES.has(role);
  } catch (_) {
    return false;
  }
}

// Ingest callers: the Edge Gateway (Bearer WORKER_SHARED_SECRET) or a named
// integration key from INGEST_KEYS ("name1:key1,name2:key2").
function ingestCaller(req) {
  const auth = String(req.headers.authorization || '');
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const secret = process.env.WORKER_SHARED_SECRET || '';
  if (secret && bearer && timingSafeEq(bearer, secret)) return 'gateway';
  const provided = String(req.headers['x-ingest-key'] || bearer || '');
  for (const pair of String(process.env.INGEST_KEYS || '').split(',')) {
    const [name, key] = pair.split(':').map((s) => (s || '').trim());
    if (name && key && provided && timingSafeEq(provided, key)) return name;
  }
  return null;
}

const MAX_INGEST_BYTES = 64 * 1024;

function readBody(req, limit = MAX_INGEST_BYTES) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (c) => {
      raw += c;
      if (raw.length > limit) {
        reject(Object.assign(new Error('payload too large'), { status: 413 }));
        req.destroy();
      }
    });
    req.on('end', () => resolve(raw));
    req.on('error', reject);
  });
}

// ── HTTP server ──────────────────────────────────────────────────────────────
http
  .createServer(async (req, res) => {
    const respond = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    try {
      if (req.url === '/health') {
        return respond(lastError ? 503 : 200, {
          ok: !lastError,
          ticks,
          lastTick,
          lastSummary,
          lastError,
          scoring: !!scoring,
          backend: PB_URL,
          storeReachable: await store.ping(),
          license: license.state,
          ingest: ingestStats,
          lastRetention,
          lastBackup: lastBackup ? { file: lastBackup.file, counts: lastBackup.counts } : null,
        });
      }
      if (req.url === '/ready') {
        const up = await store.ping();
        return respond(up ? 200 : 503, { ready: up });
      }
      if (req.url === '/license-status') {
        return respond(200, license.state);
      }
      if (req.method === 'POST' && req.url === '/ingest') {
        const caller = ingestCaller(req);
        if (!caller) return respond(401, { error: 'unauthorized' });
        let payload;
        try {
          payload = JSON.parse(await readBody(req));
        } catch (err) {
          return respond(err && err.status === 413 ? 413 : 400, { error: err.message || 'invalid JSON' });
        }
        const result = await ingestAlert(store, guard, { source: caller, ...payload }, { audit: audit.bind() });
        ingestStats[result.status === 'created' ? 'created'
          : result.status === 'duplicate' ? 'duplicates'
            : result.status === 'suppressed' ? 'suppressed' : 'invalid']++;
        if (result.status === 'created') {
          // Immediate wake-up; the per-tick ChangeWatcher remains the durable
          // fallback if this fan-out is missed.
          const users = await store.listUsers();
          const created = (await store.listAlerts()).find((a) => a.id === result.id);
          if (created) await fanOutEvents([{ type: 'new_alert', alert: created }], users);
        }
        return respond(result.status === 'invalid' ? 422 : 200, { requestId: randomUUID(), ...result });
      }
      if (req.url.startsWith('/events')) {
        if (!tokenOk(req.url)) { res.writeHead(401); res.end(); return undefined; }
        const parsed = new URL(req.url, 'http://x');
        const uid = parsed.searchParams.get('uid');
        if (!uid) { res.writeHead(400); res.end(); return undefined; }
        const pbToken = parsed.searchParams.get('pb') || req.headers.authorization || '';
        if (!(await authorizedForUid(pbToken, uid))) { res.writeHead(403); res.end(); return undefined; }
        res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
        res.write('retry: 5000\n\n');
        hub.connect(uid, res);
        return undefined;
      }
      res.writeHead(404);
      return res.end();
    } catch (err) {
      log.error('request failed', { url: req.url, err: String((err && err.message) || err) });
      return respond(500, { error: 'internal' });
    }
  })
  .listen(8787, () => log.info('listening', { health: ':8787/health', sse: ':8787/events', ingest: ':8787/ingest' }));

export { tokenOk, authorizedForUid };
