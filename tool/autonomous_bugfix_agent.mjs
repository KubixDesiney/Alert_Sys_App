#!/usr/bin/env node

import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import tls from 'node:tls';

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

if (args.has('--help') || args.has('-h')) {
  printHelp();
  process.exit(0);
}

const config = {
  dryRun: args.has('--dry-run') || envFlag('AGENT_DRY_RUN'),
  force: args.has('--force') || envFlag('AGENT_FORCE'),
  noPr: args.has('--no-pr') || envFlag('AGENT_DISABLE_PR'),
  automerge: envFlag('AGENT_AUTOMERGE'),
  triggerDeploy: envFlag('AGENT_TRIGGER_DEPLOY'),
  allowDirty: envFlag('AGENT_ALLOW_DIRTY'),
  maxAttempts: envInt('AGENT_MAX_ATTEMPTS', 3),
  commandTimeoutMs: envInt('AGENT_COMMAND_TIMEOUT_MS', 20 * 60 * 1000),
  fetchTimeoutMs: envInt('AGENT_FETCH_TIMEOUT_MS', 15000),
  maxCommandOutputChars: envInt('AGENT_MAX_COMMAND_OUTPUT_CHARS', 90000),
  maxPromptChars: envInt('AGENT_MAX_PROMPT_CHARS', 180000),
  maxFileChars: envInt('AGENT_MAX_FILE_CHARS', 45000),
  maxLogChars: envInt('AGENT_MAX_LOG_CHARS', 60000),
  workerStaleMinutes: envInt('AGENT_WORKER_STALE_MINUTES', 5),
  geminiModel: process.env.GEMINI_FIX_MODEL || 'gemini-2.5-pro',
  openaiReviewModel: process.env.OPENAI_REVIEW_MODEL || 'o3',
  baseBranch: process.env.AGENT_BASE_BRANCH || 'main',
  branchPrefix: process.env.AGENT_BRANCH_PREFIX || 'agent/autofix',
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
  await alertHuman('Autonomous bug-fix agent failed before completion', message, { fatal: true }).catch(() => {});
  process.exit(1);
});

async function main() {
  ensureArtifactDir();
  console.log(`[agent] repo: ${ROOT}`);
  console.log(`[agent] mode: ${config.dryRun ? 'dry-run' : 'active'}`);

  const signals = await gatherSignals();
  const signalArtifact = writeArtifact('signals', signals);
  console.log(`[agent] wrote signals artifact: ${relativePath(signalArtifact)}`);

  if (signals.issues.length === 0 && !config.force) {
    console.log('[agent] no actionable bugs detected');
    return;
  }

  if (config.dryRun) {
    printIssueSummary(signals);
    console.log('[agent] dry-run stops before model calls or file edits');
    return;
  }

  await assertActivePreflight();
  const branchName = config.noPr ? null : await createAgentBranch();

  let feedback = '';
  let lastValidation = null;
  let lastReview = null;
  let lastGemini = null;
  let changedPaths = [];

  for (let attempt = 1; attempt <= config.maxAttempts; attempt += 1) {
    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: gathering context`);
    const context = await gatherContext(signals, feedback, lastValidation, lastReview);
    const contextArtifact = writeArtifact(`context-attempt-${attempt}`, context);
    console.log(`[agent] wrote context artifact: ${relativePath(contextArtifact)}`);

    console.log(`[agent] attempt ${attempt}/${config.maxAttempts}: requesting Gemini fix`);
    lastGemini = await requestGeminiFix(context, attempt);
    writeArtifact(`gemini-attempt-${attempt}`, lastGemini);

    changedPaths = applyFixedFiles(lastGemini.fixedFiles || []);
    if (changedPaths.length === 0) {
      feedback = 'Gemini returned no applicable fixed files. Return full file contents for at least one repo file.';
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
      geminiFix: lastGemini,
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
      branchName,
      changedPaths,
      signals,
      geminiFix: lastGemini,
      validation: lastValidation,
      review: lastReview,
    });
    writeArtifact('publish-result', published);
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

  await alertHuman('Autonomous bug-fix agent needs human intervention', rejectionSummary, {
    issues: signals.issues,
    validation: lastValidation,
    review: lastReview,
  });
  throw new Error('automatic fix was rejected after all attempts');
}

async function assertActivePreflight() {
  const status = await gitText(['status', '--porcelain']);
  if (status.trim() && !config.allowDirty) {
    throw new Error(
      'worktree is dirty; set AGENT_ALLOW_DIRTY=1 only in an isolated CI branch owned by the agent',
    );
  }
  if (!process.env.GEMINI_API_KEY) {
    throw new Error('GEMINI_API_KEY is required to generate fixes');
  }
  if (!process.env.OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY is required for the OpenAI review gate');
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

async function requestGeminiFix(context, attempt) {
  const schema = {
    type: 'object',
    properties: {
      summary: { type: 'string' },
      rootCause: { type: 'string' },
      confidence: { type: 'number' },
      fixedFiles: {
        type: 'array',
        items: {
          type: 'object',
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

  const response = await fetchJson(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.geminiModel)}:generateContent`,
    {
      method: 'POST',
      timeoutMs: envInt('AGENT_MODEL_TIMEOUT_MS', 120000),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': process.env.GEMINI_API_KEY,
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [
            {
              text:
                'You are the code-fix generator in a dual-model autonomous deployment gate. ' +
                'Produce valid JSON only. Make minimal, production-grade changes. ' +
                'Never fabricate logs or claim validation that has not run.',
            },
          ],
        },
        contents: [
          {
            role: 'user',
            parts: [
              {
                text: JSON.stringify({
                  attempt,
                  maxAttempts: config.maxAttempts,
                  outputContract:
                    'Return JSON matching the schema. fixedFiles must contain full text contents for each changed file.',
                  context,
                }),
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.15,
          responseMimeType: 'application/json',
          responseJsonSchema: schema,
        },
      }),
    },
  );

  if (!response.ok) {
    throw new Error(`Gemini request failed (${response.status}): ${response.text || response.error}`);
  }

  const text = extractGeminiText(response.json);
  const parsed = parseJsonText(text);
  if (!parsed || !Array.isArray(parsed.fixedFiles)) {
    throw new Error(`Gemini returned invalid fix JSON: ${text.slice(0, 1000)}`);
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

async function requestOpenAiReview({ signals, geminiFix, validation, diff, changedPaths }) {
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
    geminiFix: {
      summary: geminiFix.summary,
      rootCause: geminiFix.rootCause,
      confidence: geminiFix.confidence,
      validationFocus: geminiFix.validationFocus,
      riskNotes: geminiFix.riskNotes,
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

async function publishApprovedFix({ branchName, changedPaths, signals, geminiFix, validation, review }) {
  const diffNames = (await gitText(['diff', '--name-only'])).trim().split(/\r?\n/).filter(Boolean);
  if (!diffNames.length) {
    throw new Error('approved fix has no working-tree changes to publish');
  }

  if (config.noPr) {
    console.log('[agent] PR publishing disabled; leaving approved changes in working tree');
    return { published: false, reason: 'AGENT_DISABLE_PR' };
  }

  await runProcess('git', ['add', '--', ...diffNames]);
  const title = buildPrTitle(geminiFix, signals);
  const commitMessage = title.length > 70 ? title.slice(0, 69) : title;
  await runProcess('git', ['commit', '-m', commitMessage]);
  await runProcess('git', ['push', '-u', 'origin', branchName]);

  const bodyPath = writePrBody({ signals, geminiFix, validation, review, changedPaths: diffNames });
  const prCreate = await runProcess('gh', [
    'pr',
    'create',
    '--base',
    config.baseBranch,
    '--head',
    branchName,
    '--title',
    title,
    '--body-file',
    bodyPath,
  ]);

  const prUrl = (prCreate.output || '').trim().split(/\r?\n/).at(-1) || '';
  console.log(`[agent] opened PR: ${prUrl || '(gh did not print URL)'}`);

  const checks = await waitForPullRequestChecks(prUrl);
  let merge = null;
  if (config.automerge) {
    merge = await mergePullRequest(prUrl);
  } else {
    console.log('[agent] AGENT_AUTOMERGE is not enabled; PR remains open after passing local gate');
  }

  let deploy = null;
  if (config.triggerDeploy) {
    deploy = await triggerDeployWorkflow();
  }

  return {
    published: true,
    prUrl,
    checks,
    merge,
    deploy,
  };
}

async function createAgentBranch() {
  const timestamp = new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14);
  const short = (await safeGitText(['rev-parse', '--short', 'HEAD'])).trim() || crypto.randomUUID().slice(0, 8);
  const branchName = `${config.branchPrefix}-${timestamp}-${short}`;
  await runProcess('git', ['checkout', '-b', branchName]);
  console.log(`[agent] created branch: ${branchName}`);
  return branchName;
}

async function waitForPullRequestChecks(prUrl) {
  const selector = prUrl || '--json-url-not-available';
  const command = ['pr', 'checks', selector, '--watch', '--required', '--interval', '15'];
  const result = await runProcess('gh', command, {
    timeoutMs: envInt('AGENT_CI_TIMEOUT_MS', 45 * 60 * 1000),
    allowFailure: true,
  });
  if (result.exitCode !== 0) {
    await alertHuman('Autonomous bug-fix PR failed CI', result.output, { prUrl });
    throw new Error(`PR checks failed or timed out: ${result.output.slice(-2000)}`);
  }
  return result.output;
}

async function mergePullRequest(prUrl) {
  const selector = prUrl || '';
  const strategy = process.env.AGENT_MERGE_STRATEGY || '--squash';
  const args = ['pr', 'merge', selector, strategy, '--auto', '--delete-branch'].filter(Boolean);
  const result = await runProcess('gh', args, { allowFailure: true });
  if (result.exitCode !== 0) {
    await alertHuman('Autonomous bug-fix PR could not be auto-merged', result.output, { prUrl });
    throw new Error(`auto-merge failed: ${result.output.slice(-2000)}`);
  }
  return result.output;
}

async function triggerDeployWorkflow() {
  const workflow = process.env.AGENT_DEPLOY_WORKFLOW || 'deploy.yml';
  const result = await runProcess('gh', ['workflow', 'run', workflow, '--ref', config.baseBranch], {
    allowFailure: true,
  });
  if (result.exitCode !== 0) {
    await alertHuman('Autonomous bug-fix deploy workflow trigger failed', result.output, { workflow });
  }
  return result.output;
}

async function alertHuman(title, body, details = {}) {
  const payload = {
    title,
    body,
    details: sanitizeLargeJson(details, 30000),
    repo: ROOT,
    runUrl: process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : null,
    at: new Date().toISOString(),
  };

  const tasks = [];
  if (process.env.SLACK_WEBHOOK_URL) tasks.push(sendSlack(payload));
  if (process.env.RESEND_API_KEY) tasks.push(sendResendEmail(payload));
  else if (process.env.SMTP_HOST) tasks.push(sendSmtpEmail(payload));

  if (!tasks.length) {
    console.warn(`[agent] human alert not sent; configure SLACK_WEBHOOK_URL, RESEND_API_KEY, or SMTP_HOST`);
    return;
  }

  await Promise.allSettled(tasks);
}

async function sendSlack(payload) {
  const text = [
    `*${payload.title}*`,
    payload.runUrl ? payload.runUrl : null,
    '',
    payload.body,
  ]
    .filter(Boolean)
    .join('\n');
  await fetchText(process.env.SLACK_WEBHOOK_URL, {
    method: 'POST',
    timeoutMs: 15000,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
}

async function sendResendEmail(payload) {
  const to = parseList(process.env.ALERT_EMAIL_TO);
  const from = process.env.ALERT_EMAIL_FROM;
  if (!to.length || !from) return;
  const res = await fetchJson('https://api.resend.com/emails', {
    method: 'POST',
    timeoutMs: 15000,
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to,
      subject: payload.title,
      text: renderAlertText(payload),
    }),
  });
  if (!res.ok) console.warn(`[agent] Resend alert failed: ${res.status} ${res.text}`);
}

async function sendSmtpEmail(payload) {
  const to = parseList(process.env.ALERT_EMAIL_TO);
  const from = process.env.ALERT_EMAIL_FROM || process.env.SMTP_USER;
  if (!to.length || !from) return;

  await smtpSend({
    host: process.env.SMTP_HOST,
    port: envInt('SMTP_PORT', process.env.SMTP_SECURE === '1' ? 465 : 587),
    secure: process.env.SMTP_SECURE === '1',
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
    from,
    to,
    subject: payload.title,
    body: renderAlertText(payload),
  });
}

function renderAlertText(payload) {
  return [
    payload.title,
    payload.at,
    payload.runUrl ? `Run: ${payload.runUrl}` : null,
    '',
    payload.body,
    '',
    JSON.stringify(payload.details, null, 2),
  ]
    .filter(Boolean)
    .join('\n');
}

async function smtpSend({ host, port, secure, user, pass, from, to, subject, body }) {
  const socket = secure
    ? tls.connect({ host, port, servername: host })
    : net.connect({ host, port });
  const reader = createSmtpReader(socket);
  await onceConnect(socket);
  await reader.read();
  await smtpLine(socket, reader, `EHLO ${process.env.SMTP_HELO || 'autofix-agent.local'}`);
  if (!secure && process.env.SMTP_STARTTLS !== '0') {
    await smtpLine(socket, reader, 'STARTTLS');
    const secureSocket = tls.connect({ socket, servername: host });
    const secureReader = createSmtpReader(secureSocket);
    await onceConnect(secureSocket);
    await smtpLine(secureSocket, secureReader, `EHLO ${process.env.SMTP_HELO || 'autofix-agent.local'}`);
    return smtpSendOnSocket(secureSocket, secureReader, { user, pass, from, to, subject, body });
  }
  return smtpSendOnSocket(socket, reader, { user, pass, from, to, subject, body });
}

async function smtpSendOnSocket(socket, reader, { user, pass, from, to, subject, body }) {
  if (user && pass) {
    await smtpLine(socket, reader, 'AUTH LOGIN');
    await smtpLine(socket, reader, Buffer.from(user).toString('base64'));
    await smtpLine(socket, reader, Buffer.from(pass).toString('base64'));
  }
  await smtpLine(socket, reader, `MAIL FROM:<${from}>`);
  for (const recipient of to) {
    await smtpLine(socket, reader, `RCPT TO:<${recipient}>`);
  }
  await smtpLine(socket, reader, 'DATA');
  const headers = [
    `From: ${from}`,
    `To: ${to.join(', ')}`,
    `Subject: ${subject.replace(/\r?\n/g, ' ')}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
  ].join('\r\n');
  socket.write(`${headers}\r\n\r\n${body.replace(/\r?\n\./g, '\n..')}\r\n.\r\n`);
  await reader.read();
  await smtpLine(socket, reader, 'QUIT', true);
  socket.end();
}

function createSmtpReader(socket) {
  let buffer = '';
  const waiters = [];
  socket.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    drain();
  });
  socket.on('error', (error) => {
    while (waiters.length) waiters.shift().reject(error);
  });
  function drain() {
    const complete = /\r?\n\d{3} /m.test(buffer) || /^\d{3} .*\r?\n?$/.test(buffer);
    if (!complete || !waiters.length) return;
    const value = buffer;
    buffer = '';
    waiters.shift().resolve(value);
  }
  return {
    read() {
      return new Promise((resolve, reject) => {
        waiters.push({ resolve, reject });
        drain();
      });
    },
  };
}

async function smtpLine(socket, reader, line, allowFailure = false) {
  socket.write(`${line}\r\n`);
  const response = await reader.read();
  if (!allowFailure && !/^[23]\d\d/m.test(response)) {
    throw new Error(`SMTP command failed after ${line}: ${response}`);
  }
  return response;
}

function onceConnect(socket) {
  if (socket.readyState === 'open') return Promise.resolve();
  return new Promise((resolve, reject) => {
    socket.once('connect', resolve);
    socket.once('secureConnect', resolve);
    socket.once('error', reject);
  });
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

function extractGeminiText(json) {
  return (
    json?.candidates
      ?.flatMap((candidate) => candidate?.content?.parts || [])
      .map((part) => part?.text || '')
      .join('') || ''
  ).trim();
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

function writePrBody({ signals, geminiFix, validation, review, changedPaths }) {
  ensureArtifactDir();
  const bodyPath = path.join(ARTIFACT_DIR, 'pr-body.md');
  const body = [
    '## Autonomous Bug Fix',
    '',
    `Generated at: ${new Date().toISOString()}`,
    '',
    '### Detected Issues',
    ...signals.issues.map((issue) => `- ${issue.severity} ${issue.source}: ${issue.title}`),
    '',
    '### Gemini Fix',
    '',
    geminiFix.summary || '',
    '',
    `Root cause: ${geminiFix.rootCause || 'not provided'}`,
    '',
    '### Validation',
    ...validation.results.map((result) => `- ${result.exitCode === 0 ? 'PASS' : 'FAIL'}: \`${result.command}\``),
    '',
    '### OpenAI Review Gate',
    '',
    `Approved: ${review.approved}`,
    '',
    review.summary || '',
    '',
    '### Changed Files',
    ...changedPaths.map((file) => `- \`${file}\``),
  ].join('\n');
  writeFileSync(bodyPath, body, 'utf8');
  return bodyPath;
}

function buildPrTitle(geminiFix, signals) {
  const firstIssue = signals.issues[0]?.title || 'detected production issue';
  const summary = geminiFix.summary || firstIssue;
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
  node tool/autonomous_bugfix_agent.mjs [--dry-run] [--force] [--no-pr]

Required for active fixes:
  GEMINI_API_KEY                 Generates candidate code fixes.
  OPENAI_API_KEY                 Runs the independent OpenAI review gate.
  GH_TOKEN or gh auth            Opens PRs, watches checks, and auto-merges.

Common configuration:
  AGENT_UI_HEALTH_URLS           Comma or newline separated deployed UI URLs.
  AGENT_DETECTION_COMMANDS       Newline separated commands for bug detection.
  AGENT_VALIDATION_COMMANDS      Newline separated commands for final validation.
  FIREBASE_SERVICE_ACCOUNT       Firebase service account JSON for RTDB context.
  FIREBASE_DATABASE_URL          RTDB URL. Defaults to alertappsys.
  WORKER_SHARED_SECRET           Optional Cloudflare worker health auth header.
  SLACK_WEBHOOK_URL              Human alert fallback.
  RESEND_API_KEY or SMTP_HOST    Email alert fallback.
  AGENT_AUTOMERGE=1              Enable PR auto-merge after checks pass.
  AGENT_TRIGGER_DEPLOY=1         Trigger deploy.yml after merge.
`);
}
