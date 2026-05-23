'use strict';
const admin = require('firebase-admin');
const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(sa), databaseURL: 'https://alertappsys-default-rtdb.firebaseio.com' });
const db = admin.database();
async function cleanup() {
  const snap = await db.ref('alerts').once('value');
  const batch = {};
  let count = 0;
  snap.forEach(a => {
    if (a.val().description && a.val().description.startsWith('FLOOD_TEST_')) {
      batch['alerts/' + a.key] = null;
      count++;
    }
  });
  if (count > 0) {
    await db.ref().update(batch);
    console.log('Deleted ' + count + ' flood test alerts.');
  } else {
    console.log('No flood test alerts found.');
  }
  process.exit(0);
}
cleanup().catch(e => { console.error(e); process.exit(1); });
