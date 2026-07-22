#!/usr/bin/env node
// =============================================================================
// Post-provision verification — proves a tenant instance is actually alive.
// =============================================================================
// Usage: node tool/verify_instance.mjs --tenant <slug> [--db-url <rtdb-url>]
//        [--summary <path>]         (npm run verify:instance -- --tenant t)
//
// Reads deploy/tenants/<tenant>/provision-summary.json and probes:
//   1. every tenant worker's GET /config endpoint (must respond 200)
//   2. the RTDB REST endpoint responds (/.json?shallow=true — ANY HTTP answer
//      counts as reachable; 401 is expected once rules are deployed)
//   3. rules are actually deployed: an unauthenticated read of /users.json
//      MUST be denied (401/403). A 200 here is a critical failure.
// Prints a green/red table; exit code reflects overall health. Read-only —
// safe to run anytime, wired as the final step of provision_instance --execute.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── pure helpers (unit-tested; no network here) ──────────────────────────────

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

/** Derives worker base URLs from the summary's workerConfigs + subdomain. */
export function workerUrlsFromSummary(summary) {
  if (summary?.workerUrls && typeof summary.workerUrls === 'object') return { ...summary.workerUrls };
  const sub = summary?.workersSubdomain;
  const out = {};
  for (const cfg of summary?.workerConfigs ?? []) {
    if (cfg?.key && cfg?.workerName && sub) out[cfg.key] = `https://${cfg.workerName}.${sub}.workers.dev`;
  }
  return out;
}

/** Builds the full probe plan from a provision summary. */
export function buildProbePlan(summary, { dbUrl } = {}) {
  const probes = [];
  const urls = workerUrlsFromSummary(summary);
  for (const [key, base] of Object.entries(urls)) {
    probes.push({ id: `worker:${key}`, kind: 'worker-config', url: `${String(base).replace(/\/$/, '')}/config` });
  }
  // Shared sias-app worker: the tenant's app URL must resolve AND find its KV
  // config (so the runtime Firebase config gets injected). /__config returns
  // { ok, tenant, hasConfig } — needsBody so classifyProbe can read hasConfig.
  const appUrl = String(summary?.appUrl || '').replace(/\/$/, '');
  if (appUrl) {
    probes.push({
      id: 'app:config',
      kind: 'app-config',
      url: `${appUrl}/__config`,
      needsBody: true,
      expectedTenant: summary?.tenant || null,
    });
  }
  const db = String(dbUrl || summary?.dbUrl || '').replace(/\/$/, '');
  if (db) {
    probes.push({ id: 'rtdb:reachable', kind: 'rtdb-reachable', url: `${db}/.json?shallow=true` });
    probes.push({ id: 'rules:denial', kind: 'rules-denial', url: `${db}/users.json` });
  }
  return probes;
}

/** Classifies one probe outcome. `res` = { ok, status, error } */
export function classifyProbe(probe, res) {
  if (res?.error) {
    return { ok: false, detail: `unreachable (${res.error})` };
  }
  const status = Number(res?.status ?? 0);
  switch (probe.kind) {
    case 'worker-config':
      return status === 200
        ? { ok: true, detail: 'HTTP 200 /config' }
        : { ok: false, detail: `HTTP ${status} (expected 200)` };
    case 'app-config': {
      if (status !== 200) return { ok: false, detail: `HTTP ${status} (expected 200)` };
      let body = null;
      try { body = JSON.parse(res?.body ?? ''); } catch { /* handled below */ }
      if (body && body.ok === true && body.hasConfig === true &&
          (!probe.expectedTenant || body.tenant === probe.expectedTenant)) {
        return { ok: true, detail: `HTTP 200 — config injected (tenant ${body.tenant})` };
      }
      if (body && body.ok === true && body.hasConfig === true && probe.expectedTenant) {
        return { ok: false, detail: `HTTP 200 but tenant=${body.tenant || 'missing'} (expected ${probe.expectedTenant})` };
      }
      if (body && body.hasConfig === false) {
        return { ok: false, detail: 'HTTP 200 but hasConfig=false — TENANTS KV entry missing' };
      }
      return { ok: false, detail: 'HTTP 200 but /__config body unreadable' };
    }
    case 'rtdb-reachable':
      // Any HTTP answer proves the database instance exists and is reachable;
      // 401 is the healthy answer once rules deny anonymous root reads.
      return status > 0
        ? { ok: true, detail: `HTTP ${status} (reachable${status === 401 ? ', locked' : ''})` }
        : { ok: false, detail: 'no HTTP response' };
    case 'rules-denial':
      if (status === 401 || status === 403) return { ok: true, detail: `HTTP ${status} — anonymous read denied` };
      if (status === 200) return { ok: false, detail: 'HTTP 200 — RULES NOT DEPLOYED: anonymous read of /users succeeded' };
      return { ok: false, detail: `HTTP ${status} (expected 401/403)` };
    default:
      return { ok: false, detail: `unknown probe kind ${probe.kind}` };
  }
}

const GREEN = (s) => `\x1b[32m${s}\x1b[0m`;
const RED = (s) => `\x1b[31m${s}\x1b[0m`;

/** Renders the ✓/✗ table. `results` = [{ probe, ok, detail }] */
export function renderProbeTable(results, { color = true } = {}) {
  const g = color ? GREEN : (s) => s;
  const r = color ? RED : (s) => s;
  const idWidth = Math.max(8, ...results.map((x) => x.probe.id.length));
  const lines = results.map((x) =>
    `${x.ok ? g(' ✓ ') : r(' ✗ ')} ${x.probe.id.padEnd(idWidth)}  ${x.ok ? x.detail : r(x.detail)}`,
  );
  const failed = results.filter((x) => !x.ok).length;
  lines.push('');
  lines.push(
    failed === 0
      ? g(`✓ ${results.length}/${results.length} probes healthy`)
      : r(`✗ ${failed}/${results.length} probes FAILED`),
  );
  return lines.join('\n');
}

export function summaryPathFor(tenant, root = REPO_ROOT) {
  return path.join(root, 'deploy', 'tenants', tenant, 'provision-summary.json');
}

// ── runner ───────────────────────────────────────────────────────────────────

async function probeOnce(probe, { fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(probe.url, { signal: controller.signal });
    const out = { status: res.status };
    if (probe.needsBody) {
      try { out.body = await res.text(); } catch { out.body = ''; }
    }
    return out;
  } catch (e) {
    return { error: e?.name === 'AbortError' ? 'timeout' : (e?.cause?.code || e?.message || 'fetch failed') };
  } finally {
    clearTimeout(t);
  }
}

export async function runVerification(summary, { dbUrl, fetchImpl = fetch, log = console } = {}) {
  const probes = buildProbePlan(summary, { dbUrl });
  if (probes.length === 0) {
    log.error('No probes derivable from the summary — it lists no worker URLs and no dbUrl.');
    return { ok: false, results: [] };
  }
  const results = [];
  for (const probe of probes) {
    const res = await probeOnce(probe, { fetchImpl });
    results.push({ probe, ...classifyProbe(probe, res) });
  }
  return { ok: results.every((r) => r.ok), results };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const tenant = typeof args.tenant === 'string' ? args.tenant : '';
  const summaryPath = typeof args.summary === 'string' ? args.summary : (tenant ? summaryPathFor(tenant) : '');
  if (!summaryPath) {
    console.error('Usage: node tool/verify_instance.mjs --tenant <slug> [--db-url <url>] [--summary <path>]');
    process.exit(2);
  }
  if (!fs.existsSync(summaryPath)) {
    console.error(`✗ Summary not found: ${summaryPath}\n  Run provisioning first, or pass --summary <path>.`);
    process.exit(2);
  }
  let summary;
  try {
    summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
  } catch (e) {
    console.error(`✗ Summary is not valid JSON: ${e.message}`);
    process.exit(2);
  }

  console.log(`Verifying instance "${summary.tenant ?? tenant}" (${summary.projectId ?? 'unknown project'})\n`);
  const { ok, results } = await runVerification(summary, { dbUrl: args['db-url'] });
  console.log(renderProbeTable(results));
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(2); });
}
