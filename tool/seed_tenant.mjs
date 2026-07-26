#!/usr/bin/env node
// Idempotent day-one RTDB seed for a newly provisioned SIAS tenant.
//
// Defaults to dry-run. Live mode only fills missing leaves, so rerunning a
// failed provisioning job never overwrites hierarchy or settings the buyer has
// already changed.

import { pathToFileURL } from 'node:url';

export const DEFAULT_ALERT_TYPES = Object.freeze({
  qualite: {
    code: 'qualite',
    label: 'Quality',
    color: '#DC2626',
    icon: 'fact_check',
    synonyms: ['qual'],
    severityDefault: 'normal',
    order: 0,
  },
  maintenance: {
    code: 'maintenance',
    label: 'Maintenance',
    color: '#2563EB',
    icon: 'build',
    synonyms: ['mainten', 'entretien'],
    severityDefault: 'normal',
    order: 1,
  },
  defaut_produit: {
    code: 'defaut_produit',
    label: 'Damaged Product',
    color: '#16A34A',
    icon: 'report_problem',
    synonyms: ['defaut', 'defect', 'damag', 'produit', 'product'],
    severityDefault: 'normal',
    order: 2,
  },
  manque_ressource: {
    code: 'manque_ressource',
    label: 'Resource Deficiency',
    color: '#FBBF24',
    icon: 'inventory_2',
    synonyms: ['ressource', 'resource', 'shortage', 'manque', 'stock'],
    severityDefault: 'normal',
    order: 3,
  },
});

export const DEFAULT_ESCALATION_SETTINGS = Object.freeze({
  qualite: { type: 'qualite', unclaimedMinutes: 15, claimedMinutes: 30 },
  maintenance: { type: 'maintenance', unclaimedMinutes: 20, claimedMinutes: 45 },
  defaut_produit: { type: 'defaut_produit', unclaimedMinutes: 25, claimedMinutes: 40 },
  manque_ressource: { type: 'manque_ressource', unclaimedMinutes: 30, claimedMinutes: 60 },
  default: { type: 'default', unclaimedMinutes: 20, claimedMinutes: 40 },
});

export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const equalAt = arg.indexOf('=');
    if (equalAt !== -1) {
      out[arg.slice(2, equalAt)] = arg.slice(equalAt + 1);
    } else if (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) {
      out[arg.slice(2)] = argv[i + 1];
      i += 1;
    } else {
      out[arg.slice(2)] = true;
    }
  }
  return out;
}

export function validateSeedFlags(flags) {
  const errors = [];
  for (const key of ['tenant', 'company', 'plan']) {
    if (typeof flags[key] !== 'string' || !flags[key].trim()) errors.push(`missing --${key}`);
  }
  if (flags.plan && !['starter', 'growth'].includes(String(flags.plan))) {
    errors.push('--plan must be starter or growth');
  }
  return errors;
}

export function buildTenantSeed({
  tenantCode,
  company,
  plan,
  usine = 'Usine A',
  provisionedAt = new Date().toISOString(),
}) {
  const fullPackage = plan === 'growth';
  const address = 'Complete during onboarding';
  return {
    alertCounter: 0,
    assetCounter: 1,
    app_config: {
      schemaVersion: 1,
      tenant: {
        tenantCode,
        company,
        plan,
        primaryUsine: usine,
        provisionedAt,
      },
      entitlements: {
        plan,
        fullPackage,
        aiDispatch: true,
        aiTraining: fullPackage,
        adaptiveAlertSchema: fullPackage,
        connectors: fullPackage,
        shiftCommander: fullPackage,
      },
      alertTypes: DEFAULT_ALERT_TYPES,
    },
    hierarchy: {
      factories: {
        factory_1: {
          name: usine,
          location: address,
          conveyors: {
            conveyor_1: {
              number: 1,
              stations: {
                station_1: {
                  name: 'Station 1',
                  address: 'factory_1_C1_P1',
                  assetId: 'MACH-001',
                },
              },
            },
          },
        },
      },
    },
    factories: {
      factory_1: {
        name: usine,
        address,
        aiConfig: {
          enabled: true,
          updatedAt: provisionedAt,
          updatedBy: 'provisioning',
        },
      },
    },
    assets: {
      'MACH-001': {
        assetId: 'MACH-001',
        name: 'Station 1',
        factoryId: 'factory_1',
        factoryName: usine,
        conveyorId: 'conveyor_1',
        conveyorNumber: 1,
        stationId: 'station_1',
        stationNumber: 1,
        address: 'factory_1_C1_P1',
        isDeleted: false,
        status: 'active',
        updatedAt: provisionedAt,
      },
    },
    escalation_settings: DEFAULT_ESCALATION_SETTINGS,
    ai_forecast: {
      onboarding: {
        entitled: fullPackage,
        adaptiveSchema: fullPackage,
        status: fullPackage ? 'awaiting_dataset' : 'not_entitled',
        supportedInputs: ['csv', 'json', 'xlsx'],
        createdAt: provisionedAt,
      },
    },
  };
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function flattenSeedLeaves(value, prefix = '', out = {}) {
  if (!isPlainObject(value)) {
    if (prefix) out[prefix] = value;
    return out;
  }
  for (const [key, child] of Object.entries(value)) {
    const path = prefix ? `${prefix}/${key}` : key;
    if (isPlainObject(child)) flattenSeedLeaves(child, path, out);
    else out[path] = child;
  }
  return out;
}

function valueAtPath(root, path) {
  let current = root;
  for (const part of path.split('/')) {
    if (!isPlainObject(current) || !(part in current)) return undefined;
    current = current[part];
  }
  return current;
}

export function missingSeedUpdates(seed, existingRoot) {
  const updates = {};
  for (const [path, value] of Object.entries(flattenSeedLeaves(seed))) {
    const existing = valueAtPath(existingRoot || {}, path);
    if (existing === undefined || existing === null) updates[path] = value;
  }
  return updates;
}

async function main() {
  const flags = parseArgs(process.argv.slice(2));
  const errors = validateSeedFlags(flags);
  if (errors.length) {
    console.error(`ERROR: ${errors.join('; ')}`);
    console.error(
      'Usage: node tool/seed_tenant.mjs --tenant <tenantCode> --company <company> ' +
      '--plan <starter|growth> [--usine "Usine A"] [--db-url <url>] [--execute]'
    );
    process.exitCode = 1;
    return;
  }

  const execute = flags.execute === true || flags.execute === 'true';
  const dbUrl = (typeof flags['db-url'] === 'string' && flags['db-url'])
    || process.env.FB_DB_URL
    || '';
  const seed = buildTenantSeed({
    tenantCode: flags.tenant,
    company: flags.company,
    plan: flags.plan,
    usine: typeof flags.usine === 'string' ? flags.usine : 'Usine A',
  });
  const planned = flattenSeedLeaves(seed);
  console.log(`SIAS tenant seed: ${flags.tenant} (${flags.plan})`);
  console.log(`Mode: ${execute ? 'LIVE' : 'DRY RUN'} · ${Object.keys(planned).length} schema leaves`);
  if (!execute) {
    console.log(JSON.stringify(seed, null, 2));
    return;
  }
  if (!dbUrl) throw new Error('No RTDB URL. Pass --db-url or set FB_DB_URL.');

  const admin = (await import('firebase-admin')).default;
  const credential = process.env.FIREBASE_SERVICE_ACCOUNT
    ? admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT))
    : admin.credential.applicationDefault();
  const app = admin.apps.length
    ? admin.app()
    : admin.initializeApp({ credential, databaseURL: dbUrl });
  const root = app.database().ref();
  const existing = (await root.get()).val() || {};
  const updates = missingSeedUpdates(seed, existing);
  if (Object.keys(updates).length) await root.update(updates);
  console.log(`Seed complete: ${Object.keys(updates).length} missing leaves written; existing buyer data preserved.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`Tenant seed failed: ${error.message}`);
    process.exitCode = 1;
  });
}
