#!/usr/bin/env node
// Owner activation flow: seeds a customer's SuperAdmin ("Owner") seat with a
// single-use Firebase Auth activation link. Never emails a password — the
// buyer claims the account via generatePasswordResetLink() (single-use,
// short expiry, built into Firebase Auth for free). See CLAUDE.md
// "Per-customer provisioning" for the full flow this fits into.
import { pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';

// ── pure helpers (exported + unit-tested; no Firebase/network here) ──────────

export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const eq = a.indexOf('=');
    if (eq !== -1) {
      out[a.slice(2, eq)] = a.slice(eq + 1);
      continue;
    }
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      out[key] = true; // boolean flag, e.g. --dry-run
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

const REQUIRED_FLAGS = ['email', 'name', 'company', 'tenant'];

/** @returns {string[]} names of required flags that are missing or valueless */
export function validateFlags(flags) {
  return REQUIRED_FLAGS.filter((k) => !flags[k] || flags[k] === true);
}

export function parseFullName(fullName) {
  const parts = String(fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: '', lastName: '' };
  if (parts.length === 1) return { firstName: parts[0], lastName: '' };
  return { firstName: parts[0], lastName: parts.slice(1).join(' ') };
}

export function buildUserRecord({ name, company, tenantCode }) {
  const { firstName, lastName } = parseFullName(name);
  // NOTE: no email here on purpose — the 2026-07-04 PII split keeps email/phone
  // out of users/* (`.validate: false` in database.rules.json). Email goes to
  // users_private/{uid} via buildPrivateRecord() instead.
  return {
    role: 'SuperAdmin',
    firstName,
    lastName,
    active: true,
    tenantCode,
    company,
  };
}

/** PII lives in users_private/{uid} (self + admin-role readable), never users/*. */
export function buildPrivateRecord({ email }) {
  return { email };
}

/** Random, unguessable one-time password — never logged, never emailed. */
export function generatePassword() {
  return randomBytes(24).toString('base64url');
}

export function buildSummary({ uid, email, tenantCode, activationLink, expiresNote }) {
  return { uid, email, tenantCode, activationLink, expiresNote };
}

export function planLines(flags) {
  const { firstName, lastName } = parseFullName(flags.name);
  const dbUrl = (typeof flags['db-url'] === 'string' && flags['db-url']) || process.env.FB_DB_URL || '(not set)';
  return [
    `email:       ${flags.email}`,
    `name:        ${flags.name}  (firstName="${firstName}", lastName="${lastName}")`,
    `company:     ${flags.company}`,
    `tenantCode:  ${flags.tenant}`,
    `db-url:      ${dbUrl}`,
  ];
}

const EXPIRES_NOTE =
  'Single-use activation link; Firebase Auth action links expire ~1 hour after ' +
  'generation by default — send it to the buyer promptly.';

// ── CLI (not exercised by tests — only the pure helpers above are) ───────────

async function main() {
  const flags = parseArgs(process.argv.slice(2));
  const missing = validateFlags(flags);
  if (missing.length) {
    console.error(`ERROR: missing required flag(s): ${missing.join(', ')}`);
    console.error(
      'Usage: node tool/provision_owner.mjs --email <email> --name "First Last" ' +
      '--company <company> --tenant <tenantCode> [--db-url <url>] [--dry-run]'
    );
    process.exit(1);
    return;
  }

  const email = flags.email;
  const name = flags.name;
  const company = flags.company;
  const tenantCode = flags.tenant;
  const dryRun = flags['dry-run'] === true || flags['dry-run'] === 'true';
  const dbUrl = (typeof flags['db-url'] === 'string' && flags['db-url']) || process.env.FB_DB_URL || '';

  console.log('SIAS Owner provisioning');
  console.log('=======================');
  for (const line of planLines(flags)) console.log('  ' + line);
  console.log(`  mode:        ${dryRun ? 'DRY RUN (no writes, no network)' : 'LIVE'}`);
  console.log('');

  if (dryRun) {
    console.log('Plan:');
    console.log('  1. Create (or reuse) the Firebase Auth user for the email above.');
    console.log('  2. Write users/{uid}: role=SuperAdmin, firstName/lastName/email/active/tenantCode/company.');
    console.log('  3. Generate a one-time password-reset activation link (single-use, ~1h expiry).');
    console.log('  4. Print the JSON summary.');
    console.log(
      `  5. ${process.env.N8N_ACTIVATION_WEBHOOK_URL
        ? 'POST the summary to N8N_ACTIVATION_WEBHOOK_URL (configured).'
        : 'Skip webhook POST (N8N_ACTIVATION_WEBHOOK_URL not set).'}`
    );
    console.log('\nDry run complete — no Firebase Auth user created, no RTDB writes, no network calls.');
    return;
  }

  if (!dbUrl) {
    console.error('ERROR: no RTDB URL. Pass --db-url or set FB_DB_URL.');
    process.exit(1);
    return;
  }

  const admin = (await import('firebase-admin')).default;
  const credential = process.env.FIREBASE_SERVICE_ACCOUNT
    ? admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT))
    : admin.credential.applicationDefault();

  if (!admin.apps.length) {
    admin.initializeApp({ credential, databaseURL: dbUrl });
  }

  const auth = admin.auth();
  const db = admin.database();

  let uid;
  let reused = false;
  try {
    const existing = await auth.getUserByEmail(email);
    uid = existing.uid;
    reused = true;
    console.log(`Auth user already exists (uid=${uid}) — reusing it.`);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
    const { firstName, lastName } = parseFullName(name);
    const created = await auth.createUser({
      email,
      password: generatePassword(),
      emailVerified: false,
      displayName: [firstName, lastName].filter(Boolean).join(' ') || undefined,
    });
    uid = created.uid;
    console.log(`Created Auth user (uid=${uid}).`);
  }

  const userRecord = buildUserRecord({ name, company, tenantCode });
  await db.ref(`users/${uid}`).update(userRecord);
  await db.ref(`users_private/${uid}`).update(buildPrivateRecord({ email }));
  console.log(
    `Wrote users/${uid} (role=SuperAdmin, tenantCode=${tenantCode}, company=${company}) ` +
    `and users_private/${uid} (email)` +
    (reused ? ' — merged into existing records.' : '.')
  );

  const activationLink = await auth.generatePasswordResetLink(email);
  const summary = buildSummary({ uid, email, tenantCode, activationLink, expiresNote: EXPIRES_NOTE });

  console.log('\nSummary:');
  console.log(JSON.stringify(summary, null, 2));

  const webhookUrl = process.env.N8N_ACTIVATION_WEBHOOK_URL;
  if (webhookUrl) {
    try {
      const res = await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(summary),
      });
      console.log(`Posted activation summary to N8N_ACTIVATION_WEBHOOK_URL (status ${res.status}).`);
    } catch (err) {
      console.warn(`WARN: failed to POST to N8N_ACTIVATION_WEBHOOK_URL (non-fatal): ${err.message}`);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error('Provisioning failed:', err.message);
    process.exit(1);
  });
}
