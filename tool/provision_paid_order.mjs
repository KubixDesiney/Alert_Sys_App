#!/usr/bin/env node
// End-to-end runner for repository_dispatch(event_type=sias_order_paid).
// Fetches the private order from Supabase by ID, bootstraps its Firebase
// project, builds worker secrets, runs the verified instance provisioner, and
// marks the order active. GitHub event metadata contains no buyer PII.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export function tenantSlugFromCode(tenantCode) {
  const slug = String(tenantCode || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');
  return slug || '';
}

export function projectIdForOrder(tenantCode) {
  const slug = tenantSlugFromCode(tenantCode);
  const digest = createHash('sha256').update(String(tenantCode)).digest('hex').slice(0, 6);
  const stem = slug.slice(0, 17).replace(/-+$/g, '');
  return `sias-${stem}-${digest}`;
}

export function validatePaidOrder(order, expectedTenantCode = '') {
  const errors = [];
  if (!order || typeof order !== 'object') return ['order response is empty'];
  if (expectedTenantCode && order.tenant_code !== expectedTenantCode) {
    errors.push('tenant code does not match the signed dispatch payload');
  }
  if (!['provisioning_queued', 'provisioning', 'provisioning_failed'].includes(order.status)) {
    errors.push(`order status ${order.status || '(missing)'} is not provisionable`);
  }
  for (const key of [
    'id',
    'tenant_code',
    'company',
    'plan',
    'pm_name',
    'pm_email',
    'supervisor_name',
    'supervisor_email',
  ]) {
    if (order[key] === undefined || order[key] === null || String(order[key]).trim() === '') {
      errors.push(`order is missing ${key}`);
    }
  }
  if (!['starter', 'growth'].includes(order.plan)) errors.push('order plan must be starter or growth');
  if (String(order.pm_email || '').toLowerCase() === String(order.supervisor_email || '').toLowerCase()) {
    errors.push('PM and supervisor emails must be different');
  }
  return errors;
}

async function supabaseRequest(path, options = {}) {
  const base = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const key = process.env.SUPABASE_SERVICE_KEY;
  if (!base || !key) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY are required.');
  const response = await fetch(`${base}/rest/v1/${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${key}`,
      apikey: key,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`Supabase order operation failed (${response.status}).`);
  return body;
}

async function getOrder(orderId) {
  const rows = await supabaseRequest(
    `sias_orders?id=eq.${encodeURIComponent(orderId)}&select=*&limit=1`,
  );
  return Array.isArray(rows) ? rows[0] || null : null;
}

async function patchOrder(orderId, patch) {
  const rows = await supabaseRequest(
    `sias_orders?id=eq.${encodeURIComponent(orderId)}&select=*`,
    {
      method: 'PATCH',
      headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ ...patch, updated_at: new Date().toISOString() }),
    },
  );
  return Array.isArray(rows) ? rows[0] || null : null;
}

function runChild(args, env = process.env) {
  const result = spawnSync(process.execPath, args, {
    cwd: REPO_ROOT,
    env,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.status !== 0) {
    const detail = String(result.stderr || result.stdout || '').trim().slice(0, 1000);
    throw new Error(detail || `Child process failed: ${args[0]}`);
  }
}

async function main() {
  const orderId = process.env.SIAS_ORDER_ID || '';
  const expectedTenantCode = process.env.SIAS_TENANT_CODE || '';
  if (!/^[A-Za-z0-9-]{1,80}$/.test(orderId)) throw new Error('SIAS_ORDER_ID is invalid.');
  const order = await getOrder(orderId);
  if (order?.status === 'active') {
    console.log('Order is already active; nothing to provision.');
    return;
  }
  const validationErrors = validatePaidOrder(order, expectedTenantCode);
  if (validationErrors.length) throw new Error(validationErrors.join('; '));

  const tenant = tenantSlugFromCode(order.tenant_code);
  const projectId = projectIdForOrder(order.tenant_code);
  const tenantDir = join(REPO_ROOT, 'deploy', 'tenants', tenant);
  const runtimePath = join(tenantDir, 'runtime-service-account.json');
  const webConfigPath = join(tenantDir, 'firebase-web-config.json');
  const tenantEnvPath = join(tenantDir, '.env.tenant');
  const appUrl = `https://${tenant}.kubixdesiney.com`;
  const workersSubdomain = process.env.CLOUDFLARE_WORKERS_SUBDOMAIN || '';
  if (!workersSubdomain) throw new Error('CLOUDFLARE_WORKERS_SUBDOMAIN is required.');

  console.log(`Provisioning paid SIAS order ${order.id}: tenant=${tenant}, project=${projectId}`);
  await patchOrder(order.id, {
    status: 'provisioning',
    provisioning_started_at: order.provisioning_started_at || new Date().toISOString(),
    provisioning_run_id: process.env.GITHUB_RUN_ID || null,
    provisioning_error: null,
  });

  try {
    runChild([
      join(REPO_ROOT, 'tool', 'bootstrap_firebase_project.mjs'),
      '--project-id', projectId,
      '--tenant', tenant,
      '--region', process.env.FIREBASE_DATABASE_REGION || 'europe-west1',
      '--output-dir', tenantDir,
    ]);
    runChild([
      join(REPO_ROOT, 'tool', 'build_tenant_env.mjs'),
      '--runtime-service-account', runtimePath,
      '--firebase-web-config', webConfigPath,
      '--output', tenantEnvPath,
    ]);

    const runtimeCredential = readFileSync(runtimePath, 'utf8').trim();
    runChild([
      join(REPO_ROOT, 'tool', 'provision_instance.mjs'),
      '--tenant', tenant,
      '--project-id', projectId,
      '--region', process.env.FIREBASE_DATABASE_REGION || 'europe-west1',
      '--workers-subdomain', workersSubdomain,
      '--tenant-code', order.tenant_code,
      '--company', order.company,
      '--plan', order.plan,
      '--pm-email', order.pm_email,
      '--pm-name', order.pm_name,
      '--supervisor-email', order.supervisor_email,
      '--supervisor-name', order.supervisor_name,
      '--usine', 'Usine A',
      '--skip', 'firebase-project',
      '--execute',
    ], {
      ...process.env,
      GOOGLE_APPLICATION_CREDENTIALS: runtimePath,
      FIREBASE_SERVICE_ACCOUNT: runtimeCredential,
    });

    await patchOrder(order.id, {
      status: 'active',
      app_url: appUrl,
      firebase_project_id: projectId,
      provisioned_at: new Date().toISOString(),
      provisioning_error: null,
    });
    console.log(`SIAS instance active: ${appUrl}`);
  } catch (error) {
    await patchOrder(order.id, {
      status: 'provisioning_failed',
      firebase_project_id: projectId,
      provisioning_error: String(error.message || error).slice(0, 500),
    }).catch(() => null);
    throw error;
  } finally {
    // These contain the tenant private key. Worker secrets already hold the
    // credential after a successful deploy; a retry rotates a fresh key.
    for (const sensitivePath of [runtimePath, tenantEnvPath]) {
      if (existsSync(sensitivePath)) rmSync(sensitivePath);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`Paid-order provisioning failed: ${error.message}`);
    process.exitCode = 1;
  });
}
