#!/usr/bin/env node
// Non-interactive Firebase tenant bootstrap for the Paid GitHub workflow.
// Creates/reuses the GCP project, links billing, enables Firebase services,
// creates RTDB + Email/Password Auth + Web app config, and issues one tenant-
// scoped runtime service-account key. Secret values are written only to the
// git-ignored tenant directory and are never printed.

import { pathToFileURL } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const SERVICES = [
  'firebase.googleapis.com',
  'identitytoolkit.googleapis.com',
  'firebasedatabase.googleapis.com',
  'fcm.googleapis.com',
  'iam.googleapis.com',
  'cloudresourcemanager.googleapis.com',
];

export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const equalAt = arg.indexOf('=');
    if (equalAt !== -1) out[arg.slice(2, equalAt)] = arg.slice(equalAt + 1);
    else if (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) {
      out[arg.slice(2)] = argv[i + 1];
      i += 1;
    } else out[arg.slice(2)] = true;
  }
  return out;
}

export function isValidProjectId(projectId) {
  return typeof projectId === 'string'
    && /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)
    && !projectId.includes('--');
}

export function validateBootstrapFlags(flags) {
  const errors = [];
  if (!isValidProjectId(flags['project-id'])) errors.push('invalid or missing --project-id');
  if (typeof flags.tenant !== 'string' || !flags.tenant.trim()) errors.push('missing --tenant');
  if (typeof flags['output-dir'] !== 'string' || !flags['output-dir'].trim()) {
    errors.push('missing --output-dir');
  }
  return errors;
}

export function normalizeBillingAccount(value) {
  const clean = String(value || '').trim();
  if (!clean) return '';
  return clean.startsWith('billingAccounts/') ? clean : `billingAccounts/${clean}`;
}

export function databaseUrlForRegion(projectId, region) {
  const databaseId = `${projectId}-default-rtdb`;
  return region === 'us-central1'
    ? `https://${databaseId}.firebaseio.com`
    : `https://${databaseId}.${region}.firebasedatabase.app`;
}

export function serviceBatchBody() {
  return {
    serviceIds: SERVICES,
  };
}

export function addIamBinding(policy, role, member) {
  const next = structuredClone(policy || {});
  next.bindings = Array.isArray(next.bindings) ? next.bindings : [];
  let binding = next.bindings.find((item) => item.role === role && !item.condition);
  if (!binding) {
    binding = { role, members: [] };
    next.bindings.push(binding);
  }
  binding.members = Array.isArray(binding.members) ? binding.members : [];
  if (!binding.members.includes(member)) binding.members.push(member);
  return next;
}

export function webConfigFromApi(config, projectId, databaseUrl) {
  return {
    apiKey: config.apiKey,
    authDomain: config.authDomain || `${projectId}.firebaseapp.com`,
    projectId,
    storageBucket: config.storageBucket || `${projectId}.firebasestorage.app`,
    messagingSenderId: config.messagingSenderId,
    appId: config.appId,
    databaseURL: databaseUrl,
  };
}

async function requestJson(fetchImpl, token, url, options = {}, allowed = []) {
  const response = await fetchImpl(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  if (allowed.includes(response.status)) return { status: response.status, body: null };
  const body = await response.json().catch(async () => ({ message: await response.text().catch(() => '') }));
  if (!response.ok) {
    const message = body?.error?.message || body?.message || `HTTP ${response.status}`;
    const error = new Error(message);
    error.status = response.status;
    throw error;
  }
  return { status: response.status, body };
}

async function waitOperation(fetchImpl, token, baseUrl, operation, {
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  attempts = 120,
} = {}) {
  let current = operation;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (current.done) {
      if (current.error) throw new Error(current.error.message || 'Cloud operation failed.');
      return current.response || current;
    }
    await sleep(Math.min(1000 + attempt * 200, 5000));
    const next = await requestJson(fetchImpl, token, `${baseUrl}/${current.name}`);
    current = next.body;
  }
  throw new Error(`Cloud operation timed out: ${operation.name}`);
}

async function ensureProject(fetchImpl, token, { projectId, tenant, parent }) {
  const url = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;
  try {
    return (await requestJson(fetchImpl, token, url)).body;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  const created = await requestJson(
    fetchImpl,
    token,
    'https://cloudresourcemanager.googleapis.com/v3/projects',
    {
      method: 'POST',
      body: JSON.stringify({
        projectId,
        displayName: `SIAS ${tenant}`,
        ...(parent ? { parent } : {}),
      }),
    },
  );
  await waitOperation(
    fetchImpl,
    token,
    'https://cloudresourcemanager.googleapis.com/v3',
    created.body,
  );
  return (await requestJson(fetchImpl, token, url)).body;
}

async function linkBilling(fetchImpl, token, projectId, billingAccount) {
  await requestJson(
    fetchImpl,
    token,
    `https://cloudbilling.googleapis.com/v1/projects/${projectId}/billingInfo`,
    {
      method: 'PUT',
      body: JSON.stringify({ billingAccountName: billingAccount }),
    },
  );
}

async function enableServices(fetchImpl, token, projectNumber) {
  const operation = await requestJson(
    fetchImpl,
    token,
    `https://serviceusage.googleapis.com/v1/projects/${projectNumber}/services:batchEnable`,
    { method: 'POST', body: JSON.stringify(serviceBatchBody(projectNumber)) },
  );
  await waitOperation(
    fetchImpl,
    token,
    'https://serviceusage.googleapis.com/v1',
    operation.body,
  );
}

async function ensureFirebase(fetchImpl, token, projectId) {
  const url = `https://firebase.googleapis.com/v1beta1/projects/${projectId}`;
  try {
    await requestJson(fetchImpl, token, url);
    return;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  const operation = await requestJson(
    fetchImpl,
    token,
    `${url}:addFirebase`,
    { method: 'POST', body: '{}' },
  );
  await waitOperation(fetchImpl, token, 'https://firebase.googleapis.com/v1beta1', operation.body);
}

async function ensureDatabase(fetchImpl, token, projectId, region) {
  const databaseId = `${projectId}-default-rtdb`;
  const url =
    `https://firebasedatabase.googleapis.com/v1beta/projects/${projectId}` +
    `/locations/${region}/instances?databaseId=${databaseId}`;
  try {
    await requestJson(fetchImpl, token, url, {
      method: 'POST',
      body: JSON.stringify({ type: 'DEFAULT_DATABASE' }),
    }, [409]);
  } catch (error) {
    // Some pre-existing projects return ALREADY_EXISTS as a 400.
    if (!/already exists/i.test(error.message)) throw error;
  }
}

async function enableEmailPassword(fetchImpl, token, projectId) {
  await requestJson(
    fetchImpl,
    token,
    `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId}/config` +
      '?updateMask=signIn.email.enabled,signIn.email.passwordRequired',
    {
      method: 'PATCH',
      body: JSON.stringify({
        signIn: { email: { enabled: true, passwordRequired: true } },
      }),
    },
  );
}

async function ensureWebApp(fetchImpl, token, projectId, tenant) {
  const collection = `https://firebase.googleapis.com/v1beta1/projects/${projectId}/webApps`;
  const listed = await requestJson(fetchImpl, token, collection);
  let app = listed.body?.apps?.[0];
  if (!app) {
    const operation = await requestJson(fetchImpl, token, collection, {
      method: 'POST',
      body: JSON.stringify({ displayName: `SIAS ${tenant} Web` }),
    });
    app = await waitOperation(
      fetchImpl,
      token,
      'https://firebase.googleapis.com/v1beta1',
      operation.body,
    );
  }
  const config = await requestJson(
    fetchImpl,
    token,
    `https://firebase.googleapis.com/v1beta1/${app.name}/config`,
  );
  return config.body;
}

async function ensureRuntimeServiceAccount(fetchImpl, token, projectId) {
  const email = `sias-runtime@${projectId}.iam.gserviceaccount.com`;
  const encodedEmail = encodeURIComponent(email);
  const resource = `https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts/${encodedEmail}`;
  try {
    await requestJson(fetchImpl, token, resource);
  } catch (error) {
    if (error.status !== 404) throw error;
    await requestJson(
      fetchImpl,
      token,
      `https://iam.googleapis.com/v1/projects/${projectId}/serviceAccounts`,
      {
        method: 'POST',
        body: JSON.stringify({
          accountId: 'sias-runtime',
          serviceAccount: { displayName: 'SIAS tenant runtime' },
        }),
      },
    );
  }

  const policyUrl = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;
  const policy = (await requestJson(fetchImpl, token, `${policyUrl}:getIamPolicy`, {
    method: 'POST',
    body: '{}',
  })).body;
  const nextPolicy = addIamBinding(policy, 'roles/firebase.admin', `serviceAccount:${email}`);
  await requestJson(fetchImpl, token, `${policyUrl}:setIamPolicy`, {
    method: 'POST',
    body: JSON.stringify({ policy: nextPolicy }),
  });

  const keysUrl = `${resource}/keys`;
  const oldKeys = (await requestJson(fetchImpl, token, keysUrl)).body?.keys || [];
  const created = (await requestJson(fetchImpl, token, keysUrl, {
    method: 'POST',
    body: JSON.stringify({
      privateKeyType: 'TYPE_GOOGLE_CREDENTIALS_FILE',
      keyAlgorithm: 'KEY_ALG_RSA_2048',
    }),
  })).body;
  if (!created.privateKeyData) throw new Error('Runtime service-account key response was empty.');
  for (const key of oldKeys.filter((item) => item.keyType === 'USER_MANAGED')) {
    await requestJson(fetchImpl, token, `https://iam.googleapis.com/v1/${key.name}`, {
      method: 'DELETE',
    }, [404]);
  }
  return {
    credential: JSON.parse(Buffer.from(created.privateKeyData, 'base64').toString('utf8')),
    keyName: created.name,
  };
}

async function accessTokenFromServiceAccount(serviceAccount) {
  const admin = (await import('firebase-admin')).default;
  const credential = admin.credential.cert(serviceAccount);
  const token = await credential.getAccessToken();
  return token.access_token;
}

async function main() {
  const flags = parseArgs(process.argv.slice(2));
  const errors = validateBootstrapFlags(flags);
  if (errors.length) {
    console.error(`ERROR: ${errors.join('; ')}`);
    process.exitCode = 1;
    return;
  }
  const rawCredential = process.env.FIREBASE_PROVISIONER_SERVICE_ACCOUNT;
  if (!rawCredential) throw new Error('FIREBASE_PROVISIONER_SERVICE_ACCOUNT is not set.');
  const billingAccount = normalizeBillingAccount(process.env.GOOGLE_BILLING_ACCOUNT);
  if (!billingAccount && !flags['skip-billing']) {
    throw new Error('GOOGLE_BILLING_ACCOUNT is required for production tenant provisioning.');
  }

  const serviceAccount = JSON.parse(rawCredential);
  const token = await accessTokenFromServiceAccount(serviceAccount);
  const fetchImpl = fetch;
  const projectId = flags['project-id'];
  const tenant = flags.tenant;
  const region = flags.region || 'europe-west1';
  const outputDir = flags['output-dir'];
  const databaseUrl = databaseUrlForRegion(projectId, region);

  console.log(`Firebase bootstrap: ${projectId}`);
  const project = await ensureProject(fetchImpl, token, {
    projectId,
    tenant,
    parent: process.env.GOOGLE_RESOURCE_PARENT || '',
  });
  if (billingAccount) await linkBilling(fetchImpl, token, projectId, billingAccount);
  await enableServices(fetchImpl, token, project.name.split('/').at(-1));
  await ensureFirebase(fetchImpl, token, projectId);
  await ensureDatabase(fetchImpl, token, projectId, region);
  await enableEmailPassword(fetchImpl, token, projectId);
  const apiConfig = await ensureWebApp(fetchImpl, token, projectId, tenant);
  const runtime = await ensureRuntimeServiceAccount(fetchImpl, token, projectId);

  mkdirSync(outputDir, { recursive: true });
  writeFileSync(
    join(outputDir, 'firebase-web-config.json'),
    `${JSON.stringify(webConfigFromApi(apiConfig, projectId, databaseUrl), null, 2)}\n`,
    { mode: 0o600 },
  );
  writeFileSync(
    join(outputDir, 'runtime-service-account.json'),
    `${JSON.stringify(runtime.credential)}\n`,
    { mode: 0o600 },
  );
  writeFileSync(
    join(outputDir, 'bootstrap-summary.json'),
    `${JSON.stringify({
      projectId,
      projectNumber: project.name.split('/').at(-1),
      databaseUrl,
      region,
      runtimeServiceAccount: runtime.credential.client_email,
      runtimeKeyName: runtime.keyName,
      generatedAt: new Date().toISOString(),
    }, null, 2)}\n`,
    { mode: 0o600 },
  );
  console.log('Firebase bootstrap complete: RTDB, Email/Password Auth, Web app, and tenant runtime identity are ready.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`Firebase bootstrap failed: ${error.message}`);
    process.exitCode = 1;
  });
}
