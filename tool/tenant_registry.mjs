// =============================================================================
// Tenant registry — the local ledger of provisioned dedicated instances.
// =============================================================================
// Lives at deploy/tenants/registry.json (git-ignored with the rest of the
// per-tenant output). Maintained by provision_instance / teardown_instance;
// read by list_tenants / verify_instance. Pure helpers exported for tests.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

export function registryPath(root = REPO_ROOT) {
  return path.join(root, 'deploy', 'tenants', 'registry.json');
}

export function loadRegistry(file = registryPath()) {
  if (!fs.existsSync(file)) return { tenants: [] };
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return { tenants: Array.isArray(parsed?.tenants) ? parsed.tenants : [] };
  } catch {
    return { tenants: [] };
  }
}

export function saveRegistry(registry, file = registryPath()) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(registry, null, 2) + '\n');
}

/** Pure: insert or update a tenant entry (matched by tenant slug). */
export function upsertTenant(registry, entry) {
  const tenants = [...(registry?.tenants ?? [])];
  const idx = tenants.findIndex((t) => t.tenant === entry.tenant);
  if (idx === -1) tenants.push({ createdAt: entry.createdAt ?? new Date().toISOString(), ...entry });
  else tenants[idx] = { ...tenants[idx], ...entry, updatedAt: entry.updatedAt ?? new Date().toISOString() };
  return { tenants };
}

/** Pure: flip a tenant's lifecycle status (provisioned/verified/failed/deleted). */
export function markStatus(registry, tenant, status, at = new Date().toISOString()) {
  return {
    tenants: (registry?.tenants ?? []).map((t) =>
      t.tenant === tenant ? { ...t, status, updatedAt: at } : t,
    ),
  };
}

/** Pure: fixed-width table of the registry for terminal display. */
export function renderTenantTable(registry) {
  const tenants = registry?.tenants ?? [];
  if (tenants.length === 0) return 'No tenants registered. Run npm run provision:instance to create one.';
  const rows = [
    ['TENANT', 'PROJECT', 'STATUS', 'CREATED', 'WORKERS'],
    ...tenants.map((t) => [
      t.tenant ?? '?',
      t.projectId ?? '?',
      t.status ?? '?',
      String(t.createdAt ?? '').slice(0, 10),
      String(Object.keys(t.workerUrls ?? {}).length || (t.workerConfigs?.length ?? 0)),
    ]),
  ];
  const widths = rows[0].map((_, c) => Math.max(...rows.map((r) => String(r[c]).length)));
  return rows
    .map((r, i) => {
      const line = r.map((cell, c) => String(cell).padEnd(widths[c])).join('  ');
      return i === 0 ? `${line}\n${'─'.repeat(line.length)}` : line;
    })
    .join('\n');
}
