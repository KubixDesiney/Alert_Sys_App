// boost_factories.js – add extra alerts for specific factories
'use strict';
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SA_PATH = path.join(__dirname, 'service-account.json');
if (!fs.existsSync(SA_PATH)) { console.error('service-account.json missing'); process.exit(1); }
const sa = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
const DB_URL = process.env.DATABASE_URL || `https://${sa.project_id}-default-rtdb.firebaseio.com`;

admin.initializeApp({ credential: admin.credential.cert(sa), databaseURL: DB_URL });
const db = admin.database();

const TYPES = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const FACTORIES_TO_BOOST = ['Usine A', 'Delice_B'];   // ← change these to the ones lacking alerts
const HOT = [
  { usine: 'AeroFloat', convoyeur: 1, poste: 2 },
  { usine: 'Delta',     convoyeur: 1, poste: 3 },
];

const DESC = {
  qualite: 'Quality control issue detected on the line.',
  maintenance: 'Equipment requires maintenance intervention.',
  defaut_produit: 'Product defect identified at workstation.',
  manque_ressource: 'Resource deficiency reported at production post.',
};
const FIXES = ['Part replaced', 'Adjustment completed', 'Cleaning performed', 'Supplies restocked', 'Supervised restart', 'Calibration corrected', 'Preventive maintenance', 'Operator training'];
const ri = (a,b) => Math.floor(Math.random()*(b-a+1))+a;
const pick = arr => arr[Math.floor(Math.random()*arr.length)];

async function loadSupervisors() {
  const snap = await db.ref('users').once('value');
  const map = {};
  for (const [uid, u] of Object.entries(snap.val()||{})) {
    if (!u) continue;
    if (u.role !== 'supervisor' && !uid.startsWith('sup')) continue;
    const first = (u.firstName||'').trim();
    const last = (u.lastName||'').trim();
    const fullName = first&&last ? first+' '+last : (first||last||uid);
    const usine = u.usine || pick(FACTORIES_TO_BOOST);
    (map[usine]=map[usine]||[]).push({uid, fullName});
  }
  return map;
}

async function reserveBlock(size) {
  let base = 0;
  await db.ref('alertCounter').transaction(n=>{ base=n||0; return base+size; });
  return base;
}

(async () => {
  const supsMap = await loadSupervisors();
  const now = Date.now();
  const DAY = 86400000;
  const SPAN = 30; // spread extra alerts over last 30 days
  const start = now - SPAN*DAY;
  const times = [];
  for (let d=0; d<SPAN; d++) {
    const dayStart = start + d*DAY;
    // 2-4 alerts per day per factory to give a nice boost
    for (let i=0; i<ri(2,4); i++) times.push({ts: dayStart+ri(0,86399)*1000, factory: pick(FACTORIES_TO_BOOST)});
  }
  times.sort((a,b)=>a.ts-b.ts);
  console.log(`Boosting ${FACTORIES_TO_BOOST.join(', ')} with ${times.length} extra alerts...`);

  let created=0;
  for (let i=0; i<times.length; i+=100) {
    const slice = times.slice(i,i+100);
    const base = await reserveBlock(slice.length);
    const alerts = slice.map(({ts, factory}, j) => {
      const usine = factory;
      const type = pick(TYPES);
      const isHot = Math.random()<0.3;
      const loc = isHot ? {...pick(HOT), usine} : {usine, convoyeur:ri(1,3), poste:ri(1,5)};
      const elapsed = ri(5,600);
      const resolvedAt = new Date(ts + elapsed*60000).toISOString();
      const sups = supsMap[usine]||[];
      const sup = sups.length?pick(sups):null;
      return {
        type, usine: loc.usine, convoyeur: loc.convoyeur, poste: loc.poste,
        adresse: `${loc.usine}_C${loc.convoyeur}_P${loc.poste}`,
        timestamp: new Date(ts).toISOString(),
        description: DESC[type],
        status: 'validee',
        isCritical: Math.random()<0.12,
        push_sent: true,
        superviseurId: sup?sup.uid:null,
        superviseurName: sup?sup.fullName:null,
        assistantId: null, assistantName: null,
        resolutionReason: pick(FIXES),
        elapsedTime: elapsed,
        resolvedAt,
        alertNumber: base+j+1,
        comments: [], assetId: null,
        aiAssigned: false, aiAssignmentReason: null,
        takenAtTimestamp: null, escalatedAt: null, aiAssignedAt: null,
      };
    });
    await Promise.all(alerts.map(a=>db.ref('alerts').push(a)));
    created += alerts.length;
    process.stdout.write('.');
  }
  console.log(`\nDone – added ${created} extra alerts.`);
  process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});