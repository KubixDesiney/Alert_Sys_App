#!/usr/bin/env node
/**
 * One-time migration: move sensitive user fields out of the broadly-readable
 * `users/{uid}` node into the access-scoped `users_private/{uid}` node.
 *
 * WHY: Firebase RTDB cascades read permission downward, so the collection-level
 * `.read` on `users` exposes every user's email / phone / fcmToken /
 * currentLocation to any authenticated user. `users_private` is readable only by
 * the owner and admins (see database.rules.json).
 *
 * SAFE ROLLOUT ORDER (do not skip):
 *   1. Deploy the updated database.rules.json (adds `users_private`).
 *   2. Ship the app + worker changes that WRITE and READ these fields at
 *      `users_private/{uid}` (workers read fcmToken; locator/proximity read
 *      currentLocation; admin UIs read email/phone). Test push + login + roster.
 *   3. Run this script with --apply to copy existing data into users_private.
 *   4. Verify push, login, locator, and supervisor management still work.
 *   5. Re-run with --apply --purge to delete the now-duplicated fields from
 *      `users/{uid}` (this is the step that actually closes the exposure).
 *
 * USAGE:
 *   SA_PATH=./service-account.json \
 *   FB_DB_URL=https://<project>.firebaseio.com \
 *   node tool/migrate_user_pii.mjs            # dry run (prints plan only)
 *   ... node tool/migrate_user_pii.mjs --apply           # copy to users_private
 *   ... node tool/migrate_user_pii.mjs --apply --purge   # + strip from users
 */
import admin from 'firebase-admin';
import { readFileSync } from 'fs';

// Stage 1 (app-only) moves email/phone. fcmToken/currentLocation are read by
// the workers, so only migrate them in Stage 2 AFTER the workers read from
// users_private — pass --fields=fcmToken,currentLocation then.
const fieldsArg = process.argv.find((a) => a.startsWith('--fields='));
const SENSITIVE = fieldsArg
  ? fieldsArg.slice('--fields='.length).split(',').map((s) => s.trim()).filter(Boolean)
  : ['email', 'phone'];
const APPLY = process.argv.includes('--apply');
const PURGE = process.argv.includes('--purge');

const dbUrl = process.env.FB_DB_URL;
const saPath = process.env.SA_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!dbUrl || !saPath) {
  console.error('ERROR: set SA_PATH=./service-account.json and FB_DB_URL=https://<project>.firebaseio.com');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(readFileSync(saPath, 'utf8'))),
  databaseURL: dbUrl,
});

const db = admin.database();

async function main() {
  const snap = await db.ref('users').get();
  if (!snap.exists()) {
    console.log('No users found. Nothing to do.');
    return;
  }
  const users = snap.val();
  let copied = 0;
  let purged = 0;

  for (const [uid, rec] of Object.entries(users)) {
    if (!rec || typeof rec !== 'object') continue;
    const priv = {};
    for (const f of SENSITIVE) {
      if (rec[f] !== undefined && rec[f] !== null) priv[f] = rec[f];
    }
    if (Object.keys(priv).length === 0) continue;

    console.log(`${uid}: ${Object.keys(priv).join(', ')}`);
    if (APPLY) {
      await db.ref(`users_private/${uid}`).update(priv);
      copied++;
      if (PURGE) {
        const nulls = {};
        for (const f of Object.keys(priv)) nulls[`users/${uid}/${f}`] = null;
        await db.ref().update(nulls);
        purged++;
      }
    }
  }

  if (!APPLY) {
    console.log('\nDRY RUN — no writes performed. Re-run with --apply to copy.');
  } else {
    console.log(`\nCopied ${copied} user(s) to users_private.` +
      (PURGE ? ` Stripped fields from ${purged} user(s) in /users.` : ''));
  }
  process.exit(0);
}

main().catch((e) => {
  console.error('Migration failed:', e);
  process.exit(1);
});
