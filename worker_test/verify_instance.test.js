// Post-provision verification: probe-plan derivation from the summary, probe
// classification (incl. the rules-not-deployed critical case), the red/green
// table, and the full runVerification path against a FAKE summary with
// unreachable URLs (the acceptance case: readable red table + non-zero).
import { jest } from '@jest/globals';
import {
  workerUrlsFromSummary,
  buildProbePlan,
  classifyProbe,
  renderProbeTable,
  runVerification,
} from '../tool/verify_instance.mjs';
import { classifyBackupStatus } from '../tool/backup_drill.mjs';

const SUMMARY = {
  tenant: 'nsw-7k2f',
  projectId: 'sias-nsw-7k2f',
  dbUrl: 'https://sias-nsw-7k2f-default-rtdb.firebaseio.com',
  workersSubdomain: 'acme',
  workerConfigs: [
    { key: 'ai', file: 'wrangler.ai.nsw-7k2f.toml', workerName: 'alert-notifier-nsw-7k2f' },
    { key: 'backup', file: 'wrangler.backup.nsw-7k2f.toml', workerName: 'alertsys-backup-nsw-7k2f' },
  ],
};

describe('workerUrlsFromSummary', () => {
  test('prefers an explicit workerUrls map', () => {
    expect(workerUrlsFromSummary({ workerUrls: { ai: 'https://x' } })).toEqual({ ai: 'https://x' });
  });

  test('derives URLs from workerConfigs + subdomain', () => {
    expect(workerUrlsFromSummary(SUMMARY)).toEqual({
      ai: 'https://alert-notifier-nsw-7k2f.acme.workers.dev',
      backup: 'https://alertsys-backup-nsw-7k2f.acme.workers.dev',
    });
  });

  test('no subdomain → no derivable URLs', () => {
    expect(workerUrlsFromSummary({ workerConfigs: SUMMARY.workerConfigs })).toEqual({});
  });
});

describe('buildProbePlan', () => {
  test('one /config probe per worker plus RTDB reachability + rules denial', () => {
    const plan = buildProbePlan(SUMMARY);
    expect(plan.map((p) => p.id)).toEqual(['worker:ai', 'worker:backup', 'rtdb:reachable', 'rules:denial']);
    expect(plan[0].url).toBe('https://alert-notifier-nsw-7k2f.acme.workers.dev/config');
    expect(plan[2].url).toContain('/.json?shallow=true');
    expect(plan[3].url).toContain('/users.json');
  });

  test('db-url override wins over the summary value', () => {
    const plan = buildProbePlan(SUMMARY, { dbUrl: 'https://other.firebaseio.com/' });
    expect(plan.at(-1).url).toBe('https://other.firebaseio.com/users.json');
  });

  test('empty summary yields an empty plan', () => {
    expect(buildProbePlan({})).toEqual([]);
  });
});

describe('classifyProbe', () => {
  test('worker /config wants exactly 200', () => {
    expect(classifyProbe({ kind: 'worker-config' }, { status: 200 }).ok).toBe(true);
    expect(classifyProbe({ kind: 'worker-config' }, { status: 404 }).ok).toBe(false);
    expect(classifyProbe({ kind: 'worker-config' }, { error: 'ENOTFOUND' }).ok).toBe(false);
  });

  test('rtdb reachability accepts 401 as healthy-and-locked', () => {
    const locked = classifyProbe({ kind: 'rtdb-reachable' }, { status: 401 });
    expect(locked.ok).toBe(true);
    expect(locked.detail).toContain('locked');
    expect(classifyProbe({ kind: 'rtdb-reachable' }, { error: 'timeout' }).ok).toBe(false);
  });

  test('rules denial: 401/403 pass, an anonymous 200 is the critical failure', () => {
    expect(classifyProbe({ kind: 'rules-denial' }, { status: 401 }).ok).toBe(true);
    expect(classifyProbe({ kind: 'rules-denial' }, { status: 403 }).ok).toBe(true);
    const open = classifyProbe({ kind: 'rules-denial' }, { status: 200 });
    expect(open.ok).toBe(false);
    expect(open.detail).toContain('RULES NOT DEPLOYED');
  });
});

describe('renderProbeTable', () => {
  test('marks failures red and reports the failed count', () => {
    const table = renderProbeTable(
      [
        { probe: { id: 'worker:ai' }, ok: true, detail: 'HTTP 200 /config' },
        { probe: { id: 'rules:denial' }, ok: false, detail: 'HTTP 200 — RULES NOT DEPLOYED: anonymous read of /users succeeded' },
      ],
      { color: false },
    );
    expect(table).toContain('✓  worker:ai');
    expect(table).toContain('✗  rules:denial');
    expect(table).toContain('1/2 probes FAILED');
  });

  test('all-green summary line', () => {
    const table = renderProbeTable([{ probe: { id: 'a' }, ok: true, detail: 'fine' }], { color: false });
    expect(table).toContain('1/1 probes healthy');
  });
});

describe('runVerification against a fake summary with unreachable URLs', () => {
  test('every probe fails, table is renderable, overall verdict is false', async () => {
    const deadFetch = jest.fn(async () => { throw Object.assign(new Error('getaddrinfo ENOTFOUND'), { cause: { code: 'ENOTFOUND' } }); });
    const { ok, results } = await runVerification(SUMMARY, { fetchImpl: deadFetch });
    expect(ok).toBe(false);
    expect(results).toHaveLength(4);
    expect(results.every((r) => r.ok === false)).toBe(true);
    const table = renderProbeTable(results, { color: false });
    expect(table).toContain('4/4 probes FAILED');
    expect(table).toContain('unreachable');
  });

  test('healthy responses produce a green verdict', async () => {
    const healthyFetch = jest.fn(async (url) => ({
      status: String(url).includes('firebaseio.com') ? 401 : 200,
    }));
    const { ok, results } = await runVerification(SUMMARY, { fetchImpl: healthyFetch });
    expect(ok).toBe(true);
    expect(results.every((r) => r.ok)).toBe(true);
  });

  test('empty summary is an immediate failure with no probes', async () => {
    const { ok, results } = await runVerification({}, { log: { error: () => {} } });
    expect(ok).toBe(false);
    expect(results).toEqual([]);
  });
});

describe('backup drill classification', () => {
  const NOW = Date.parse('2026-07-20T12:00:00Z');
  const cfg = (uploaded, extra = {}) => ({
    ok: true, worker: 'alertsys-backup', configured: true, snapshots: 12,
    latest: { key: 'rtdb/2026-07-20-02-00-00.json', uploaded, size: 1024 }, ...extra,
  });

  test('fresh snapshot passes with its age reported', () => {
    const v = classifyBackupStatus(cfg('2026-07-20T02:00:00Z'), { nowMs: NOW });
    expect(v.ok).toBe(true);
    expect(v.ageHours).toBeCloseTo(10, 0);
    expect(v.reason).toContain('rtdb/2026-07-20');
  });

  test('stale snapshot (>36h) fails with the age in the reason', () => {
    const v = classifyBackupStatus(cfg('2026-07-18T02:00:00Z'), { nowMs: NOW });
    expect(v.ok).toBe(false);
    expect(v.reason).toContain('58.0h');
  });

  test('missing snapshots, unhealthy worker, junk timestamps all fail readably', () => {
    expect(classifyBackupStatus({ ok: true, configured: false, latest: null }).ok).toBe(false);
    expect(classifyBackupStatus({ ok: false }).ok).toBe(false);
    expect(classifyBackupStatus(null).ok).toBe(false);
    expect(classifyBackupStatus(cfg('yesterday-ish')).ok).toBe(false);
  });

  test('custom max age is honored', () => {
    const v = classifyBackupStatus(cfg('2026-07-20T02:00:00Z'), { nowMs: NOW, maxAgeHours: 8 });
    expect(v.ok).toBe(false);
  });
});
