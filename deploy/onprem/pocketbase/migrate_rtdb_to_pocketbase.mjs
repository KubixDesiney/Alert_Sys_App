// Migrate a Firebase RTDB JSON export into the on-prem PocketBase instance.
//
//   node migrate_rtdb_to_pocketbase.mjs --input export.json --pb http://localhost:8090 \
//        --token <superuser-token> [--dry-run]
//
// `export.json` is a Firebase RTDB tree (e.g. from tool/backup_rtdb.mjs or
// `firebase database:get /`). Collections must already exist (import pb_schema.json).
// Pure transforms are exported for tests; the uploader is best-effort + idempotent-ish.
import fs from 'node:fs';

const numOrNull = (v) => (v === null || v === undefined || v === '' ? null : Number(v));
const asBool = (v) => v === true || v === 'true';
const asStr = (v) => (v === null || v === undefined ? '' : String(v));

export function rtdbAlertToRecord(a = {}) {
  return {
    alertNumber: numOrNull(a.alertNumber),
    type: asStr(a.type),
    usine: asStr(a.usine),
    convoyeur: numOrNull(a.convoyeur),
    poste: numOrNull(a.poste),
    adresse: asStr(a.adresse),
    status: asStr(a.status || 'disponible'),
    superviseurId: asStr(a.superviseurId),
    superviseurName: asStr(a.superviseurName),
    assistantId: asStr(a.assistantId),
    isCritical: asBool(a.isCritical),
    isEscalated: asBool(a.isEscalated),
    timestamp: asStr(a.timestamp),
    takenAtTimestamp: asStr(a.takenAtTimestamp),
    resolvedAt: asStr(a.resolvedAt),
    elapsedTime: numOrNull(a.elapsedTime),
    resolutionReason: asStr(a.resolutionReason || a.reason),
    aiAssigned: asBool(a.aiAssigned),
    aiAssignmentReason: asStr(a.aiAssignmentReason),
  };
}

export function rtdbUserToRecord(u = {}) {
  return {
    email: asStr(u.email),
    role: asStr(u.role || 'supervisor').toLowerCase(),
    usine: asStr(u.usine || u.factoryName),
    firstName: asStr(u.firstName),
    lastName: asStr(u.lastName),
    factoryId: asStr(u.factoryId),
    active: u.active === true || u.isActive === true || u.status === 'active',
  };
}

export function rtdbActiveToRecords(map = {}) {
  return Object.entries(map || {}).map(([uid, v]) => ({
    supervisorId: uid,
    alertId: asStr(v && (v.alertId ?? v.id)),
    status: asStr((v && v.status) || 'en_cours'),
  }));
}

export function rtdbNotificationsToRecords(map = {}) {
  const out = [];
  for (const [uid, byId] of Object.entries(map || {})) {
    for (const n of Object.values(byId || {})) {
      out.push({
        recipientId: uid,
        notifType: asStr(n && n.notifType),
        alertId: asStr(n && n.alertId),
        pushSent: !!(n && n.pushSent === true),
        createdAt: asStr(n && (n.createdAt ?? n.at)),
      });
    }
  }
  return out;
}

export function rtdbEscalationToRecord(settings = {}) {
  return { settings: settings || {} };
}

// ── uploader ──────────────────────────────────────────────────────────────
async function createRecord(pb, token, collection, body) {
  const res = await fetch(`${pb}/api/collections/${collection}/records`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: token },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${collection} create ${res.status}: ${await res.text()}`);
}

function randomPassword() {
  return 'Pb' + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2) + '!';
}

export async function migrate(input, pb, token, { dryRun = false, log = console.log } = {}) {
  const counts = { alerts: 0, users: 0, supervisor_active_alerts: 0, notifications: 0, escalation_settings: 0 };
  const send = async (collection, body) => {
    counts[collection]++;
    if (!dryRun) await createRecord(pb, token, collection, body);
  };
  for (const a of Object.values(input.alerts || {})) await send('alerts', rtdbAlertToRecord(a));
  for (const u of Object.values(input.users || {})) {
    const rec = rtdbUserToRecord(u);
    if (!rec.email) continue; // PB auth records need an email
    const pw = randomPassword();
    await send('users', { ...rec, password: pw, passwordConfirm: pw, emailVisibility: false });
  }
  for (const r of rtdbActiveToRecords(input.supervisor_active_alerts)) await send('supervisor_active_alerts', r);
  for (const r of rtdbNotificationsToRecords(input.notifications)) await send('notifications', r);
  if (input.escalation_settings) await send('escalation_settings', rtdbEscalationToRecord(input.escalation_settings));
  log(`${dryRun ? '[dry-run] would migrate' : 'migrated'}: ` +
      Object.entries(counts).map(([k, v]) => `${k}=${v}`).join(', '));
  return counts;
}

// ── CLI ───────────────────────────────────────────────────────────────────
function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? (process.argv[i + 1] ?? true) : def;
}

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const inputPath = arg('input');
  const pb = arg('pb', 'http://localhost:8090');
  const token = arg('token', '');
  const dryRun = process.argv.includes('--dry-run');
  if (!inputPath) {
    console.error('Usage: node migrate_rtdb_to_pocketbase.mjs --input export.json --pb URL --token T [--dry-run]');
    process.exit(2);
  }
  const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  migrate(input, String(pb).replace(/\/+$/, ''), token, { dryRun })
    .then(() => console.log('done'))
    .catch((e) => { console.error('migration failed:', e.message); process.exit(1); });
}
