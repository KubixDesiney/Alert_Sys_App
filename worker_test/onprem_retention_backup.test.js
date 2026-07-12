// Retention policy + local backup/restore for the on-prem runner.
import { describe, test, expect, beforeEach, afterEach } from '@jest/globals';
import { mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { MemoryStore } from '../deploy/onprem/worker-runner/store.mjs';
import {
  findExpiredAlerts, findExpiredNotifications, runRetentionCycle,
} from '../deploy/onprem/worker-runner/retention.mjs';
import {
  runBackup, restoreBackup, readBackup, pruneBackups, makeArchiveSink,
} from '../deploy/onprem/worker-runner/backup.mjs';
import { AuditTrail } from '../deploy/onprem/worker-runner/audit.mjs';

const NOW = Date.UTC(2026, 6, 11);
const DAY = 24 * 60 * 60 * 1000;
const iso = (msAgo) => new Date(NOW - msAgo).toISOString();

let dir;
beforeEach(() => { dir = mkdtempSync(join(tmpdir(), 'sias-backup-test-')); });
afterEach(() => { rmSync(dir, { recursive: true, force: true }); });

describe('retention selection', () => {
  test('only terminal alerts older than the cutoff are selected', () => {
    const alerts = [
      { id: 'keep-open', status: 'disponible', timestamp: iso(500 * DAY) },
      { id: 'keep-recent', status: 'validee', resolvedAt: iso(10 * DAY) },
      { id: 'expire-me', status: 'validee', resolvedAt: iso(400 * DAY) },
      { id: 'expire-legacy', status: 'validee', timestamp: iso(400 * DAY) }, // no resolvedAt
    ];
    expect(findExpiredAlerts(alerts, { retentionDays: 365, now: NOW }).map((a) => a.id))
      .toEqual(['expire-me', 'expire-legacy']);
  });

  test('stale notifications are selected after 30 days', () => {
    const notifications = [
      { id: 'n-old', createdAt: iso(31 * DAY) },
      { id: 'n-new', createdAt: iso(2 * DAY) },
    ];
    expect(findExpiredNotifications(notifications, { now: NOW }).map((n) => n.id))
      .toEqual(['n-old']);
  });
});

describe('runRetentionCycle', () => {
  test('archives BEFORE deleting, purges notifications, writes an audit row', async () => {
    const store = new MemoryStore({
      alerts: [
        { id: 'live', status: 'en_cours', timestamp: iso(400 * DAY) },
        { id: 'ancient', status: 'validee', resolvedAt: iso(400 * DAY) },
      ],
      notifications: [{ id: 'n1', createdAt: iso(40 * DAY) }],
    });
    const archived = [];
    const audits = [];

    const result = await runRetentionCycle(store, {
      retentionDays: 365,
      now: NOW,
      archive: async (label, rows) => archived.push({ label, rows }),
      audit: async (action, fields) => audits.push({ action, ...fields }),
    });

    expect(result).toEqual({ alertsArchived: 1, alertsDeleted: 1, notificationsDeleted: 1 });
    expect(archived[0].label).toBe('alerts_archive');
    expect(archived[0].rows[0].id).toBe('ancient');
    expect((await store.listAlerts()).map((a) => a.id)).toEqual(['live']); // open alert untouched
    expect(await store.listNotifications()).toEqual([]);
    expect(audits[0].action).toBe('retention.cycle');
  });

  test('a quiet day writes no audit noise', async () => {
    const store = new MemoryStore({ alerts: [{ id: 'a', status: 'disponible', timestamp: iso(DAY) }] });
    const audits = [];
    const result = await runRetentionCycle(store, {
      now: NOW, audit: async (a) => audits.push(a),
    });
    expect(result.alertsDeleted).toBe(0);
    expect(audits).toEqual([]);
  });
});

describe('backup + restore', () => {
  test('snapshot round-trips every collection through gzip JSON', async () => {
    const store = new MemoryStore({
      users: [{ id: 'u1', role: 'supervisor' }],
      alerts: [{ id: 'al1', status: 'disponible' }],
      notifications: [{ id: 'n1', recipientId: 'u1' }],
      escalationSettings: { default: { unclaimedMinutes: 15 } },
    });

    const { file, counts } = await runBackup(store, dir, { now: NOW });
    expect(counts.alerts).toBe(1);
    expect(counts.users).toBe(1);

    const raw = readBackup(file);
    expect(raw.collections.alerts[0].id).toBe('al1');

    const empty = new MemoryStore();
    const { restored } = await restoreBackup(empty, file);
    expect(restored.alerts).toBe(1);
    expect((await empty.listAlerts())[0].id).toBe('al1');
    expect((await empty.listUsers())[0].id).toBe('u1');
    expect((await empty.getEscalationSettings()).default.unclaimedMinutes).toBe(15);
  });

  test('pruning keeps only the newest N snapshots', async () => {
    const store = new MemoryStore();
    for (let i = 0; i < 5; i++) {
      await runBackup(store, dir, { now: NOW + i * 1000, keep: 100 });
    }
    pruneBackups(dir, 2);
    const left = readdirSync(dir).filter((f) => f.startsWith('sias-backup-'));
    expect(left.length).toBe(2);
    // the two newest survive (sorted names == sorted timestamps)
    expect(left.sort().pop()).toContain('2026-07-11');
  });

  test('archive sink writes labeled gzip files next to the backups', async () => {
    const sink = makeArchiveSink(dir, () => NOW);
    await sink('alerts_archive', [{ id: 'x' }]);
    expect(readdirSync(dir).some((f) => f.startsWith('alerts_archive-'))).toBe(true);
  });
});

describe('AuditTrail', () => {
  test('writes to the store and the local JSONL file, and never throws', async () => {
    const store = new MemoryStore();
    const file = join(dir, 'audit.jsonl');
    const trail = new AuditTrail(store, { file });

    await trail.record('ingest.created', { targetType: 'alert', targetId: 'al1', detail: 'x' });
    expect(store.auditLogs.length).toBe(1);
    expect(store.auditLogs[0].actorId).toBe('worker-runner');

    // a store that explodes must not break the caller
    const broken = new AuditTrail({ addAudit: async () => { throw new Error('db down'); } }, { file });
    await expect(broken.record('backup.created', {})).resolves.toBeDefined();
  });
});
