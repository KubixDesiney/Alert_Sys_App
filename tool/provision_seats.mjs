#!/usr/bin/env node
// Seat provisioning: creates the seats a delivered SIAS instance ships with —
// Owner (SuperAdmin), Production Manager (admin) and one Supervisor
// (supervisor) — each with its own single-use Firebase Auth activation link.
//
// This is the multi-seat sibling of tool/provision_owner.mjs and deliberately
// mirrors it: same PII split (no email in users/*, it lives in
// users_private/{uid}), same activation mechanism (generatePasswordResetLink —
// single-use, short expiry), never a password by email, never a password logged.
//
// Safety posture follows tool/provision_instance.mjs rather than
// provision_owner.mjs: this creates real Auth users and hands out real
// activation links, so it DEFAULTS TO DRY RUN and needs --execute to touch
// anything.
//
//   node tool/provision_seats.mjs \
//     --tenant "NSW#7K2F" --company "Nagati Steel Works" \
//     --owner-email owner@customer.com      --owner-name "Amine Ben Salah" \
//     --pm-email    pm@customer.com         --pm-name    "Sonia Trabelsi" \
//     --supervisor-email sup@customer.com   --supervisor-name "Karim Aloui" \
//     [--usine "Usine A"] [--db-url https://<project>-default-rtdb.firebaseio.com] \
//     [--execute]
//
// Seats are independent: pass only the ones you want. Re-running is safe — an
// existing Auth user is reused and its records are merged, so a failed run can
// simply be repeated (matching the resumable style of provision_instance).
import { pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';

// ── pure helpers (exported + unit-tested; no Firebase/network/process here) ──

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
      out[key] = true; // boolean flag, e.g. --execute
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

/**
 * The seats a delivered instance ships with.
 *
 * `role` values are the ones database.rules.json actually enforces — do not
 * "tidy" the casing: the rules check users/{uid}/role against the literals
 * 'SuperAdmin', 'admin' and 'supervisor', and the Flutter UserModel treats
 * role === 'admin' as the manager tier (see also the pm_actions RTDB node).
 */
export const SEAT_TYPES = [
  { key: 'owner', role: 'SuperAdmin', label: 'Owner' },
  { key: 'pm', role: 'admin', label: 'Production Manager' },
  { key: 'supervisor', role: 'supervisor', label: 'Supervisor' },
];

export const DEFAULT_USINE = 'Usine A';

const REQUIRED_FLAGS = ['tenant', 'company'];

export function validateFlags(flags) {
  return REQUIRED_FLAGS.filter((k) => !flags[k] || flags[k] === true);
}

export function parseFullName(fullName) {
  const parts = String(fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: '', lastName: '' };
  if (parts.length === 1) return { firstName: parts[0], lastName: '' };
  return { firstName: parts[0], lastName: parts.slice(1).join(' ') };
}

/**
 * Turns --<seat>-email / --<seat>-name flags into the concrete seat list.
 * A seat is only provisioned when BOTH its email and name are present; half a
 * seat is an operator mistake, so it is reported rather than silently skipped.
 */
export function collectSeats(flags) {
  const seats = [];
  const errors = [];
  const emailOwners = new Map();
  for (const type of SEAT_TYPES) {
    const email = typeof flags[`${type.key}-email`] === 'string'
      ? flags[`${type.key}-email`].trim().toLowerCase()
      : flags[`${type.key}-email`];
    const name = flags[`${type.key}-name`];
    const hasEmail = typeof email === 'string' && email.length > 0;
    const hasName = typeof name === 'string' && name.length > 0;
    if (!hasEmail && !hasName) continue;
    if (hasEmail !== hasName) {
      errors.push(
        `${type.key}: needs both --${type.key}-email and --${type.key}-name ` +
        `(got only --${type.key}-${hasEmail ? 'email' : 'name'})`
      );
      continue;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      errors.push(`${type.key}: invalid email address`);
      continue;
    }
    if (emailOwners.has(email)) {
      errors.push(`${type.key}: email is already assigned to the ${emailOwners.get(email)} seat`);
      continue;
    }
    emailOwners.set(email, type.key);
    seats.push({ ...type, email, name });
  }
  if (seats.length === 0 && errors.length === 0) {
    errors.push('no seats requested — pass at least one --<seat>-email/--<seat>-name pair');
  }
  return { seats, errors };
}

/** The commercial Paid flow must always deliver exactly these two seats. */
export function validateDeliveryPair(seats) {
  const keys = new Set(seats.map((seat) => seat.key));
  const missing = ['pm', 'supervisor'].filter((key) => !keys.has(key));
  return missing.length
    ? [`automatic delivery requires ${missing.join(' and ')} seat${missing.length > 1 ? 's' : ''}`]
    : [];
}

/**
 * The broadly-readable users/{uid} record.
 * NOTE: no email here on purpose — the 2026-07-04 PII split keeps email/phone
 * out of users/* (`.validate: false` in database.rules.json). Email goes to
 * users_private/{uid} via buildPrivateRecord() instead.
 * `usine` is included because users/* is indexed on it and the app filters by it.
 */
export function buildUserRecord({ name, company, tenantCode, role, usine }) {
  const { firstName, lastName } = parseFullName(name);
  return {
    role,
    firstName,
    lastName,
    active: true,
    tenantCode,
    company,
    usine: usine || DEFAULT_USINE,
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

export const EXPIRES_NOTE =
  'Single-use activation link; Firebase Auth action links expire ~1 hour after ' +
  'generation by default — send it to the seat holder promptly.';

/** Per-seat payload; shaped so n8n WF3 can consume it unchanged (uid/email/tenantCode/activationLink). */
export function buildSeatSummary({ seat, uid, email, tenantCode, company, activationLink, consoleUrl }) {
  return {
    seat: seat.key,
    role: seat.role,
    seatLabel: seat.label,
    uid,
    email,
    tenantCode,
    company,
    activationLink,
    consoleUrl: consoleUrl || '',
    expiresNote: EXPIRES_NOTE,
  };
}

export function buildDeliverySummary({ tenantCode, company, seats }) {
  return {
    tenantCode,
    company,
    seatCount: seats.length,
    seats,
    generatedAt: new Date().toISOString(),
  };
}

/** Safe to persist in artifacts/logs: activation URL and account email removed. */
export function redactSeatSummary(summary) {
  return {
    seat: summary.seat,
    role: summary.role,
    seatLabel: summary.seatLabel,
    uid: summary.uid,
    tenantCode: summary.tenantCode,
    company: summary.company,
    consoleUrl: summary.consoleUrl,
    activationDelivered: true,
  };
}

export function maskEmail(email) {
  const [local, domain] = String(email || '').split('@');
  if (!domain) return '(invalid)';
  return `${local.slice(0, 1)}***@${domain}`;
}

export async function postActivationPayload(
  webhookUrl,
  payload,
  {
    authToken = '',
    fetchImpl = fetch,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    attempts = 3,
  } = {},
) {
  let lastError = 'activation delivery failed';
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const headers = { 'Content-Type': 'application/json' };
      if (authToken) headers.Authorization = `Bearer ${authToken}`;
      const response = await fetchImpl(webhookUrl, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(10_000),
      });
      if (response.ok) return { ok: true, status: response.status, attempts: attempt };
      lastError = `activation webhook returned ${response.status}`;
    } catch (error) {
      lastError = `activation webhook failed: ${error.message}`;
    }
    if (attempt < attempts) await sleep(attempt * 250);
  }
  return { ok: false, error: lastError, attempts };
}

export function planLines(flags) {
  const { seats, errors } = collectSeats(flags);
  const dbUrl = (typeof flags['db-url'] === 'string' && flags['db-url']) || process.env.FB_DB_URL || '(not set)';
  const lines = [
    `tenantCode:  ${flags.tenant}`,
    `company:     ${flags.company}`,
    `usine:       ${flags.usine || DEFAULT_USINE}`,
    `db-url:      ${dbUrl}`,
  ];
  for (const s of seats) {
    const { firstName, lastName } = parseFullName(s.name);
    const display = [firstName, lastName].filter(Boolean).join(' ');
    lines.push(`seat ${s.key.padEnd(10)} role=${s.role.padEnd(11)} ${maskEmail(s.email)}  ("${display}")`);
  }
  for (const e of errors) lines.push(`ERROR: ${e}`);
  return lines;
}

// ── CLI (not exercised by tests — only the pure helpers above are) ───────────

async function main() {
  const flags = parseArgs(process.argv.slice(2));
  const missing = validateFlags(flags);
  if (missing.length) {
    console.error(`ERROR: missing required flag(s): ${missing.join(', ')}`);
    console.error(
      'Usage: node tool/provision_seats.mjs --tenant <tenantCode> --company <company> ' +
      '[--owner-email <e> --owner-name "First Last"] [--pm-email <e> --pm-name "First Last"] ' +
      '[--supervisor-email <e> --supervisor-name "First Last"] [--usine <usine>] ' +
      '[--db-url <url>] [--require-delivery-pair] [--execute]'
    );
    process.exit(1);
    return;
  }

  const { seats, errors } = collectSeats(flags);
  if (flags['require-delivery-pair']) errors.push(...validateDeliveryPair(seats));
  const tenantCode = flags.tenant;
  const company = flags.company;
  const usine = typeof flags.usine === 'string' ? flags.usine : DEFAULT_USINE;
  const execute = flags.execute === true || flags.execute === 'true';
  const dbUrl = (typeof flags['db-url'] === 'string' && flags['db-url']) || process.env.FB_DB_URL || '';
  const consoleUrl = (typeof flags['console-url'] === 'string' && flags['console-url']) || process.env.SIAS_CONSOLE_URL || '';

  console.log('SIAS seat provisioning');
  console.log('======================');
  for (const line of planLines(flags)) console.log('  ' + line);
  console.log(`  mode:        ${execute ? 'LIVE' : 'DRY RUN (no writes, no network)'}`);
  console.log('');

  if (errors.length) {
    for (const e of errors) console.error(`ERROR: ${e}`);
    process.exit(1);
    return;
  }

  if (!execute) {
    console.log('Plan:');
    let n = 1;
    for (const seat of seats) {
      console.log(`  ${n++}. ${seat.label} <${maskEmail(seat.email)}>: create (or reuse) the Auth user, ` +
        `write users/{uid} (role=${seat.role}, usine=${usine}) + users_private/{uid} (email), ` +
        'then generate a single-use activation link.');
    }
    console.log(`  ${n++}. Print the delivery summary (one entry per seat).`);
    console.log(
      `  ${n}. ${process.env.N8N_ACTIVATION_WEBHOOK_URL
        ? 'POST each seat summary to N8N_ACTIVATION_WEBHOOK_URL (configured).'
        : 'Skip webhook POST (N8N_ACTIVATION_WEBHOOK_URL not set).'}`
    );
    console.log('\nDry run complete — no Auth users created, no RTDB writes, no network calls.');
    console.log('Re-run with --execute to provision for real.');
    return;
  }

  if (!dbUrl) {
    console.error('ERROR: no RTDB URL. Pass --db-url or set FB_DB_URL.');
    process.exit(1);
    return;
  }

  const webhookUrl = process.env.N8N_ACTIVATION_WEBHOOK_URL;
  const allowNoWebhook = flags['allow-no-webhook'] === true || flags['allow-no-webhook'] === 'true';
  if (!webhookUrl && !allowNoWebhook) {
    console.error(
      'ERROR: N8N_ACTIVATION_WEBHOOK_URL is required for live delivery. ' +
      'Use --allow-no-webhook only for a controlled recovery run.'
    );
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
  const provisioned = [];

  for (const seat of seats) {
    let uid;
    let reused = false;
    try {
      const existing = await auth.getUserByEmail(seat.email);
      uid = existing.uid;
      reused = true;
      console.log(`[${seat.key}] Auth user already exists (uid=${uid}, email=${maskEmail(seat.email)}) — reusing it.`);
    } catch (err) {
      if (err.code !== 'auth/user-not-found') throw err;
      const { firstName, lastName } = parseFullName(seat.name);
      const created = await auth.createUser({
        email: seat.email,
        password: generatePassword(),
        emailVerified: false,
        displayName: [firstName, lastName].filter(Boolean).join(' ') || undefined,
      });
      uid = created.uid;
      console.log(`[${seat.key}] Created Auth user (uid=${uid}, email=${maskEmail(seat.email)}).`);
    }

    await db.ref(`users/${uid}`).update(
      buildUserRecord({ name: seat.name, company, tenantCode, role: seat.role, usine })
    );
    await db.ref(`users_private/${uid}`).update(buildPrivateRecord({ email: seat.email }));
    console.log(
      `[${seat.key}] Wrote users/${uid} (role=${seat.role}, usine=${usine}, tenantCode=${tenantCode}) ` +
      `and users_private/${uid} (email)` + (reused ? ' — merged into existing records.' : '.')
    );

    const activationLink = await auth.generatePasswordResetLink(seat.email);
    const privateDelivery = buildSeatSummary({
      seat, uid, email: seat.email, tenantCode, company, activationLink, consoleUrl,
    });
    if (webhookUrl) {
      const delivered = await postActivationPayload(webhookUrl, privateDelivery, {
        authToken: process.env.N8N_ACTIVATION_WEBHOOK_AUTH || process.env.N8N_WEBHOOK_AUTH || '',
      });
      if (!delivered.ok) {
        throw new Error(`[${seat.key}] ${delivered.error}; rerun safely to issue a fresh activation link`);
      }
      console.log(`[${seat.key}] Activation email accepted by delivery workflow (${delivered.status}).`);
    } else {
      console.warn(`[${seat.key}] Activation email intentionally skipped by --allow-no-webhook.`);
    }
    provisioned.push(redactSeatSummary(privateDelivery));
  }

  const summary = buildDeliverySummary({ tenantCode, company, seats: provisioned });
  console.log('\nDelivery summary:');
  console.log(JSON.stringify(summary, null, 2));

}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error('Seat provisioning failed:', err.message);
    process.exit(1);
  });
}
