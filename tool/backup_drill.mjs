#!/usr/bin/env node
// =============================================================================
// Backup drill — "are backups actually happening?" for a tenant instance.
// =============================================================================
// Usage: node tool/backup_drill.mjs --tenant <slug> [--max-age-hours 36]
//        node tool/backup_drill.mjs --url https://<backup-worker>/config
//
// Fetches the tenant backup worker's GET /config (added alongside this tool),
// checks the newest R2 snapshot is fresher than --max-age-hours (default 36 —
// one missed daily run is tolerated, two is an incident) and exits 0/1
// accordingly. Read-only.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { workerUrlsFromSummary, summaryPathFor, parseArgs } from './verify_instance.mjs';

// ── pure helpers (unit-tested) ────────────────────────────────────────────────

/** Classifies snapshot freshness from the /config payload. */
export function classifyBackupStatus(config, { nowMs = Date.now(), maxAgeHours = 36 } = {}) {
  if (!config || config.ok !== true) return { ok: false, reason: 'backup worker unreachable or unhealthy' };
  if (!config.latest || !config.latest.uploaded) {
    return { ok: false, reason: `no snapshots found (worker ${config.configured ? 'configured' : 'NOT configured'})` };
  }
  const uploadedMs = Date.parse(config.latest.uploaded);
  if (!Number.isFinite(uploadedMs)) return { ok: false, reason: `unparseable snapshot timestamp: ${config.latest.uploaded}` };
  const ageHours = (nowMs - uploadedMs) / 3600000;
  if (ageHours > maxAgeHours) {
    return { ok: false, ageHours, reason: `newest snapshot is ${ageHours.toFixed(1)}h old (max ${maxAgeHours}h)` };
  }
  return {
    ok: true,
    ageHours,
    reason: `newest snapshot ${config.latest.key} is ${ageHours.toFixed(1)}h old (${config.snapshots ?? '?'} kept)`,
  };
}

// ── runner ───────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const maxAgeHours = Number(args['max-age-hours']) || 36;

  let url = typeof args.url === 'string' ? args.url : '';
  if (!url) {
    const tenant = typeof args.tenant === 'string' ? args.tenant : '';
    if (!tenant) {
      console.error('Usage: node tool/backup_drill.mjs --tenant <slug> [--max-age-hours 36] | --url <backup-worker>/config');
      process.exit(2);
    }
    const summaryPath = summaryPathFor(tenant);
    if (!fs.existsSync(summaryPath)) {
      console.error(`✗ Summary not found: ${summaryPath}`);
      process.exit(2);
    }
    const summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
    const base = workerUrlsFromSummary(summary).backup;
    if (!base) {
      console.error('✗ Summary lists no backup worker URL (re-provision with a workers subdomain, or pass --url).');
      process.exit(2);
    }
    url = `${String(base).replace(/\/$/, '')}/config`;
  }

  let config;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    config = await res.json();
  } catch (e) {
    console.error(`✗ Backup worker unreachable: ${e?.message || e}`);
    process.exit(1);
  }

  const verdict = classifyBackupStatus(config, { maxAgeHours });
  console.log(verdict.ok ? `✓ ${verdict.reason}` : `✗ ${verdict.reason}`);
  process.exit(verdict.ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(2); });
}
