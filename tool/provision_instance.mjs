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

/** The 8 worker configs every dedicated instance needs — never edit the source files. */
export const WORKER_TEMPLATES = [
  { key: 'ai', file: 'wrangler.ai.toml' },
  { key: 'notify', file: 'wrangler.notify.toml' },
  { key: 'github', file: 'wrangler.github.toml' },
  { key: 'ingest', file: 'wrangler.ingest.toml' },
  { key: 'scim', file: 'wrangler.scim.toml' },
  { key: 'monitor', file: 'wrangler.monitor.toml' },
  { key: 'backup', file: 'wrangler.backup.toml' },
  { key: 'store', file: 'wrangler.store.toml' },
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
  monitor: ['FIREBASE_SERVICE_ACCOUNT', 'ALERT_WEBHOOK_URL'],
  backup: ['FIREBASE_SERVICE_ACCOUNT'],
  store: ['N8N_CHAT_WEBHOOK_URL'],
};

export const OPTIONAL_SECRET_SPECS = {
  ai: [],
  notify: [],
  github: [],
  ingest: ['INGEST_SHARED_SECRET'],
  scim: ['SCIM_DEFAULT_ROLE', 'SCIM_GRANTABLE_ROLES', 'SCIM_DEFAULT_FACTORY'],
  monitor: [],
  backup: ['WORKER_SHARED_SECRET'],
  store: ['N8N_WEBHOOK_AUTH'],
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
export function templateTenantConfig({ content, tenant, dbUrl, notifyUrl }) {
  const nameMatch = content.match(/^name\s*=\s*"([^"]+)"/m);
  const originalName = nameMatch ? nameMatch[1] : null;
  const workerName = originalName ? tenantWorkerName(originalName, tenant) : null;
  let out = workerName ? renameWorker(content, workerName) : content;
  out = out.replace(/alertsys-backups/g, `${tenant}-alertsys-backups`);
  out = injectVars(out, { FB_DB_URL: dbUrl, NOTIFY_WORKER_URL: notifyUrl });
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
  ['worker-configs', 'Generate the 8 per-tenant wrangler configs under deploy/tenants/<tenant>/'],
  ['secrets', 'Push per-tenant secrets from .env.tenant via wrangler secret put'],
  ['deploy', 'Deploy the 8 tenant workers'],
  ['seed-owner', "Seed the customer's Owner (SuperAdmin) account via tool/provision_owner.mjs"],
  ['summary', 'Write provision-summary.json and print remaining manual TODOs'],
  ['verify', 'Post-provision verification — probe workers /config, RTDB reachability, rules denial'],
];

/** Numbers the runbook and marks which steps --skip excludes. Pure — no execution. */
export function buildStepPlan(skipSet = new Set()) {
  return STEP_ORDER.map(([id, label], i) => ({ id, n: i + 1, label, skip: skipSet.has(id) }));
}

/** Pulls the JSON block provision_owner.mjs prints after its "Summary:" line. */
export function extractJsonSummary(stdout) {
  const idx = String(stdout || '').indexOf('Summary:');
  if (idx === -1) return null;
  const jsonText = stdout.slice(idx + 'Summary:'.length).trim();
  try {
    return JSON.parse(jsonText);
  } catch {
    return null;
  }
}

export function dbUrlForProject(projectId) {
  return `https://${projectId}-default-rtdb.firebaseio.com`;
}

export function notifyWorkerUrl(tenant, subdomain) {
  return `https://alertsys-${tenant}.${subdomain || 'REPLACE-workers-subdomain'}.workers.dev/notify`;
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
      '[--workers-subdomain <sub>] [--owner-email <e>] [--owner-name "First Last"] [--owner-company <co>]'
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
  const dbUrl = dbUrlForProject(projectId);
  const notifyUrl = notifyWorkerUrl(tenant, flags['workers-subdomain'] || process.env.CLOUDFLARE_WORKERS_SUBDOMAIN);
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
      const login = runCmd('firebase', ['login:list']);
      if (login.status !== 0 || /no authorized accounts/i.test(login.stdout || '')) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error('  Not logged in to Firebase. Run: firebase login');
        process.exit(1);
        return;
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
      runCmd('firebase', [
        'database:instances:create', `${projectId}-default-rtdb`,
        '--project', projectId, '--location', region,
      ]);
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
          console.warn(`  WARN: ${file} not found — skipping ${key}.`);
          continue;
        }
        const content = readFileSync(src, 'utf8');
        const { content: out, workerName } = templateTenantConfig({ content, tenant, dbUrl, notifyUrl });
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
          runCmd('wrangler', ['secret', 'put', name, '--config', cfgPath], { input: value });
        }
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'deploy') {
      for (const { key } of WORKER_TEMPLATES) {
        const cfgPath = join(tenantDir, tenantConfigFileName(key, tenant));
        if (!existsSync(cfgPath)) continue;
        const r = runCmd('wrangler', ['deploy', '--config', cfgPath]);
        if (r.status !== 0) {
          console.error(`  WARN: deploy failed for ${key}: ${(r.stderr || r.stdout || '').slice(0, 300)}`);
        }
      }
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'seed-owner') {
      if (!flags['owner-email'] || !flags['owner-name'] || !flags['owner-company']) {
        console.log(`[TODO]    ${step.n}. ${step.label}`);
        console.log('  Pass --owner-email/--owner-name/--owner-company to run this automatically, or later:');
        console.log(
          `    node tool/provision_owner.mjs --email <email> --name "First Last" ` +
          `--company <company> --tenant ${tenant} --db-url ${dbUrl}`
        );
        manualTodos.push('Seed the Owner account with tool/provision_owner.mjs (see command above).');
        continue;
      }
      const r = runCmd('node', [
        join(REPO_ROOT, 'tool', 'provision_owner.mjs'),
        '--email', flags['owner-email'],
        '--name', flags['owner-name'],
        '--company', flags['owner-company'],
        '--tenant', tenant,
        '--db-url', dbUrl,
      ]);
      if (r.stdout) console.log(r.stdout);
      if (r.status !== 0) {
        console.error(`[FAIL]    ${step.n}. ${step.label}`);
        console.error(r.stderr || '');
        process.exit(1);
        return;
      }
      step._ownerSummary = extractJsonSummary(r.stdout || '');
      console.log(`[DONE]    ${step.n}. ${step.label}`);
      continue;
    }

    if (step.id === 'summary') {
      const written = (plan.find((s) => s.id === 'worker-configs') || {})._written || [];
      const workersSubdomain =
        flags['workers-subdomain'] || process.env.CLOUDFLARE_WORKERS_SUBDOMAIN || null;
      const summary = {
        tenant,
        projectId,
        region,
        dbUrl,
        workersSubdomain,
        workerUrls: workerUrlsForTenant(written, workersSubdomain),
        workerConfigs: written,
        owner: (plan.find((s) => s.id === 'seed-owner') || {})._ownerSummary || null,
        generatedAt: new Date().toISOString(),
      };
      mkdirSync(tenantDir, { recursive: true });
      writeFileSync(join(tenantDir, 'provision-summary.json'), JSON.stringify(summary, null, 2) + '\n');
      // Registry: the local ledger list_tenants/teardown read.
      saveRegistry(upsertTenant(loadRegistry(), {
        tenant,
        projectId,
        status: 'provisioned',
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
