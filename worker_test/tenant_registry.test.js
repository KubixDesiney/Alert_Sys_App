// Tenant registry + teardown pure helpers: upsert/status/table rendering,
// tenant-config filtering (never a root config), and archive naming.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  loadRegistry, saveRegistry, upsertTenant, markStatus, renderTenantTable,
} from '../tool/tenant_registry.mjs';
import { tenantConfigsIn, archiveDirName, buildTeardownPlan } from '../tool/teardown_instance.mjs';
import { workerUrlsForTenant } from '../tool/provision_instance.mjs';

describe('registry operations (pure)', () => {
  test('upsert inserts new tenants and merges existing ones', () => {
    let reg = { tenants: [] };
    reg = upsertTenant(reg, { tenant: 'a', projectId: 'p-a', status: 'provisioned', createdAt: '2026-07-01T00:00:00Z' });
    expect(reg.tenants).toHaveLength(1);
    reg = upsertTenant(reg, { tenant: 'a', status: 'verified', updatedAt: '2026-07-02T00:00:00Z' });
    expect(reg.tenants).toHaveLength(1);
    expect(reg.tenants[0]).toMatchObject({ tenant: 'a', projectId: 'p-a', status: 'verified' });
    reg = upsertTenant(reg, { tenant: 'b', projectId: 'p-b', status: 'provisioned' });
    expect(reg.tenants).toHaveLength(2);
  });

  test('markStatus flips only the named tenant', () => {
    const reg = {
      tenants: [
        { tenant: 'a', status: 'verified' },
        { tenant: 'b', status: 'provisioned' },
      ],
    };
    const out = markStatus(reg, 'b', 'deleted', '2026-07-20T00:00:00Z');
    expect(out.tenants[0].status).toBe('verified');
    expect(out.tenants[1]).toMatchObject({ status: 'deleted', updatedAt: '2026-07-20T00:00:00Z' });
  });

  test('renderTenantTable produces an aligned table and an empty-state hint', () => {
    const table = renderTenantTable({
      tenants: [{
        tenant: 'nsw-7k2f', projectId: 'sias-nsw', status: 'verified',
        createdAt: '2026-07-01T10:00:00Z', workerUrls: { ai: 'x', notify: 'y' },
      }],
    });
    expect(table).toContain('TENANT');
    expect(table).toContain('nsw-7k2f');
    expect(table).toContain('verified');
    expect(table).toContain('2026-07-01');
    expect(renderTenantTable({ tenants: [] })).toContain('No tenants registered');
  });

  test('load/save round-trip and corrupt-file resilience', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sias-reg-'));
    const file = path.join(dir, 'registry.json');
    try {
      expect(loadRegistry(file)).toEqual({ tenants: [] });
      saveRegistry(upsertTenant({ tenants: [] }, { tenant: 'a', projectId: 'p' }), file);
      expect(loadRegistry(file).tenants).toHaveLength(1);
      fs.writeFileSync(file, '{corrupt');
      expect(loadRegistry(file)).toEqual({ tenants: [] });
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('teardown helpers (pure)', () => {
  const files = [
    'wrangler.ai.nsw-7k2f.toml',
    'wrangler.backup.nsw-7k2f.toml',
    'wrangler.ai.other-tenant.toml',
    'provision-summary.json',
    '.env.tenant',
  ];

  test('tenantConfigsIn matches only this tenant\'s wrangler configs', () => {
    expect(tenantConfigsIn(files, 'nsw-7k2f')).toEqual([
      'wrangler.ai.nsw-7k2f.toml',
      'wrangler.backup.nsw-7k2f.toml',
    ]);
    expect(tenantConfigsIn(files, 'missing')).toEqual([]);
    expect(tenantConfigsIn(undefined, 'x')).toEqual([]);
  });

  test('archive name embeds the date; plan lists deletions + manual steps', () => {
    const nowMs = Date.parse('2026-07-20T15:00:00Z');
    expect(archiveDirName('nsw-7k2f', nowMs)).toBe('nsw-7k2f-2026-07-20');
    const plan = buildTeardownPlan('nsw-7k2f', files, nowMs);
    expect(plan.workers).toHaveLength(2);
    expect(plan.workers[0].action).toContain('wrangler delete --config deploy/tenants/nsw-7k2f/');
    expect(plan.archiveTo).toBe('deploy/tenants/_archived/nsw-7k2f-2026-07-20/');
    expect(plan.manualSteps.join(' ')).toMatch(/IRREVERSIBLE/);
    expect(plan.manualSteps.join(' ')).toMatch(/R2 backup/);
  });
});

describe('provision summary worker URLs (pure)', () => {
  test('derives per-tenant workers.dev URLs; empty without a subdomain', () => {
    const written = [
      { key: 'ai', file: 'f', workerName: 'alert-notifier-nsw' },
      { key: 'store', file: 'g', workerName: 'sias-store-nsw' },
    ];
    expect(workerUrlsForTenant(written, 'acme')).toEqual({
      ai: 'https://alert-notifier-nsw.acme.workers.dev',
      store: 'https://sias-store-nsw.acme.workers.dev',
    });
    expect(workerUrlsForTenant(written, '')).toEqual({});
    expect(workerUrlsForTenant(undefined, 'acme')).toEqual({});
  });
});
