#!/usr/bin/env node
// Guardian preflight: report which credentials are present and what each unlocks.
// NEVER prints secret values — only present/absent. Pure checkSecrets() is testable;
// the CLI prints a readable table for the GitHub Actions log and the console.

/** @returns {{capabilities:object[], canRunLive:boolean, canDeployWeb:boolean, canDeployWorkers:boolean}} */
export function checkSecrets(env = {}) {
  const has = (k) => typeof env[k] === 'string' && env[k].trim().length > 0;
  const anyAiKey =
    has('GUARDIAN_FIX_API_KEY') || has('GUARDIAN_REVIEW_API_KEY') ||
    has('ANTHROPIC_API_KEY') || has('OPENAI_API_KEY') ||
    has('DEEPSEEK_API_KEY') || has('QWEN_API_KEY') || has('GROQ_API_KEY') ||
    has('MISTRAL_API_KEY') || has('XAI_API_KEY') || has('GEMINI_API_KEY');

  const capabilities = [
    {
      name: 'Joint Fix+Review AI',
      present: anyAiKey,
      requires: 'at least one AI provider key (GUARDIAN_FIX_API_KEY / GUARDIAN_REVIEW_API_KEY, or ANTHROPIC_API_KEY / OPENAI_API_KEY / …)',
      unlocks: 'real two-AI repair (otherwise the drill runs dry / no patch is generated)',
    },
    {
      name: 'Commit & push fixes',
      present: has('AUTOFIX_GITHUB_TOKEN') || has('GITHUB_TOKEN'),
      requires: 'AUTOFIX_GITHUB_TOKEN (or the default GITHUB_TOKEN inside Actions)',
      unlocks: 'committing the injected fault and the AI fix; opening PRs',
    },
    {
      name: 'Deploy web (Firebase Hosting)',
      present: has('FIREBASE_TOKEN'),
      requires: 'FIREBASE_TOKEN',
      unlocks: 'auto-deploy of the healed web build in automatic mode',
    },
    {
      name: 'Deploy / redeploy workers',
      present: has('CLOUDFLARE_API_TOKEN') && has('CLOUDFLARE_ACCOUNT_ID'),
      requires: 'CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID',
      unlocks: 'the broken-drill-worker scenario and worker redeploys',
    },
    {
      name: 'Android app build',
      present: has('ANDROID_KEYSTORE_BASE64') && has('ANDROID_KEY_PROPERTIES'),
      requires: 'ANDROID_KEYSTORE_BASE64 + ANDROID_KEY_PROPERTIES (signed release) — optional',
      unlocks: 'signed Android artifact on automatic-mode heals (unsigned debug build works without these)',
    },
    {
      name: 'Console → workflow trigger',
      present: has('WORKER_SHARED_SECRET'),
      requires: 'WORKER_SHARED_SECRET (shared with the GitHub proxy worker)',
      unlocks: 'Guardian dispatch flows in the SuperAdmin console',
    },
  ];

  return {
    capabilities,
    canRunLive: anyAiKey && (has('AUTOFIX_GITHUB_TOKEN') || has('GITHUB_TOKEN')),
    canDeployWeb: has('FIREBASE_TOKEN'),
    canDeployWorkers: has('CLOUDFLARE_API_TOKEN') && has('CLOUDFLARE_ACCOUNT_ID'),
  };
}

function mainCli() {
  const r = checkSecrets(process.env);
  const mark = (b) => (b ? 'PRESENT' : 'missing');
  console.log('Guardian preflight — credential status (values never shown)\n');
  const pad = Math.max(...r.capabilities.map((c) => c.name.length));
  for (const c of r.capabilities) {
    console.log(`  [${c.present ? 'x' : ' '}] ${c.name.padEnd(pad)}  ${mark(c.present)}`);
    if (!c.present) console.log(`        needs: ${c.requires}`);
  }
  console.log('');
  console.log(`  live joint-fix possible : ${r.canRunLive ? 'YES' : 'NO (add an AI key + a GitHub token)'}`);
  console.log(`  auto web deploy possible: ${r.canDeployWeb ? 'YES' : 'NO (add FIREBASE_TOKEN)'}`);
  console.log(`  worker (re)deploy       : ${r.canDeployWorkers ? 'YES' : 'NO (add CLOUDFLARE_API_TOKEN + ACCOUNT_ID)'}`);

  const strict = process.argv.includes('--strict');
  if (strict && !r.canRunLive) {
    console.error('\npreflight --strict: cannot run the joint fix live with current secrets.');
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) mainCli();
