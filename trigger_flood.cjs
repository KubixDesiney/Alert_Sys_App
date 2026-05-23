// trigger_flood.js – Creates 50 test alerts to trigger alert flood anomaly
'use strict';
const admin = require('firebase-admin');

// Use the same service account credentials as other scripts.
// You can either read from file or use the environment variable.
let sa;
try {
  sa = require('./service-account.json');
} catch (_) {
  sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
}
if (!sa.project_id) {
  console.error('No project_id found.');
  process.exit(1);
}

const DB_URL = process.env.DATABASE_URL
  || `https://${sa.project_id}-default-rtdb.firebaseio.com`;

admin.initializeApp({
  credential: admin.credential.cert(sa),
  databaseURL: DB_URL,
});
const db = admin.database();

const TEST_PREFIX = 'FLOOD_TEST_';   // used to identify and delete these alerts

async function createFloodAlerts() {
  const now = Date.now();
  const alerts = [];
  for (let i = 0; i < 50; i++) {
    // Stagger timestamps within the last 30 seconds so they all fall in the worker's 60-second window
    const ts = new Date(now - i * 500).toISOString();
    alerts.push({
      type: 'qualite',
      usine: 'AeroFloat',      // any existing factory
      convoyeur: 1,
      poste: 1,
      adresse: `AeroFloat_C1_P1`,
      description: TEST_PREFIX + i,
      status: 'disponible',    // unclaimed, just like real new alerts
      timestamp: ts,
      push_sent: true,         // don't send actual push notifications
      isCritical: false,
    });
  }

  // Write all 50 alerts in parallel
  await Promise.all(alerts.map(a => db.ref('alerts').push(a)));
  console.log('50 flood test alerts created.');
  await db.app.delete();
}

createFloodAlerts().catch(e => { console.error(e); process.exit(1); });