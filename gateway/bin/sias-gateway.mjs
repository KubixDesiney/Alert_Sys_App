#!/usr/bin/env node
// =============================================================================
// sias-gateway CLI — bridge plant telemetry into your SIAS instance.
// =============================================================================
//   node bin/sias-gateway.mjs --config gateway.config.json
//   node bin/sias-gateway.mjs --sim 6 --fault-every 90s        # live demo plant
//   node bin/sias-gateway.mjs --sim 3 --dry-run                # print payloads, no POSTs
//
// --dry-run prints the mapped ingest payloads for a couple of simulation ticks
// and exits — the fastest way to see exactly what would be sent.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, parseDuration, validateConfig } from '../src/config.mjs';
import { Gateway } from '../src/runtime.mjs';
import { SimSource, simMapRules } from '../src/sources/sim.mjs';
import { mapReadings } from '../src/mapping.mjs';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) { out[key] = true; continue; }
    out[key] = next;
    i++;
  }
  return out;
}

const HELP = `sias-gateway — SIAS reference edge gateway

Usage:
  sias-gateway --config gateway.config.json     run against your configured sources
  sias-gateway --sim <N> [--fault-every 90s]    built-in plant simulator (N machines)
  sias-gateway --sim <N> --dry-run              print mapped payloads and exit
Options:
  --config <path>      config file (see gateway.config.example.json)
  --sim <N>            add a simulator source with N machines
  --fault-every <dur>  simulator fault injection cadence (default 90s)
  --dry-run            map + print instead of POSTing; exits after 2 ticks
  --queue-dir <path>   on-disk retry queue location (default gateway/queue)
`;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { console.log(HELP); return; }

  const gatewayDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const defaultConfigPath = path.join(gatewayDir, 'gateway.config.json');
  const dryRun = !!args['dry-run'];

  // --dry-run --sim: fully offline — print two ticks of mapped payloads, exit 0.
  if (dryRun && args.sim) {
    const machines = Number(args.sim) || 3;
    const sim = new SimSource({ machines, faultEveryMs: 1, seed: 7 }); // force a fault on tick 1
    const rules = simMapRules(machines);
    for (let tick = 0; tick < 2; tick++) {
      const { readings } = sim.tick(Date.now() + tick * 2000);
      const { mapped } = mapReadings(readings, rules, { source: 'sim' });
      for (const payload of mapped) console.log(JSON.stringify(payload));
    }
    console.error(`\n[sias-gateway] dry run complete: ${machines} machines × 2 ticks mapped. Nothing was sent.`);
    return;
  }

  // Build the effective config: file (if present) + --sim source.
  let config;
  if (args.config) {
    config = loadConfig(String(args.config));
  } else if (fs.existsSync(defaultConfigPath)) {
    config = loadConfig(defaultConfigPath);
  } else if (args.sim && dryRun === false) {
    config = { ingestUrl: process.env.SIAS_INGEST_URL, ingestKey: process.env.SIAS_INGEST_KEY, sources: [] };
  } else {
    console.error('No config found. Pass --config <path>, or --sim N --dry-run for an offline demo.\n');
    console.error(HELP);
    process.exit(1);
  }

  if (args.sim) {
    config.sources = [
      ...(config.sources || []),
      {
        type: 'sim',
        machines: Number(args.sim) || 6,
        faultEveryMs: parseDuration(args['fault-every'], 90000),
      },
    ];
  }

  const v = validateConfig(config);
  if (!v.ok) {
    console.error(`Invalid configuration:\n  - ${v.errors.join('\n  - ')}`);
    console.error('\nHint: set ingestUrl/ingestKey in the config file (or SIAS_INGEST_URL / SIAS_INGEST_KEY env vars for --sim runs).');
    process.exit(1);
  }

  const gateway = new Gateway(config, { dryRun, queueDir: args['queue-dir'] ? String(args['queue-dir']) : undefined });
  await gateway.start();
  console.log(`[sias-gateway] running — ${config.sources.length} source(s) → ${config.ingestUrl}`);

  const shutdown = async (sig) => {
    console.log(`\n[sias-gateway] ${sig} — flushing and stopping…`);
    await gateway.stop();
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((e) => {
  console.error(`[sias-gateway] fatal: ${e?.message || e}`);
  process.exit(1);
});
