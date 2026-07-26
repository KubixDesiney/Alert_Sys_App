#!/usr/bin/env node
// Instance provisioning (v1): scripts the per-customer dedicated-instance runbook
// documented in docs/PROVISIONING.md. Bias to safe, idempotent, resumable steps
// over completeness — anything that still needs a human (billing, auth provider
// toggles, native app registration) is printed as an explicit TODO, never guessed.
//
// Defaults to --dry-run (prints the numbered plan, touches nothing); a real run
// requires --execute. Never modifies the root wrangler.*.toml templates — every
// generated artifact lives under deploy/tenants/<tenant>/ (git-ignored).
import { pathToFileURL, fileURLToPath } from 'node:url';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { loadRegistry, saveRegistry, upsertTenant, markStatus } from './tenant_registry.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');

// ── pure helpers (exported + unit-tested; no network/filesystem/process here) ─

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
      out[key] = true;
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

const REQUIRED_FLAGS = ['tenant', 'project-id'];

export function validateFlags(flags) {
  return REQUIRED_FLAGS.filter((k) => !flags[k] || flags[k] === true);
}

export function isValidTenantSlug(slug) {
  return typeof slug === 'string' && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(slug);
}

export function parseSkipList(value) {
  if (!value || value === true) return new Set();
  return new Set(String(value).split(',').map((s) => s.trim()).filter(Boolean));
}

/** The 7 data-plane workers every dedicated instance needs.
 * sias-store and sias-app are shared control-plane/front-door workers. */
export const WORKER_TEMPLATES = [
  { key: 'ai', file: 'wrangler.ai.toml' },
  { key: 'notify', file: 'wrangler.notify.toml' },
  { key: 'github', file: 'wrangler.github.toml' },
  { key: 'ingest', file: 'wrangler.ingest.toml' },
  { key: 'scim', file: 'wrangler.scim.toml' },
  { key: 'monitor', file: 'wrangler.monitor.toml' },
  { key: 'backup', file: 'wrangler.backup.toml' },
];

// Mirrors CLAUDE.md's "Worker Secrets And Runtime Config" + per-worker wrangler.*.toml
// comments. FB_DB_URL is deliberately absent here — it's derived from --project-id and
// templated directly into the generated config as a [vars] entry, not asked for twice.
export const SECRET_SPECS = {
  ai: ['FB_API_KEY', 'FIREBASE_SERVICE_ACCOUNT', 'WORKER_SHARED_SECRET'],
  notify: ['FIREBASE_SERVICE_ACCOUNT', 'WORKER_SHARED_SECRET'],
  github: ['GITHUB_TOKEN', 'WORKER_SHARED_SECRET'],
  ingest: ['FIREBASE_SERVICE_ACCOUNT', 'WORKER_SHARED_SECRET'],
  scim: ['FIREBASE_SERVICE_ACCOUNT', 'SCIM_TOKEN'],
  monitor: ['FIREBASE_SERVICE_ACCOUNT', 'ALERT_WEBHOOK_URL', 'WORKER_SHARED_SECRET'],
  backup: ['FIREBASE_SERVICE_ACCOUNT'],
};

export const OPTIONAL_SECRET_SPECS = {
  ai: [],
  notify: [],
  github: [],
  ingest: ['INGEST_SHARED_SECRET'],
  scim: ['SCIM_DEFAULT_ROLE', 'SCIM_GRANTABLE_ROLES', 'SCIM_DEFAULT_FACTORY'],
  monitor: [],
  backup: ['WORKER_SHARED_SECRET'],
};

export function tenantWorkerName(originalName, tenant) {
  return `${originalName}-${tenant}`;
}

export function tenantConfigFileName(key, tenant) {
  return `wrangler.${key}.${tenant}.toml`;
}

export function renameWorker(tomlContent, newName) {
  return tomlContent.replace(/^name\s*=\s*"[^"]+"/m, `name = "${newName}"`);
}

/** Sets (or inserts) `[vars]` entries in a wrangler.toml string. Pure string transform. */
export function injectVars(tomlContent, vars) {
  let content = tomlContent;
  if (!/^\[vars\]\s*$/m.test(content)) {
    content = content.replace(/\s*$/, '') + '\n\n[vars]\n';
  }
  for (const [key, value] of Object.entries(vars)) {
    if (value === undefined || value === null || value === '') continue;
    const lineRe = new RegExp(`^${key}\\s*=\\s*".*"$`, 'm');
    const line = `${key} = "${value}"`;
    content = lineRe.test(content)
      ? content.replace(lineRe, line)
      : content.replace(/^\[vars\]\s*$/m, `[vars]\n${line}`);
  }
  return content;
}

/**
 * Templates one root wrangler.*.toml into its per-tenant version: suffixes the
 * worker name with "-<tenant>", namespaces the backup R2 bucket, and injects the
 * instance's FB_DB_URL / NOTIFY_WORKER_URL vars. Never mutates the input.
 */
export function templateTenantConfig({ content, tenant, dbUrl, notifyUrl, aiUrl }) {
  const nameMatch = content.match(/^name\s*=\s*"([^"]+)"/m);
  const originalName = nameMatch ? nameMatch[1] : null;
  const workerName = originalName ? tenantWorkerName(originalName, tenant) : null;
  let out = workerName ? renameWorker(content, workerName) : content;
  // Generated configs live three directories below the repository root.
  // Wrangler resolves `main` relative to the config file, so point back to the
  // real source instead of producing a config whose entrypoint does not exist.
  out = out.replace(/^main\s*=\s*"([^"]+)"/m, (_line, entrypoint) => {
    const clean = String(entrypoint).replace(/^\.\//, '');
    return `main = "../../../${clean}"`;
  });
  out = out.replace(/alertsys-backups/g, `${tenant}-alertsys-backups`);
  out = injectVars(out, {
    FB_DB_URL: dbUrl,
    NOTIFY_WORKER_URL: notifyUrl,
    AI_WORKER_URL: aiUrl,
  });
  return { content: out, workerName };
}

const PLACEHOLDER = 'REPLACE_ME';

/** Generates the commented .env.tenant template listing every secret every worker needs. */
export function buildEnvTemplate(tenant) {
  const lines = [
    `# Secrets for tenant ${tenant} — fill in real values, then re-run:`,
    `#   node tool/provision_instance.mjs --tenant ${tenant} --project-id <id> --execute`,
    '# This file is git-ignored (see .gitignore) — never commit it.',
    '',
  ];
  for (const { key } of WORKER_TEMPLATES) {
    lines.push(`# --- ${key} ---`);
    for (const name of SECRET_SPECS[key]) lines.push(`${name}=${PLACEHOLDER}`);
    for (const name of OPTIONAL_SECRET_SPECS[key] || []) lines.push(`# optional: ${name}=${PLACEHOLDER}`);
    lines.push('');
  }
  return lines.join('\n');
}

/** Minimal KEY=VALUE parser for .env.tenant — no quoting/escaping support needed here. */
export function parseEnvFile(content) {
  const out = {};
  for (const rawLine of String(content || '').split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    out[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return out;
}

/** Required secret keys still missing or left as the placeholder value. */
export function missingSecretKeys(envMap) {
  const missing = [];
  for (const { key } of WORKER_TEMPLATES) {
    for (const name of SECRET_SPECS[key]) {
      if (!envMap[name] || envMap[name] === PLACEHOLDER) missing.push(name);
    }
  }
  return [...new Set(missing)];
}

const STEP_ORDER = [
  ['preflight', 'Preflight — firebase-tools/wrangler on PATH, login status'],
  ['firebase-project', 'Create (or reuse) the Firebase project + default RTDB instance'],
  ['rules', 'Deploy database.rules.json to the new project'],
  ['worker-configs', 'Generate the 7 per-tenant data-plane worker configs under deploy/tenants/<tenant>/'],
  ['secrets', 'Push per-tenant secrets from .env.tenant via wrangler secret put'],
  ['deploy', 'Deploy the 7 tenant data-plane workers'],
  ['seed-data', 'Seed the tenant RTDB hierarchy, assets, alert vocabulary, escalation defaults, and plan entitlements'],
  ['app-delivery', 'Publish the tenant app config to the TENANTS KV namespace + wire the branded ingest host'],
  ['summary', 'Write provision-summary.json and print remaining manual TODOs'],
  ['verify', 'Post-provision verification — probe workers /config, RTDB reachability, rules denial'],
  ['seed-seats', 'Create the Production Manager + Supervisor accounts and deliver activation emails after verification'],
];

/** Numbers the runbook and marks which steps --skip excludes. Pure — no execution. */
export function buildStepPlan(skipSet = new Set()) {
  return STEP_ORDER.map(([id, label], i) => ({ id, n: i + 1, label, skip: skipSet.has(id) }));
}

/** Pulls the safe JSON block a provisioning child tool prints. */
export function extractJsonSummary(stdout) {
  const text = String(stdout || '');
  const marker = text.includes('Delivery summary:') ? 'Delivery summary:' : 'Summary:';
  const idx = text.indexOf(marker);
  if (idx === -1) return null;
  const jsonText = text.slice(idx + marker.length).trim();
  try {
    return JSON.parse(jsonText);
  } catch {
    return null;
  }
}

export function dbUrlForProject(projectId, region = 'us-central1') {
  const databaseId = `${projectId}-default-rtdb`;
  return region === 'us-central1'
    ? `https://${databaseId}.firebaseio.com`
    : `https://${databaseId}.${region}.firebasedatabase.app`;
}

export function notifyWorkerUrl(tenant, subdomain) {
  return `https://alertsys-${tenant}.${subdomain || 'REPLACE-workers-subdomain'}.workers.dev/notify`;
}

export function aiWorkerUrl(tenant, subdomain) {
  return `https://alert-notifier-${tenant}.${subdomain || 'REPLACE-workers-subdomain'}.workers.dev`;
}

/** Per-tenant worker base URLs, keyed like WORKER_TEMPLATES. Pure. */
export function workerUrlsForTenant(written, subdomain) {
  const out = {};
  if (!subdomain) return out;
  for (const cfg of written ?? []) {
    if (cfg?.key && cfg?.workerName) out[cfg.key] = `https://${cfg.workerName}.${subdomain}.workers.dev`;
  }
  return out;
}

// ── Per-tenant app delivery (shared sias-app worker + TENANTS KV) ─────────────
// See CLAUDE.md "Per-Tenant App Delivery". These are all pure + unit-tested.

/** The customer-facing domain every tenant subdomain lives under. */
export const APP_DOMAIN = 'kubixdesiney.com';

/** The tenant's SIAS web app URL, e.g. https://nagati.kubixdesiney.com. */
export function tenantAppUrl(tenant, domain = APP_DOMAIN) {
  return `https://${tenant}.${domain}`;
}

/** The tenant's branded ingest host plant IT whitelists in their firewall. */
export function tenantIngestHost(tenant, domain = APP_DOMAIN) {
  return `${tenant}-ingest.${domain}`;
}

/** The app-worker route pattern that serves this tenant's web hostname. */
export function tenantAppRoute(tenant, domain = APP_DOMAIN) {
  return `${tenant}.${domain}/*`;
}

/** The ingest-worker route pattern for this tenant's branded ingest hostname. */
export function tenantIngestRoute(tenant, domain = APP_DOMAIN) {
  return `${tenantIngestHost(tenant, domain)}/*`;
}

/** The buyer's Kubix Copilot deep link, carrying tenant/company context. */
export function tenantCopilotUrl(tenantCode, company, storefront = `https://sias.${APP_DOMAIN}`) {
  const p = new URLSearchParams();
  if (tenantCode) p.set('tenant', tenantCode);
  if (company) p.set('company', company);
  const q = p.toString();
  return `${storefront}/copilot${q ? `?${q}` : ''}`;
}

/** The exact JSON value written into the TENANTS KV namespace for a tenant. */
export function buildTenantKvValue({ tenantCode, company, firebase, workerUrls, copilotUrl }) {
  return {
    tenantCode: tenantCode || null,
    company: company || null,
    firebase: firebase || {},
    workers: {
      ai: workerUrls?.ai || null,
      notify: workerUrls?.notify || null,
      ingest: workerUrls?.ingest || null,
      copilotUrl: copilotUrl || null,
    },
  };
}

/** Extracts the TENANTS KV namespace id from wrangler.app.toml (either key order). */
export function parseTenantsKvId(tomlContent) {
  const s = String(tomlContent || '');
  const a = s.match(/binding\s*=\s*"TENANTS"[\s\S]{0,200}?id\s*=\s*"([^"]+)"/);
  if (a) return a[1];
  const b = s.match(/id\s*=\s*"([^"]+)"[\s\S]{0,200}?binding\s*=\s*"TENANTS"/);
  return b ? b[1] : null;
}

export function isPlaceholderKvId(id) {
  return !id || /^replace/i.test(String(id));
}

/** A commented [[routes]] block for the tenant's branded ingest host. */
export function ingestRouteBlock(tenant, domain = APP_DOMAIN) {
  return [
    '',
    `# --- Branded ingest host (activate once the *.${domain} DNS wildcard exists) ---`,
    '# A stable hostname plant IT can whitelist. MORE specific than the sias-app',
    '# wildcard route, so it wins for this host. Uncomment after DNS is in place.',
    '# routes = [',
    `#   { pattern = "${tenantIngestRoute(tenant, domain)}", zone_name = "${domain}" }`,
    '# ]',
    '',
  ].join('\n');
}

/** Idempotently appends the branded ingest route to a tenant ingest config. */
export function appendIngestRoute(tomlContent, tenant, domain = APP_DOMAIN) {
  const content = String(tomlContent || '');
  if (content.includes(tenantIngestHost(tenant, domain))) return content;
  return content.replace(/\s*$/, '\n') + ingestRouteBlock(tenant, domain);
}

/** Template dropped for the operator to paste the tenant's Firebase WEB config. */
export function firebaseWebConfigTemplate() {
  return JSON.stringify(
    {
      apiKey: PLACEHOLDER,
      authDomain: PLACEHOLDER,
      projectId: PLACEHOLDER,
      storageBucket: PLACEHOLDER,
      messagingSenderId: PLACEHOLDER,
      appId: PLACEHOLDER,
      databaseURL: PLACEHOLDER,
    },
    null,
    2,
  ) + '\n';
}

/** True until the operator fills the required Firebase web-config identity fields. */
export function isPlaceholderWebConfig(cfg) {
  if (!cfg || typeof cfg !== 'object') return true;
  return ['apiKey', 'appId', 'messagingSenderId', 'projectId'].some(
    (k) => !cfg[k] || cfg[k] === PLACEHOLDER,
  );
}

// ── CLI (not exercised by tests — only the pure helpers above are) ───────────

function runCmd(cmd, args, opts = {}) {
  const useShell = process.platform === 'win32' && (cmd === 'firebase' || cmd === 'wrangler');
  return spawnSync(cmd, args, { encoding: 'utf8', shell: useShell, ...opts });
}

function toolAvailable(cmd) {
  return runCmd(cmd, ['--version']).status === 0;
}

async function main() {
  const flags = parseArgs(process.argv.slice(2));
  const missing = validateFlags(flags);
  if (missing.length) {
    console.error(`ERROR: missing required flag(s): ${missing.join(', ')}`);
    console.error(
      'Usage: node tool/provision_instance.mjs --tenant <slug> --project-id <id> ' +
      '[--region europe-west1] [--execute] [--skip step,step] ' +
      '[--workers-subdomain <sub>] --company <co> --plan <starter|growth> ' +
      '--pm-email <e> --pm-name "First Last" --supervisor-email <e> ' +
      '--supervisor-name "First Last" [--tenant-code <T#CODE>] [--usine "Usine A"]'
    );
    process.exit(1);
    return;
  }

  const tenant = flags.tenant;
  if (!isValidTenantSlug(tenant)) {
    console.error(`ERROR: --tenant "${tenant}" must be a lowercase slug (a-z, 0-9, dashes), e.g. nsw-7k2f.`);
    process.exit(1);
    return;
  }

  const projectId = flags['project-id'];
  const region = flags.region || 'europe-west1';
  const execute = flags.execute === true || flags.execute === 'true';
  const dryRun = !execute;
  const skipSet = parseSkipList(flags.skip);
  const plan = buildStepPlan(skipSet);
  const tenantDir = join(REPO_ROOT, 'deploy', 'tenants', tenant);
  const dbUrl = dbUrlForProject(projectId, region);
  const workersSubdomain =
    flags['workers-subdomain'] || process.env.CLOUDFLARE_WORKERS_SUBDOMAIN;
  const notifyUrl = notifyWorkerUrl(tenant, workersSubdomain);
  const aiUrl = aiWorkerUrl(tenant, workersSubdomain);
  const manualTodos = [];

  console.log(`SIAS instance provisioning — tenant "${tenant}"`);
  console.log(`  project-id: ${projectId}`);
  console.log(`  region:     ${region}`);
  console.log(`  rtdb url:   ${dbUrl}`);
  console.log(`  mode:       ${dryRun ? 'DRY RUN (default — pass --execute for a real run)' : 'EXECUTE'}`);
  console.log('');

  for (const step of plan) {
    if (step.skip) {
      console.log(`[SKIPPED] ${step.n}. ${step.label}  (--skip)`);
      continue;
    }

    if (dryRun) {
      console.log(`[TODO]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'preflight') {
      if (!toolAvailable('firebase')) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  firebase-tools not found on PATH. Install: npm i -g firebase-tools');
        process.exit(1);
        return;
      }
      if (!toolAvailable('wrangler')) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  wrangler not found on PATH. Install: npm i -g wrangler');
        process.exit(1);
        return;
      }
      const nonInteractiveFirebaseAuth =
        !!process.env.GOOGLE_APPLICATION_CREDENTIALS || !!process.env.FIREBASE_TOKEN;
      if (!nonInteractiveFirebaseAuth) {
        const login = runCmd('firebase', ['login:list']);
        if (login.status !== 0 || /no authorized accounts/i.test(login.stdout || '')) {
          console.error(`[FAIL]    ${step.n}. ${step.label}`);
          console.error('  No Firebase credential. Run firebase login or set GOOGLE_APPLICATION_CREDENTIALS.');
          process.exit(1);
          return;
        }
      }
      const whoami = runCmd('wrangler', ['whoami']);
      if (whoami.status !== 0) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  Not logged in to Cloudflare. Run: wrangler login');
        process.exit(1);
        return;
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'firebase-project') {
      const create = runCmd('firebase', ['projects:create', projectId, '--display-name', `SIAS ${tenant}`]);
      const reused = /already in use|already exists/i.test((create.stderr || '') + (create.stdout || ''));
      if (create.status !== 0 && !reused) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(create.stderr || create.stdout);
        process.exit(1);
        return;
      }
      const database = runCmd('firebase', [
        'database:instances:create', `${projectId}-default-rtdb`,
        '--project', projectId, '--location', region,
      ]);
      const dbReused = /already exists|already in use/i.test(
        `${database.stderr || ''}${database.stdout || ''}`,
      );
      if (database.status !== 0 && !dbReused) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(database.stderr || database.stdout);
        process.exit(1);
        return;
      }
      console.log(`[${reused ? 'DONE (reused)' : 'DONE'}]    ${step.n}. ${step.label}`);
      manualTodos.push('Enable Blaze billing on the project (console → Usage & billing).');
      manualTodos.push('Enable the Email/Password sign-in provider (console → Authentication → Sign-in method).');
      manualTodos.push('Create the Android app + download google-services.json (console → Project settings → Add app).');
      manualTodos.push('Confirm Cloud Messaging (FCM) is enabled for the Android app.');
      continue;
    }

    if (step.id === 'rules') {
      const r = runCmd('firebase', ['deploy', '--only', 'database', '--project', projectId]);
      if (r.status !== 0) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(r.stderr || r.stdout);
        process.exit(1);
        return;
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'worker-configs') {
      mkdirSync(tenantDir, { recursive: true });
      const written = [];
      for (const { key, file } of WORKER_TEMPLATES) {
        const src = join(REPO_ROOT, file);
        if (!existsSync(src)) {
          console.error(`[FAIL]    ${step.n}. ${step.label}`);
          console.error(`  Required worker template ${file} is missing (${key}).`);
          process.exit(1);
          return;
        }
        const content = readFileSync(src, 'utf8');
        let { content: out, workerName } = templateTenantConfig({
          content,
          tenant,
          dbUrl,
          notifyUrl,
          aiUrl,
        });
        // Give the ingest worker its branded <tenant>-ingest host (commented
        // until DNS exists; see appendIngestRoute).
        if (key === 'ingest') out = appendIngestRoute(out, tenant, APP_DOMAIN);
        const outName = tenantConfigFileName(key, tenant);
        writeFileSync(join(tenantDir, outName), out);
        written.push({ key, file: outName, workerName });
      }
      step._written = written;
      console.log(`[DONE]    ${step.n}. ${step.label} (${written.length}/${WORKER_TEMPLATES.length} configs written)`);
      continue;
    }

    if (step.id === 'secrets') {
      const envPath = join(tenantDir, '.env.tenant');
      if (!existsSync(envPath)) {
        mkdirSync(tenantDir, { recursive: true });
        writeFileSync(envPath, buildEnvTemplate(tenant));
        console.log(`[TODO]    ${step.n}. ${step.label}`);
        console.log(`  Wrote deploy/tenants/${tenant}/.env.tenant — fill in real values, then re-run.`);
        process.exit(1);
        return;
      }
      const envMap = parseEnvFile(readFileSync(envPath, 'utf8'));
      const missingKeys = missingSecretKeys(envMap);
      if (missingKeys.length) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(`  deploy/tenants/${tenant}/.env.tenant still has placeholder/missing values: ${missingKeys.join(', ')}`);
        process.exit(1);
        return;
      }
      for (const { key } of WORKER_TEMPLATES) {
        const cfgPath = join(tenantDir, tenantConfigFileName(key, tenant));
        if (!existsSync(cfgPath)) continue;
        const names = [...SECRET_SPECS[key], ...(OPTIONAL_SECRET_SPECS[key] || []).filter((n) => envMap[n])];
        for (const name of names) {
          const value = envMap[name];
          if (!value) continue;
          const result = runCmd('wrangler', ['secret', 'put', name, '--config', cfgPath], { input: value });
          if (result.status !== 0) {
            console.error(`[FAIL]    ${step.n}. ${step.label}`);
            console.error(`  Could not set ${name} for ${key}: ${result.stderr || result.stdout || ''}`);
            process.exit(1);
            return;
          }
        }
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'deploy') {
      const bucketName = `${tenant}-alertsys-backups`;
      const bucket = runCmd('wrangler', ['r2', 'bucket', 'create', bucketName]);
      const bucketReused = /already exists|already been taken|code\s*10004/i.test(
        `${bucket.stderr || ''}${bucket.stdout || ''}`,
      );
      if (bucket.status !== 0 && !bucketReused) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(`  Could not create R2 bucket ${bucketName}: ${bucket.stderr || bucket.stdout || ''}`);
        process.exit(1);
        return;
      }
      for (const { key } of WORKER_TEMPLATES) {
        const cfgPath = join(tenantDir, tenantConfigFileName(key, tenant));
        if (!existsSync(cfgPath)) continue;
        const r = runCmd('wrangler', ['deploy', '--config', cfgPath]);
        if (r.status !== 0) {
          console.error(`[FAIL]    ${step.n}. ${step.label}`);
          console.error(`  Deploy failed for ${key}: ${(r.stderr || r.stdout || '').slice(0, 500)}`);
          process.exit(1);
          return;
        }
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'seed-data') {
      const company = flags.company || flags['owner-company'];
      const tenantCode = flags['tenant-code'];
      if (!company || !tenantCode || !['starter', 'growth'].includes(flags.plan)) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  --company, --tenant-code, and --plan <starter|growth> are required.');
        process.exit(1);
        return;
      }
      const args = [
        join(REPO_ROOT, 'tool', 'seed_tenant.mjs'),
        '--tenant', tenantCode,
        '--company', company,
        '--plan', flags.plan,
        '--usine', flags.usine || 'Usine A',
        '--db-url', dbUrl,
        '--execute',
      ];
      const result = runCmd('node', args);
      if (result.stdout) console.log(result.stdout);
      if (result.status !== 0) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(result.stderr || '');
        process.exit(1);
        return;
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'seed-seats') {
      const company = flags.company || flags['owner-company'];
      const required = ['pm-email', 'pm-name', 'supervisor-email', 'supervisor-name', 'tenant-code'];
      const missingSeatFlags = required.filter((key) => !flags[key]);
      if (!company || missingSeatFlags.length) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(
          `  Missing delivery data: ${[
            ...(!company ? ['company'] : []),
            ...missingSeatFlags,
          ].join(', ')}`,
        );
        process.exit(1);
        return;
      }
      const result = runCmd('node', [
        join(REPO_ROOT, 'tool', 'provision_seats.mjs'),
        '--tenant', flags['tenant-code'],
        '--company', company,
        '--pm-email', flags['pm-email'],
        '--pm-name', flags['pm-name'],
        '--supervisor-email', flags['supervisor-email'],
        '--supervisor-name', flags['supervisor-name'],
        '--usine', flags.usine || 'Usine A',
        '--db-url', dbUrl,
        '--console-url', tenantAppUrl(tenant, APP_DOMAIN),
        '--require-delivery-pair',
        '--execute',
      ]);
      if (result.stdout) console.log(result.stdout);
      if (result.status !== 0) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(result.stderr || '');
        process.exit(1);
        return;
      }
      step._seatSummary = extractJsonSummary(result.stdout || '');
      const summaryPath = join(tenantDir, 'provision-summary.json');
      if (existsSync(summaryPath)) {
        const summary = JSON.parse(readFileSync(summaryPath, 'utf8'));
        summary.seats = step._seatSummary;
        summary.deliveryCompletedAt = new Date().toISOString();
        writeFileSync(summaryPath, JSON.stringify(summary, null, 2) + '\n');
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'app-delivery') {
      const appUrl = tenantAppUrl(tenant, APP_DOMAIN);
      const ingestHost = tenantIngestHost(tenant, APP_DOMAIN);
      step._appUrl = appUrl;
      step._ingestHost = ingestHost;

      // Build the KV value from the tenant's worker URLs + Firebase WEB config.
      const written = (plan.find((s) => s.id === 'worker-configs') || {})._written || [];
      const workersSubdomain =
        flags['workers-subdomain'] || process.env.CLOUDFLARE_WORKERS_SUBDOMAIN || null;
      const workerUrls = workerUrlsForTenant(written, workersSubdomain);
      const seatSummary = (plan.find((s) => s.id === 'seed-seats') || {})._seatSummary || {};
      const tenantCode = flags['tenant-code'] || seatSummary.tenantCode || null;
      const company = flags.company || flags['owner-company'] || seatSummary.company || null;

      const webCfgPath = join(tenantDir, 'firebase-web-config.json');
      let webCfg = null;
      if (existsSync(webCfgPath)) {
        try { webCfg = JSON.parse(readFileSync(webCfgPath, 'utf8')); } catch { webCfg = null; }
      }

      const kvValue = buildTenantKvValue({
        tenantCode,
        company,
        firebase: webCfg || {},
        workerUrls,
        copilotUrl: tenantCopilotUrl(tenantCode, company),
      });
      const kvValuePath = join(tenantDir, 'tenant-kv.json');
      mkdirSync(tenantDir, { recursive: true });
      writeFileSync(kvValuePath, JSON.stringify(kvValue, null, 2) + '\n');
      step._kvValue = kvValue;

      const appTomlPath = join(REPO_ROOT, 'wrangler.app.toml');
      const kvId = existsSync(appTomlPath) ? parseTenantsKvId(readFileSync(appTomlPath, 'utf8')) : null;

      if (isPlaceholderKvId(kvId)) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  wrangler.app.toml has no real TENANTS KV id.');
        process.exit(1);
        return;
      } else if (isPlaceholderWebConfig(webCfg)) {
        if (!existsSync(webCfgPath)) writeFileSync(webCfgPath, firebaseWebConfigTemplate());
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(`  deploy/tenants/${tenant}/firebase-web-config.json is missing or incomplete.`);
        process.exit(1);
        return;
      } else {
        const r = runCmd('wrangler', ['kv', 'key', 'put', tenant, '--namespace-id', kvId, '--path', kvValuePath]);
        if (r.status !== 0) {
          console.error(`[FAIL]    ${step.n}. ${step.label}`);
          console.error(`  KV write failed: ${(r.stderr || r.stdout || '').slice(0, 500)}`);
          process.exit(1);
          return;
        }
        console.log(`[DONE]    ${step.n}. ${step.label} → ${appUrl}`);
      }
      manualTodos.push(
        `Route ${tenantAppRoute(tenant, APP_DOMAIN)} to sias-app (the app worker's wildcard route ` +
        `covers it; keep the more-specific sias.${APP_DOMAIN}/* storefront route).`,
      );
      manualTodos.push(
        `Add DNS + route for the branded ingest host ${ingestHost} (uncomment the route in ` +
        `the generated ingest config once *.${APP_DOMAIN} DNS exists).`,
      );
      manualTodos.push(
        `Build this tenant's Android APK: run the "Build tenant APK" GitHub workflow ` +
        `(.github/workflows/build-tenant-apk.yml) with tenant="${tenant}" — it publishes ` +
        `${appUrl}/app/sias-${tenant}.apk. The web PWA already works with no install.`,
      );
      continue;
    }

    if (step.id === 'summary') {
      const written = (plan.find((s) => s.id === 'worker-configs') || {})._written || [];
      const appStep = plan.find((s) => s.id === 'app-delivery') || {};
      const workersSubdomain =
        flags['workers-subdomain'] || process.env.CLOUDFLARE_WORKERS_SUBDOMAIN || null;
      const summary = {
        tenant,
        projectId,
        region,
        dbUrl,
        workersSubdomain,
        appUrl: appStep._appUrl || tenantAppUrl(tenant, APP_DOMAIN),
        ingestHost: appStep._ingestHost || tenantIngestHost(tenant, APP_DOMAIN),
        workerUrls: workerUrlsForTenant(written, workersSubdomain),
        workerConfigs: written,
        seats: (plan.find((s) => s.id === 'seed-seats') || {})._seatSummary || null,
        generatedAt: new Date().toISOString(),
      };
      mkdirSync(tenantDir, { recursive: true });
      writeFileSync(join(tenantDir, 'provision-summary.json'), JSON.stringify(summary, null, 2) + '\n');
      // Registry: the local ledger list_tenants/teardown read.
      saveRegistry(upsertTenant(loadRegistry(), {
        tenant,
        projectId,
        status: 'provisioned',
        appUrl: summary.appUrl,
        workerUrls: summary.workerUrls,
        workerConfigs: written.map((w) => w.file),
      }));
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'verify') {
      const v = runCmd('node', [join(REPO_ROOT, 'tool', 'verify_instance.mjs'), '--tenant', tenant]);
      if (v.stdout) console.log(v.stdout);
      if (v.status !== 0) {
        saveRegistry(markStatus(loadRegistry(), tenant, 'failed-verification'));
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(v.stderr || '  One or more probes failed — see the table above.');
        process.exit(1);
        return;
      }
      saveRegistry(markStatus(loadRegistry(), tenant, 'verified'));
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }
  }

  if (manualTodos.length) {
    console.log('\nRemaining manual TODOs:');
    for (const t of [...new Set(manualTodos)]) console.log(`  - ${t}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error('Provisioning failed:', err.message);
    process.exit(1);
  });
}
