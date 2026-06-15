#!/usr/bin/env node
/**
 * Automated company provisioning for the dedicated-instance deployment model.
 *
 * One command turns a handful of company facts into every per-company artifact
 * needed to stand up an isolated instance:
 *   - companies/<id>/company.json         canonical, non-secret config record
 *   - companies/<id>/build.ps1 / build.sh the exact `flutter build` commands
 *                                          (all --dart-define flags pre-filled)
 *   - companies/<id>/wrangler.*.toml       per-company worker configs (unique
 *                                          names + R2 bucket, read live from the
 *                                          repo templates so they never drift)
 *   - companies/<id>/secrets.md            the `wrangler secret put` checklist
 *   - companies/<id>/PROVISION.md          the ordered, copy-pasteable runbook
 *
 * It writes NO secrets to disk — secret values are only ever referenced by name.
 * It performs NO network calls — it generates the artifacts and the exact
 * commands; the operator runs the privileged firebase/wrangler steps with their
 * own credentials (see the generated PROVISION.md).
 *
 * USAGE:
 *   node tool/provision_company.mjs \
 *     --id=acme --name="ACME Manufacturing" --project=acme-alerts \
 *     --account=<cloudflare-account-id> --subdomain=<your-workers-subdomain> \
 *     [--brand=0xFF1565C0] [--logo=https://acme.com/logo.png] \
 *     [--support=ops@acme.com] [--title="ACME Alerts"] \
 *     [--sso=oidc.acme-azure] [--sso-label="Sign in with ACME"] [--mfa]
 *
 *   # or load everything from a JSON file (flags override file values):
 *   node tool/provision_company.mjs --config=companies/acme.input.json
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';

// ── arg parsing ──────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    if (!a.startsWith('--')) continue;
    const eq = a.indexOf('=');
    if (eq === -1) out[a.slice(2)] = true; // boolean flag, e.g. --mfa
    else out[a.slice(2, eq)] = a.slice(eq + 1);
  }
  return out;
}

const flags = parseArgs(process.argv.slice(2));
let cfg = {};
if (flags.config) {
  cfg = JSON.parse(readFileSync(flags.config, 'utf8'));
}
// flags override file
for (const [k, v] of Object.entries(flags)) {
  if (k !== 'config') cfg[k] = v;
}

// ── validate ─────────────────────────────────────────────────────────────────
const REQUIRED = ['id', 'name', 'project', 'account', 'subdomain'];
const missing = REQUIRED.filter((k) => !cfg[k]);
if (missing.length) {
  console.error('ERROR: missing required field(s): ' + missing.join(', '));
  console.error('Required: --id --name --project --account --subdomain');
  console.error('  --account    your Cloudflare account id');
  console.error('  --subdomain  your workers.dev subdomain (the part before .workers.dev)');
  process.exit(1);
}
if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(cfg.id)) {
  console.error(`ERROR: --id "${cfg.id}" must be a lowercase slug (a-z, 0-9, dashes).`);
  process.exit(1);
}

const id = cfg.id;
const brand = cfg.brand || '0xFF1565C0';
const title = cfg.title || cfg.name;
const logo = cfg.logo || '';
const support = cfg.support || '';
const sso = cfg.sso || '';
const ssoLabel = cfg['sso-label'] || (sso ? `Sign in with ${cfg.name} SSO` : '');
const mfa = cfg.mfa === true || cfg.mfa === 'true' || cfg.mfa === '1';
const dbUrl = cfg.dburl || `https://${cfg.project}-default-rtdb.firebaseio.com`;

const root = process.cwd();
const outDir = join(root, 'companies', id);
mkdirSync(outDir, { recursive: true });

// ── per-company worker configs (read live templates, prefix names) ────────────
const WORKERS = [
  { key: 'ai', file: 'wrangler.ai.toml', urlVar: 'ALERTSYS_AI_WORKER_URL' },
  { key: 'notify', file: 'wrangler.notify.toml', urlVar: 'ALERTSYS_NOTIFY_WORKER_URL' },
  { key: 'backup', file: 'wrangler.backup.toml' },
  { key: 'monitor', file: 'wrangler.monitor.toml' },
];
const workerUrls = {};
const workerNames = {};
const writtenConfigs = [];

for (const w of WORKERS) {
  const src = join(root, w.file);
  if (!existsSync(src)) {
    console.warn(`WARN: template ${w.file} not found — skipping its per-company config.`);
    continue;
  }
  let content = readFileSync(src, 'utf8');
  const m = content.match(/^name\s*=\s*"([^"]+)"/m);
  if (!m) {
    console.warn(`WARN: no name field in ${w.file} — skipping.`);
    continue;
  }
  const origName = m[1];
  const newName = `${id}-${origName}`;
  workerNames[w.key] = newName;
  content = content.replace(/^name\s*=\s*"[^"]+"/m, `name = "${newName}"`);
  // Backup worker also owns an R2 bucket — give it a per-company bucket.
  if (w.key === 'backup') {
    content = content.replace(/alertsys-backups/g, `${id}-alertsys-backups`);
  }
  const outName = `wrangler.${w.key}.toml`;
  writeFileSync(join(outDir, outName), content);
  writtenConfigs.push(outName);
  if (w.urlVar) workerUrls[w.urlVar] = `https://${newName}.${cfg.subdomain}.workers.dev`;
}

const aiUrl = workerUrls.ALERTSYS_AI_WORKER_URL || `https://${id}-alert-notifier.${cfg.subdomain}.workers.dev`;
const notifyUrl = workerUrls.ALERTSYS_NOTIFY_WORKER_URL || `https://${id}-alertsys.${cfg.subdomain}.workers.dev`;
const backupBucket = `${id}-alertsys-backups`;

// ── canonical config record ───────────────────────────────────────────────────
const record = {
  id, name: cfg.name, appTitle: title, brandColor: brand, logoUrl: logo,
  supportEmail: support, firebaseProject: cfg.project, firebaseDbUrl: dbUrl,
  cloudflareAccount: cfg.account, workersSubdomain: cfg.subdomain,
  sso: { providerId: sso, label: ssoLabel }, mfaRequired: mfa,
  workers: { names: workerNames, aiUrl, notifyUrl, backupBucket },
  generatedAt: new Date().toISOString(),
};
writeFileSync(join(outDir, 'company.json'), JSON.stringify(record, null, 2) + '\n');

// ── build commands (the long, error-prone part — fully pre-filled) ────────────
const defines = [
  ['COMPANY_ID', id],
  ['COMPANY_NAME', cfg.name],
  ['COMPANY_APP_TITLE', title],
  ['COMPANY_BRAND_COLOR', brand],
  ['COMPANY_LOGO_URL', logo],
  ['COMPANY_SUPPORT_EMAIL', support],
  ['COMPANY_FIREBASE_PROJECT', cfg.project],
  ['COMPANY_SSO_PROVIDER', sso],
  ['COMPANY_SSO_LABEL', ssoLabel],
  ['COMPANY_MFA_REQUIRED', mfa ? 'true' : 'false'],
  ['ALERTSYS_AI_WORKER_URL', aiUrl],
  ['ALERTSYS_NOTIFY_WORKER_URL', notifyUrl],
].filter(([, v]) => v !== '' && v !== undefined);

const psDefines = defines
  .map(([k, v]) => `  --dart-define=${k}="${v}" \``)
  .join('\n');
const shDefines = defines
  .map(([k, v]) => `  --dart-define=${k}="${v}" \\`)
  .join('\n');
// The shared secret is sensitive: reference it from the environment, never inline.
const psSecret = '  --dart-define=ALERTSYS_WORKER_SHARED_SECRET="$env:ALERTSYS_WORKER_SHARED_SECRET"';
const shSecret = '  --dart-define=ALERTSYS_WORKER_SHARED_SECRET="$ALERTSYS_WORKER_SHARED_SECRET"';

writeFileSync(join(outDir, 'build.ps1'),
`# Build ${cfg.name} (${id}). Run from the repo root.
# Set the shared secret first:  $env:ALERTSYS_WORKER_SHARED_SECRET = "<secret>"

flutter build apk --release \`
${psDefines}
${psSecret}

flutter build web --release --no-wasm-dry-run \`
${psDefines}
${psSecret}
`);

writeFileSync(join(outDir, 'build.sh'),
`#!/usr/bin/env bash
# Build ${cfg.name} (${id}). Run from the repo root.
# Set the shared secret first:  export ALERTSYS_WORKER_SHARED_SECRET="<secret>"
set -euo pipefail

flutter build apk --release \\
${shDefines}
${shSecret}

flutter build web --release --no-wasm-dry-run \\
${shDefines}
${shSecret}
`);

// ── secrets checklist ──────────────────────────────────────────────────────────
writeFileSync(join(outDir, 'secrets.md'),
`# Secrets for ${cfg.name} (${id})

Set per worker with \`wrangler secret put <NAME> --config companies/${id}/wrangler.<worker>.toml\`.
Never commit secret values. The same FIREBASE_SERVICE_ACCOUNT JSON (full admin on
\`${cfg.project}\`) is used by every worker.

## AI worker (${workerNames.ai || `${id}-alert-notifier`})
- FB_DB_URL = ${dbUrl}
- FB_API_KEY
- FIREBASE_SERVICE_ACCOUNT
- WORKER_SHARED_SECRET
- NOTIFY_WORKER_URL = ${notifyUrl}/notify

## Notify worker (${workerNames.notify || `${id}-alertsys`})
- FB_DB_URL = ${dbUrl}
- FIREBASE_SERVICE_ACCOUNT
- WORKER_SHARED_SECRET

## Backup worker (${workerNames.backup || `${id}-alertsys-backup`})
- FB_DB_URL = ${dbUrl}
- FIREBASE_SERVICE_ACCOUNT
- WORKER_SHARED_SECRET   (optional; guards the manual /backup trigger)

## Monitor worker (${workerNames.monitor || `${id}-alertsys-monitor`})
- FB_DB_URL = ${dbUrl}
- FIREBASE_SERVICE_ACCOUNT
(The monitor reads its webhook/check config live from \`monitoring_config\` in RTDB —
the customer's IT team sets that in the SuperAdmin → Reliability tab, no redeploy.)
`);

// ── ordered runbook ─────────────────────────────────────────────────────────────
const deployCmds = writtenConfigs
  .map((c) => `   npx wrangler deploy --config companies/${id}/${c}`)
  .join('\n');

writeFileSync(join(outDir, 'PROVISION.md'),
`# Provision ${cfg.name} (${id})

Generated ${record.generatedAt}. Run every step from the repo root.

## 1. Firebase project
- Create project \`${cfg.project}\` (or confirm it exists) and upgrade to Blaze
  (required for SMS MFA and worker FCM).
- Enable Authentication (Email/Password${sso ? `, plus the "${sso}" provider in Identity Platform` : ''})
  and Realtime Database at \`${dbUrl}\`.
- \`flutterfire configure --project=${cfg.project}\` to regenerate lib/firebase_options.dart
  for this build. (The app's isolation check refuses to run if the wired project
  id != COMPANY_FIREBASE_PROJECT.)

## 2. Database rules
   firebase use ${cfg.project}
   firebase deploy --only database

## 3. Cloudflare R2 (for backups)
   npx wrangler r2 bucket create ${backupBucket}

## 4. Deploy the four workers (per-company configs already generated)
${deployCmds}
   Then set each worker's secrets — see companies/${id}/secrets.md.

## 5. Build the apps
   # PowerShell
   $env:ALERTSYS_WORKER_SHARED_SECRET = "<secret>"
   ./companies/${id}/build.ps1
   # or bash
   export ALERTSYS_WORKER_SHARED_SECRET="<secret>"
   bash companies/${id}/build.sh

## 6. First admin + monitoring
- Create the SuperAdmin user, then set \`users/<uid>/role = "SuperAdmin"\` in RTDB.
- In-app: SuperAdmin → Reliability — enter the R2/backup + webhook monitoring config
  (writes to \`monitoring_config\`; the monitor worker picks it up live).
- SuperAdmin → Access & Identity — confirm SSO/MFA${mfa ? ' (MFA is required for this company)' : ''}.

## 7. Distribute
- Android: ship build/app/outputs/flutter-apk/app-release.apk (or Play Console).
- Web: \`firebase deploy --only hosting\` (build/web is already built).

---
Brand: ${brand}${logo ? ` · Logo: ${logo}` : ''}${support ? ` · Support: ${support}` : ''}
SSO: ${sso || '(none)'} · MFA required: ${mfa}
`);

// ── summary ───────────────────────────────────────────────────────────────────
console.log(`✓ Provisioned "${cfg.name}" (${id}) → companies/${id}/`);
console.log(`  config:   company.json`);
console.log(`  build:    build.ps1, build.sh`);
console.log(`  workers:  ${writtenConfigs.join(', ')}`);
console.log(`  docs:     secrets.md, PROVISION.md`);
console.log('');
console.log(`  AI worker URL:     ${aiUrl}`);
console.log(`  Notify worker URL: ${notifyUrl}`);
console.log(`  Backup bucket:     ${backupBucket}`);
console.log('');
console.log(`Next: open companies/${id}/PROVISION.md and follow steps 1→7.`);
