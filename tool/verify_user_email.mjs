#!/usr/bin/env node
/**
 * Mark a user's email as verified.
 *
 * Firebase blocks enrolling a second factor (MFA) until the account's email is
 * verified. Admin-created accounts (SuperAdmin, Production Managers) often aren't,
 * so this flips the flag for them without waiting on a verification email.
 *
 * Usage:
 *   SA_PATH="C:\\path\\to\\service-account.json" node tool/verify_user_email.mjs user@email.com
 */
import admin from 'firebase-admin';
import { readFileSync } from 'fs';

const saPath = process.env.SA_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;
const email = process.argv[2];

if (!saPath || !email) {
  console.error('Usage: SA_PATH=./service-account.json node tool/verify_user_email.mjs user@email.com');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(readFileSync(saPath, 'utf8'))),
});

try {
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().updateUser(user.uid, { emailVerified: true });
  console.log(`Email verified for ${email} (uid ${user.uid}). They can now enrol MFA.`);
  process.exit(0);
} catch (e) {
  console.error('Failed:', e.message);
  process.exit(1);
}
