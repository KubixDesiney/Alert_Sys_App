#!/usr/bin/env node
// =============================================================================
// Tenant teardown — deletes a tenant's Cloudflare workers, archives its files.
// =============================================================================
// DRY-RUN BY DEFAULT: prints the exact plan and touches nothing. With
// --execute it:
//   1. deletes each tenant worker (`wrangler delete` per generated config)
//   2. archives deploy/tenants/<tenant>/ → deploy/tenants/_archived/<tenant>-<date>/
//   3. marks the tenant "deleted" in the registry
//
// ⚠ WHAT THIS TOOL WILL **NOT** DO — read this before running --execute:
//   - It does NOT delete the customer's Firebase project (database, auth
//     users, storage). That deletion is MANUAL and IRREVERSIBLE — do it in the
//     Firebase console only after contractual data-retention obligations are
//     met: https://console.firebase.google.com → project settings → delete.
//   - It does NOT delete R2 backup buckets/snapshots (retention obligations).
//   - It does NOT touch root wrangler.*.toml files or any other tenant.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadRegistry, saveRegistry, markStatus } from './tenant_registry.mjs';

const REPO_ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── pure helpers (unit-tested) ────────────────────────────────────────────────

export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[key] = true;
    else { out[key] = next; i++; }
  }
  return out;
}

/** Tenant wrangler configs inside a tenant dir (never root configs). */
export function tenantConfigsIn(files, tenant) {
  const re = new RegExp(`^wrangler\\.[a-z]+\\.${tenant}\\.toml$`);
  return (files ?? []).filter((f) => re.test(f)).sort();
}

export function archiveDirName(tenant, nowMs = Date.now()) {
  return `${tenant}-${new Date(nowMs).toISOString().slice(0, 10)}`;
}

/** The teardown plan: pure description of every action --execute would take. */
export function buildTeardownPlan(tenant, files, nowMs = Date.now()) {
  return {
    workers: tenantConfigsIn(files, tenant).map((file) => ({
      file,
      action: `wrangler delete --config deploy/tenants/${tenant}/${file}`,
    })),
    archiveTo: `deploy/tenants/_archived/${archiveDirName(tenant, nowMs)}/`,
    manualSteps: [
      'Firebase project deletion is MANUAL and IRREVERSIBLE — Firebase console → project settings → delete (only after data-retention obligations are met).',
      'R2 backup snapshots are kept — delete the bucket manually when retention allows.',
      'Revoke the customer-specific secrets at their providers (Stripe/n8n/GitHub) if any were issued.',
    ],
  };
}

// ── runner ───────────────────────────────────────────────────────────────────

function runWrangler(args, cwd) {
  return spawnSync('wrangler', args, {
    encoding: 'utf8',
    cwd,
    shell: process.platform === 'win32',
    // Non-TTY/CI mode makes wrangler skip interactive confirmation prompts.
    env: { ...process.env, CI: 'true' },
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const tenant = typeof args.tenant === 'string' ? args.tenant : '';
  if (!tenant || !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(tenant)) {
    console.error('Usage: node tool/teardown_instance.mjs --tenant <slug> [--execute]');
    process.exit(2);
  }
  const execute = args.execute === true || args.execute === 'true';
  const tenantDir = path.join(REPO_ROOT, 'deploy', 'tenants', tenant);
  if (!fs.existsSync(tenantDir)) {
    console.error(`✗ No tenant directory: deploy/tenants/${tenant}/ — nothing to tear down.`);
    process.exit(2);
  }

  const files = fs.readdirSync(tenantDir);
  const plan = buildTeardownPlan(tenant, files);

  console.log(`Teardown plan for tenant "${tenant}" — ${execute ? 'EXECUTE' : 'DRY RUN (default; pass --execute)'}\n`);
  if (plan.workers.length === 0) {
    console.log('  (no tenant wrangler configs found — workers may already be deleted)');
  }
  for (const w of plan.workers) console.log(`  DELETE  ${w.action}`);
  console.log(`  ARCHIVE deploy/tenants/${tenant}/ → ${plan.archiveTo}`);
  console.log('\nThis tool will NOT do (manual, deliberate steps):');
  for (const s of plan.manualSteps) console.log(`  ⚠ ${s}`);

  if (!execute) {
    console.log('\nDry run complete — nothing was changed.');
    return;
  }

  let failures = 0;
  for (const w of plan.workers) {
    const r = runWrangler(['delete', '--config', path.join(tenantDir, w.file)], REPO_ROOT);
    if (r.status === 0) {
      console.log(`  ✓ deleted worker from ${w.file}`);
    } else {
      failures++;
      console.error(`  ✗ delete failed for ${w.file}: ${(r.stderr || r.stdout || '').trim().slice(0, 300)}`);
    }
  }

  const archiveRoot = path.join(REPO_ROOT, 'deploy', 'tenants', '_archived');
  const dest = path.join(archiveRoot, archiveDirName(tenant));
  fs.mkdirSync(archiveRoot, { recursive: true });
  fs.renameSync(tenantDir, dest);
  console.log(`  ✓ archived to ${path.relative(REPO_ROOT, dest)}`);

  const registry = loadRegistry();
  saveRegistry(markStatus(registry, tenant, 'deleted'));
  console.log('  ✓ registry updated (status: deleted)');

  if (failures) {
    console.error(`\n✗ ${failures} worker deletion(s) failed — re-run after fixing, or delete them in the Cloudflare dashboard.`);
    process.exit(1);
  }
  console.log('\n✓ Teardown complete. Remember the manual steps above.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(2); });
}
