'use strict';
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SA_PATH = path.join(__dirname, 'service-account.json');
if (!fs.existsSync(SA_PATH)) {
  console.error('[ERROR] service-account.json not found.');
  process.exit(1);
}
const sa = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
const DB_URL = process.env.DATABASE_URL
  || `https://${sa.project_id}-default-rtdb.firebaseio.com`;

admin.initializeApp({ credential: admin.credential.cert(sa), databaseURL: DB_URL });
const db = admin.database();

async function reset() {
  const snap = await db.ref('alerts').once('value');
  const updates = {};
  let count = 0;

  snap.forEach(alert => {
    const data = alert.val();
    if (data && data.push_sent === true) {
      // Only include 'status' alerts that are not 'validee' to skip resolved ones
      updates[`alerts/${alert.key}/push_sent`] = false;
      count++;
    }
  });

  if (count === 0) {
    console.log('All alerts already have push_sent: false.');
    process.exit(0);
  }

  console.log(`Resetting push_sent to false on ${count} alerts...`);
  await db.ref().update(updates);
  console.log(`Done. ${count} alerts updated.`);
  process.exit(0);
}

reset().catch(e => {
  console.error('Script failed:', e.message || e);
  process.exit(1);
});