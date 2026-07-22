import { describe, test, expect } from '@jest/globals';
import {
  parseArgs,
  validateFlags,
  isValidTenantSlug,
  parseSkipList,
  WORKER_TEMPLATES,
  SECRET_SPECS,
  OPTIONAL_SECRET_SPECS,
  tenantWorkerName,
  tenantConfigFileName,
  renameWorker,
  injectVars,
  templateTenantConfig,
  buildEnvTemplate,
  parseEnvFile,
  missingSecretKeys,
  buildStepPlan,
  extractJsonSummary,
  dbUrlForProject,
  notifyWorkerUrl,
  APP_DOMAIN,
  tenantAppUrl,
  tenantIngestHost,
  tenantAppRoute,
  tenantIngestRoute,
  tenantCopilotUrl,
  buildTenantKvValue,
  parseTenantsKvId,
  isPlaceholderKvId,
  ingestRouteBlock,
  appendIngestRoute,
  firebaseWebConfigTemplate,
  isPlaceholderWebConfig,
} from '../tool/provision_instance.mjs';

describe('parseArgs / validateFlags', () => {
  test('parses required + optional flags', () => {
    expect(parseArgs(['--tenant', 'nsw-7k2f', '--project-id=nsw-7k2f-alerts', '--execute'])).toEqual({
      tenant: 'nsw-7k2f',
      'project-id': 'nsw-7k2f-alerts',
      execute: true,
    });
  });

  test('reports missing required flags', () => {
    expect(validateFlags({})).toEqual(['tenant', 'project-id']);
    expect(validateFlags({ tenant: 'x', 'project-id': 'y' })).toEqual([]);
  });
});

describe('isValidTenantSlug', () => {
  test('accepts lowercase alnum-dash slugs', () => {
    expect(isValidTenantSlug('nsw-7k2f')).toBe(true);
    expect(isValidTenantSlug('a')).toBe(true);
  });
  test('rejects uppercase, spaces, leading/trailing dash', () => {
    expect(isValidTenantSlug('NSW-7K2F')).toBe(false);
    expect(isValidTenantSlug('nsw 7k2f')).toBe(false);
    expect(isValidTenantSlug('-nsw')).toBe(false);
    expect(isValidTenantSlug('nsw-')).toBe(false);
    expect(isValidTenantSlug('')).toBe(false);
  });
});

describe('parseSkipList', () => {
  test('splits a comma list and trims whitespace', () => {
    expect(parseSkipList('preflight, rules,deploy')).toEqual(new Set(['preflight', 'rules', 'deploy']));
  });
  test('empty/boolean input yields an empty set', () => {
    expect(parseSkipList(undefined)).toEqual(new Set());
    expect(parseSkipList(true)).toEqual(new Set());
    expect(parseSkipList('')).toEqual(new Set());
  });
});

describe('WORKER_TEMPLATES / SECRET_SPECS', () => {
  test('covers exactly the 8 root worker configs', () => {
    expect(WORKER_TEMPLATES).toHaveLength(8);
    expect(WORKER_TEMPLATES.map((w) => w.key).sort()).toEqual(
      ['ai', 'backup', 'github', 'ingest', 'monitor', 'notify', 'scim', 'store'].sort()
    );
  });
  test('every template has a matching secret spec (possibly empty optional list)', () => {
    for (const { key } of WORKER_TEMPLATES) {
      expect(Array.isArray(SECRET_SPECS[key])).toBe(true);
      expect(Array.isArray(OPTIONAL_SECRET_SPECS[key])).toBe(true);
    }
  });
});

describe('tenantWorkerName / tenantConfigFileName', () => {
  test('suffixes the worker name with -<tenant>', () => {
    expect(tenantWorkerName('alert-notifier', 'nsw-7k2f')).toBe('alert-notifier-nsw-7k2f');
  });
  test('builds the per-tenant config filename', () => {
    expect(tenantConfigFileName('ai', 'nsw-7k2f')).toBe('wrangler.ai.nsw-7k2f.toml');
  });
});

describe('renameWorker', () => {
  test('replaces only the name line', () => {
    const toml = 'name = "alert-notifier"\nmain = "cloudflare_ai_worker.js"\n';
    expect(renameWorker(toml, 'alert-notifier-nsw-7k2f')).toBe(
      'name = "alert-notifier-nsw-7k2f"\nmain = "cloudflare_ai_worker.js"\n'
    );
  });
});

describe('injectVars', () => {
  test('appends a new [vars] section when none exists', () => {
    const toml = 'name = "x"\nmain = "y.js"\n';
    const out = injectVars(toml, { FB_DB_URL: 'https://x-default-rtdb.firebaseio.com' });
    expect(out).toContain('[vars]');
    expect(out).toContain('FB_DB_URL = "https://x-default-rtdb.firebaseio.com"');
  });

  test('inserts a new key into an existing [vars] section', () => {
    const toml = 'name = "x"\n\n[vars]\nEXISTING = "1"\n';
    const out = injectVars(toml, { FB_DB_URL: 'https://x-default-rtdb.firebaseio.com' });
    expect(out).toContain('EXISTING = "1"');
    expect(out).toContain('FB_DB_URL = "https://x-default-rtdb.firebaseio.com"');
  });

  test('overwrites an existing key value in place', () => {
    const toml = 'name = "x"\n\n[vars]\nFB_DB_URL = "https://old-default-rtdb.firebaseio.com"\n';
    const out = injectVars(toml, { FB_DB_URL: 'https://new-default-rtdb.firebaseio.com' });
    expect(out).toContain('FB_DB_URL = "https://new-default-rtdb.firebaseio.com"');
    expect(out).not.toContain('old-default-rtdb');
  });

  test('skips undefined/empty values without touching the content', () => {
    const toml = 'name = "x"\n';
    expect(injectVars(toml, { NOTIFY_WORKER_URL: undefined })).toContain('name = "x"');
  });
});

describe('templateTenantConfig', () => {
  test('renames the worker and injects instance vars', () => {
    const content = 'name = "alertsys"\nmain = "cloudflare_notify_worker.js"\ncompatibility_date = "2025-01-01"\n';
    const { content: out, workerName } = templateTenantConfig({
      content,
      tenant: 'nsw-7k2f',
      dbUrl: 'https://nsw-7k2f-alerts-default-rtdb.firebaseio.com',
      notifyUrl: 'https://alertsys-nsw-7k2f.acct.workers.dev/notify',
    });
    expect(workerName).toBe('alertsys-nsw-7k2f');
    expect(out).toContain('name = "alertsys-nsw-7k2f"');
    expect(out).toContain('FB_DB_URL = "https://nsw-7k2f-alerts-default-rtdb.firebaseio.com"');
    expect(out).toContain('NOTIFY_WORKER_URL = "https://alertsys-nsw-7k2f.acct.workers.dev/notify"');
  });

  test('namespaces the shared backup R2 bucket name per tenant', () => {
    const content = 'name = "alertsys-backup"\n\n[[r2_buckets]]\nbinding = "BACKUPS"\nbucket_name = "alertsys-backups"\n';
    const { content: out } = templateTenantConfig({ content, tenant: 'nsw-7k2f', dbUrl: 'x', notifyUrl: 'y' });
    expect(out).toContain('bucket_name = "nsw-7k2f-alertsys-backups"');
  });

  test('never mutates the original string (root templates stay untouched)', () => {
    const content = 'name = "alertsys"\n';
    templateTenantConfig({ content, tenant: 'nsw-7k2f', dbUrl: 'x', notifyUrl: 'y' });
    expect(content).toBe('name = "alertsys"\n');
  });
});

describe('buildEnvTemplate / parseEnvFile / missingSecretKeys', () => {
  test('template lists every required secret with a placeholder', () => {
    const tpl = buildEnvTemplate('nsw-7k2f');
    expect(tpl).toContain('FIREBASE_SERVICE_ACCOUNT=REPLACE_ME');
    expect(tpl).toContain('N8N_CHAT_WEBHOOK_URL=REPLACE_ME');
    expect(tpl).toContain('nsw-7k2f');
  });

  test('parseEnvFile ignores comments/blank lines and splits on the first =', () => {
    const env = parseEnvFile('# comment\n\nKEY=value=with=equals\nOTHER=1\n');
    expect(env).toEqual({ KEY: 'value=with=equals', OTHER: '1' });
  });

  test('a freshly generated template is entirely "missing" (still placeholders)', () => {
    const env = parseEnvFile(buildEnvTemplate('nsw-7k2f'));
    const missing = missingSecretKeys(env);
    expect(missing).toContain('FIREBASE_SERVICE_ACCOUNT');
    expect(missing).toContain('N8N_CHAT_WEBHOOK_URL');
    expect(missing.length).toBeGreaterThan(0);
  });

  test('once every required key has a real value, nothing is missing', () => {
    const allKeys = new Set();
    for (const { key } of WORKER_TEMPLATES) for (const name of SECRET_SPECS[key]) allKeys.add(name);
    const envText = [...allKeys].map((k) => `${k}=some-real-value`).join('\n');
    expect(missingSecretKeys(parseEnvFile(envText))).toEqual([]);
  });
});

describe('buildStepPlan', () => {
  test('returns the 10 steps in order, numbered from 1', () => {
    const plan = buildStepPlan(new Set());
    expect(plan).toHaveLength(10);
    expect(plan.map((s) => s.n)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(plan[0].id).toBe('preflight');
    expect(plan.at(-1).id).toBe('verify'); // provisioning now proves itself
    expect(plan.every((s) => s.skip === false)).toBe(true);
  });

  test('marks skipped steps without reordering (app-delivery sits before summary)', () => {
    const plan = buildStepPlan(new Set(['rules', 'deploy']));
    const byId = Object.fromEntries(plan.map((s) => [s.id, s.skip]));
    expect(byId.rules).toBe(true);
    expect(byId.deploy).toBe(true);
    expect(byId.preflight).toBe(false);
    expect(plan.map((s) => s.id)).toEqual([
      'preflight', 'firebase-project', 'rules', 'worker-configs', 'secrets', 'deploy',
      'seed-owner', 'app-delivery', 'summary', 'verify',
    ]);
  });
});

describe('extractJsonSummary', () => {
  test('parses the JSON block after "Summary:"', () => {
    const stdout = 'some log line\nSummary:\n{"uid":"abc","email":"a@b.c"}\n';
    expect(extractJsonSummary(stdout)).toEqual({ uid: 'abc', email: 'a@b.c' });
  });
  test('returns null when there is no Summary section or it is malformed', () => {
    expect(extractJsonSummary('no summary here')).toBeNull();
    expect(extractJsonSummary('Summary:\nnot json')).toBeNull();
    expect(extractJsonSummary('')).toBeNull();
  });
});

describe('dbUrlForProject / notifyWorkerUrl', () => {
  test('builds the default RTDB URL from a project id', () => {
    expect(dbUrlForProject('nsw-7k2f-alerts')).toBe('https://nsw-7k2f-alerts-default-rtdb.firebaseio.com');
  });
  test('builds the tenant notify worker URL, falling back to a placeholder subdomain', () => {
    expect(notifyWorkerUrl('nsw-7k2f', 'aziz-nagati01')).toBe('https://alertsys-nsw-7k2f.aziz-nagati01.workers.dev/notify');
    expect(notifyWorkerUrl('nsw-7k2f')).toBe('https://alertsys-nsw-7k2f.REPLACE-workers-subdomain.workers.dev/notify');
  });
});

describe('per-tenant app delivery helpers', () => {
  test('app + ingest hostnames are one level under the app domain', () => {
    expect(APP_DOMAIN).toBe('kubixdesiney.com');
    expect(tenantAppUrl('nagati')).toBe('https://nagati.kubixdesiney.com');
    expect(tenantIngestHost('nagati')).toBe('nagati-ingest.kubixdesiney.com');
    expect(tenantAppRoute('nagati')).toBe('nagati.kubixdesiney.com/*');
    expect(tenantIngestRoute('nagati')).toBe('nagati-ingest.kubixdesiney.com/*');
  });

  test('copilot deep link carries encoded tenant + company context', () => {
    const url = tenantCopilotUrl('NSW#7K2F', 'Nagati Steel');
    expect(url).toContain('/copilot?');
    expect(url).toContain('tenant=NSW%237K2F');
    expect(url).toContain('company=Nagati+Steel');
    expect(tenantCopilotUrl(null, null)).toBe('https://sias.kubixdesiney.com/copilot');
  });

  test('buildTenantKvValue shapes exactly the KV contract the app worker reads', () => {
    const v = buildTenantKvValue({
      tenantCode: 'NSW#7K2F', company: 'Nagati',
      firebase: { projectId: 'p' },
      workerUrls: { ai: 'https://ai', notify: 'https://n', ingest: 'https://ing' },
      copilotUrl: 'https://c',
    });
    expect(v).toEqual({
      tenantCode: 'NSW#7K2F', company: 'Nagati', firebase: { projectId: 'p' },
      workers: { ai: 'https://ai', notify: 'https://n', ingest: 'https://ing', copilotUrl: 'https://c' },
    });
  });

  test('missing pieces fall back to null, never undefined', () => {
    const v = buildTenantKvValue({});
    expect(v.tenantCode).toBeNull();
    expect(v.workers.ai).toBeNull();
    expect(v.firebase).toEqual({});
  });

  test('parseTenantsKvId reads the id from either key order; placeholders are detected', () => {
    expect(parseTenantsKvId('[[kv_namespaces]]\nbinding = "TENANTS"\nid = "abc123"\n')).toBe('abc123');
    expect(parseTenantsKvId('[[kv_namespaces]]\nid = "xyz"\nbinding = "TENANTS"\n')).toBe('xyz');
    expect(parseTenantsKvId('binding = "OTHER"\nid = "nope"\n')).toBeNull();
    expect(isPlaceholderKvId('REPLACE_WITH_TENANTS_KV_ID')).toBe(true);
    expect(isPlaceholderKvId('abc123')).toBe(false);
    expect(isPlaceholderKvId(null)).toBe(true);
  });

  test('appendIngestRoute adds a commented branded-host route, idempotently', () => {
    const toml = 'name = "alertsys-ingest-nagati"\ncompatibility_date = "2025-01-01"\n';
    const once = appendIngestRoute(toml, 'nagati');
    expect(once).toContain('nagati-ingest.kubixdesiney.com/*');
    expect(once).toContain('# routes = ['); // commented until DNS exists
    expect(appendIngestRoute(once, 'nagati')).toBe(once); // idempotent
    expect(ingestRouteBlock('nagati')).toContain('zone_name = "kubixdesiney.com"');
  });

  test('isPlaceholderWebConfig gates on the required Firebase identity fields', () => {
    expect(isPlaceholderWebConfig(null)).toBe(true);
    expect(isPlaceholderWebConfig(JSON.parse(firebaseWebConfigTemplate()))).toBe(true);
    expect(isPlaceholderWebConfig({ apiKey: 'k', appId: 'a', messagingSenderId: 'm', projectId: 'p' })).toBe(false);
    expect(isPlaceholderWebConfig({ apiKey: 'k' })).toBe(true); // missing appId/sender/project
  });
});
