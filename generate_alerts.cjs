/*
 * AlertSys – Validee‑Only Generator (LSTM‑ready density)
 * ======================================================
 *  - 90 days, 10 alerts per day
 *  - Every alert is status "validee" (no claimed/pending)
 *  - Supervisor name = firstName + lastName (or fallback to uid)
 *  - English descriptions, static per‑type defaults
 *  - Factories: AeroFloat, Delta, Delice_B, Usine A
 *
 *  Usage:
 *    1. firebase database:remove /alerts --project alertappsys
 *    2. node generate_validee_only.js
 */

'use strict';
const admin = require('firebase-admin');
const fs    = require('fs');
const path  = require('path');

// --------------- Bootstrap ---------------
const SA_PATH = path.join(__dirname, 'service-account.json');
if (!fs.existsSync(SA_PATH)) {
  console.error('[ERROR] service-account.json not found.');
  process.exit(1);
}
const sa = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
if (!sa.project_id) {
  console.error('[ERROR] project_id missing from service-account.json.');
  process.exit(1);
}

const DB_URL = process.env.DATABASE_URL
  || `https://${sa.project_id}-default-rtdb.firebaseio.com`;

admin.initializeApp({ credential: admin.credential.cert(sa), databaseURL: DB_URL });
const db = admin.database();

// --------------- Constants ---------------
const TYPES     = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const FACTORIES = ['AeroFloat', 'Delta', 'Delice_B', 'Usine A'];

const DEFAULT_DESCRIPTIONS = {
  qualite:          'Quality control issue detected on the line.',
  maintenance:      'Equipment requires maintenance intervention.',
  defaut_produit:   'Product defect identified at workstation.',
  manque_ressource: 'Resource deficiency reported at production post.',
};

const FIXES = [
  'Part replaced',
  'Adjustment completed',
  'Cleaning and inspection performed',
  'Supplies restocked',
  'Supervised restart completed',
  'Calibration corrected',
  'Preventive maintenance performed',
  'Operator training completed',
];

// Hot combos – locations that recur more often
const HOT = [
  { usine: 'AeroFloat', convoyeur: 1, poste: 2 },
  { usine: 'Delta',     convoyeur: 1, poste: 3 },
];

const BATCH_SIZE = 100;
const DELAY_MS   = 200;

// --------------- Helpers ---------------
const ri   = (a, b) => Math.floor(Math.random() * (b - a + 1)) + a;
const pick = arr => arr[Math.floor(Math.random() * arr.length)];

async function loadSupervisors() {
  const snap = await db.ref('users').once('value');
  const map  = {};
  for (const [uid, u] of Object.entries(snap.val() || {})) {
    if (!u) continue;
    const isSup = (u.role === 'supervisor') || uid.startsWith('sup');
    if (!isSup) continue;
    // Build proper fullName from first + last
    const first = (u.firstName || '').trim();
    const last  = (u.lastName  || '').trim();
    const fullName = first && last ? first + ' ' + last : (first || last || uid);
    const usine = u.usine || pick(FACTORIES);
    (map[usine] = map[usine] || []).push({ uid, fullName });
  }
  return map;
}

async function reserveBlock(size) {
  let base = 0;
  await db.ref('alertCounter').transaction(n => { base = n || 0; return base + size; });
  return base;
}

function genLocation() {
  return Math.random() < 0.25
    ? { ...pick(HOT) }
    : { usine: pick(FACTORIES), convoyeur: ri(1, 3), poste: ri(1, 5) };
}

function buildAlert(alertNumber, ts, supsMap) {
  const { usine, convoyeur, poste } = genLocation();
  const type = pick(TYPES);
  const elapsedTime = ri(5, 600);
  const resolvedAt   = new Date(ts + elapsedTime * 60_000).toISOString();
  const resolutionReason = pick(FIXES);

  // Pick a supervisor for this factory
  const sups = supsMap[usine] || [];
  const sup  = sups.length ? pick(sups) : null;

  let superviseurId = null, superviseurName = null;
  if (sup) {
    superviseurId   = sup.uid;
    superviseurName = sup.fullName;
  }

  // Always validee – no claimed/pending
  return {
    type, usine, convoyeur, poste,
    adresse:     `${usine}_C${convoyeur}_P${poste}`,
    timestamp:   new Date(ts).toISOString(),
    description: DEFAULT_DESCRIPTIONS[type],
    status:      'validee',
    isCritical:  Math.random() < 0.12,
    push_sent:   true,
    superviseurId, superviseurName,
    assistantId:   null, assistantName: null,
    resolutionReason, elapsedTime, resolvedAt,
    alertNumber,
    comments:          [],
    assetId:           null,
    aiAssigned:        false,
    aiAssignmentReason: null,
    takenAtTimestamp:  null,
    escalatedAt:       null,
    aiAssignedAt:      null,
  };
}

// --------------- Main ---------------
async function main() {
  console.log(`\nDatabase : ${DB_URL}`);

  const supsMap = await loadSupervisors();
  const supKeys = Object.keys(supsMap);
  console.log(`Supervisors found for : ${supKeys.length ? supKeys.join(', ') : '(none)'}`);

  const now   = Date.now();
  const DAY   = 86_400_000;
  const SPAN_DAYS = 90;            // 90 days for LSTM
  const ALERTS_PER_DAY = 10;       // 10 alerts per day
  const start = now - SPAN_DAYS * DAY;

  // Build timestamps: exactly ALERTS_PER_DAY per calendar day
  const times = [];
  for (let d = 0; d < SPAN_DAYS; d++) {
    const dayStart = start + d * DAY;
    for (let i = 0; i < ALERTS_PER_DAY; i++) {
      times.push(dayStart + ri(0, 86_399) * 1_000);
    }
  }
  times.sort((a, b) => a - b);
  console.log(`Generating ${times.length} alerts over ${SPAN_DAYS} days...\n`);

  let created = 0, critical = 0;
  const fac  = {};

  for (let i = 0; i < times.length; i += BATCH_SIZE) {
    const slice  = times.slice(i, i + BATCH_SIZE);
    const base   = await reserveBlock(slice.length);
    const alerts = slice.map((ts, j) => buildAlert(base + j + 1, ts, supsMap));

    await Promise.all(alerts.map(a => db.ref('alerts').push(a)));

    for (const a of alerts) {
      created++;
      if (a.isCritical) critical++;
      fac[a.usine] = (fac[a.usine] || 0) + 1;
      if (created % 100 === 0) process.stdout.write('.');
    }

    if (i + BATCH_SIZE < times.length) await new Promise(r => setTimeout(r, DELAY_MS));
  }

  const pct = n => `${(n / created * 100).toFixed(1)} %`;
  console.log(`\n\n${'═'.repeat(48)}`);
  console.log(`  Total alerts   : ${created}`);
  console.log(`  Critical       : ${critical.toString().padStart(5)}  (${pct(critical)})`);
  console.log(`  Status         : all validee (no claimed/pending)`);
  console.log(`\n  Per-factory breakdown:`);
  for (const [f, c] of Object.entries(fac))
    console.log(`    ${f.padEnd(14)} ${c.toString().padStart(5)}  (${pct(c)})`);
  console.log(`${'═'.repeat(48)}\n`);

  await db.app.delete();
}

main().catch(e => { console.error('\n[FATAL]', e.message || e); process.exit(1); });