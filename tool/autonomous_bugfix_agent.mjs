#!/usr/bin/env node

import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const ROOT = findRepoRoot(process.cwd());
const ARTIFACT_DIR = path.join(ROOT, '.dart_tool', 'autofix-agent');

const DEFAULT_AI_WORKER_URL = 'https://alert-notifier.aziz-nagati01.workers.dev';
const DEFAULT_NOTIFY_WORKER_URL = 'https://alertsys.aziz-nagati01.workers.dev';
const DEFAULT_UI_URL = 'https://alertappsys.web.app';
const DEFAULT_DB_URL = 'https://alertappsys-default-rtdb.firebaseio.com';

const TEXT_FILE_EXTENSIONS = new Set([
  '.arb',
  '.cjs',
  '.css',
  '.dart',
  '.gradle',
  '.html',
  '.js',
  '.json',
  '.kt',
  '.lock',
  '.md',
  '.mjs',
  '.plist',
  '.properties',
  '.swift',
  '.toml',
  '.ts',
  '.tsx',
  '.txt',
  '.xml',
  '.yaml',
  '.yml',
]);

const DEFAULT_CONTEXT_FILES = [
  'CLAUDE.md',
  'package.json',
  'pubspec.yaml',
  'analysis_options.yaml',
  'database.rules.json',
  '.github/workflows/ci.yml',
  '.github/workflows/deploy.yml',
  'wrangler.ai.toml',
  'wrangler.notify.toml',
  'lib/config/app_config.dart',
  'lib/main.dart',
  'worker/health.js',
  'worker/auth.js',
  'worker/index.js',
  'worker/auto_fix.js',
  'cloudflare_ai_worker.js',
  'cloudflare_notify_worker.js',
];

const args = new Set(process.argv.slice(2));
const publishMode = process.env.AGENT_PUBLISH_MODE || 'pull_request';

if (args.has('--help') || args.has('-h')) {
  printHelp();
  process.exit(0);
}

const config = {
  dryRun: args.has('--dry-run') || envFlag('AGENT_DRY_RUN'),
  force: args.has('--force') || envFlag('AGENT_FORCE'),
  allowDirty: envFlag('AGENT_ALLOW_DIRTY'),
  publishMode,
  publishBranch: '',
  publishBranchPrefix: process.env.AGENT_BRANCH_PREFIX || 'autofix',
  deployWeb: publishMode === 'direct' && !envFlag('AGENT_SKIP_WEB_DEPLOY'),
  deployWorkers: publishMode === 'direct' && envFlag('AGENT_DEPLOY_WORKERS'),
  maxAttempts: envInt('AGENT_MAX_ATTEMPTS', 3),
  commandTimeoutMs: envInt('AGENT_COMMAND_TIMEOUT_MS', 20 * 60 * 1000),
  fetchTimeoutMs: envInt('AGENT_FETCH_TIMEOUT_MS', 15000),
  maxCommandOutputChars: envInt('AGENT_MAX_COMMAND_OUTPUT_CHARS', 90000),
  maxPromptChars: envInt('AGENT_MAX_PROMPT_CHARS', 180000),
  maxFileChars: envInt('AGENT_MAX_FILE_CHARS', 45000),
  maxLogChars: envInt('AGENT_MAX_LOG_CHARS', 60000),
  workerStaleMinutes: envInt('AGENT_WORKER_STALE_MINUTES', 5),
  claudeFixModel: process.env.CLAUDE_FIX_MODEL || 'claude-opus-4-8',
  openaiReviewModel: process.env.OPENAI_REVIEW_MODEL || 'o3',
  baseBranch: process.env.AGENT_BASE_BRANCH || 'main',
  uiHealthUrls: envFlag('AGENT_DISABLE_UI_HEALTH')
    ? []
    : parseList(process.env.AGENT_UI_HEALTH_URLS ?? process.env.APP_HEALTH_URL ?? DEFAULT_UI_URL),
  aiWorkerUrl: trimSlash(process.env.AGENT_AI_WORKER_URL || process.env.ALERTSYS_AI_WORKER_URL || DEFAULT_AI_WORKER_URL),
  notifyWorkerUrl: trimSlash(
    process.env.AGENT_NOTIFY_WORKER_URL || process.env.ALERTSYS_NOTIFY_WORKER_URL || DEFAULT_NOTIFY_WORKER_URL,
  ),
  databaseUrl: trimSlash(process.env.FIREBASE_DATABASE_URL || process.env.FB_DB_URL || DEFAULT_DB_URL),
  detectionCommands: envCommands('AGENT_DETECTION_COMMANDS', []),
  validationCommands: envCommands('AGENT_VALIDATION_COMMANDS', [
    'npm test',
    'flutter analyze --no-fatal-infos --no-fatal-warnings',
    'flutter test --reporter expanded',
  ]),
};

main().catch(async (error) => {
  const message = error?.stack || error?.message || String(error);
  console.error(`[agent] fatal: ${message}`);
  process.exit(1);
});

async function main() {
  ensureArtifactDir();
  console.log(`[agent] repo: ${ROOT}`);
  console.log(`[agent] mode: ${config.dryRun ? 'dry-run' : 'active'}`);
  console.log(`[agent] publish mode: ${config.publishMode}`);

  const signals = await gatherSignals();
  const signalArtifact = writeArtifact('signals', signals);
  console.log(`[agent] wrote signals artifact: ${relativePath(signalArtifact)}`);

  if (signals.issues.length === 0 && !config.force) {
    console.log('[agent] no actionable bugs detected');
    if (!config.dryRun) await recordAgentRun('clean', { signals });
    return;
  }

  if (config.dryRun) {
    printIssueSummary(signals);
    console.log('[agent] dry-run stops before model calls or file edits');
    return;
  }

  await assertActivePreflight();
  await prepareBranchForAutofix();

  let feedback = '';
  let lastValidation = null;
  let lastReview = null;
  let lastClaude = null;
  let changedPaths = [];

  for (let attempt = 1; attempt <= config.maxAttempts; attempt += 1) {
    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: gathering context`);
    const context = await gatherContext(signals, feedback, lastValidation, lastReview);
    const contextArtifact = writeArtifact(`context-attempt-${attempt}`, context);
    console.log(`[agent] wrote context artifact: ${relativePath(contextArtifact)}`);

    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: requesting Claude fix`);
    lastClaude = await requestClaudeFix(context, attempt);
    writeArtifact(`claude-attempt-${attempt}`, lastClaude);

    changedPaths = applyFixedFiles(lastClaude.fixedFiles || []);
    if (changedPaths.length === 0) {
      feedback = 'Claude returned no applicable fixed files. Return full file contents for at least one repo file.';
      console.warn(`[agent] ${feedback}`);
      continue;
    }

    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: validating ${changedPaths.length} file(s)`);
    lastValidation = await runValidation();
    writeArtifact(`validation-attempt-${attempt}`, lastValidation);

    if (!lastValidation.passed) {
      feedback = buildValidationFeedback(lastValidation);
      console.warn('[agent] validation rejected fix');
      continue;
    }

    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: requesting OpenAI review gate`);
    const diff = await gitText(['diff', '--', ...changedPaths]);
    lastReview = await requestOpenAiReview({
      signals,
      claudeFix: lastClaude,
      validation: lastValidation,
      diff,
      changedPaths,
    });
    writeArtifact(`openai-review-attempt-${attempt}`, lastReview);

    if (!lastReview.approved) {
      feedback = buildReviewFeedback(lastReview);
      console.warn('[agent] OpenAI review rejected fix');
      continue;
    }

    console.log('[agent] fix approved by validation and OpenAI review');
    const published = await publishApprovedFix({
      changedPaths,
      signals,
      claudeFix: lastClaude,
      validation: lastValidation,
      review: lastReview,
    });
    writeArtifact('publish-result', published);
    const commitSha = await safeGitText(['rev-parse', '--short', 'HEAD']);
    await recordAgentRun(published.pullRequestUrl ? 'ai_pr_opened' : 'ai_fixed', {
      signals,
      commit: commitSha,
      summary: published.commitMessage,
      prUrl: published.pullRequestUrl,
      changedPaths: published.changedPaths,
    });
    return;
  }

  const rejectionSummary = [
    `Attempts exhausted: ${config.maxAttempts}`,
    lastValidation ? `Last validation passed: ${lastValidation.passed}` : 'No validation result',
    lastReview ? `Last review approved: ${lastReview.approved}` : 'No review result',
    feedback ? `Feedback: ${feedback}` : '',
  ]
    .filter(Boolean)
    .join('\n\n');

  writeArtifact('rejected-after-retries', {
    summary: rejectionSummary,
    issues: signals.issues,
    validation: lastValidation,
    review: lastReview,
  });

  // Human escalation path: open a GitHub issue carrying the full rejection
  // context, then surface the run in RTDB so the SuperAdmin Logs tab shows
  // the bug as escalated rather than silently failing.
  const issueUrl = await createGitHubEscalationIssue(signals, rejectionSummary);
  await recordAgentRun(issueUrl ? 'escalated' : 'rejected', {
    signals,
    summary: rejectionSummary.slice(0, 800),
    issueUrl,
  });
  throw new Error('automatic fix was rejected after all attempts');
}

/**
 * Records the outcome of an agent run under `bugs/agent/{runId}` so the
 * SuperAdmin Logs tab can display what the AI detected, fixed or escalated.
 * Best-effort: never fails the agent.
 */
async function recordAgentRun(status, { signals, commit, summary, issueUrl, prUrl, changedPaths } = {}) {
  try {
    const db = await getFirebaseDatabase();
    if (!db) {
      console.warn('[agent] no FIREBASE_SERVICE_ACCOUNT; skipping RTDB run record');
      return;
    }
    const record = {
      at: new Date().toISOString(),
      status,
      issues: (signals?.issues || []).slice(0, 10).map((issue) => `${issue.severity}/${issue.source}: ${issue.title}`),
    };
    if (commit) record.commit = commit;
    if (summary) record.summary = String(summary).slice(0, 1000);
    if (issueUrl) record.issueUrl = issueUrl;
    if (prUrl) record.prUrl = prUrl;
    if (changedPaths?.length) record.changedPaths = changedPaths.slice(0, 20);
    await db.ref('bugs/agent').push(record);
    console.log(`[agent] recorded ${status} run to bugs/agent`);
  } catch (error) {
    console.warn(`[agent] failed to record run to RTDB: ${error?.message || error}`);
  }
}

/**
 * Opens a GitHub issue when every automatic fix attempt was rejected.
 * Returns the issue URL or null. Best-effort.
 */
async function createGitHubEscalationIssue(signals, rejectionSummary) {
  const token = githubToken();
  if (!token) {
    console.warn('[agent] no GitHub token; cannot escalate to an issue');
    return null;
  }
  const repo = await resolveGitHubRepository();
  if (!repo) {
    console.warn('[agent] cannot resolve GitHub repository for escalation');
    return null;
  }
  const firstIssue = signals?.issues?.[0]?.title || 'production issue';
  const issueLines = (signals?.issues || [])
    .map((issue) => `- **${issue.severity}** \`${issue.source}\`: ${issue.title}`)
    .join('\n');
  const body = [
    'The autonomous bug-fix agent detected the issue(s) below but every automatic fix attempt was rejected by validation or the review gate. A human needs to take over.',
    '',
    '## Detected issues',
    issueLines || '_none captured_',
    '',
    '## Rejection context',
    '```',
    rejectionSummary.slice(0, 5000),
    '```',
    '',
    `_Run artifacts are stored under \`.dart_tool/autofix-agent\` in the workflow run. Reported at ${new Date().toISOString()}._`,
  ].join('\n');
  try {
    const response = await fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'alertsys-autofix-agent',
      },
      body: JSON.stringify({
        title: `[autofix-escalation] ${firstIssue}`.slice(0, 240),
        body,
        labels: ['autofix-escalation', 'bug'],
      }),
    });
    if (!response.ok) {
      const text = await response.text();
      console.warn(`[agent] GitHub issue creation failed: ${response.status} ${text.slice(0, 300)}`);
      return null;
    }
    const json = await response.json();
    console.log(`[agent] escalated to GitHub issue: ${json.html_url}`);
    return json.html_url || null;
  } catch (error) {
    console.warn(`[agent] GitHub escalation error: ${error?.message || error}`);
    return null;
  }
}

function githubToken() {
  return process.env.AUTOFIX_GITHUB_TOKEN || process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
}

async function resolveGitHubRepository() {
  let repo = process.env.GITHUB_REPOSITORY;
  if (!repo) {
    const remote = await safeGitText(['remote', 'get-url', 'origin']);
    const match = remote.match(/github\.com[:/]([^/]+\/[^/.\s]+)/);
    if (match) repo = match[1];
  }
  return repo || '';
}

async function assertActivePreflight() {
  if (!['pull_request', 'direct'].includes(config.publishMode)) {
    throw new Error("AGENT_PUBLISH_MODE must be 'pull_request' or 'direct'");
  }
  const status = await gitText(['status', '--porcelain']);
  if (status.trim() && !config.allowDirty) {
    throw new Error(
      'worktree is dirty; set AGENT_ALLOW_DIRTY=1 only in an isolated CI branch owned by the agent',
    );
  }
  if (!process.env.ANTHROPIC_API_KEY) {
    throw new Error('ANTHROPIC_API_KEY is required to generate fixes with Claude');
  }
  if (!process.env.OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY is required for the OpenAI review gate');
  }
  if (config.publishMode === 'direct' && !envFlag('AGENT_DIRECT_MAIN_PUSH_ALLOWED')) {
    throw new Error('AGENT_DIRECT_MAIN_PUSH_ALLOWED=1 is required for direct main publishing');
  }
  if (config.deployWeb && !process.env.FIREBASE_TOKEN) {
    throw new Error('FIREBASE_TOKEN is required for direct production web deploy');
  }
}

async function gatherSignals() {
  const signals = {
    generatedAt: new Date().toISOString(),
    repo: {
      root: ROOT,
      head: await safeGitText(['rev-parse', '--short', 'HEAD']),
      branch: await safeGitText(['branch', '--show-current']),
      status: await safeGitText(['status', '--short']),
    },
    issues: [],
    ui: [],
    workers: [],
    logs: [],
    db: null,
    commands: [],
    skipped: [],
  };

  await Promise.all([
    collectUiHealth(signals),
    collectWorkerHealth(signals),
    collectLogSignals(signals),
    collectDetectionCommands(signals),
  ]);

  signals.db = await collectDbState(signals);
  evaluateDbHealth(signals);
  return signals;
}

async function collectUiHealth(signals) {
  if (!config.uiHealthUrls.length) {
    signals.skipped.push('ui health: no AGENT_UI_HEALTH_URLS configured');
    return;
  }

  for (const url of config.uiHealthUrls) {
    const result = await fetchText(url, { timeoutMs: config.fetchTimeoutMs });
    const record = {
      url,
      ok: result.ok,
      status: result.status,
      error: result.error || null,
      bodySample: result.text ? result.text.slice(0, 500) : '',
    };
    signals.ui.push(record);

    if (!result.ok) {
      addIssue(signals, 'critical', 'ui', `UI health check failed: ${url}`, record);
      continue;
    }

    const body = result.text || '';
    if (/flutter initialization failed|failed to load|uncaught|fatal error/i.test(body)) {
      addIssue(signals, 'critical', 'ui', `UI health body contains failure marker: ${url}`, record);
    }
  }
}

async function collectWorkerHealth(signals) {
  const endpoints = [
    { name: 'ai-config', url: `${config.aiWorkerUrl}/config`, method: 'GET' },
    { name: 'ai-security-status', url: `${config.aiWorkerUrl}/security-status`, method: 'GET' },
    { name: 'notify-config', url: `${config.notifyWorkerUrl}/config`, method: 'GET' },
  ];

  const headers = {};
  const workerSecret = process.env.WORKER_SHARED_SECRET || process.env.ALERTSYS_WORKER_SHARED_SECRET;
  if (workerSecret) headers['X-SIA-Worker-Secret'] = workerSecret;

  for (const endpoint of endpoints) {
    const result = await fetchJson(endpoint.url, {
      method: endpoint.method,
      headers,
      timeoutMs: config.fetchTimeoutMs,
    });
    const record = {
      ...endpoint,
      ok: result.ok,
      status: result.status,
      error: result.error || null,
      json: result.json || null,
      textSample: result.text ? result.text.slice(0, 800) : '',
    };
    signals.workers.push(record);
    if (!result.ok) {
      addIssue(signals, 'critical', 'worker', `Cloudflare worker endpoint failed: ${endpoint.name}`, record);
    }
  }
}

async function collectLogSignals(signals) {
  const maxAgeHours = envInt('AGENT_LOG_MAX_AGE_HOURS', 24);
  const logFiles = discoverLogFiles();
  if (!logFiles.length) {
    signals.skipped.push('log monitoring: no log files matched');
    return;
  }

  const cutoff = Date.now() - maxAgeHours * 60 * 60 * 1000;
  const errorPattern = new RegExp(
    process.env.AGENT_LOG_ERROR_PATTERN ||
      String.raw`\b(error|exception|fatal|failed|failure|uncaught|unhandled|panic)\b`,
    'i',
  );

  for (const file of logFiles) {
    const stat = statSync(file);
    if (stat.mtimeMs < cutoff) {
      signals.logs.push({
        path: relativePath(file),
        skipped: `older than ${maxAgeHours}h`,
        mtime: stat.mtime.toISOString(),
      });
      continue;
    }

    const tail = readText(file).slice(-config.maxLogChars);
    const matchingLines = tail
      .split(/\r?\n/)
      .filter((line) => errorPattern.test(line))
      .slice(-40);

    const record = {
      path: relativePath(file),
      mtime: stat.mtime.toISOString(),
      size: stat.size,
      matches: matchingLines,
    };
    signals.logs.push(record);

    if (matchingLines.length > 0) {
      addIssue(signals, 'warning', 'logs', `Recent log errors in ${relativePath(file)}`, record);
    }
  }
}

async function collectDetectionCommands(signals) {
  for (const command of config.detectionCommands) {
    const result = await runShell(command, {
      timeoutMs: config.commandTimeoutMs,
      maxOutputChars: config.maxCommandOutputChars,
    });
    signals.commands.push(result);
    if (result.exitCode !== 0) {
      addIssue(signals, 'critical', 'command', `Detection command failed: ${command}`, {
        command,
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        output: result.output,
      });
    }
  }
}

async function collectDbState(signals) {
  const paths = parseList(
    process.env.AGENT_DB_PATHS ||
      'workers/health,cron_lock,ai_runtime/lastAttemptAt,ai_runtime/lastAssignedAt,ai_predictions/performance/latest',
  );
  const state = {
    available: false,
    databaseUrl: config.databaseUrl,
    paths: {},
    recentAlerts: null,
    recentSecurityLogs: null,
    error: null,
  };

  try {
    const db = await getFirebaseDatabase();
    if (!db) {
      signals.skipped.push('db state: FIREBASE_SERVICE_ACCOUNT is not configured');
      return state;
    }

    state.available = true;
    for (const dbPath of paths) {
      const snapshot = await db.ref(dbPath).get();
      state.paths[dbPath] = sanitizeLargeJson(snapshot.val(), 50000);
    }

    const alertsSnap = await db.ref('alerts').orderByChild('timestamp').limitToLast(envInt('AGENT_RECENT_ALERT_LIMIT', 20)).get();
    state.recentAlerts = sanitizeLargeJson(alertsSnap.val(), 80000);

    const securitySnap = await db.ref('security/logs').limitToLast(envInt('AGENT_SECURITY_LOG_LIMIT', 20)).get();
    state.recentSecurityLogs = sanitizeLargeJson(securitySnap.val(), 50000);
  } catch (error) {
    state.error = error?.message || String(error);
    addIssue(signals, 'warning', 'db', 'Firebase RTDB context collection failed', state);
  }

  return state;
}

function evaluateDbHealth(signals) {
  const db = signals.db;
  if (!db?.available) return;

  const health = db.paths?.['workers/health'];
  if (!health || typeof health !== 'object') {
    addIssue(signals, 'warning', 'worker-cron', 'Worker health node is missing from RTDB', {
      path: 'workers/health',
      value: health,
    });
    return;
  }

  const checks = [
    { name: 'ai cron', node: health.lastRun },
    { name: 'notification cron', node: health.notifyLastRun },
  ];

  for (const check of checks) {
    if (!check.node) {
      addIssue(signals, 'critical', 'worker-cron', `${check.name} health pulse is missing`, check);
      continue;
    }

    const timestamp = check.node.timestamp || check.node.completedAt || check.node.runStart;
    const ageMinutes = timestampAgeMinutes(timestamp);
    if (ageMinutes == null) {
      addIssue(signals, 'warning', 'worker-cron', `${check.name} health timestamp is unreadable`, check);
    } else if (ageMinutes > config.workerStaleMinutes) {
      addIssue(signals, 'critical', 'worker-cron', `${check.name} health pulse is stale`, {
        ...check,
        ageMinutes,
        thresholdMinutes: config.workerStaleMinutes,
      });
    }

    const errors = Array.isArray(check.node.errors) ? check.node.errors.filter(Boolean) : [];
    if (errors.length > 0) {
      addIssue(signals, 'critical', 'worker-cron', `${check.name} reported cron errors`, {
        ...check,
        errors,
      });
    }
  }
}

async function gatherContext(signals, feedback, validation, review) {
  const contextFiles = await collectContextFiles(signals, feedback, validation, review);
  return {
    generatedAt: new Date().toISOString(),
    mission:
      'Autonomously fix this Smart Industrial Alert repo. Preserve product architecture in CLAUDE.md. Make the smallest safe code change.',
    constraints: [
      'Return complete file contents only for files that must change.',
      'Do not include secrets, generated caches, build outputs, node_modules, or binary assets.',
      'Keep Cloudflare split-worker behavior aligned with CLAUDE.md.',
      'Keep Firebase Realtime Database field types compatible with database.rules.json.',
      'Prefer existing project patterns over new frameworks.',
      'If a fix is unsafe or insufficiently evidenced, return an empty fixedFiles array and explain why.',
    ],
    repo: signals.repo,
    detectedIssues: signals.issues,
    healthSignals: {
      ui: signals.ui,
      workers: signals.workers,
      logs: signals.logs,
      db: signals.db,
      commands: signals.commands,
      skipped: signals.skipped,
    },
    priorFeedback: feedback || '',
    lastValidation: validation ? summarizeValidation(validation) : null,
    lastReview: review || null,
    files: budgetContextFiles(contextFiles),
  };
}

async function collectContextFiles(signals, feedback, validation, review) {
  const candidates = new Set(DEFAULT_CONTEXT_FILES);
  const allText = JSON.stringify({ signals, feedback, validation, review });

  for (const file of extractFilePaths(allText)) {
    candidates.add(file);
  }

  if (/worker|cron|cloudflare|wrangler/i.test(allText)) {
    addExistingFiles(candidates, [
      'worker/config.js',
      'worker/load_core.js',
      'worker/alerts.js',
      'worker/fcm.js',
      'worker/shift_commander.js',
      'worker/predictive.js',
      'worker/suggest_assignee.js',
      'cloudflare_worker.js',
    ]);
  }

  if (/flutter|dart|widget|ui|render|screen|provider/i.test(allText)) {
    addExistingFiles(candidates, [
      'lib/providers/alert_provider.dart',
      'lib/services/alert_actions_service.dart',
      'lib/services/alert_stream_service.dart',
      'test/widget_test.dart',
    ]);
  }

  for (const file of [...candidates]) {
    if (file.endsWith('.dart')) {
      for (const imported of discoverDartImports(file)) {
        candidates.add(imported);
      }
    }
  }

  const files = [];
  for (const candidate of candidates) {
    const rel = normalizeRepoPath(candidate);
    if (!rel) continue;
    const abs = path.join(ROOT, rel);
    if (!existsSync(abs) || !statSync(abs).isFile()) continue;
    if (!isTextPath(rel)) continue;
    const content = readText(abs);
    files.push({
      path: rel,
      content,
      size: content.length,
      sha256: sha256(content),
    });
  }

  files.sort((a, b) => {
    const ai = DEFAULT_CONTEXT_FILES.includes(a.path) ? 0 : 1;
    const bi = DEFAULT_CONTEXT_FILES.includes(b.path) ? 0 : 1;
    return ai - bi || a.path.localeCompare(b.path);
  });
  return files;
}

function budgetContextFiles(files) {
  let remaining = config.maxPromptChars;
  const budgeted = [];

  for (const file of files) {
    if (remaining <= 0) break;
    const maxForFile = Math.min(config.maxFileChars, Math.max(2000, remaining));
    const content =
      file.content.length > maxForFile
        ? `${file.content.slice(0, maxForFile)}\n\n/* TRUNCATED: ${file.content.length - maxForFile} chars omitted */`
        : file.content;
    remaining -= content.length;
    budgeted.push({
      path: file.path,
      content,
      truncated: content.length < file.content.length,
      size: file.size,
      sha256: file.sha256,
    });
  }

  return budgeted;
}

async function requestClaudeFix(context, attempt) {
  const schema = {
    type: 'object',
    additionalProperties: false,
    properties: {
      summary: { type: 'string' },
      rootCause: { type: 'string' },
      confidence: { type: 'number' },
      fixedFiles: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          properties: {
            path: { type: 'string' },
            content: { type: 'string' },
          },
          required: ['path', 'content'],
        },
      },
      validationFocus: {
        type: 'array',
        items: { type: 'string' },
      },
      riskNotes: {
        type: 'array',
        items: { type: 'string' },
      },
    },
    required: ['summary', 'rootCause', 'confidence', 'fixedFiles', 'validationFocus', 'riskNotes'],
  };

  const headers = {
    'Content-Type': 'application/json',
    'x-api-key': process.env.ANTHROPIC_API_KEY,
    'anthropic-version': process.env.ANTHROPIC_VERSION || '2023-06-01',
  };
  if (process.env.ANTHROPIC_BETA) headers['anthropic-beta'] = process.env.ANTHROPIC_BETA;

  const response = await fetchJson('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    timeoutMs: envInt('AGENT_MODEL_TIMEOUT_MS', 120000),
    headers,
    body: JSON.stringify({
      model: config.claudeFixModel,
      max_tokens: envInt('CLAUDE_FIX_MAX_TOKENS', 12000),
      system:
        'You are Claude acting as the code-fix generator in a dual-model autonomous deployment gate. ' +
        'Make minimal, production-grade changes. Never fabricate logs or claim validation that has not run. ' +
        'Return the result only by calling the submit_code_fix tool.',
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                attempt,
                maxAttempts: config.maxAttempts,
                outputContract:
                  'Call submit_code_fix. fixedFiles must contain full text contents for each changed file.',
                context,
              }),
            },
          ],
        },
      ],
      tools: [
        {
          name: 'submit_code_fix',
          description: 'Submit the minimal code fix for the detected issue.',
          input_schema: schema,
        },
      ],
      tool_choice: {
        type: 'tool',
        name: 'submit_code_fix',
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Claude request failed (${response.status}): ${response.text || response.error}`);
  }

  const parsed = extractClaudeToolInput(response.json) || parseJsonText(extractClaudeText(response.json));
  if (!parsed || !Array.isArray(parsed.fixedFiles)) {
    throw new Error(`Claude returned invalid fix JSON: ${JSON.stringify(response.json).slice(0, 1000)}`);
  }
  return parsed;
}

function applyFixedFiles(fixedFiles) {
  const changed = [];
  for (const file of fixedFiles) {
    const rel = normalizeRepoPath(file?.path);
    if (!rel || !isAllowedWritePath(rel)) {
      console.warn(`[agent] refusing to write unsafe path: ${file?.path || '<missing>'}`);
      continue;
    }
    if (typeof file.content !== 'string') {
      console.warn(`[agent] refusing to write non-string content for ${rel}`);
      continue;
    }

    const abs = path.join(ROOT, rel);
    mkdirSync(path.dirname(abs), { recursive: true });
    const existing = existsSync(abs) ? readText(abs) : null;
    if (existing === file.content) continue;
    writeFileSync(abs, file.content, 'utf8');
    changed.push(rel);
  }
  return [...new Set(changed)];
}

async function runValidation() {
  const results = [];
  for (const command of config.validationCommands) {
    const result = await runShell(command, {
      timeoutMs: config.commandTimeoutMs,
      maxOutputChars: config.maxCommandOutputChars,
    });
    results.push(result);
    if (result.exitCode !== 0) {
      return {
        passed: false,
        failedCommand: command,
        results,
      };
    }
  }
  return {
    passed: true,
    failedCommand: null,
    results,
  };
}

async function requestOpenAiReview({ signals, claudeFix, validation, diff, changedPaths }) {
  const schema = {
    type: 'object',
    additionalProperties: false,
    properties: {
      approved: { type: 'boolean' },
      severity: { type: 'string', enum: ['none', 'low', 'medium', 'high', 'critical'] },
      summary: { type: 'string' },
      requiredChanges: {
        type: 'array',
        items: { type: 'string' },
      },
      testGaps: {
        type: 'array',
        items: { type: 'string' },
      },
      securityConcerns: {
        type: 'array',
        items: { type: 'string' },
      },
      deploymentRisk: { type: 'string' },
    },
    required: [
      'approved',
      'severity',
      'summary',
      'requiredChanges',
      'testGaps',
      'securityConcerns',
      'deploymentRisk',
    ],
  };

  const reviewPrompt = {
    role:
      'You are the independent OpenAI review gate for an autonomous bug-fix agent. ' +
      'Reject if the diff is unsafe, broad, untested, inconsistent with CLAUDE.md, or likely to break CI/deploy.',
    approvalCriteria: [
      'Tests passed in the supplied validation output.',
      'The change is minimal and directly addresses the detected issue.',
      'No secrets, generated build artifacts, or unrelated user changes are included.',
      'Firebase RTDB field types and Cloudflare split-worker behavior remain compatible.',
      'No deployment step should proceed if any required change remains.',
    ],
    detectedIssues: signals.issues,
    changedPaths,
    claudeFix: {
      summary: claudeFix.summary,
      rootCause: claudeFix.rootCause,
      confidence: claudeFix.confidence,
      validationFocus: claudeFix.validationFocus,
      riskNotes: claudeFix.riskNotes,
    },
    validation: summarizeValidation(validation),
    diff,
  };

  const body = {
    model: config.openaiReviewModel,
    input: [
      {
        role: 'system',
        content: [
          {
            type: 'input_text',
            text:
              'Return JSON only. You are a strict senior code reviewer and release gate. ' +
              'If unsure, reject with concrete requiredChanges.',
          },
        ],
      },
      {
        role: 'user',
        content: [{ type: 'input_text', text: JSON.stringify(reviewPrompt) }],
      },
    ],
    text: {
      format: {
        type: 'json_schema',
        name: 'autonomous_bugfix_review',
        strict: true,
        schema,
      },
    },
    reasoning: {
      effort: process.env.OPENAI_REASONING_EFFORT || 'medium',
    },
    max_output_tokens: envInt('OPENAI_REVIEW_MAX_OUTPUT_TOKENS', 2400),
  };

  let response = await fetchJson('https://api.openai.com/v1/responses', {
    method: 'POST',
    timeoutMs: envInt('AGENT_MODEL_TIMEOUT_MS', 120000),
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok && /reasoning|max_output_tokens/i.test(response.text || '')) {
    const fallbackBody = { ...body };
    delete fallbackBody.reasoning;
    response = await fetchJson('https://api.openai.com/v1/responses', {
      method: 'POST',
      timeoutMs: envInt('AGENT_MODEL_TIMEOUT_MS', 120000),
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fallbackBody),
    });
  }

  if (!response.ok) {
    throw new Error(`OpenAI review failed (${response.status}): ${response.text || response.error}`);
  }

  const text = extractOpenAiText(response.json);
  const parsed = parseJsonText(text);
  if (!parsed || typeof parsed.approved !== 'boolean') {
    throw new Error(`OpenAI review returned invalid JSON: ${text.slice(0, 1000)}`);
  }
  return parsed;
}

async function publishApprovedFix({ changedPaths, signals, claudeFix, validation, review }) {
  const diffNames = (await gitText(['diff', '--name-only'])).trim().split(/\r?\n/).filter(Boolean);
  if (!diffNames.length) {
    throw new Error('approved fix has no working-tree changes to publish');
  }

  await runProcess('git', ['add', '--', ...diffNames]);
  await ensureGitIdentity();
  const title = buildCommitTitle(claudeFix, signals);
  const commitMessage = title.length > 70 ? title.slice(0, 69) : title;
  await runProcess('git', ['commit', '-m', commitMessage]);

  if (config.publishMode === 'direct') {
    await runProcess('git', ['push', 'origin', `HEAD:${config.baseBranch}`]);
    const deploy = await deployProduction();
    return {
      published: true,
      mode: 'direct',
      branch: config.baseBranch,
      commitMessage,
      changedPaths: diffNames,
      validation: summarizeValidation(validation),
      review,
      deploy,
    };
  }

  const branch = config.publishBranch || buildAgentBranchName(signals);
  await runProcess('git', ['push', '--set-upstream', 'origin', `HEAD:${branch}`]);
  const pullRequestUrl = await createAutofixPullRequest({
    branch,
    title: commitMessage,
    changedPaths: diffNames,
    signals,
    validation,
    review,
  });
  return {
    published: true,
    mode: 'pull_request',
    branch,
    pullRequestUrl,
    commitMessage,
    changedPaths: diffNames,
    validation: summarizeValidation(validation),
    review,
    deploy: [],
  };
}

async function prepareBranchForAutofix() {
  await runProcess('git', ['fetch', 'origin', config.baseBranch]);
  if (config.publishMode === 'direct') {
    await runProcess('git', ['checkout', '-B', config.baseBranch, `origin/${config.baseBranch}`]);
    return;
  }
  config.publishBranch = buildAgentBranchName();
  await runProcess('git', ['checkout', '-B', config.publishBranch, `origin/${config.baseBranch}`]);
}

function buildAgentBranchName(signals = null) {
  const slug = (signals?.issues?.[0]?.title || 'approved-fix')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 40) || 'approved-fix';
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, 'z');
  const prefix = config.publishBranchPrefix.replace(/[^A-Za-z0-9._/-]+/g, '-').replace(/^\/+|\/+$/g, '') || 'autofix';
  return `${prefix}/${stamp}-${slug}`;
}

async function createAutofixPullRequest({ branch, title, changedPaths, signals, validation, review }) {
  const token = githubToken();
  if (!token) {
    throw new Error('GITHUB_TOKEN or GH_TOKEN is required to open an autofix pull request');
  }
  const repo = await resolveGitHubRepository();
  if (!repo) {
    throw new Error('GITHUB_REPOSITORY or a GitHub origin remote is required to open an autofix pull request');
  }
  const issueLines = (signals?.issues || [])
    .map((issue) => `- **${issue.severity}** \`${issue.source}\`: ${issue.title}`)
    .join('\n');
  const validationSummary = summarizeValidation(validation);
  const body = [
    'Automated bug-fix proposal generated by the SIA autonomous agent.',
    '',
    'This branch passed local agent validation and the independent OpenAI review gate. It is intentionally opened as a pull request so normal branch protection, CI, and human review decide whether it reaches `main`.',
    '',
    '## Detected issues',
    issueLines || '_none captured_',
    '',
    '## Changed files',
    ...changedPaths.map((file) => `- \`${file}\``),
    '',
    '## Validation',
    ...validationSummary.results.map((item) => `- \`${item.command}\`: exit ${item.exitCode}`),
    '',
    '## Review gate',
    `- Approved: ${review.approved}`,
    `- Risk: ${review.deploymentRisk || 'not provided'}`,
    '',
    '_Do not merge without the repository required checks and a human reviewer approval._',
  ].join('\n');

  const response = await fetch(`https://api.github.com/repos/${repo}/pulls`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'alertsys-autofix-agent',
    },
    body: JSON.stringify({
      title: `[autofix] ${title}`.slice(0, 240),
      head: branch,
      base: config.baseBranch,
      body,
      maintainer_can_modify: true,
      draft: true,
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GitHub pull request creation failed: ${response.status} ${text.slice(0, 500)}`);
  }
  const json = await response.json();
  console.log(`[agent] opened autofix PR: ${json.html_url}`);
  return json.html_url;
}

async function ensureGitIdentity() {
  const name = await safeGitText(['config', 'user.name']);
  const email = await safeGitText(['config', 'user.email']);
  if (!name) await runProcess('git', ['config', 'user.name', 'github-actions[bot]']);
  if (!email) await runProcess('git', ['config', 'user.email', 'github-actions[bot]@users.noreply.github.com']);
}

async function deployProduction() {
  const results = [];

  if (config.deployWeb) {
    const buildCommand = [
      'flutter build web --release --no-wasm-dry-run',
      `--dart-define=ALERTSYS_WORKER_SHARED_SECRET=${shellQuote(process.env.WORKER_SHARED_SECRET || '')}`,
      `--dart-define=ALERTSYS_AI_WORKER_URL=${shellQuote(config.aiWorkerUrl)}`,
      `--dart-define=ALERTSYS_NOTIFY_WORKER_URL=${shellQuote(config.notifyWorkerUrl)}`,
    ].join(' ');
    results.push(await runShell(buildCommand, { timeoutMs: envInt('AGENT_WEB_BUILD_TIMEOUT_MS', 30 * 60 * 1000) }));

    const deployCommand = process.env.AGENT_WEB_DEPLOY_COMMAND || 'npx firebase-tools deploy --only hosting --token "$FIREBASE_TOKEN"';
    results.push(await runShell(deployCommand, { timeoutMs: envInt('AGENT_WEB_DEPLOY_TIMEOUT_MS', 20 * 60 * 1000) }));
  }

  if (config.deployWorkers) {
    if (!process.env.CLOUDFLARE_API_TOKEN || !process.env.CLOUDFLARE_ACCOUNT_ID) {
      throw new Error('CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are required when AGENT_DEPLOY_WORKERS=1');
    }
    const workerDeployCommand = process.env.AGENT_WORKER_DEPLOY_COMMAND || 'npm run deploy:workers';
    results.push(await runShell(workerDeployCommand, { timeoutMs: envInt('AGENT_WORKER_DEPLOY_TIMEOUT_MS', 20 * 60 * 1000) }));
  }

  const failed = results.find((result) => result.exitCode !== 0);
  if (failed) {
    throw new Error(`production deploy failed: ${failed.command}\n${failed.output.slice(-4000)}`);
  }
  return results.map((result) => ({
    command: result.command,
    exitCode: result.exitCode,
    outputTail: result.output.slice(-4000),
  }));
}

async function getFirebaseDatabase() {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT || readOptionalFile(process.env.GOOGLE_APPLICATION_CREDENTIALS);
  if (!serviceAccountJson) return null;
  const serviceAccount = JSON.parse(serviceAccountJson);
  const adminModule = await import('firebase-admin');
  const admin = adminModule.default || adminModule;
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: config.databaseUrl,
    });
  }
  return admin.database();
}

function extractClaudeToolInput(json) {
  for (const part of json?.content || []) {
    if (part?.type === 'tool_use' && part?.name === 'submit_code_fix' && part?.input) {
      return part.input;
    }
  }
  return null;
}

function extractClaudeText(json) {
  return (json?.content || [])
    .filter((part) => part?.type === 'text' && typeof part?.text === 'string')
    .map((part) => part.text)
    .join('')
    .trim();
}

function extractOpenAiText(json) {
  if (typeof json?.output_text === 'string') return json.output_text.trim();
  const parts = [];
  for (const item of json?.output || []) {
    for (const content of item?.content || []) {
      if (typeof content?.text === 'string') parts.push(content.text);
      if (typeof content?.output_text === 'string') parts.push(content.output_text);
    }
  }
  return parts.join('').trim();
}

function parseJsonText(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    const start = text.indexOf('{');
    const end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(text.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

async function fetchJson(url, options = {}) {
  const result = await fetchText(url, options);
  if (!result.text) return { ...result, json: null };
  try {
    return { ...result, json: JSON.parse(result.text) };
  } catch (_) {
    return { ...result, json: null };
  }
}

async function fetchText(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs || config.fetchTimeoutMs);
  try {
    const response = await fetch(url, {
      method: options.method || 'GET',
      headers: options.headers || {},
      body: options.body,
      signal: controller.signal,
    });
    const text = await response.text();
    return {
      ok: response.ok,
      status: response.status,
      text,
      headers: Object.fromEntries(response.headers.entries()),
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      text: '',
      error: error?.message || String(error),
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function runShell(command, options = {}) {
  return runSpawn(command, [], {
    ...options,
    shell: true,
    display: command,
    allowFailure: true,
  });
}

async function runProcess(command, args = [], options = {}) {
  return runSpawn(command, args, {
    ...options,
    shell: false,
    display: [command, ...args].join(' '),
  });
}

async function runSpawn(command, args, options) {
  const maxOutputChars = options.maxOutputChars || config.maxCommandOutputChars;
  const timeoutMs = options.timeoutMs || config.commandTimeoutMs;
  console.log(`[agent] $ ${options.display}`);

  return new Promise((resolve, reject) => {
    let output = '';
    let timedOut = false;
    const child = spawn(command, args, {
      cwd: ROOT,
      env: process.env,
      shell: options.shell,
      windowsHide: true,
    });

    const append = (chunk) => {
      output += chunk.toString('utf8');
      if (output.length > maxOutputChars) output = output.slice(-maxOutputChars);
    };

    child.stdout?.on('data', append);
    child.stderr?.on('data', append);

    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      setTimeout(() => child.kill('SIGKILL'), 5000).unref();
    }, timeoutMs);

    child.on('error', (error) => {
      clearTimeout(timeout);
      const result = {
        command: options.display,
        exitCode: 127,
        timedOut,
        output: `${output}\n${error.message}`,
      };
      if (options.allowFailure) resolve(result);
      else reject(error);
    });

    child.on('close', (code) => {
      clearTimeout(timeout);
      const result = {
        command: options.display,
        exitCode: code ?? (timedOut ? 124 : 1),
        timedOut,
        output,
      };
      if (!options.allowFailure && result.exitCode !== 0) {
        reject(new Error(`${options.display} failed with exit ${result.exitCode}\n${output.slice(-4000)}`));
      } else {
        resolve(result);
      }
    });
  });
}

async function gitText(args) {
  const result = await runProcess('git', args, { maxOutputChars: 500000 });
  return result.output;
}

async function safeGitText(args) {
  const result = await runProcess('git', args, { allowFailure: true, maxOutputChars: 10000 });
  return result.exitCode === 0 ? result.output.trim() : '';
}

function discoverLogFiles() {
  const configured = parseList(process.env.AGENT_LOG_FILES);
  if (configured.length) {
    return configured
      .map((file) => path.join(ROOT, normalizeSlashes(file)))
      .filter((file) => existsSync(file) && statSync(file).isFile());
  }

  return readdirSync(ROOT)
    .filter((name) => /^\.codex-.*\.log$/.test(name) || /^flutter_\d+\.log$/.test(name) || name === 'firebase-debug.log')
    .map((name) => path.join(ROOT, name));
}

function extractFilePaths(text) {
  const paths = new Set();
  const regex = /(?:^|[\s('"`])([A-Za-z0-9_./\\:-]+?\.(?:arb|cjs|dart|html|js|json|kt|mjs|toml|ts|tsx|xml|ya?ml|md))(?:[:)\s'"`,]|$)/g;
  let match;
  while ((match = regex.exec(text || ''))) {
    const normalized = normalizeRepoPath(match[1].replace(/:\d+(:\d+)?$/, ''));
    if (normalized) paths.add(normalized);
  }
  return [...paths];
}

function discoverDartImports(relPath) {
  const rel = normalizeRepoPath(relPath);
  if (!rel) return [];
  const abs = path.join(ROOT, rel);
  if (!existsSync(abs)) return [];
  const imports = [];
  const content = readText(abs);
  const regex = /^\s*import\s+['"]([^'"]+)['"]/gm;
  let match;
  while ((match = regex.exec(content))) {
    const spec = match[1];
    if (spec.startsWith('package:alertsysapp/')) {
      imports.push(`lib/${spec.slice('package:alertsysapp/'.length)}`);
    } else if (spec.startsWith('.') || !spec.includes(':')) {
      imports.push(relativePath(path.resolve(path.dirname(abs), spec)));
    }
  }
  return imports.filter(Boolean);
}

function addExistingFiles(set, files) {
  for (const file of files) {
    if (existsSync(path.join(ROOT, file))) set.add(file);
  }
}

function normalizeRepoPath(input) {
  if (!input || typeof input !== 'string') return null;
  let value = input.replace(/^file:\/\//, '').replace(/\\/g, '/').trim();
  value = value.replace(/^\.\//, '');
  if (/^[A-Za-z]:\//.test(value)) {
    value = relativePath(value);
  }
  value = path.posix.normalize(value);
  if (value === '.' || value.startsWith('../') || path.isAbsolute(value)) return null;
  if (value.startsWith('.git/') || value === '.git') return null;
  return value;
}

function isAllowedWritePath(rel) {
  if (!isTextPath(rel)) return false;
  const blocked = ['.git/', '.dart_tool/', 'build/', 'node_modules/', '.wrangler/', 'android_backup/', 'android_old/'];
  return !blocked.some((prefix) => rel === prefix.slice(0, -1) || rel.startsWith(prefix));
}

function isTextPath(rel) {
  const ext = path.extname(rel).toLowerCase();
  return TEXT_FILE_EXTENSIONS.has(ext) || rel.endsWith('gradle.properties') || rel.endsWith('Dockerfile');
}

function readText(file) {
  return readFileSync(file, 'utf8').replace(/\u0000/g, '');
}

function readOptionalFile(file) {
  if (!file) return '';
  try {
    return existsSync(file) ? readText(file) : '';
  } catch (_) {
    return '';
  }
}

function writeArtifact(name, value) {
  ensureArtifactDir();
  const safeName = name.replace(/[^A-Za-z0-9_.-]/g, '-');
  const file = path.join(ARTIFACT_DIR, `${new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14)}-${safeName}.json`);
  writeFileSync(file, JSON.stringify(value, null, 2), 'utf8');
  return file;
}

function buildCommitTitle(claudeFix, signals) {
  const firstIssue = signals.issues[0]?.title || 'detected production issue';
  const summary = claudeFix.summary || firstIssue;
  return `AI bug fix: ${summary.replace(/\s+/g, ' ').slice(0, 90)}`;
}

function buildValidationFeedback(validation) {
  const failed = validation.results.find((result) => result.exitCode !== 0) || validation.results.at(-1);
  return [
    'Validation failed.',
    `Command: ${failed?.command}`,
    `Exit code: ${failed?.exitCode}`,
    failed?.timedOut ? 'The command timed out.' : '',
    'Output tail:',
    failed?.output?.slice(-25000) || '',
  ]
    .filter(Boolean)
    .join('\n');
}

function buildReviewFeedback(review) {
  return [
    'OpenAI review rejected the fix.',
    `Severity: ${review.severity}`,
    `Summary: ${review.summary}`,
    'Required changes:',
    ...(review.requiredChanges || []).map((item) => `- ${item}`),
    'Test gaps:',
    ...(review.testGaps || []).map((item) => `- ${item}`),
    'Security concerns:',
    ...(review.securityConcerns || []).map((item) => `- ${item}`),
    `Deployment risk: ${review.deploymentRisk}`,
  ].join('\n');
}

function summarizeValidation(validation) {
  return {
    passed: validation.passed,
    failedCommand: validation.failedCommand,
    results: validation.results.map((result) => ({
      command: result.command,
      exitCode: result.exitCode,
      timedOut: result.timedOut,
      outputTail: result.output.slice(-12000),
    })),
  };
}

function addIssue(signals, severity, source, title, details) {
  signals.issues.push({
    severity,
    source,
    title,
    details: sanitizeLargeJson(details, 30000),
    at: new Date().toISOString(),
  });
}

function sanitizeLargeJson(value, maxChars) {
  const text = JSON.stringify(value);
  if (!text || text.length <= maxChars) return value;
  return {
    truncated: true,
    originalChars: text.length,
    sample: text.slice(0, maxChars),
  };
}

function timestampAgeMinutes(value) {
  if (!value) return null;
  const time = Date.parse(value);
  if (!Number.isFinite(time)) return null;
  return Math.round((Date.now() - time) / 60000);
}

function sha256(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function envFlag(name) {
  return /^(1|true|yes|on)$/i.test(process.env[name] || '');
}

function envInt(name, fallback) {
  const value = Number.parseInt(process.env[name] || '', 10);
  return Number.isFinite(value) ? value : fallback;
}

function envCommands(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  return raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !line.startsWith('#'));
}

function parseList(raw) {
  if (!raw) return [];
  return String(raw)
    .split(/[\n,]/)
    .map((value) => value.trim())
    .filter(Boolean);
}

function trimSlash(value) {
  return String(value || '').replace(/\/+$/, '');
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\"'\"'")}'`;
}

function normalizeSlashes(value) {
  return String(value || '').replace(/\\/g, '/');
}

function ensureArtifactDir() {
  mkdirSync(ARTIFACT_DIR, { recursive: true });
}

function relativePath(file) {
  return normalizeSlashes(path.relative(ROOT, path.resolve(file)));
}

function findRepoRoot(start) {
  let current = path.resolve(start);
  while (current !== path.dirname(current)) {
    if (existsSync(path.join(current, '.git'))) return current;
    current = path.dirname(current);
  }
  return path.resolve(start);
}

function printIssueSummary(signals) {
  if (!signals.issues.length) {
    console.log('[agent] no issues');
    return;
  }
  console.log('[agent] detected issues:');
  for (const issue of signals.issues) {
    console.log(`- ${issue.severity} ${issue.source}: ${issue.title}`);
  }
}

function printHelp() {
  console.log(`
Autonomous bug-fix and deployment agent

Usage:
  node tool/autonomous_bugfix_agent.mjs [--dry-run] [--force]

Required for active fixes:
  ANTHROPIC_API_KEY              Generates candidate code fixes with Claude.
  OPENAI_API_KEY                 Runs the independent OpenAI review gate.
  GITHUB_TOKEN or GH_TOKEN       Opens the reviewed autofix pull request.

Common configuration:
  AGENT_PUBLISH_MODE             pull_request (default) or direct.
  AGENT_DIRECT_MAIN_PUSH_ALLOWED=1
                                 Required in addition to AGENT_PUBLISH_MODE=direct.
  AGENT_BRANCH_PREFIX            Branch prefix for autofix PRs. Defaults to autofix.
  AGENT_UI_HEALTH_URLS           Comma or newline separated deployed UI URLs.
  AGENT_DETECTION_COMMANDS       Newline separated commands for bug detection.
  AGENT_VALIDATION_COMMANDS      Newline separated commands for final validation.
  CLAUDE_FIX_MODEL               Claude fix model. Defaults to claude-opus-4-8.
  FIREBASE_TOKEN                 Required only for direct web deploy mode.
  AGENT_SKIP_WEB_DEPLOY=1        Direct mode only: skip Firebase Hosting deploy.
  AGENT_DEPLOY_WORKERS=1         Direct mode only: also deploy Cloudflare workers.
  FIREBASE_SERVICE_ACCOUNT       Firebase service account JSON for RTDB context.
  FIREBASE_DATABASE_URL          RTDB URL. Defaults to alertappsys.
  WORKER_SHARED_SECRET           Optional Cloudflare worker health auth header.
`);
}
