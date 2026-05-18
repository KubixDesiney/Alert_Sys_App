// Cloudflare Worker - AlertSys AI & Security Worker
// Cron schedule: "* * * * *" (every minute). Notification fan-out lives in cloudflare_notify_worker.js.
// Required env vars: FB_DB_URL, FB_API_KEY, FIREBASE_SERVICE_ACCOUNT, optional GEMINI_API_KEY
// Optional: enable Workers AI binding (env.AI) for Llama 3.2 3B

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_ESCALATION_CHECKS = 5;
const MAX_FANOUT = 5;
const MAX_CRON_FANOUT = 1;
const PUSH_LOCK_TTL_MS = 2 * 60 * 1000;
const VALIDATION_CRON_INTERVAL_MIN = 30;
const PREDICTIVE_CRON_INTERVAL_MIN = 60;
const LSTM_CRON_INTERVAL_MIN = 60;
const LSTM_CRON_ENABLED = false;
const SECURITY_SCAN_INTERVAL_MIN = 30;

function _cronEvery(runStartMs, intervalMin) {
  const minutes = Math.max(1, Number(intervalMin) || 1);
  return Math.floor(runStartMs / 60000) % minutes === 0;
}

// ============ Firebase Auth ============
async function getFirebaseToken(env) {
  const now = Date.now();
  if (_fbToken && now < _fbTokenExpMs) return _fbToken;

  if (env?.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      const jwt = await createFirebaseAuthJWT(sa.client_email, sa.private_key);
      const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${env.FB_API_KEY}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: jwt, returnSecureToken: true }),
      });
      if (!res.ok) throw new Error(`Auth ${res.status}`);
      const data = await res.json();
      _fbToken = data.idToken;
      _fbTokenExpMs = now + 50 * 60 * 1000;
      return _fbToken;
    } catch (e) {
      console.error('[AUTH] Service account failed: ' + e.message);
    }
  }

  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${env.FB_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const data = await res.json();
  _fbToken = data.idToken;
  _fbTokenExpMs = now + 50 * 60 * 1000;
  return _fbToken;
}

async function createFirebaseAuthJWT(clientEmail, privateKeyPem) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat: now,
    exp: now + 3600,
    uid: 'worker-escalation',
    claims: { role: 'admin' },
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;
  const privateKey = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    privateKey,
    new TextEncoder().encode(signatureInput),
  );
  return `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function importPrivateKey(pem) {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

function base64UrlEncode(data) {
  const b64 =
    typeof data === 'string'
      ? btoa(data)
      : btoa(String.fromCharCode(...data));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ============ Helper functions ============
function _briefingDateKey(date) {
  const d = new Date(date);
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function _typeName(type) {
  switch (String(type || '')) {
    case 'qualite': return 'Quality';
    case 'maintenance': return 'Maintenance';
    case 'defaut_produit': return 'Damaged Product';
    case 'manque_ressource': return 'Resource Deficiency';
    default: return String(type || '');
  }
}

function _toMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function commanderCapabilities(shift) {
  const aiCommander = !!(shift && shift.aiCommander === true);
  const fullControl = !!(shift && shift.fullControl === true);
  const hasExplicitTaskConfig =
    shift &&
    (Object.prototype.hasOwnProperty.call(shift, 'handleAssignments') ||
      Object.prototype.hasOwnProperty.call(shift, 'handleCollaborations') ||
      Object.prototype.hasOwnProperty.call(shift, 'handleCrossFactoryTransfer') ||
      Object.prototype.hasOwnProperty.call(shift, 'fullControl'));
  return {
    aiCommander,
    fullControl,
    handleAssignments:
      aiCommander &&
      (fullControl ||
        shift?.handleAssignments === true ||
        (!hasExplicitTaskConfig && aiCommander)),
    handleCollaborations:
      aiCommander &&
      (fullControl ||
        shift?.handleCollaborations === true ||
        (!hasExplicitTaskConfig && aiCommander)),
    handleCrossFactoryTransfer:
      aiCommander && (fullControl || shift?.handleCrossFactoryTransfer === true),
  };
}

async function writeShiftAiLog(env, token, shiftId, entry) {
  if (!shiftId) return null;
  try {
    const nowIso = new Date().toISOString();
    const res = await fetch(`${env.FB_DB_URL}shift_ai_logs/${shiftId}.json?auth=${token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        at: entry.at || nowIso,
        kind: String(entry.kind || 'action'),
        shiftId,
        alertLabel: entry.alertLabel || null,
        supervisorName: entry.supervisorName || null,
        supervisorId: entry.supervisorId || null,
        factory: entry.factory || null,
        confidence: Number(entry.confidence || 0),
        reason: String(entry.reason || ''),
        gate: entry.gate || null,
        details: entry.details ?? null,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => null);
    return data?.name || null;
  } catch (e) {
    console.error('[SHIFT-AI] log write failed: ' + e.message);
    return null;
  }
}

function cloneCtxWithShift(ctx, shift) {
  return {
    ...ctx,
    activeShift: shift ?? null,
    targetShift: shift ?? null,
  };
}

// ============================================================================
// SECURITY AI AGENT — defensive layer for every worker request and cron tick.
// ============================================================================
// This module hardens the worker against a wide range of external threats:
//   • DDoS / function exhaustion       (per-IP sliding-window rate limiting)
//   • LLM prompt injection             (pattern matcher on text fields)
//   • Payload abuse                    (JSON shape + size validation)
//   • Database flooding                (cron-time anomaly scan)
//   • Enumeration / credential abuse   (auth-failure surge detection)
//   • Replay / burst scripting         (per-fingerprint window budgets)
//
// Design rules:
//   1. Security log writes are ALWAYS fire-and-forget — the user's response
//      must never wait for an audit write to flush.
//   2. In-memory state lives in the Worker isolate. Cold starts wipe it, but
//      a real attacker hits the same isolate repeatedly and convergence is
//      fast (a handful of requests until throttled).
//   3. Every block bumps `_securityActionsCounter`, which is read by
//      `_writeCronHealth` and surfaced as `securityActions` in the health
//      pulse at `workers/health/lastRun`.
//   4. We never expose internal patterns or thresholds in error responses —
//      attackers should not be able to fingerprint the security policy.
// ============================================================================

// Tunable configuration. Frozen so a runtime bug cannot mutate the policy.
const _SECURITY = Object.freeze({
  // Per-endpoint sliding-window rate limits, keyed by URL pathname (no slash).
  // Tighter limits sit on the expensive LLM endpoints; relaxed limits on the
  // cheap helpers. Anything not listed falls back to `default`.
  RATE_LIMITS: {
    'ai-suggest':          { windowSec: 60, max: 30 },
    'ai-proxy':            { windowSec: 60, max: 20 },
    'briefing':            { windowSec: 60, max: 15 },
    'predict':             { windowSec: 60, max: 10 },
    'predict-lstm':        { windowSec: 60, max: 10 },
    'suggest-assignee':    { windowSec: 60, max: 20 },
    'auto-fix':            { windowSec: 60, max: 10 },
    'auto-fix-full':       { windowSec: 60, max: 6 },
    'shift-ai-action':     { windowSec: 60, max: 30 },
    'validate-predictions':{ windowSec: 60, max: 4 },
    'ai-retry':            { windowSec: 60, max: 10 },
    'notify':              { windowSec: 60, max: 15 },
    'config':              { windowSec: 60, max: 60 },
    'security-status':     { windowSec: 60, max: 12 },
    'default':             { windowSec: 60, max: 20 },
  },

  // Hard caps on payload sizes. Anything larger is rejected outright; we do
  // not want a malicious client streaming megabytes of text into Llama.
  MAX_BODY_BYTES: 64 * 1024,        // 64 KB per JSON request
  MAX_PROMPT_CHARS: 8000,           // single text field max length

  // Cron anomaly thresholds.
  FLOOD_ALERTS_PER_MIN: 40,         // suspiciously many new alerts in 60 s
  FLOOD_NOTIF_BACKLOG: 800,         // shallow size of /notifications that
                                    //   indicates something is mass-writing

  // How many distinct caller fingerprints we keep tracked at once. A soft
  // cap that protects the isolate's memory; we evict on overflow.
  MAX_TRACKED_FINGERPRINTS: 1000,

  // A single matched pattern is enough to flag a prompt-injection attempt.
  // Patterns are heuristic and intentionally tuned to common attack strings.
  PROMPT_INJECTION_MATCH_THRESHOLD: 1,

  // External SOC/SIEM export. Elastic data streams follow
  // {type}-{dataset}-{namespace}; this becomes logs / sia.security /
  // production in ECS documents.
  ELASTIC_DEFAULT_DATA_STREAM: 'logs-sia.security-production',
  SIEM_OUTBOX_BATCH_SIZE: 25,
  SIEM_MAX_ATTEMPTS: 5,
  SIEM_RETRY_BASE_MS: 60 * 1000,
  SIEM_AUDIT_RETENTION_DAYS: 14,
});

// Per-fingerprint sliding window for rate limiting.
// Map<fingerprint, Map<endpoint, number[]>> where number[] is millisecond
// timestamps of recent requests. Older entries are pruned on each check.
const _securityRateLog = new Map();

// Module-level counter of how many security ACTIONS (= blocks) were taken
// since the last reset. `scheduled()` reads + resets this every cron tick.
let _securityActionsCounter = 0;
function _securityIncrementActions(n = 1) { _securityActionsCounter += n; }
function _securityResetActions()         { _securityActionsCounter = 0; }
function _securityGetActions()           { return _securityActionsCounter; }

// Firebase keys cannot contain ':' or '.' — reuse the escaping that
// `_historyKey()` uses elsewhere, so all timestamp-keyed nodes are consistent.
function _securityFbKey(iso) {
  return String(iso).replace(/[:.]/g, '-');
}

// ── Caller fingerprint ─────────────────────────────────────────────────────
// We never trust client-supplied identifiers. Cloudflare populates
// `cf-connecting-ip` for us; we combine it with a tiny non-cryptographic
// hash of the user-agent so different clients behind the same NAT still
// get separate budgets when their UAs differ. Falls back to a shared `anon`
// bucket if nothing identifies the caller (which still rate-limits, just
// less precisely).
function _securityFingerprint(request) {
  const rawIp =
    request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-real-ip') ||
    request.headers.get('x-forwarded-for') ||
    'anon';
  const ip = String(rawIp).split(',')[0].trim() || 'anon';
  const ua = request.headers.get('user-agent') || '';
  let h = 0;
  for (let i = 0; i < ua.length; i++) h = (h * 31 + ua.charCodeAt(i)) | 0;
  return `${ip}|${h.toString(36)}`;
}

// ── Sliding-window rate limiter ───────────────────────────────────────────
// Records timestamps of recent requests per (fingerprint, endpoint), prunes
// anything outside the configured window, and returns ok=false with a
// retry-after hint once the budget is exceeded.
function _securityRateLimit(request, endpoint) {
  const cfg = _SECURITY.RATE_LIMITS[endpoint] || _SECURITY.RATE_LIMITS.default;
  const fp = _securityFingerprint(request);
  const now = Date.now();
  const windowMs = cfg.windowSec * 1000;

  let perEndpoint = _securityRateLog.get(fp);
  if (!perEndpoint) {
    // Soft eviction so a malicious client cannot blow up our memory by
    // spraying random UAs to spawn distinct fingerprints. We drop the
    // oldest entry; legitimate clients are the most-recently-used so they
    // are not evicted.
    if (_securityRateLog.size >= _SECURITY.MAX_TRACKED_FINGERPRINTS) {
      const firstKey = _securityRateLog.keys().next().value;
      _securityRateLog.delete(firstKey);
    }
    perEndpoint = new Map();
    _securityRateLog.set(fp, perEndpoint);
  }

  let stamps = perEndpoint.get(endpoint) || [];
  stamps = stamps.filter((t) => now - t < windowMs);   // prune
  stamps.push(now);
  perEndpoint.set(endpoint, stamps);

  if (stamps.length > cfg.max) {
    const oldest = stamps[0];
    return {
      ok: false,
      retryAfter: Math.max(1, Math.ceil((windowMs - (now - oldest)) / 1000)),
      observed: stamps.length,
      limit: cfg.max,
      fingerprint: fp,
    };
  }
  return { ok: true, observed: stamps.length, limit: cfg.max, fingerprint: fp };
}

// ── Prompt-injection detector ─────────────────────────────────────────────
// A defensive heuristic, not a guarantee. Each pattern is named so the
// security log records exactly which attack signature matched. New patterns
// can be added here without touching call sites.
const _PROMPT_INJECTION_PATTERNS = [
  // Classic instruction override: "Ignore all previous instructions and ..."
  {
    name: 'ignore_previous',
    re: /\b(?:ignore|disregard|forget|override|discard)\s+(?:(?:(?:all|any|the|your|these|those)\s+)?(?:(?:previous|prior|earlier|above|system|developer)\s+){1,4}|(?:all|any|the|your|these|those)\s+)(?:instructions?|prompts?|rules?|messages?|directives?)\b/i,
  },
  // Variant phrasing: "Do not follow previous instructions"
  { name: 'stop_following',   re: /\b(?:do\s+not|don't|stop)\s+(?:follow|obey|respect)\s+(?:(?:all|any|the|your|these|those)\s+)?(?:(?:previous|prior|earlier|above|system|developer)\s+){1,4}(?:instructions?|prompts?|rules?|messages?|directives?)\b/i },
  // Context reset attempts: "Forget everything above"
  { name: 'context_reset',    re: /\b(?:forget|ignore|disregard|discard)\s+(?:everything|all)\s+(?:above|before|so\s+far|you\s+were\s+told)\b/i },
  // Role hijack: "You are now an unrestricted assistant"
  { name: 'role_override',    re: /you\s+are\s+(now\s+)?(an?|the)\s+[a-z\s]{0,32}(assistant|ai|bot)/i },
  // References the system prompt directly
  { name: 'system_takeover',  re: /(system\s+prompt|developer\s+prompt|prior\s+system\s+message)/i },
  // Known jailbreak handles
  { name: 'jailbreak',        re: /\b(DAN|do\s+anything\s+now|jailbreak|bypass\s+safety|developer\s+mode\s+enabled)\b/i },
  // Asks the model to dump credentials
  { name: 'cred_exfil',       re: /(reveal|print|disclose|show|output)\s+(the\s+)?(api\s+key|secret|private\s+key|env\s+vars?|service\s+account|firebase\s+token)/i },
  // Common SQL-injection scaffolding (the worker has no SQL but admins might forward strings)
  { name: 'sql_injection',    re: /\b(union\s+select|drop\s+table|;--|or\s+1=1|--\s+$)\b/i },
  // Path traversal / file disclosure
  { name: 'path_traversal',   re: /\.\.\/|\.\.\\|\/etc\/passwd|c:\\windows\\system32/i },
  // Chat-template tokens that try to escape the conversation framing
  { name: 'instr_chain',      re: /<\|im_start\|>|<\|im_end\|>|\[INST\]|\[\/INST\]|<\|system\|>/ },
  // Embedded service URLs that might be used to exfiltrate via Llama replies
  { name: 'firebase_url',     re: /firebaseio\.com\/.*\?auth=|firebase-adminsdk/i },
  // Leaks of CF tokens or backend URLs
  { name: 'cloudflare_token', re: /workers\.dev\/.*\?auth=/i },
];

function _securityDetectPromptInjection(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return { hit: false, matches: [] };
  }
  const matches = [];
  for (const p of _PROMPT_INJECTION_PATTERNS) {
    if (p.re.test(text)) matches.push(p.name);
  }
  return {
    hit: matches.length >= _SECURITY.PROMPT_INJECTION_MATCH_THRESHOLD,
    matches,
  };
}

// ── Text sanitizer ────────────────────────────────────────────────────────
// Removes control characters that some LLMs treat as separators (NULs,
// vertical tabs, zero-width joiners, BOMs) and clamps the length. Strings
// that pass through here are safe to embed inside a Llama prompt without
// breaking out of the surrounding template.
function _securitySanitizeText(text, maxLen) {
  if (typeof text !== 'string') return '';
  const cap = Number.isFinite(maxLen) ? maxLen : _SECURITY.MAX_PROMPT_CHARS;
  let cleaned = text.replace(
    /[ --﻿​-‏]/g,
    '',
  );
  if (cleaned.length > cap) cleaned = cleaned.slice(0, cap);
  return cleaned;
}

// ── Safe JSON body parser ─────────────────────────────────────────────────
// Reads the request body with three guards: declared length, actual length,
// and JSON validity. Returns a typed result so the caller can map each
// failure mode to its own HTTP status without try/catching itself.
async function _securityParseJsonBody(request) {
  const lenHeader = request.headers.get('content-length');
  if (lenHeader && Number(lenHeader) > _SECURITY.MAX_BODY_BYTES) {
    return { ok: false, error: 'payload_too_large', body: null };
  }
  let raw;
  try {
    raw = await request.text();
  } catch (e) {
    return { ok: false, error: 'read_error', body: null };
  }
  if (raw.length > _SECURITY.MAX_BODY_BYTES) {
    return { ok: false, error: 'payload_too_large', body: null };
  }
  if (!raw) return { ok: true, body: {} };
  try {
    const obj = JSON.parse(raw);
    if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
      return { ok: true, body: obj };
    }
    return { ok: false, error: 'bad_shape', body: null };
  } catch (e) {
    return { ok: false, error: 'invalid_json', body: null };
  }
}

// ── Fire-and-forget log writers ───────────────────────────────────────────
// Two-tier audit trail:
//   • security/logs/{key}     — every observation (heartbeats, malformed
//                                payloads we sanitized through, etc.)
//   • security/actions/{key}  — every BLOCK we took (rate limit hits,
//                                rejected prompt injections, anomalies)
// Anything written to `security/actions` also bumps the counter so the next
// health pulse reflects the new totals.
async function _securityLogEvent(env, event) {
  try {
    if (!env?.FB_DB_URL) return;
    const token = await getFirebaseToken(env);
    if (!token) return;
    const iso = new Date().toISOString();
    const key = _securityFbKey(iso) + '_' + Math.floor(Math.random() * 1e6).toString(36);
    const auditRecord = { at: iso, ...event };
    const outboxRecord = {
      source: 'logs',
      eventId: key,
      status: 'pending',
      attempts: 0,
      createdAt: iso,
      nextAttemptAt: iso,
      event: auditRecord,
    };
    // Multi-location PATCH keeps the local audit copy and SIEM outbox in sync.
    await fetch(`${env.FB_DB_URL}.json?auth=${token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        [`security/logs/${key}`]: auditRecord,
        [`security/siem_outbox/${key}`]: outboxRecord,
      }),
    });
  } catch (e) {
    // Silent — we MUST NOT propagate logging errors.
  }
}

async function _securityRecordAction(env, action) {
  _securityIncrementActions(1);
  try {
    if (!env?.FB_DB_URL) return;
    const token = await getFirebaseToken(env);
    if (!token) return;
    const iso = new Date().toISOString();
    const key = _securityFbKey(iso) + '_' + Math.floor(Math.random() * 1e6).toString(36);
    const auditRecord = { at: iso, ...action };
    const outboxRecord = {
      source: 'actions',
      eventId: key,
      status: 'pending',
      attempts: 0,
      createdAt: iso,
      nextAttemptAt: iso,
      event: auditRecord,
    };
    await fetch(`${env.FB_DB_URL}.json?auth=${token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        [`security/actions/${key}`]: auditRecord,
        [`security/siem_outbox/${key}`]: outboxRecord,
      }),
    });
  } catch (e) {
    // Silent — see comment above.
  }
}

// ── Elastic SIEM export helpers ───────────────────────────────────────────
function _securityBoolEnv(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
}

function _securityElasticConfig(env) {
  const requested = _securityBoolEnv(env?.ELASTIC_SIEM_ENABLED);
  const baseUrl = String(env?.ELASTICSEARCH_URL || '').trim().replace(/\/+$/, '');
  const apiKey = String(env?.ELASTIC_API_KEY || '').trim();
  const dataStream =
    String(env?.ELASTIC_SECURITY_DATA_STREAM || _SECURITY.ELASTIC_DEFAULT_DATA_STREAM)
      .trim() || _SECURITY.ELASTIC_DEFAULT_DATA_STREAM;
  const missing = [];
  if (!baseUrl) missing.push('ELASTICSEARCH_URL');
  if (!apiKey) missing.push('ELASTIC_API_KEY');
  return {
    requested,
    enabled: requested && missing.length === 0,
    baseUrl,
    apiKey,
    dataStream,
    missing,
  };
}

function _securityDataStreamParts(dataStream) {
  const parts = String(dataStream || _SECURITY.ELASTIC_DEFAULT_DATA_STREAM).split('-');
  return {
    type: parts[0] || 'logs',
    dataset: parts[1] || 'sia.security',
    namespace: parts.slice(2).join('-') || 'production',
  };
}

function _securitySourceIpFromFingerprint(fingerprint) {
  const raw = String(fingerprint || '').split('|')[0].trim();
  if (!raw || raw === 'anon') return undefined;
  if (/^[0-9]{1,3}(?:\.[0-9]{1,3}){3}$/.test(raw)) return raw;
  if (/^[0-9a-fA-F:]+$/.test(raw) && raw.includes(':')) return raw;
  return undefined;
}

function _securityEventProfile(kind, source) {
  const profiles = {
    rate_limit_block: {
      eventKind: 'alert',
      category: ['network'],
      type: ['denied'],
      outcome: 'failure',
      severity: 7,
      message: 'SIA security guard blocked a rate-limited request.',
    },
    prompt_injection_block: {
      eventKind: 'alert',
      category: ['intrusion_detection', 'web'],
      type: ['denied'],
      outcome: 'failure',
      severity: 8,
      message: 'SIA security guard blocked a prompt-injection attempt.',
    },
    bad_payload: {
      eventKind: 'alert',
      category: ['web'],
      type: ['denied', 'error'],
      outcome: 'failure',
      severity: 5,
      message: 'SIA security guard rejected an invalid request payload.',
    },
    alert_flood_detected: {
      eventKind: 'alert',
      category: ['intrusion_detection'],
      type: ['info'],
      outcome: 'unknown',
      severity: 7,
      message: 'SIA anomaly scan detected alert flooding.',
    },
    notifications_backlog: {
      eventKind: 'alert',
      category: ['intrusion_detection'],
      type: ['info'],
      outcome: 'unknown',
      severity: 6,
      message: 'SIA anomaly scan detected a notification backlog.',
    },
    auth_failure_surge: {
      eventKind: 'alert',
      category: ['authentication'],
      type: ['info'],
      outcome: 'failure',
      severity: 8,
      message: 'SIA anomaly scan detected an authentication failure surge.',
    },
    malformed_alerts_seen: {
      eventKind: 'event',
      category: ['database'],
      type: ['info'],
      outcome: 'unknown',
      severity: 4,
      message: 'SIA anomaly scan observed malformed alert records.',
    },
    scan_heartbeat: {
      eventKind: 'event',
      category: ['configuration'],
      type: ['info'],
      outcome: 'success',
      severity: 1,
      message: 'SIA security anomaly scan completed.',
    },
    scan_error: {
      eventKind: 'event',
      category: ['configuration'],
      type: ['error'],
      outcome: 'failure',
      severity: 5,
      message: 'SIA security anomaly scan failed.',
    },
  };
  return profiles[kind] || {
    eventKind: source === 'actions' ? 'alert' : 'event',
    category: ['intrusion_detection'],
    type: source === 'actions' ? ['denied'] : ['info'],
    outcome: source === 'actions' ? 'failure' : 'unknown',
    severity: source === 'actions' ? 6 : 2,
    message: 'SIA security event.',
  };
}

function _securityEventToEcsDocument(
  source,
  eventId,
  rawEvent,
  dataStream = _SECURITY.ELASTIC_DEFAULT_DATA_STREAM,
) {
  const event = rawEvent && typeof rawEvent === 'object' ? rawEvent : {};
  const kind = String(event.kind || 'security_event');
  const profile = _securityEventProfile(kind, source);
  const ds = _securityDataStreamParts(dataStream);
  const fingerprint = event.fingerprint != null ? String(event.fingerprint) : undefined;
  const sourceIp = _securitySourceIpFromFingerprint(fingerprint);
  const at = event.at && !Number.isNaN(Date.parse(String(event.at)))
    ? String(event.at)
    : new Date().toISOString();

  const siaSecurity = {
    source_collection: source === 'actions' ? 'actions' : 'logs',
    firebase_event_id: String(eventId || ''),
    kind,
  };
  for (const key of [
    'endpoint',
    'field',
    'reason',
    'fingerprint',
    'observed',
    'limit',
    'count',
    'threshold',
    'windowSec',
    'windowMin',
    'total',
    'alertsScanned',
    'usersScanned',
    'shiftsScanned',
  ]) {
    if (event[key] != null) siaSecurity[key] = event[key];
  }
  if (Array.isArray(event.matches)) siaSecurity.matches = event.matches.slice(0, 20);
  if (event.preview != null) {
    siaSecurity.preview = _securitySanitizeText(String(event.preview), 120);
  }
  if (event.message != null) {
    siaSecurity.message = _securitySanitizeText(String(event.message), 240);
  }

  const doc = {
    '@timestamp': at,
    message: profile.message,
    data_stream: ds,
    event: {
      kind: profile.eventKind,
      category: profile.category,
      type: profile.type,
      action: kind,
      outcome: profile.outcome,
      severity: profile.severity,
      module: 'sia.security',
      dataset: 'sia.security',
      provider: 'sia-ai-security-worker',
    },
    service: { name: 'sia-ai-security-worker', type: 'cloudflare-worker' },
    observer: { vendor: 'Cloudflare', type: 'worker', name: 'alert-notifier' },
    cloud: { provider: 'cloudflare' },
    sia: { security: siaSecurity },
  };
  if (sourceIp) doc.source = { ip: sourceIp };
  return doc;
}

function _securityBuildElasticBulkNdjson(records, dataStream) {
  return (records || [])
    .map((record) => {
      const id = String(record.id || record.eventId || '');
      const doc = record.doc || record;
      return `${JSON.stringify({ create: { _index: dataStream, _id: id } })}\n${JSON.stringify(doc)}\n`;
    })
    .join('');
}

async function _securityPatchRoot(env, token, patch) {
  const keys = Object.keys(patch || {});
  if (!keys.length || !env?.FB_DB_URL || !token) return false;
  const res = await fetch(`${env.FB_DB_URL}.json?auth=${token}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(patch),
  });
  return res.ok;
}

function _securityShortError(error) {
  if (!error) return 'unknown_error';
  if (typeof error === 'string') return _securitySanitizeText(error, 240);
  return _securitySanitizeText(error.message || JSON.stringify(error), 240);
}

function _securityRetryIso(attempts, nowMs = Date.now()) {
  const exponent = Math.max(0, Math.min(5, Number(attempts || 0) - 1));
  const delay = _SECURITY.SIEM_RETRY_BASE_MS * Math.pow(2, exponent);
  return new Date(nowMs + delay).toISOString();
}

async function _securityLoadDueOutbox(env, token) {
  const res = await fetch(
    `${env.FB_DB_URL}security/siem_outbox.json?auth=${token}` +
      `&orderBy=%22nextAttemptAt%22&limitToFirst=${_SECURITY.SIEM_OUTBOX_BATCH_SIZE * 2}`,
  );
  if (!res.ok) return [];
  const map = (await res.json().catch(() => null)) || {};
  const nowIso = new Date().toISOString();
  return Object.entries(map)
    .filter(([, v]) => {
      if (!v || typeof v !== 'object') return false;
      const status = String(v.status || 'pending');
      if (status !== 'pending' && status !== 'retry') return false;
      return !v.nextAttemptAt || String(v.nextAttemptAt) <= nowIso;
    })
    .slice(0, _SECURITY.SIEM_OUTBOX_BATCH_SIZE);
}

async function _securityWriteSiemStatus(env, token, status) {
  await _securityPatchRoot(env, token, {
    'security/siem_export_status/lastRun': {
      at: new Date().toISOString(),
      ...status,
    },
  });
}

async function _securityMarkSiemFailures(env, token, records, error) {
  const nowIso = new Date().toISOString();
  const patch = {};
  let deadLetter = 0;
  for (const record of records) {
    const attempts = Number(record.attempts || 0) + 1;
    const dead = attempts >= _SECURITY.SIEM_MAX_ATTEMPTS;
    if (dead) deadLetter++;
    patch[`security/siem_outbox/${record.outboxId}/attempts`] = attempts;
    patch[`security/siem_outbox/${record.outboxId}/lastAttemptAt`] = nowIso;
    patch[`security/siem_outbox/${record.outboxId}/lastError`] = _securityShortError(error);
    patch[`security/siem_outbox/${record.outboxId}/status`] = dead ? 'dead_letter' : 'pending';
    patch[`security/siem_outbox/${record.outboxId}/nextAttemptAt`] = dead
      ? null
      : _securityRetryIso(attempts);
  }
  await _securityPatchRoot(env, token, patch);
  return { failed: records.length, deadLetter };
}

async function _securityMarkSiemResults(env, token, records, items) {
  const nowIso = new Date().toISOString();
  const patch = {};
  let exported = 0;
  let failed = 0;
  let deadLetter = 0;
  records.forEach((record, i) => {
    const item = items?.[i]?.create || items?.[i]?.index || {};
    const status = Number(item.status || 0);
    if ((status >= 200 && status < 300) || status === 409) {
      exported++;
      patch[`security/siem_outbox/${record.outboxId}/status`] = 'exported';
      patch[`security/siem_outbox/${record.outboxId}/exportedAt`] = nowIso;
      patch[`security/siem_outbox/${record.outboxId}/lastAttemptAt`] = nowIso;
      patch[`security/siem_outbox/${record.outboxId}/lastError`] = null;
      return;
    }
    failed++;
    const attempts = Number(record.attempts || 0) + 1;
    const dead = attempts >= _SECURITY.SIEM_MAX_ATTEMPTS;
    if (dead) deadLetter++;
    patch[`security/siem_outbox/${record.outboxId}/attempts`] = attempts;
    patch[`security/siem_outbox/${record.outboxId}/lastAttemptAt`] = nowIso;
    patch[`security/siem_outbox/${record.outboxId}/lastError`] = _securityShortError(
      item.error || `elastic_status_${status || 'missing'}`,
    );
    patch[`security/siem_outbox/${record.outboxId}/status`] = dead ? 'dead_letter' : 'pending';
    patch[`security/siem_outbox/${record.outboxId}/nextAttemptAt`] = dead
      ? null
      : _securityRetryIso(attempts);
  });
  await _securityPatchRoot(env, token, patch);
  return { exported, failed, deadLetter };
}

async function _securityPruneExportedAudit(env, token) {
  try {
    const cutoff = new Date(
      Date.now() - _SECURITY.SIEM_AUDIT_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    const res = await fetch(
      `${env.FB_DB_URL}security/siem_outbox.json?auth=${token}` +
        '&orderBy=%22status%22&equalTo=%22exported%22&limitToFirst=100',
    );
    if (!res.ok) return 0;
    const map = (await res.json().catch(() => null)) || {};
    const patch = {};
    let pruned = 0;
    for (const [id, item] of Object.entries(map)) {
      if (!item || typeof item !== 'object') continue;
      if (!item.exportedAt || String(item.exportedAt) >= cutoff) continue;
      const source = item.source === 'actions' ? 'actions' : 'logs';
      const eventId = item.eventId || id;
      patch[`security/${source}/${eventId}`] = null;
      patch[`security/siem_outbox/${id}`] = null;
      pruned++;
    }
    if (pruned > 0) await _securityPatchRoot(env, token, patch);
    return pruned;
  } catch (_) {
    return 0;
  }
}

async function _securityFlushSiemOutbox(env, ctx) {
  const cfg = _securityElasticConfig(env);
  if (!cfg.enabled) {
    return {
      enabled: false,
      requested: cfg.requested,
      missing: cfg.missing,
      attempted: 0,
      exported: 0,
      failed: 0,
      deadLetter: 0,
    };
  }

  const token = ctx?.token || await getFirebaseToken(env);
  const due = await _securityLoadDueOutbox(env, token);
  if (!due.length) {
    const pruned = await _securityPruneExportedAudit(env, token);
    await _securityWriteSiemStatus(env, token, {
      enabled: true,
      dataStream: cfg.dataStream,
      attempted: 0,
      exported: 0,
      failed: 0,
      deadLetter: 0,
      pruned,
    });
    return { enabled: true, attempted: 0, exported: 0, failed: 0, deadLetter: 0, pruned };
  }

  const records = due.map(([outboxId, item]) => {
    const source = item.source === 'actions' ? 'actions' : 'logs';
    const eventId = item.eventId || outboxId;
    return {
      outboxId,
      attempts: Number(item.attempts || 0),
      id: `sia-${eventId}`,
      doc: _securityEventToEcsDocument(source, eventId, item.event, cfg.dataStream),
    };
  });
  const body = _securityBuildElasticBulkNdjson(records, cfg.dataStream);

  try {
    const res = await fetch(`${cfg.baseUrl}/_bulk`, {
      method: 'POST',
      headers: {
        Authorization: `ApiKey ${cfg.apiKey}`,
        'Content-Type': 'application/x-ndjson',
      },
      body,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const result = await _securityMarkSiemFailures(
        env,
        token,
        records,
        text || `elastic_http_${res.status}`,
      );
      await _securityWriteSiemStatus(env, token, {
        enabled: true,
        dataStream: cfg.dataStream,
        attempted: records.length,
        exported: 0,
        ...result,
        lastError: `elastic_http_${res.status}`,
      });
      return {
        enabled: true,
        attempted: records.length,
        exported: 0,
        ...result,
      };
    }
    const json = await res.json().catch(() => ({}));
    const result = await _securityMarkSiemResults(env, token, records, json.items || []);
    const pruned = await _securityPruneExportedAudit(env, token);
    await _securityWriteSiemStatus(env, token, {
      enabled: true,
      dataStream: cfg.dataStream,
      attempted: records.length,
      ...result,
      pruned,
    });
    return { enabled: true, attempted: records.length, ...result, pruned };
  } catch (e) {
    const result = await _securityMarkSiemFailures(env, token, records, e);
    await _securityWriteSiemStatus(env, token, {
      enabled: true,
      dataStream: cfg.dataStream,
      attempted: records.length,
      exported: 0,
      ...result,
      lastError: _securityShortError(e),
    });
    return {
      enabled: true,
      attempted: records.length,
      exported: 0,
      ...result,
    };
  }
}

// ── Main per-request guard ────────────────────────────────────────────────
// Every fetch handler funnels through this. It returns either:
//   { ok: true,  body }                             — proceed; use `body`
//   { ok: false, response }                         — bail; return `response`
//
// Options:
//   endpoint:    string keyed into _SECURITY.RATE_LIMITS
//   requireBody: true if the endpoint expects a JSON payload
//   textFields:  array of body keys whose contents will be (a) scanned for
//                prompt injection and (b) sanitized in-place if clean
//   maxTextLen:  optional cap override per endpoint
async function _securityGuard(request, env, options) {
  const opts = options || {};
  const endpoint = opts.endpoint || 'default';

  // 1. Rate limit per fingerprint × endpoint.
  const rl = _securityRateLimit(request, endpoint);
  if (!rl.ok) {
    await _securityRecordAction(env, {
      kind: 'rate_limit_block',
      endpoint,
      fingerprint: rl.fingerprint,
      observed: rl.observed,
      limit: rl.limit,
    });
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: 'rate_limited', retryAfter: rl.retryAfter }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
            'Retry-After': String(rl.retryAfter),
          },
        },
      ),
    };
  }

  // 2. Body parse (size + JSON) and text-field scanning + sanitization.
  let body = {};
  if (opts.requireBody) {
    const parsed = await _securityParseJsonBody(request);
    if (!parsed.ok) {
      await _securityRecordAction(env, {
        kind: 'bad_payload',
        endpoint,
        reason: parsed.error,
        fingerprint: rl.fingerprint,
      });
      const status = parsed.error === 'payload_too_large' ? 413 : 400;
      return {
        ok: false,
        response: new Response(JSON.stringify({ error: parsed.error }), {
          status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }),
      };
    }
    body = parsed.body;

    const textFields = Array.isArray(opts.textFields) ? opts.textFields : [];
    for (const f of textFields) {
      if (body[f] != null && typeof body[f] === 'string') {
        const det = _securityDetectPromptInjection(body[f]);
        if (det.hit) {
          // We log the matches but do NOT feed the poisoned text to Llama.
          await _securityRecordAction(env, {
            kind: 'prompt_injection_block',
            endpoint,
            field: f,
            matches: det.matches,
            preview: body[f].slice(0, 120),
            fingerprint: rl.fingerprint,
          });
          return {
            ok: false,
            response: new Response(
              JSON.stringify({
                error: 'input_blocked_by_security',
                detail: 'The request was flagged by the security policy.',
              }),
              {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              },
            ),
          };
        }
        body[f] = _securitySanitizeText(body[f], opts.maxTextLen);
      }
    }
  }

  return { ok: true, body, fingerprint: rl.fingerprint };
}

// ── Cron-time anomaly scan ────────────────────────────────────────────────
// Runs once per scheduled() tick. It surveys the loaded data for shapes
// consistent with mass-write, enumeration, or credential-stuffing attacks
// and logs anything it finds. The return value is the number of actions
// taken; the caller folds it into the health pulse.
async function _runSecurityAnomalyScan(env, ctx) {
  if (!ctx || !ctx.token) return 0;
  const startActions = _securityGetActions();
  const nowMs = Date.now();

  try {
    // 1. ALERT FLOOD — too many alerts created in the last minute.
    //    Catches scripts that authenticate as a supervisor and loop on
    //    AlertService.createAlert() to fill the DB.
    const recentAlerts = Object.values(ctx.alertsMap || {}).filter((a) => {
      const t = _toMs(a?.timestamp);
      return t != null && nowMs - t < 60_000;
    });
    if (recentAlerts.length >= _SECURITY.FLOOD_ALERTS_PER_MIN) {
      await _securityRecordAction(env, {
        kind: 'alert_flood_detected',
        count: recentAlerts.length,
        threshold: _SECURITY.FLOOD_ALERTS_PER_MIN,
        windowSec: 60,
      });
    }

    // 2. MALFORMED ALERTS — control characters or absurd field sizes
    //    suggest someone is fuzzing the create endpoint or trying to
    //    smuggle prompt-injection payloads through alert descriptions.
    let malformed = 0;
    for (const a of Object.values(ctx.alertsMap || {})) {
      if (!a || typeof a !== 'object') continue;
      const desc = String(a.description || '');
      const type = String(a.type || '');
      if (
        /[ --]/.test(desc) ||
        desc.length > 4000 ||
        type.length > 64
      ) {
        malformed++;
      }
    }
    if (malformed > 0) {
      await _securityLogEvent(env, {
        kind: 'malformed_alerts_seen',
        count: malformed,
      });
    }

    // 3. NOTIFICATION BACKLOG — too many queued notifications, indicating
    //    a fan-out loop or a compromised account spamming requests.
    try {
      const res = await fetch(
        `${env.FB_DB_URL}notifications.json?auth=${ctx.token}&shallow=true`,
      );
      if (res.ok) {
        const map = (await res.json()) || {};
        const total = Object.keys(map).length;
        if (total >= _SECURITY.FLOOD_NOTIF_BACKLOG) {
          await _securityRecordAction(env, {
            kind: 'notifications_backlog',
            total,
            threshold: _SECURITY.FLOOD_NOTIF_BACKLOG,
          });
        }
      }
    } catch (_) {
      // Best-effort — never block the cron on a security-scan IO error.
    }

    // 4. AUTH-FAILURE SURGE — look at recent security_logs and see whether
    //    a particular fingerprint has been failing repeatedly.
    try {
      const res = await fetch(
        `${env.FB_DB_URL}security/logs.json?auth=${ctx.token}` +
          `&orderBy=%22at%22&limitToLast=200`,
      );
      if (res.ok) {
        const map = (await res.json()) || {};
        const cutoffIso = new Date(nowMs - 5 * 60_000).toISOString();
        const perFp = new Map();
        for (const v of Object.values(map)) {
          if (!v || typeof v !== 'object') continue;
          if (String(v.at || '') < cutoffIso) continue;
          if (v.kind !== 'auth_failure') continue;
          const fp = String(v.fingerprint || 'unknown');
          perFp.set(fp, (perFp.get(fp) || 0) + 1);
        }
        for (const [fp, count] of perFp) {
          if (count >= 10) {
            await _securityRecordAction(env, {
              kind: 'auth_failure_surge',
              fingerprint: fp,
              count,
              windowMin: 5,
            });
          }
        }
      }
    } catch (_) {}

    // 5. HEARTBEAT — write a "scan ran" log so the developer UI always has
    //    a fresh `last scan` indicator, even when nothing is suspicious.
    await _securityLogEvent(env, {
      kind: 'scan_heartbeat',
      alertsScanned: Object.keys(ctx.alertsMap || {}).length,
      usersScanned: Object.keys(ctx.usersMap || {}).length,
      shiftsScanned: Object.keys(ctx.shiftsMap || {}).length,
    });
  } catch (e) {
    console.error('[SECURITY] scan failed: ' + e.message);
    await _securityLogEvent(env, {
      kind: 'scan_error',
      message: String(e?.message || e),
    });
  }

  return _securityGetActions() - startActions;
}

// ── /security-status endpoint ─────────────────────────────────────────────
// Returns a snapshot of the policy + last cron pulse for the developer UI.
// Rate-limited so it cannot itself become a probe target.
async function handleSecurityStatus(env) {
  let lastHealth = null;
  try {
    const token = await getFirebaseToken(env);
    const res = await fetch(
      `${env.FB_DB_URL}workers/health/lastRun.json?auth=${token}`,
    );
    if (res.ok) lastHealth = await res.json();
  } catch (_) {}
  return new Response(
    JSON.stringify({
      ok: true,
      policy: {
        rateLimits: _SECURITY.RATE_LIMITS,
        maxBodyBytes: _SECURITY.MAX_BODY_BYTES,
        maxPromptChars: _SECURITY.MAX_PROMPT_CHARS,
        floodAlertsPerMin: _SECURITY.FLOOD_ALERTS_PER_MIN,
        floodNotifBacklog: _SECURITY.FLOOD_NOTIF_BACKLOG,
        promptInjectionPatterns: _PROMPT_INJECTION_PATTERNS.map((p) => p.name),
      },
      runtime: {
        trackedFingerprints: _securityRateLog.size,
        pendingActionCount: _securityGetActions(),
      },
      lastHealth,
      generatedAt: new Date().toISOString(),
    }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
}

function _aggregateWeek(alertsMap = {}, factoryFilter = null) {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const stats = {
    total: 0,
    solved: 0,
    inProgress: 0,
    pending: 0,
    critical: 0,
    aiAssigned: 0,
    fastestMin: 0,
    slowestMin: 0,
    avgResolutionMin: 0,
    byType: {},
    byFactory: {},
  };
  let resolutionCount = 0;
  let resolutionTotal = 0;
  for (const alert of Object.values(alertsMap || {})) {
    const ts = _toMs(alert?.timestamp);
    if (ts == null || ts < cutoff) continue;
    if (factoryFilter && String(alert?.usine || '') !== factoryFilter) continue;
    stats.total++;
    if (alert?.isCritical === true) stats.critical++;
    if (alert?.aiAssigned === true) stats.aiAssigned++;
    const type = String(alert?.type || '');
    const factory = String(alert?.usine || '');
    stats.byType[type] = (stats.byType[type] || 0) + 1;
    stats.byFactory[factory] = (stats.byFactory[factory] || 0) + 1;
    if (alert?.status === 'validee') {
      stats.solved++;
      const elapsed = Number(alert?.elapsedTime);
      if (Number.isFinite(elapsed)) {
        resolutionCount++;
        resolutionTotal += elapsed;
        if (stats.fastestMin === 0 || elapsed < stats.fastestMin) stats.fastestMin = elapsed;
        if (elapsed > stats.slowestMin) stats.slowestMin = elapsed;
      }
    } else if (alert?.status === 'en_cours') {
      stats.inProgress++;
    } else if (alert?.status === 'disponible') {
      stats.pending++;
    }
  }
  if (resolutionCount > 0) {
    stats.avgResolutionMin = Math.round(resolutionTotal / resolutionCount);
  }
  return stats;
}

// Returns a safe slug for a factory name usable as a Firebase path segment.
function _briefingFactorySlug(factory) {
  return String(factory || '').toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');
}

function _filterAlertsMapByFactorySlug(alertsMap = {}, factorySlug = null) {
  if (!factorySlug) return alertsMap || {};
  return Object.fromEntries(
    Object.entries(alertsMap || {}).filter(([, alert]) => {
      return _briefingFactorySlug(alert?.usine || '') === factorySlug;
    }),
  );
}

// Returns the top performing supervisor (by resolved alert count) in the past 7 days.
function _topSupervisorWeek(alertsMap = {}, usersMap = {}, factoryFilter = null) {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const counts = {};
  for (const alert of Object.values(alertsMap || {})) {
    const ts = _toMs(alert?.timestamp);
    if (ts == null || ts < cutoff || alert?.status !== 'validee') continue;
    if (factoryFilter && String(alert?.usine || '') !== factoryFilter) continue;
    const uid = alert?.superviseurId;
    if (!uid) continue;
    if (!counts[uid]) {
      const user = usersMap[uid] || {};
      const fullName = user.fullName || `${user.firstName || ''} ${user.lastName || ''}`.trim() || uid;
      counts[uid] = { name: fullName, count: 0, totalTime: 0, byType: {} };
    }
    counts[uid].count++;
    const type = String(alert?.type || '');
    counts[uid].byType[type] = (counts[uid].byType[type] || 0) + 1;
    const elapsed = Number(alert?.elapsedTime);
    if (Number.isFinite(elapsed)) counts[uid].totalTime += elapsed;
  }
  const entries = Object.values(counts).sort((a, b) => b.count - a.count);
  if (entries.length === 0) return null;
  const top = entries[0];
  const topTypeEntry = Object.entries(top.byType).sort((a, b) => b[1] - a[1])[0];
  return {
    name: top.name,
    count: top.count,
    topType: topTypeEntry ? topTypeEntry[0] : null,
    avgMin: top.count > 0 ? Math.round(top.totalTime / top.count) : null,
  };
}

// ============ Scoring helpers ============
function buildSupStats(alertsMap = {}) {
  const stats = {};
  const ensure = (uid) => {
    if (!stats[uid]) {
      stats[uid] = {
        typeCounts: {},
        typeTotalTimes: {},
        stationCounts: {},
        conveyorCounts: {},
      };
    }
    return stats[uid];
  };
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || alert.status !== 'validee') continue;
    if (typeof alert.elapsedTime !== 'number' || !Number.isFinite(alert.elapsedTime)) continue;
    const ids = [alert.superviseurId, alert.assistantId].filter(Boolean);
    if (ids.length === 0) continue;
    const type = String(alert.type || 'unknown');
    const factory = String(alert.usine || '');
    const stationKey = `${factory}|${alert.convoyeur}|${alert.poste}`;
    const conveyorKey = `${factory}|${alert.convoyeur}`;
    for (const uid of ids) {
      const entry = ensure(uid);
      entry.typeCounts[type] = (entry.typeCounts[type] || 0) + 1;
      entry.typeTotalTimes[type] = (entry.typeTotalTimes[type] || 0) + alert.elapsedTime;
      entry.stationCounts[stationKey] = (entry.stationCounts[stationKey] || 0) + 1;
      entry.conveyorCounts[conveyorKey] = (entry.conveyorCounts[conveyorKey] || 0) + 1;
    }
  }
  for (const id of Object.keys(stats)) {
    const s = stats[id];
    s.typeAvgRes = {};
    for (const type of Object.keys(s.typeTotalTimes)) {
      if (s.typeCounts[type] > 0) {
        s.typeAvgRes[type] = Math.round(s.typeTotalTimes[type] / s.typeCounts[type]);
      }
    }
  }
  return stats;
}

function scoreSupervisor(sup, alert, stats, feedbackSummary, recentAssignments, now, { isCommander = false, reinforcementAdjustment = 0 } = {}) {
  let score = 0;
  const reasons = [];
  const supFactory = aiSanitizeFactoryId(sup?.usine || sup?.factoryId || '');
  const alertFactory = aiSanitizeFactoryId(alert?.usine || alert?.factoryId || '');
  const supStats = stats[sup.uid] || {};
  const type = alert.type || '';
  const typeCount = supStats.typeCounts?.[type] || 0;

  if (alertFactory && supFactory && alertFactory === supFactory) {
    score += 30;
    reasons.push('Same factory (+30)');
  } else if (!isCommander) {
    // Under AI Shift Commander the cross-factory penalty is waived so that
    // experienced shift members from other factories can compete fairly.
    score -= 25;
    reasons.push('Different factory (−25)');
  }

  if (typeCount > 0) {
    const bonus = Math.min(typeCount * 4, 40);
    score += bonus;
    reasons.push(`${typeCount} past ${type} resolved (+${bonus})`);
  } else {
    reasons.push(`No prior ${type} experience`);
  }

  const avgTime = supStats.typeAvgRes?.[type];
  if (avgTime !== undefined && avgTime !== null) {
    const speedBonus = Math.min(Math.max(0, 60 - avgTime), 25);
    score += speedBonus;
    reasons.push(`Avg resolution ${Math.floor(avgTime)}min (+${Math.floor(speedBonus)})`);
  }

  const stationKey = `${alert.usine || ''}|${alert.convoyeur}|${alert.poste}`;
  const stationCount = supStats.stationCounts?.[stationKey] || 0;
  if (stationCount > 0) {
    const bonus = Math.min(stationCount * 6, 30);
    score += bonus;
    reasons.push(`${stationCount} fixes at workstation (+${bonus})`);
  }

  const convKey = `${alert.usine || ''}|${alert.convoyeur}`;
  const convCount = supStats.conveyorCounts?.[convKey] || 0;
  if (convCount > 0) {
    const bonus = Math.min(convCount * 1.5, 15);
    score += bonus;
    reasons.push(`${convCount} fixes on line (+${bonus})`);
  }

  if (!alert.isCritical && recentAssignments > 0) {
    const penalty = recentAssignments * 8;
    score -= penalty;
    reasons.push(`Recent load (−${penalty})`);
  }

  const fb = feedbackSummary[sup.uid] || {};
  const adjustment = Math.min(Math.max(
    (fb.acceptedAssignments || 0) * 2 +
    (fb.resolvedOutcomes || 0) * 3 -
    (fb.rejectedAssignments || 0) * 2 -
    (fb.abortedAssignments || 0) * 1.5,
    -20
  ), 20);
  if (adjustment !== 0) {
    score += adjustment;
    reasons.push(`Feedback adjustment (${adjustment > 0 ? '+' : ''}${adjustment})`);
  }

  // Reinforcement adjustment — same ±15% cap as the Dart AIScoringEngine.
  // Only apply if the base score is positive (to match Dart's maxAdj > 0 check).
  if (reinforcementAdjustment !== 0) {
    const raw = score;
    const maxAdj = raw * 0.15;
    if (maxAdj > 0) {
      const clamped = Math.max(-maxAdj, Math.min(maxAdj, reinforcementAdjustment));
      if (Math.abs(clamped) >= 0.01) {
        score += clamped;
        const rounded = Math.round(clamped);
        reasons.push(`Reinforcement adjustment (${rounded > 0 ? '+' : ''}${rounded})`);
      }
    }
  }

  return { score: Math.max(0, Math.round(score)), reasons };
}

// ============ Predictive model ============
const _PREDICTIVE_TYPES = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const _PREDICTIVE_HORIZON_DAYS = 180;
const _PREDICTIVE_HALFLIFE_DAYS = 14;
const _PREDICTIVE_DAY_MS = 24 * 60 * 60 * 1000;

function _predictiveDecay(ageDays, halflifeDays = _PREDICTIVE_HALFLIFE_DAYS) {
  if (!Number.isFinite(ageDays) || ageDays < 0) return 0;
  return Math.exp(-Math.log(2) * ageDays / halflifeDays);
}

function _predictiveEffectiveWindowDays(
  horizonDays = _PREDICTIVE_HORIZON_DAYS,
  halflifeDays = _PREDICTIVE_HALFLIFE_DAYS,
) {
  const decayRate = Math.LN2 / halflifeDays;
  return (1 - Math.exp(-decayRate * horizonDays)) / decayRate;
}

function _poissonAtLeastOne(lambda) {
  return lambda > 0 ? 1 - Math.exp(-lambda) : 0;
}

function buildPredictiveModel(alertsMap = {}) {
  const now = Date.now();
  const horizonMs = _PREDICTIVE_HORIZON_DAYS * _PREDICTIVE_DAY_MS;
  const effectiveWindowDays = _predictiveEffectiveWindowDays();
  const hodCounts = {};
  const dowCounts = {};
  const recentCounts = {};
  const sampleCounts = {};
  const machineHistory = {};
  const factoryRisk = {};

  for (const t of _PREDICTIVE_TYPES) {
    hodCounts[t] = new Array(24).fill(0);
    dowCounts[t] = new Array(7).fill(0);
    recentCounts[t] = 0;
    sampleCounts[t] = 0;
  }

  for (const [, a] of Object.entries(alertsMap || {})) {
    if (!a) continue;
    const tsMs = _toMs(a.timestamp);
    if (!tsMs || (now - tsMs) > horizonMs || tsMs > now) continue;
    const type = String(a.type || '');
    if (!_PREDICTIVE_TYPES.includes(type)) continue;

    const d = new Date(tsMs);
    const hod = d.getUTCHours();
    const dow = d.getUTCDay();
    const ageDays = (now - tsMs) / _PREDICTIVE_DAY_MS;
    const decay = _predictiveDecay(ageDays);
    hodCounts[type][hod] += decay;
    dowCounts[type][dow] += decay;
    recentCounts[type] += decay;
    sampleCounts[type]++;

    const factoryId = aiSanitizeFactoryId(a.usine || '');
    const conv = a.convoyeur ?? 0;
    const post = a.poste ?? 0;
    const mKey = `${factoryId}|${conv}|${post}|${type}`;
    if (!machineHistory[mKey]) {
      machineHistory[mKey] = {
        factoryId,
        usine: a.usine || '',
        convoyeur: conv,
        poste: post,
        type,
        score: 0,
        count: 0,
        lastTs: tsMs,
        firstTs: tsMs,
        critical: 0,
      };
    }
    const m = machineHistory[mKey];
    m.score += decay;
    m.count++;
    if (a.isCritical) m.critical++;
    if (tsMs > m.lastTs) m.lastTs = tsMs;
    if (tsMs < m.firstTs) m.firstTs = tsMs;
    if (!factoryRisk[factoryId]) factoryRisk[factoryId] = { name: a.usine || factoryId, score: 0, count: 0 };
    factoryRisk[factoryId].score += decay;
    factoryRisk[factoryId].count++;
  }

  const startHour = new Date(now).getUTCHours();
  const curves = {};
  for (const type of _PREDICTIVE_TYPES) {
    const buckets = [];
    let total = 0;
    for (let i = 0; i < 12; i++) {
      const h1 = (startHour + i * 2) % 24;
      const h2 = (startHour + i * 2 + 1) % 24;
      const cnt = hodCounts[type][h1] + hodCounts[type][h2];
      const lambda = cnt / effectiveWindowDays;
      const probability = _poissonAtLeastOne(lambda);
      total += probability;
      buckets.push({
        offsetHours: i * 2,
        startHour: h1,
        endHour: h2,
        probability: Number(probability.toFixed(4)),
        expected: Number(lambda.toFixed(4)),
      });
    }
    const weightedRecent = recentCounts[type];
    const dailyAvg = weightedRecent / effectiveWindowDays;
    const peak = buckets.reduce((p, c) => (c.probability > p.probability ? c : p), buckets[0]);
    curves[type] = {
      buckets,
      total24h: Number(_poissonAtLeastOne(dailyAvg).toFixed(4)),
      hourlyRate: Number((dailyAvg / 24).toFixed(4)),
      peakHour: peak.startHour,
      peakProbability: peak.probability,
      avgProbability: Number((total / 12).toFixed(4)),
      sampleSize: sampleCounts[type],
      weightedSampleSize: Number(weightedRecent.toFixed(4)),
      effectiveWindowDays: Number(effectiveWindowDays.toFixed(2)),
    };
  }

  const ranked = Object.values(machineHistory)
    .filter((m) => m.count >= 1)
    .sort((a, b) => b.score - a.score)
    .slice(0, 10);
  const maxScore = ranked[0]?.score || 1;
  const predictions = ranked.map((m) => {
    const ageDays = (now - m.lastTs) / 86400000;
    const span = Math.max(1, (m.lastTs - m.firstTs) / 86400000);
    const meanGap = m.count > 1 ? span / (m.count - 1) : null;
    const etaHours = meanGap !== null ? Math.max(0, (meanGap - ageDays) * 24) : null;
    const confidence = Math.min(96, Math.round((m.score / maxScore) * 88 + 8));
    return {
      factoryId: m.factoryId,
      usine: m.usine,
      convoyeur: m.convoyeur,
      poste: m.poste,
      type: m.type,
      confidence,
      pastCount: m.count,
      criticalCount: m.critical,
      lastTs: new Date(m.lastTs).toISOString(),
      etaHours: etaHours !== null ? Number(etaHours.toFixed(1)) : null,
      score: Number(m.score.toFixed(3)),
    };
  });

  const factoryRanked = Object.entries(factoryRisk)
    .map(([id, v]) => ({ id, name: v.name, score: Number(v.score.toFixed(3)), count: v.count }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 6);

  return {
    curves,
    predictions,
    factoryRisk: factoryRanked,
    generatedAt: new Date().toISOString(),
    horizonDays: _PREDICTIVE_HORIZON_DAYS,
    halflifeDays: _PREDICTIVE_HALFLIFE_DAYS,
  };
}

const _LSTM_ENDPOINT = 'https://kubixdesiney-alertsys-lstm.hf.space/predict';
const _LSTM_DAY_MS = 24 * 60 * 60 * 1000;
const _LSTM_TYPES = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const _LSTM_FEATURE_COLS = [
  'is_qualite',
  'is_maintenance',
  'is_defaut_produit',
  'is_manque_ressource',
  'critical_count',
  'days_since_failure',
  'hour',
  'dayofweek',
];

function _lstmUtcDayStartMs(tsMs) {
  const d = new Date(tsMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

function _lstmUtcDateKey(tsMs) {
  const d = new Date(tsMs);
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function _lstmDayOfWeek(tsMs) {
  // Mirror pandas dayofweek semantics: Monday=0, Sunday=6.
  return (new Date(tsMs).getUTCDay() + 6) % 7;
}

function _lstmMachineKey(machine) {
  const usine = String(machine?.usine || '').trim();
  const convoyeur = Number(machine?.convoyeur ?? 0);
  const poste = Number(machine?.poste ?? 0);
  return `${usine}|${convoyeur}|${poste}`;
}

function _buildDailyFeatures(alertsMap = {}) {
  const machines = {};

  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    const tsMs = _toMs(
      alert.timestamp ??
      alert.createdAt ??
      alert.created_at ??
      alert.date ??
      alert.ts,
    );
    if (tsMs == null) continue;

    const usine = String(alert.usine || alert.factoryId || '').trim();
    const convoyeur = Number(alert.convoyeur ?? 0);
    const poste = Number(alert.poste ?? 0);
    const machineKey = _lstmMachineKey({ usine, convoyeur, poste });
    const dayMs = _lstmUtcDayStartMs(tsMs);
    const dayKey = _lstmUtcDateKey(tsMs);
    const type = String(alert.type || '');

    if (!machines[machineKey]) {
      machines[machineKey] = {
        usine,
        convoyeur,
        poste,
        minDayMs: dayMs,
        maxDayMs: dayMs,
        days: {},
      };
    }
    const machine = machines[machineKey];
    if (dayMs < machine.minDayMs) machine.minDayMs = dayMs;
    if (dayMs > machine.maxDayMs) machine.maxDayMs = dayMs;

    if (!machine.days[dayKey]) {
      machine.days[dayKey] = {
        date: dayKey,
        dayMs,
        totalAlerts: 0,
        hourSum: 0,
        hourSamples: 0,
        is_qualite: 0,
        is_maintenance: 0,
        is_defaut_produit: 0,
        is_manque_ressource: 0,
        critical_count: 0,
      };
    }

    const day = machine.days[dayKey];
    if (_LSTM_TYPES.includes(type)) {
      day[`is_${type}`] += 1;
    }
    day.totalAlerts += 1;
    if (alert.isCritical === true) day.critical_count += 1;
    day.hourSum += new Date(tsMs).getUTCHours();
    day.hourSamples += 1;
  }

  const rows = [];
  for (const machine of Object.values(machines)) {
    let dayMs = machine.minDayMs;
    let lastFailureDayMs = null;

    while (dayMs <= machine.maxDayMs) {
      const dayKey = _lstmUtcDateKey(dayMs);
      const day = machine.days[dayKey];
      const hadFailure = (day?.totalAlerts || 0) > 0;

      if (hadFailure) lastFailureDayMs = dayMs;

      rows.push({
        usine: machine.usine,
        convoyeur: machine.convoyeur,
        poste: machine.poste,
        date: dayKey,
        is_qualite: day?.is_qualite || 0,
        is_maintenance: day?.is_maintenance || 0,
        is_defaut_produit: day?.is_defaut_produit || 0,
        is_manque_ressource: day?.is_manque_ressource || 0,
        critical_count: day?.critical_count || 0,
        days_since_failure: hadFailure || lastFailureDayMs == null
          ? 0
          : Math.round((dayMs - lastFailureDayMs) / _LSTM_DAY_MS),
        hour: hadFailure && (day?.hourSamples || 0) > 0
          ? Number((day.hourSum / day.hourSamples).toFixed(4))
          : 0,
        dayofweek: _lstmDayOfWeek(dayMs),
      });

      dayMs += _LSTM_DAY_MS;
    }
  }

  return rows;
}

function _fitGlobalScaler(dailyRows = [], featureCols = _LSTM_FEATURE_COLS) {
  const scaler = {};

  for (const col of featureCols) {
    scaler[col] = { min: Infinity, max: -Infinity };
  }

  for (const row of dailyRows || []) {
    for (const col of featureCols) {
      const value = Number(row?.[col]);
      if (!Number.isFinite(value)) continue;
      if (value < scaler[col].min) scaler[col].min = value;
      if (value > scaler[col].max) scaler[col].max = value;
    }
  }

  for (const col of featureCols) {
    if (!Number.isFinite(scaler[col].min) || !Number.isFinite(scaler[col].max)) {
      scaler[col] = { min: 0, max: 0 };
    }
  }

  return scaler;
}

function _scaleFeatures(featureRows = [], scaler = {}, featureCols = Object.keys(scaler || {})) {
  return (featureRows || []).map((row) => {
    const scaled = {};
    for (const col of featureCols) {
      const bounds = scaler[col] || { min: 0, max: 0 };
      const value = Number(row?.[col]);
      const safeValue = Number.isFinite(value) ? value : 0;
      scaled[col] = bounds.max === bounds.min
        ? 0.5
        : (safeValue - bounds.min) / (bounds.max - bounds.min);
    }
    return scaled;
  });
}

function _mergeLstmIntoPredictiveModel(model = {}, lstmPayload = null) {
  const predictions = Array.isArray(model?.predictions) ? model.predictions : [];
  const curves = model?.curves && typeof model.curves === 'object' ? model.curves : {};
  const lstmPredictions = Array.isArray(lstmPayload?.predictions)
    ? lstmPayload.predictions
    : Array.isArray(lstmPayload)
      ? lstmPayload
      : [];

  const byMachine = {};
  const curveAgg = {};
  for (const type of _LSTM_TYPES) {
    curveAgg[type] = [];
  }

  for (const pred of lstmPredictions) {
    const key = `${aiSanitizeFactoryId(pred?.factoryId || pred?.usine || '')}|${Number(pred?.convoyeur ?? 0)}|${Number(pred?.poste ?? 0)}`;
    byMachine[key] = pred;

    const probs = pred?.lstmProbs || {};
    for (const type of _LSTM_TYPES) {
      const value = Number(probs[type]);
      if (Number.isFinite(value)) curveAgg[type].push(value);
    }
  }

  const mergedPredictions = predictions.map((pred) => {
    const key = `${aiSanitizeFactoryId(pred?.factoryId || pred?.usine || '')}|${Number(pred?.convoyeur ?? 0)}|${Number(pred?.poste ?? 0)}`;
    const lstm = byMachine[key];
    if (!lstm) return pred;
    return {
      ...pred,
      lstmProbabilities: lstm.lstmProbs || {},
    };
  });

  const mergedCurves = {};
  for (const [type, curve] of Object.entries(curves)) {
    const values = curveAgg[type] || [];
    const avg = values.length > 0
      ? values.reduce((sum, value) => sum + value, 0) / values.length
      : null;
    const max = values.length > 0 ? Math.max(...values) : null;
    mergedCurves[type] = {
      ...curve,
      lstmProbabilities: values.length > 0
        ? {
            average: Number(avg.toFixed(4)),
            max: Number(max.toFixed(4)),
            sampleSize: values.length,
          }
        : null,
    };
  }

  return {
    ...model,
    curves: mergedCurves,
    predictions: mergedPredictions,
    lstmGeneratedAt: lstmPayload?.generatedAt || null,
  };
}

function _normalizeLstmProbabilityEntry(entry) {
  if (!entry || typeof entry !== 'object') return null;
  if (entry.probabilities && typeof entry.probabilities === 'object') {
    return entry.probabilities;
  }

  const direct = {};
  let found = false;
  for (const type of _LSTM_TYPES) {
    const value = Number(entry[type]);
    if (Number.isFinite(value)) {
      direct[type] = value;
      found = true;
    }
  }
  if (Array.isArray(entry.top)) direct.top = entry.top;
  return found ? direct : null;
}

async function _runLstmForecast(env, ctx) {
  const dailyRows = _buildDailyFeatures(ctx?.alertsMap || {});
  if (dailyRows.length === 0) return [];

  const scaler = _fitGlobalScaler(dailyRows, _LSTM_FEATURE_COLS);
  const grouped = {};
  for (const row of dailyRows) {
    const key = _lstmMachineKey(row);
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(row);
  }

  const machines = [];
  for (const rows of Object.values(grouped)) {
    rows.sort((a, b) => String(a.date).localeCompare(String(b.date)));
    if (rows.length < 14) continue;

    const windowRows = rows.slice(-14);
    const scaledWindow = _scaleFeatures(windowRows, scaler, _LSTM_FEATURE_COLS);
    machines.push({
      factoryId: aiSanitizeFactoryId(rows[0].usine || ''),
      usine: rows[0].usine,
      convoyeur: Number(rows[0].convoyeur ?? 0),
      poste: Number(rows[0].poste ?? 0),
      features: scaledWindow.map((row) => _LSTM_FEATURE_COLS.map((col) => Number(row[col] ?? 0))),
    });
  }

  if (machines.length === 0) return [];

  const generatedAt = new Date().toISOString();
  try {
    // The live HF endpoint accepts exactly one JSON key: `features`, shaped as
    // a 3D tensor [machineCount, 14, 8]. Alternate keys like `inputs` / `batch`
    // and 4D nesting are rejected. Successful responses now arrive as
    // `{ ok: true, predictions: [...] }`, where each prediction entry lines up
    // by index with the machine metadata we pushed into the batch tensor.
    const raw = await fetch(_LSTM_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        features: machines.map((machine) => machine.features),
      }),
    });
    if (!raw.ok) {
      console.error(`[LSTM] Forecast batch request failed: HTTP ${raw.status}`);
      return [];
    }

    const data = await raw.json();
    if (!data?.ok || !Array.isArray(data?.predictions)) {
      console.error('[LSTM] Invalid batch response payload');
      return [];
    }

    if (data.predictions.length !== machines.length) {
      console.warn(
        `[LSTM] Batch response length mismatch: predictions=${data.predictions.length}, machines=${machines.length}`,
      );
    }

    const limit = Math.min(data.predictions.length, machines.length);
    const predictions = [];
    for (let i = 0; i < limit; i++) {
      const probs = _normalizeLstmProbabilityEntry(data.predictions[i]);
      if (!probs) continue;
      predictions.push({
        factoryId: machines[i].factoryId,
        usine: machines[i].usine,
        convoyeur: machines[i].convoyeur,
        poste: machines[i].poste,
        lstmProbs: probs,
        generatedAt,
      });
    }
    return predictions;
  } catch (e) {
    console.error('[LSTM] Forecast batch request failed: ' + e.message);
    return [];
  }
}

// ============ FCM access token and send helper ============
async function getFcmAccessToken(env) {
  const now = Date.now();
  if (_fcmToken && now < _fcmTokenExpMs) return _fcmToken;
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const header = { alg: 'RS256', typ: 'JWT' };
  const nowSec = Math.floor(now / 1000);
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: nowSec + 3600,
    iat: nowSec,
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;
  const privateKey = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    privateKey,
    new TextEncoder().encode(signatureInput),
  );
  const jwt = `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) throw new Error(`FCM token failed: ${JSON.stringify(data)}`);
  const expiresIn = Number(data.expires_in || 3600);
  _fcmToken = data.access_token;
  _fcmTokenExpMs = now + Math.max(60, expiresIn - 60) * 1000;
  return _fcmToken;
}

function parseFcmFailure(status, text) {
  let errorCode = '';
  let message = text || '';
  try {
    const parsed = JSON.parse(text || '{}');
    const error = parsed?.error || {};
    message = error.message || message;
    errorCode = String(error.status || '');
    const detail = Array.isArray(error.details)
      ? error.details.find((d) => d && d.errorCode)
      : null;
    if (detail?.errorCode) errorCode = String(detail.errorCode);
  } catch (_) {
    errorCode = '';
  }
  const unregistered =
    status === 404 &&
    (errorCode === 'UNREGISTERED' ||
      errorCode === 'NOT_FOUND' ||
      /UNREGISTERED|Device unregistered/i.test(text || ''));
  return { errorCode, message, unregistered };
}

async function clearUnregisteredFcmToken(env, firebaseAuthToken, uid, staleToken) {
  if (!env?.FB_DB_URL || !firebaseAuthToken || !uid || !staleToken) return false;
  const tokenUrl = `${env.FB_DB_URL}users/${uid}/fcmToken.json?auth=${firebaseAuthToken}`;
  try {
    const currentRes = await fetch(tokenUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!currentRes.ok) return false;
    const etag = currentRes.headers.get('ETag');
    const current = await currentRes.json();
    if (current !== staleToken) return false;
    const clearRes = await fetch(tokenUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag ?? '*' },
      body: 'null',
    });
    return clearRes.ok;
  } catch (e) {
    console.warn('[FCM] Failed to clear unregistered token: ' + e.message);
    return false;
  }
}

async function sendFcmDetailed(token, title, body, data, env, options = {}) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          // Data-only message: no top-level "notification" field.
          // This guarantees firebaseMessagingBackgroundHandler is invoked even
          // when the app is terminated, so flutter_local_notifications can show
          // a fullScreenIntent notification that bypasses the Android lock screen.
          // Title/body are carried in the data map and read by the Flutter handler.
          data: { ...data, title, body },
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { 'content-available': 1 } },
          },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      const failure = parseFcmFailure(res.status, err);
      if (failure.unregistered) {
        const uid = String(options.uid || data?.recipientId || '').trim();
        console.warn(`[FCM] Dropping unregistered token${uid ? ` for ${uid}` : ''}`);
        await clearUnregisteredFcmToken(
          env,
          options.firebaseAuthToken,
          uid,
          token,
        );
      } else {
        console.error(`[FCM] Send failed (${res.status}):` + err);
      }
      return { ok: false, status: res.status, ...failure };
    }
    return { ok: true, status: res.status, errorCode: '', message: '', unregistered: false };
  } catch (e) {
    console.error('[FCM] Error:' + e.message);
    return { ok: false, status: 0, errorCode: 'EXCEPTION', message: e.message, unregistered: false };
  }
}

async function sendFcm(token, title, body, data, env, options = {}) {
  const result = await sendFcmDetailed(token, title, body, data, env, options);
  return result.ok;
}

// ============ Shift helpers ============
function _shiftContainsTime(shift, nowMin) {
  const s = Number(shift?.startMinutes ?? 0);
  const e = Number(shift?.endMinutes ?? 0);
  if (e >= s) return nowMin >= s && nowMin < e;
  return nowMin >= s || nowMin < e;
}

function pickActiveShift(shiftsMap, now = new Date()) {
  if (!shiftsMap) return null;
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  for (const [id, shift] of Object.entries(shiftsMap || {})) {
    if (!shift || typeof shift !== 'object') continue;
    if (_shiftContainsTime(shift, nowMin)) {
      return { id, ...shift };
    }
  }
  return null;
}

// ============ Core data loader ============
async function loadCoreData(env) {
  const token = await getFirebaseToken(env);
  const [alertsRes, usersRes, shiftsRes, factoriesRes, activeClaimsRes] = await Promise.all([
    fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}shifts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}factories.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}supervisor_active_alerts.json?auth=${token}`),
  ]);
  const shiftsMap = shiftsRes.ok ? ((await shiftsRes.json()) || {}) : {};
  return {
    token,
    alertsMap: alertsRes.ok ? ((await alertsRes.json()) || {}) : {},
    usersMap: usersRes.ok ? ((await usersRes.json()) || {}) : {},
    shiftsMap,
    factoriesMap: factoriesRes.ok ? ((await factoriesRes.json()) || {}) : {},
    supervisorActiveAlertsMap: activeClaimsRes.ok ? ((await activeClaimsRes.json()) || {}) : {},
    activeShift: pickActiveShift(shiftsMap, new Date()),
  };
}

// ============ FCM tokens ============
const NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES = new Set(['active', 'available', 'online', 'ready']);

function isActiveSupervisorForNotification(user) {
  const status = String(user?.status || '').toLowerCase();
  return NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES.has(status) ||
    user?.active === true ||
    user?.isActive === true;
}

function engagedSupervisorIds(alertsMap = {}, supervisorActiveAlertsMap = {}) {
  const ids = new Set();
  for (const a of Object.values(alertsMap || {})) {
    if (!a || a.status !== 'en_cours') continue;
    if (a.superviseurId) ids.add(String(a.superviseurId));
    if (a.assistantId) ids.add(String(a.assistantId));
  }

  for (const [uid, claim] of Object.entries(supervisorActiveAlertsMap || {})) {
    if (!claim) continue;
    const alertId =
      typeof claim === 'string'
        ? claim
        : String(claim.alertId || claim.id || '').trim();
    const alert = alertId ? alertsMap?.[alertId] : null;
    if (alert && alert.status === 'en_cours') ids.add(String(uid));
  }
  return ids;
}

function getFcmRecipientsForFactory(
  factoryName,
  usersMap,
  alertsMap,
  {
    allSupervisors = false,
    allFactories = false,
    includeAdmins = true,
    requireActiveSupervisors = false,
    supervisorActiveAlertsMap = {},
  } = {},
) {
  const targetId = aiSanitizeFactoryId(factoryName);
  const busySupervisors = allSupervisors
    ? new Set()
    : engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const recipientsByToken = new Map();
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (requireActiveSupervisors && !isActiveSupervisorForNotification(user)) continue;
      if (busySupervisors.has(uid)) continue;
      if (!allFactories) {
        const userFid = aiResolveFactory(user);
        if (userFid !== targetId) continue;
      }
    } else if (user.role !== 'admin') {
      continue;
    } else if (!includeAdmins) {
      continue;
    }
    const token = String(user.fcmToken);
    if (!recipientsByToken.has(token)) {
      recipientsByToken.set(token, { uid, token, role: String(user.role || '') });
    }
  }
  return [...recipientsByToken.values()];
}

function getFcmTokensForFactory(factoryName, usersMap, alertsMap, options = {}) {
  return getFcmRecipientsForFactory(factoryName, usersMap, alertsMap, options)
    .map((recipient) => recipient.token);
}

// Stable 31-bit notification ID derived from an alertId string.
// Same algorithm implemented in Dart (FcmService._alertNotifId) so both sides
// agree on the ID without sharing state across isolates.
function _alertNotifId(alertId) {
  let h = 0;
  for (let i = 0; i < alertId.length; i++) {
    h = (h * 31 + alertId.charCodeAt(i)) % 0x7FFFFFFF;
  }
  return h || 1;
}

function _pushLockIsFresh(alert) {
  if (!alert || alert.push_sending !== true) return false;
  const started = _toMs(alert.push_sending_at);
  return started != null && Date.now() - started < PUSH_LOCK_TTL_MS;
}

async function claimAlertPush(env, token, alertId) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return null;
  const etag = getRes.headers.get('ETag');
  const current = await getRes.json();
  if (!current || current.push_sent !== false || current.status !== 'disponible') return null;
  if (_pushLockIsFresh(current)) return null;

  const nowIso = new Date().toISOString();
  const claimRes = await fetch(alertUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': etag },
    body: JSON.stringify({
      ...current,
      push_sending: true,
      push_sending_at: nowIso,
    }),
  });
  if (claimRes.status === 412 || !claimRes.ok) return null;
  return { alertUrl, alert: { id: alertId, ...current } };
}

async function finishAlertPush(alertUrl, sent) {
  const nowIso = new Date().toISOString();
  await fetch(alertUrl, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(
      sent
        ? {
            push_sent: true,
            push_sent_at: nowIso,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: null,
          }
        : {
            push_sent: false,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: nowIso,
          },
    ),
  });
}

// ============ New‑alert FCM push ============
// ============ Escalation check ============
async function checkEscalations(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;
  const settingsRes = await fetch(`${env.FB_DB_URL}escalation_settings.json?auth=${token}`);
  if (!settingsRes.ok) {
    console.error('[ESCALATION] Failed to fetch escalation_settings');
    return;
  }
  const settings = await settingsRes.json();
  if (!settings || typeof settings !== 'object') {
    console.error('[ESCALATION] escalation_settings empty or invalid');
    return;
  }
  const now = Date.now();

  // Pre-filter to only active, unescalated alerts so the MAX_ESCALATION_CHECKS
  // budget is not consumed by already-handled entries.
  const candidates = Object.entries(alertsMap).filter(
    ([, a]) => a && !a.isEscalated && a.status !== 'validee' && a.status !== 'cancelled',
  );

  let escalated = 0;
  for (const [alertId, alert] of candidates) {
    if (escalated >= MAX_ESCALATION_CHECKS) break;
    try {
      let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
      if (!threshold && settings.default) threshold = settings.default;
      if (!threshold) continue;

      let createdAtMs;
      if (typeof alert.timestamp === 'number') {
        createdAtMs = alert.timestamp;
      } else if (typeof alert.timestamp === 'string') {
        const parsed = Date.parse(alert.timestamp);
        if (isNaN(parsed)) continue;
        createdAtMs = parsed;
      } else { continue; }

      let shouldEscalate = false;
      let reason = '';
      if (alert.status === 'disponible') {
        const mins = (now - createdAtMs) / 60000;
        if (typeof threshold.unclaimedMinutes === 'number' && mins >= threshold.unclaimedMinutes) {
          shouldEscalate = true;
          reason = `Unclaimed for ${Math.floor(mins)} minutes`;
        }
      } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
        let takenMs;
        if (typeof alert.takenAtTimestamp === 'number') {
          takenMs = alert.takenAtTimestamp;
        } else {
          const parsed = Date.parse(alert.takenAtTimestamp);
          if (isNaN(parsed)) continue;
          takenMs = parsed;
        }
        const mins = (now - takenMs) / 60000;
        if (typeof threshold.claimedMinutes === 'number' && mins >= threshold.claimedMinutes) {
          shouldEscalate = true;
          reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
        }
      } else { continue; }

      if (!shouldEscalate) continue;

      const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
      });
      if (!patchRes.ok) {
        console.error(`[ESCALATION] Failed to patch alert ${alertId}: ${patchRes.status}`);
        continue;
      }
      try {
        await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event: 'escalated_worker', reason, timestamp: new Date().toISOString() }),
        });
      } catch (e) { console.error('[ESCALATION] Failed to write aiHistory: ' + e.message); }

      const escalMsg  = `⚠️ Alert Escalated: ${alert.type}`;
      const escalBody = `${alert.usine} — ${alert.description}\n${reason}`;
      // Escalations deliberately bypass the new-alert gates. Busy, assisting,
      // and cross-factory active supervisors still receive escalation pushes.
      const escalData = {
        alertId,
        type:      alert.type || '',
        usine:     alert.usine || '',
        factoryId: String(alert.factoryId || ''),
        escalated: 'true',
        notifType: 'escalation',
      };
      const recipients = getFcmRecipientsForFactory(alert.factoryId || alert.usine || '', usersMap, alertsMap, {
        allSupervisors: true,
        allFactories: true,
        includeAdmins: true,
        requireActiveSupervisors: false,
      });
      const notifiedTokens = new Set();
      for (const recipient of recipients) {
        notifiedTokens.add(recipient.token);
        const result = await sendFcmDetailed(
          recipient.token,
          escalMsg,
          escalBody,
          { ...escalData, recipientId: recipient.uid },
          env,
          { firebaseAuthToken: token, uid: recipient.uid },
        );
        if (result.unregistered && usersMap?.[recipient.uid]?.fcmToken === recipient.token) {
          usersMap[recipient.uid].fcmToken = null;
        }
      }
      // Also notify the current claimant if their token is not already in the list.
      if (alert.status === 'en_cours' && alert.superviseurId) {
        const claimant = usersMap[alert.superviseurId];
        const claimantToken = claimant?.fcmToken;
        if (claimantToken && !notifiedTokens.has(claimantToken)) {
          await sendFcmDetailed(
            claimantToken,
            escalMsg,
            escalBody,
            { ...escalData, recipientId: alert.superviseurId },
            env,
            { firebaseAuthToken: token, uid: alert.superviseurId },
          );
        }
      }
      console.log(`[ESCALATION] Escalated alert ${alertId} (${alert.type}) reason=${reason}`);
      escalated++;
    } catch (e) {
      console.error('[ESCALATION] Error processing alert: ' + e.message);
    }
  }
}

// ============ Workers AI helpers ============
const _AI_FALLBACK = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';

const _TYPE_LABELS = {
  qualite: 'Quality',
  maintenance: 'Maintenance',
  defaut_produit: 'Damaged Product',
  manque_ressource: 'Resource Deficiency',
};

async function _runLlama(prompt, env) {
  if (!env.AI) return null;
  try {
    const resp = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
    });
    return (resp.response || '').trim() || null;
  } catch (e) {
    console.error('[AI] Llama run failed: ' + e.message);
    return null;
  }
}

// /ai-proxy – generic prompt relay (used by auto-fix features).
// Routed through the security guard: rate-limited, body-size-capped, and
// the `prompt` field is scanned for prompt-injection patterns before we
// hand it to Llama. A poisoned prompt is rejected with 400 instead of being
// forwarded.
async function handleAiProxy(request, env) {
  const guard = await _securityGuard(request, env, {
    endpoint: 'ai-proxy',
    requireBody: true,
    textFields: ['prompt'],
  });
  if (!guard.ok) return guard.response;

  try {
    const prompt = String(guard.body.prompt || '');
    const suggestion = await _runLlama(prompt, env) ?? _AI_FALLBACK;
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// /ai-suggest – context-aware alert resolution suggestion.
// Reads the last 10 resolved alerts at the same factory/conveyor/station/type
// from Firebase so Llama can learn from real past fixes.
// Security: the free-form `description` field is the prime injection vector
// since it comes from supervisor speech-to-text. The guard sanitizes it
// before it ever reaches the prompt template.
async function handleAiSuggest(request, env) {
  const guard = await _securityGuard(request, env, {
    endpoint: 'ai-suggest',
    requireBody: true,
    textFields: ['description', 'usine', 'type'],
  });
  if (!guard.ok) return guard.response;

  try {
    const { type, usine, convoyeur, poste, description } = guard.body;
    if (!type || !usine) {
      return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Fetch resolved alerts for this factory so we can extract past fixes.
    let pastResolutions = [];
    try {
      const token = await getFirebaseToken(env);
      const res = await fetch(
        `${env.FB_DB_URL}alerts.json?auth=${token}&orderBy="usine"&equalTo=${encodeURIComponent(usine)}`,
      );
      if (res.ok) {
        const data = (await res.json()) || {};
        pastResolutions = Object.values(data)
          .filter(
            (a) =>
              a &&
              a.status === 'validee' &&
              a.type === type &&
              Number(a.convoyeur) === Number(convoyeur) &&
              Number(a.poste) === Number(poste) &&
              a.resolutionReason,
          )
          .sort((a, b) => (String(b.resolvedAt || '') > String(a.resolvedAt || '') ? 1 : -1))
          .slice(0, 10)
          .map((a) => a.resolutionReason);
      }
    } catch (e) {
      console.error('[AI-SUGGEST] History fetch failed: ' + e.message);
    }

    const typeLabel = _TYPE_LABELS[type] || type;
    const historyBlock =
      pastResolutions.length > 0
        ? `Past resolutions for this exact location (most recent first):\n${pastResolutions.map((r) => `- ${r}`).join('\n')}`
        : 'No past resolutions on record for this specific location.';

    const prompt = `You are an industrial operations assistant. A supervisor needs a resolution suggestion.

Alert type: ${typeLabel}
Description: ${description}
Location: Factory: ${usine}, Conveyor line: ${convoyeur}, Workstation: #${poste}

${historyBlock}

Provide a concise, actionable resolution in 2-3 bullet points. Base it on the past fixes when available; otherwise suggest the most likely root cause and immediate action.`;

    const suggestion = await _runLlama(prompt, env) ?? _AI_FALLBACK;
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Predictions endpoint ============
// Firebase keys cannot contain '.', '#', '$', '[', ']', '/' — replace ':' and '.'
// in ISO timestamps so they survive as a valid path segment.
function _historyKey(iso) {
  return String(iso).replace(/[:.]/g, '-');
}

async function handlePredictions(request, env) {
  // /predict triggers a full alerts-history scan + predictive model build,
  // which is one of the more CPU-heavy paths in the worker. Rate-limit it
  // so an unauthenticated attacker cannot use it to burn our Worker quota.
  const guard = await _securityGuard(request, env, { endpoint: 'predict' });
  if (!guard.ok) return guard.response;

  try {
    const url = new URL(request.url);
    const factoryParamRaw = url.searchParams.get('factory') || null;
    const factoryParam = factoryParamRaw
      ? _securitySanitizeText(factoryParamRaw, 128)
      : null;
    const factorySlug = factoryParam ? _briefingFactorySlug(factoryParam) : null;

    const coreCtx = await loadCoreData(env);
    const scopedAlertsMap = _filterAlertsMapByFactorySlug(
      coreCtx.alertsMap || {},
      factorySlug,
    );
    const model = buildPredictiveModel(scopedAlertsMap);
    const payload = factoryParam ? { ...model, factoryScope: factoryParam } : model;
    // Snapshot to history first (fire-and-forget) so we never lose it even if
    // the latest write somehow fails afterwards.
    const histKey = _historyKey(model.generatedAt);
    const latestPath = factorySlug
      ? `ai_predictions/factory/${factorySlug}/latest.json`
      : 'ai_predictions/latest.json';
    const historyPath = factorySlug
      ? `ai_predictions/factory/${factorySlug}/history/${histKey}.json`
      : `ai_predictions/history/${histKey}.json`;
    fetch(`${env.FB_DB_URL}${historyPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, validated: false }),
    }).catch(() => {});
    await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Predictive validation ============
const MIN_VALIDATION_AGE_HOURS = 24;
const DEFAULT_VALIDATION_WINDOW_HOURS = 24;
const MAX_VALIDATION_PER_RUN = 10;

// Cross-references each historical prediction snapshot against alerts created
// during its validation window to compute hit rate (TP / total predicted).
// Snapshots already marked validated=true are skipped. Updates each snapshot
// in place with a `validation` sub-object and writes a rolling aggregate to
// ai_predictions/performance/latest.
async function validatePredictions(env, ctx) {
  const token = ctx?.token ?? (await getFirebaseToken(env));
  let alertsMap = ctx?.alertsMap;
  if (!alertsMap) {
    try {
      const ar = await fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`);
      alertsMap = ar.ok ? ((await ar.json()) || {}) : {};
    } catch (_) { alertsMap = {}; }
  }

  let history = {};
  try {
    const hr = await fetch(`${env.FB_DB_URL}ai_predictions/history.json?auth=${token}`);
    if (hr.ok) history = (await hr.json()) || {};
  } catch (e) {
    console.error('[VALIDATE] Failed to fetch history: ' + e.message);
    return 0;
  }
  if (!history || typeof history !== 'object') return 0;

  const nowMs = Date.now();
  const minAgeMs = MIN_VALIDATION_AGE_HOURS * 60 * 60 * 1000;

  // Pre-compute a lookup of alerts by location+type for fast TP scoring.
  const alertIndex = {}; // key → list of {tsMs}
  for (const [, a] of Object.entries(alertsMap || {})) {
    if (!a) continue;
    const ts = _toMs(a.timestamp);
    if (ts == null) continue;
    const fid = aiSanitizeFactoryId(a.usine || a.factoryId || '');
    const conv = a.convoyeur ?? 0;
    const post = a.poste ?? 0;
    const type = String(a.type || '');
    const k = `${fid}|${conv}|${post}|${type}`;
    if (!alertIndex[k]) alertIndex[k] = [];
    alertIndex[k].push(ts);
  }

  // Eligible snapshots: not yet validated, generatedAt at least 24h old.
  const candidates = [];
  for (const [snapKey, snap] of Object.entries(history)) {
    if (!snap || typeof snap !== 'object') continue;
    if (snap.validated === true) continue;
    const genMs = _toMs(snap.generatedAt);
    if (genMs == null) continue;
    if (nowMs - genMs < minAgeMs) continue;
    candidates.push([genMs, snapKey, snap]);
  }
  candidates.sort((a, b) => a[0] - b[0]); // oldest-first

  let processed = 0;
  for (const [genMs, snapKey, snap] of candidates) {
    if (processed >= MAX_VALIDATION_PER_RUN) break;
    try {
      const preds = Array.isArray(snap.predictions) ? snap.predictions : [];
      const totalPredicted = preds.length;

      // Window = max ETA across predictions, defaulted to 24h.
      let windowHours = DEFAULT_VALIDATION_WINDOW_HOURS;
      for (const p of preds) {
        const eta = Number(p?.etaHours);
        if (Number.isFinite(eta) && eta > windowHours) windowHours = eta;
      }
      const windowMs = windowHours * 60 * 60 * 1000;
      const winStart = genMs;
      const winEnd = genMs + windowMs;

      let truePositives = 0;
      for (const p of preds) {
        const fid = aiSanitizeFactoryId(p?.factoryId || p?.usine || '');
        const conv = p?.convoyeur ?? 0;
        const post = p?.poste ?? 0;
        const type = String(p?.type || '');
        const k = `${fid}|${conv}|${post}|${type}`;
        const matches = alertIndex[k] || [];
        const hit = matches.some((ts) => ts >= winStart && ts <= winEnd);
        if (hit) truePositives++;
      }
      const accuracy = totalPredicted > 0 ? truePositives / totalPredicted : 0;
      const validatedAt = new Date().toISOString();

      // Patch snapshot in place.
      await fetch(`${env.FB_DB_URL}ai_predictions/history/${snapKey}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          validated: true,
          validation: {
            totalPredicted,
            truePositives,
            accuracy: Number(accuracy.toFixed(4)),
            validatedAt,
          },
        }),
      }).catch((e) => console.error('[VALIDATE] PATCH failed: ' + e.message));

      processed++;
    } catch (e) {
      console.error('[VALIDATE] Snapshot ' + snapKey + ' failed: ' + e.message);
    }
  }

  // Aggregate macro-average across all validated snapshots (after this pass).
  try {
    const hr2 = await fetch(`${env.FB_DB_URL}ai_predictions/history.json?auth=${token}`);
    if (hr2.ok) {
      const allHist = (await hr2.json()) || {};
      let totalSnapshots = 0;
      let accSum = 0;
      let lastValidatedUtc = null;
      for (const snap of Object.values(allHist)) {
        if (!snap || snap.validated !== true || !snap.validation) continue;
        const acc = Number(snap.validation.accuracy);
        if (!Number.isFinite(acc)) continue;
        totalSnapshots++;
        accSum += acc;
        const v = String(snap.validation.validatedAt || '');
        if (!lastValidatedUtc || v > lastValidatedUtc) lastValidatedUtc = v;
      }
      const averageAccuracy = totalSnapshots > 0 ? accSum / totalSnapshots : 0;
      await fetch(`${env.FB_DB_URL}ai_predictions/performance/latest.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          totalSnapshots,
          averageAccuracy: Number(averageAccuracy.toFixed(4)),
          lastValidatedUtc,
        }),
      }).catch(() => {});
    }
  } catch (e) {
    console.error('[VALIDATE] Aggregate failed: ' + e.message);
  }

  return processed;
}

async function handleValidatePredictions(request, env) {
  // Validation walks the entire history node and the entire alerts map,
  // matching them in O(n·m). The strictest rate limit in the policy sits
  // on this endpoint for that reason.
  const guard = await _securityGuard(request, env, {
    endpoint: 'validate-predictions',
  });
  if (!guard.ok) return guard.response;

  try {
    const processed = await validatePredictions(env, null);
    return new Response(JSON.stringify({ ok: true, processed }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Briefing endpoint (Llama 3.2 via Workers AI) ============
async function handleBriefing(request, env) {
  // Briefing is a GET endpoint, but we still rate-limit it: an attacker can
  // spam ?force=1 to force expensive Llama runs. No body to scan.
  const guard = await _securityGuard(request, env, { endpoint: 'briefing' });
  if (!guard.ok) return guard.response;

  try {
    const url = new URL(request.url);
    const force = url.searchParams.get('force') === '1';
    // Optional factory scope — when set the briefing covers only that plant.
    // We sanitize the factory name so a crafted query-string cannot leak
    // through into the Llama prompt template.
    const factoryParamRaw = url.searchParams.get('factory') || null;
    const factoryParam = factoryParamRaw
      ? _securitySanitizeText(factoryParamRaw, 128)
      : null;
    const factorySlug = factoryParam ? _briefingFactorySlug(factoryParam) : null;

    const coreCtx = await loadCoreData(env);
    const today = _briefingDateKey(new Date());

    // Factory-scoped briefings are stored under a sub-path; global ones at root.
    const latestPath = factorySlug
      ? `ai_briefing/factory/${factorySlug}/latest.json`
      : 'ai_briefing/latest.json';
    const historyPath = factorySlug
      ? `ai_briefing/factory/${factorySlug}/history/${today}.json`
      : `ai_briefing/history/${today}.json`;

    if (!force) {
      const existing = await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`);
      if (existing.ok) {
        const data = await existing.json();
        if (data?.date === today) {
          return new Response(JSON.stringify(data), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
      }
    }

    const stats = _aggregateWeek(coreCtx.alertsMap || {}, factoryParam);
    const topType = Object.entries(stats.byType || {}).sort((a, b) => b[1] - a[1])[0];
    const topFactory = Object.entries(stats.byFactory || {}).sort((a, b) => b[1] - a[1])[0];
    const resolutionRate = stats.total > 0 ? Math.round((stats.solved / stats.total) * 100) : 0;

    // --- Predictive accuracy & top prediction for this factory ---
    let accuracyPct = null;
    let predictiveInsight = null;
    try {
      const [accRes, predRes] = await Promise.all([
        fetch(`${env.FB_DB_URL}ai_predictions/performance/latest.json?auth=${coreCtx.token}`),
        fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`),
      ]);
      if (accRes.ok) {
        const accData = await accRes.json();
        if (accData?.averageAccuracy != null && accData?.totalSnapshots > 0) {
          accuracyPct = Math.round(accData.averageAccuracy * 100);
        }
      }
      if (predRes.ok) {
        const predData = await predRes.json();
        const preds = Array.isArray(predData?.predictions) ? predData.predictions : [];
        // Pick highest-confidence prediction scoped to factory (or global top if no factory).
        const scopedPreds = factoryParam
          ? preds.filter(p => String(p?.usine || '') === factoryParam)
          : preds;
        scopedPreds.sort((a, b) => (b.confidence || 0) - (a.confidence || 0));
        if (scopedPreds.length > 0) {
          const top = scopedPreds[0];
          predictiveInsight = {
            type: top.type || null,
            convoyeur: top.convoyeur ?? null,
            confidence: top.confidence ?? null,
          };
        }
      }
    } catch (e) {
      console.warn('[BRIEFING] Predictive fetch failed: ' + e.message);
    }

    // --- Top performing supervisor this week ---
    const topSup = _topSupervisorWeek(coreCtx.alertsMap || {}, coreCtx.usersMap || {}, factoryParam);

    // --- Build AI prompt ---
    const factoryLine = factoryParam ? `\n- Plant scope: ${factoryParam}` : '';
    const accuracyLine = accuracyPct != null ? `\n- AI predictive model accuracy (validated): ${accuracyPct}%` : '';
    const predLine = predictiveInsight?.type
      ? `\n- AI expects a possible ${_typeName(predictiveInsight.type)} issue${predictiveInsight.convoyeur != null ? ` on Line ${predictiveInsight.convoyeur}` : ''} today (confidence: ${predictiveInsight.confidence ?? '?'}%)`
      : '';
    const supLine = topSup
      ? `\n- Top supervisor this week: ${topSup.name} resolved ${topSup.count} alerts${topSup.topType ? ` (fastest for ${_typeName(topSup.topType)} issues)` : ''}`
      : '';

    const prompt = `You are an industrial operations briefing officer addressing the production manager at the start of the day. Write a single, warm, concise paragraph (3 to 4 sentences, no bullets, no headers, no markdown, no lists). Use these facts from the past 7 days:${factoryLine}
- Total alerts: ${stats.total}
- Resolved: ${stats.solved} (${resolutionRate}% resolution rate)
- Critical alerts: ${stats.critical}
- Currently claimed: ${stats.inProgress}, pending: ${stats.pending}
- Average resolution time: ${stats.avgResolutionMin} minutes
- Fastest fix: ${stats.fastestMin ?? 'n/a'} min · slowest: ${stats.slowestMin ?? 'n/a'} min
- Most frequent alert type: ${topType ? `${_typeName(topType[0])} (${topType[1]})` : 'none'}
- Most active site: ${topFactory ? `${topFactory[0]} (${topFactory[1]})` : 'none'}
- AI auto-assignments: ${stats.aiAssigned}${accuracyLine}${predLine}${supLine}

Begin with "Good morning". Acknowledge what is going well, name the top supervisor by name if present, weave in the AI prediction if present, and close with a forward-looking sentence about today. Sound calm, professional, and human — not a press release.`;

    let summary = `Good morning. Last week the team handled ${stats.total} alerts with a ${resolutionRate}% resolution rate and an average response of ${stats.avgResolutionMin} minutes. Stay sharp on critical signals today.`;
    let model = 'fallback';
    try {
      if (env.AI) {
        const resp = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
          messages: [{ role: 'user', content: prompt }],
        });
        const out = (resp.response || '').trim();
        if (out) {
          summary = out;
          model = '@cf/meta/llama-3.2-3b-instruct';
        }
      }
    } catch (e) {
      console.error('[BRIEFING] AI failed: ' + e.message);
    }

    const payload = {
      date: today,
      summary,
      generatedAt: new Date().toISOString(),
      model,
      stats,
      topType: topType ? { type: topType[0], count: topType[1] } : null,
      topFactory: topFactory ? { name: topFactory[0], count: topFactory[1] } : null,
      resolutionRate,
      factoryScope: factoryParam || null,
      accuracyPct,
      predictiveInsight,
      topSupervisor: topSup,
    };

    await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    await fetch(`${env.FB_DB_URL}${historyPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Auto‑fix endpoints ============
// Both auto-fix endpoints accept arbitrary code and arbitrary error text
// from the caller and forward them to Llama. The guard rate-limits hits
// (this is the most expensive endpoint family) and scans both fields for
// prompt-injection markers. Code that contains the injection patterns is
// blocked — by design — so an attacker cannot smuggle "ignore previous
// instructions" through a `code` payload.
async function handleAutoFix(request, env) {
  const guard = await _securityGuard(request, env, {
    endpoint: 'auto-fix',
    requireBody: true,
    textFields: ['code', 'errors'],
    maxTextLen: 32 * 1024,
  });
  if (!guard.ok) return guard.response;

  try {
    const { code = '', errors = '' } = guard.body;
    const prompt =
      'Fix this Dart/Flutter code using the error list. Return only the fixed source code.\n\n' +
      `Errors:\n${errors}\n\nCode:\n${code}`;
    const suggestion = await _runLlama(prompt, env) ?? '';
    return new Response(JSON.stringify({ fixedCode: suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedCode: '', error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

async function handleAutoFixFull(request, env) {
  const guard = await _securityGuard(request, env, {
    endpoint: 'auto-fix-full',
    requireBody: true,
    textFields: ['errors'],
  });
  if (!guard.ok) return guard.response;

  try {
    const { files = [], errors = '' } = guard.body;
    // We also sweep file content for injection markers — same policy as
    // single-file auto-fix, but applied to every file in the bundle.
    const safeFiles = Array.isArray(files) ? files : [];
    for (const f of safeFiles) {
      if (!f || typeof f !== 'object') continue;
      const content = String(f.content || '');
      const det = _securityDetectPromptInjection(content);
      if (det.hit) {
        await _securityRecordAction(env, {
          kind: 'prompt_injection_block',
          endpoint: 'auto-fix-full',
          field: 'files[].content',
          path: String(f.path || ''),
          matches: det.matches,
        });
        return new Response(
          JSON.stringify({
            fixedFiles: [],
            error: 'input_blocked_by_security',
          }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }
      f.content = _securitySanitizeText(content, 32 * 1024);
      f.path = _securitySanitizeText(String(f.path || ''), 256);
    }

    const combined = safeFiles
      .map((f) => `=== ${f?.path || 'file'} ===\n${f?.content || ''}`)
      .join('\n\n');
    const prompt =
      'Fix the provided project files based on the errors. Return only a JSON array of objects with path and content.\n\n' +
      `Errors:\n${errors}\n\nFiles:\n${combined}`;
    const raw = await _runLlama(prompt, env) ?? '[]';
    let fixedFiles = [];
    try {
      fixedFiles = JSON.parse(raw);
      if (!Array.isArray(fixedFiles)) fixedFiles = [];
    } catch (_) {
      fixedFiles = [];
    }
    return new Response(JSON.stringify({ fixedFiles }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedFiles: [], error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Fan‑out notifications ============
// Notification types that are always delivered regardless of whether the
// recipient supervisor is currently busy with another alert.
const COLLAB_NOTIF_TYPES = new Set([
  'collaboration_request',
  'collaboration_assistant_accepted',
  'collaboration_assistant_removed',
  'collaboration_removed',
  'collaboration_approved',
  'collaboration_rejected',
  'collaboration_refused',
  'collaboration_request_admin',
  'assistant_assigned',
  'collab_auto_approved',
  'cross_factory_transfer',
  // Help and assistance requests must also bypass the busy filter — a supervisor
  // needs to know someone is asking for help even if they are occupied.
  'help_request',
  'assistance_request',
  'alert_critical_update',
]);

const ADMIN_ONLY_NOTIF_TYPES = new Set([
  'ai_cross_factory_recommendation',
  'ai_rejection',
  'alert_suspended',
  'collaboration_request_admin',
]);

function notificationTargetFactory(notif, alertsMap = {}) {
  const directFactory =
    notif?.usine || notif?.alertUsine || notif?.factoryName || notif?.factoryId || '';
  if (String(directFactory || '').trim()) {
    return aiSanitizeFactoryId(directFactory);
  }
  const alertId = String(notif?.alertId || '').trim();
  if (!alertId) return null;
  return aiResolveFactory(alertsMap?.[alertId] || null);
}

function notifTitle(type) {
  switch (String(type || '')) {
    case 'ai_assigned': return 'AI Assignment';
    case 'collaboration_request': return 'Collaboration request';
    case 'collaboration_assistant_accepted':
    case 'collaboration_assistant_removed':
    case 'collaboration_removed':
    case 'collaboration_approved':
    case 'collaboration_rejected':
    case 'collaboration_refused':
    case 'collab_auto_approved': return 'Collaboration update';
    case 'assistant_assigned': return 'Assistant assigned';
    case 'cross_factory_transfer': return 'Cross-factory transfer';
    case 'help_request':
    case 'assistance_request': return 'Help request';
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'AlertSys';
  }
}
// ============ AI Assignment Engine (FULL SCORING) ============
const AI_COOLDOWN_MS = 10 * 60 * 1000;
const AI_ACTIVE_STATUSES = new Set(['active', 'available']);
const CROSS_FACTORY_CRITICAL_THRESHOLD = 2;
const DONOR_MAX_ACTIVE_ALERTS = 2;
const MAX_LOCATION_AGE_MS = 10 * 60 * 1000;

function aiSanitizeFactoryId(input) {
  return String(input || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function aiResolveFactory(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const fid = String(obj.factoryId || '').trim();
  if (fid) return aiSanitizeFactoryId(fid);
  const usine = String(obj.usine || '').trim();
  return usine ? aiSanitizeFactoryId(usine) : null;
}

// ============ Proximity Helpers ============
function _parseLatLng(value) {
  if (!value || typeof value !== 'object') return null;
  const lat = Number(value.lat ?? value.latitude);
  const lng = Number(value.lng ?? value.lon ?? value.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
}

function _freshLatLng(value, maxAgeMs, now = Date.now()) {
  const point = _parseLatLng(value);
  if (!point) return null;
  const updatedAt = _toMs(value.updatedAt ?? value.timestamp ?? value.at);
  if (updatedAt == null || now - updatedAt > maxAgeMs) return null;
  return { ...point, updatedAt };
}

function _factoryLookup(factoriesMap = {}, factoryId = '') {
  const wanted = aiSanitizeFactoryId(factoryId);
  if (!wanted || !factoriesMap || typeof factoriesMap !== 'object') return null;
  if (factoriesMap[factoryId]) return factoriesMap[factoryId];
  if (factoriesMap[wanted]) return factoriesMap[wanted];
  for (const [key, value] of Object.entries(factoriesMap)) {
    if (aiSanitizeFactoryId(key) === wanted) return value;
    if (value && typeof value === 'object' && aiResolveFactory(value) === wanted) {
      return value;
    }
  }
  return null;
}

function _factoriesFromUsersMap(usersMap = {}) {
  return usersMap.__factoriesMap || usersMap.__factories || usersMap.factoriesMap || usersMap.factories || {};
}

function _usersMapWithFactories(usersMap = {}, factoriesMap = {}) {
  if (!factoriesMap || typeof factoriesMap !== 'object' || Object.keys(factoriesMap).length === 0) {
    return usersMap || {};
  }
  const enriched = { ...(usersMap || {}) };
  Object.defineProperty(enriched, '__factoriesMap', {
    value: factoriesMap,
    enumerable: false,
    configurable: true,
  });
  return enriched;
}

function inferFactoryLocation(usersMap = {}, factoryId, maxAgeMs) {
  const targetFactory = aiSanitizeFactoryId(factoryId);
  const freshPoints = [];
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (String(uid || '').startsWith('__')) continue;
    if (!user || typeof user !== 'object' || user.role !== 'supervisor') continue;
    if (aiResolveFactory(user) !== targetFactory) continue;
    const point = _freshLatLng(user.currentLocation, maxAgeMs);
    if (point) freshPoints.push(point);
  }

  if (freshPoints.length > 0) {
    const total = freshPoints.reduce(
      (acc, point) => ({ lat: acc.lat + point.lat, lng: acc.lng + point.lng }),
      { lat: 0, lng: 0 },
    );
    return {
      lat: total.lat / freshPoints.length,
      lng: total.lng / freshPoints.length,
      source: 'supervisor_average',
      count: freshPoints.length,
    };
  }

  const factory = _factoryLookup(_factoriesFromUsersMap(usersMap), targetFactory);
  const staticPoint = _parseLatLng(factory?.location);
  return staticPoint ? { ...staticPoint, source: 'factory_static', count: 0 } : null;
}

function haversineDistance(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (Number(deg) * Math.PI) / 180;
  const p1 = toRad(lat1);
  const p2 = toRad(lat2);
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(p1) * Math.cos(p2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function _isActiveAlert(alert) {
  const status = String(alert?.status || '').toLowerCase();
  return status === 'disponible' || status === 'en_cours';
}

function _isUnclaimedCriticalAlert(alert) {
  const status = String(alert?.status || '').toLowerCase();
  return status === 'disponible' && alert?.isCritical === true && !alert?.superviseurId;
}

function _factoryAlertCounts(alertsMap = {}, factoryId = '') {
  const targetFactory = aiSanitizeFactoryId(factoryId);
  let criticalUnclaimed = 0;
  let activeCritical = 0;
  let activeTotal = 0;
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    if (aiResolveFactory(alert) !== targetFactory) continue;
    if (_isUnclaimedCriticalAlert(alert)) criticalUnclaimed++;
    if (_isActiveAlert(alert)) {
      activeTotal++;
      if (alert.isCritical === true) activeCritical++;
    }
  }
  return { criticalUnclaimed, activeCritical, activeTotal };
}

function _activeSupervisorCount(usersMap = {}, factoryId = '', { excludeUid = null } = {}) {
  const targetFactory = aiSanitizeFactoryId(factoryId);
  let count = 0;
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (String(uid || '').startsWith('__')) continue;
    if (!user || user.role !== 'supervisor') continue;
    if (excludeUid && uid === excludeUid) continue;
    if (!AI_ACTIVE_STATUSES.has(String(user.status || '').toLowerCase())) continue;
    if (aiResolveFactory(user) === targetFactory) count++;
  }
  return count;
}

function _crossFactoryGate1(alertsMap = {}, usersMap = {}, factoryId = '') {
  const counts = _factoryAlertCounts(alertsMap, factoryId);
  const activeSupervisors = _activeSupervisorCount(usersMap, factoryId);
  const allowed =
    counts.criticalUnclaimed >= CROSS_FACTORY_CRITICAL_THRESHOLD &&
    activeSupervisors < counts.criticalUnclaimed;
  return {
    allowed,
    details: {
      alertFactory: factoryId,
      criticalUnclaimedAlerts: counts.criticalUnclaimed,
      activeSupervisors,
      threshold: CROSS_FACTORY_CRITICAL_THRESHOLD,
    },
  };
}

function _crossFactoryGate2(alertsMap = {}, usersMap = {}, candidate = {}) {
  const donorFactory = candidate.factoryId || aiResolveFactory(candidate);
  const counts = _factoryAlertCounts(alertsMap, donorFactory);
  const remainingActiveSupervisors = _activeSupervisorCount(usersMap, donorFactory, {
    excludeUid: candidate.uid,
  });
  const allowed =
    counts.activeCritical === 0 &&
    counts.activeTotal <= DONOR_MAX_ACTIVE_ALERTS &&
    remainingActiveSupervisors >= 1;
  return {
    allowed,
    details: {
      supervisorId: candidate.uid || null,
      donorFactory,
      donorCriticalAlerts: counts.activeCritical,
      donorActiveAlerts: counts.activeTotal,
      donorMaxActiveAlerts: DONOR_MAX_ACTIVE_ALERTS,
      donorActiveSupervisorsAfterTransfer: remainingActiveSupervisors,
    },
  };
}

async function aiAssignAlert(alertId, supervisor, reasonSummary, confidence, env, token, allCandidates = []) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  // Deterministic idempotency key — stable for a given alert+supervisor within the same minute.
  const actionId = `worker_${alertId}_${Math.floor(Date.now() / 60000)}`;

  // Skip if this exact action was already persisted this minute (duplicate cron tick guard).
  try {
    const existingRes = await fetch(`${env.FB_DB_URL}ai_decisions/${alertId}/actionId.json?auth=${token}`);
    if (existingRes.ok) {
      const existingId = await existingRes.json();
      if (existingId === actionId) {
        console.log(`[AI-ASSIGN] Idempotency skip: ${actionId} already recorded`);
        return false;
      }
    }
  } catch (_) { /* non-fatal — proceed */ }

  // Retry loop: attempt the ETag-guarded PUT up to twice.
  // On a 412 (concurrent write) we re-fetch a fresh ETag and try once more.
  for (let attempt = 1; attempt <= 2; attempt++) {
    const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) return false;
    const etag = getRes.headers.get('ETag');
    const current = await getRes.json();
    if (!current || current.status !== 'disponible' || current.superviseurId) return false;

    const nowIso = new Date().toISOString();
    const putRes = await fetch(alertUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag },
      body: JSON.stringify({
        ...current,
        status: 'en_cours',
        superviseurId: supervisor.uid,
        superviseurName: supervisor.name,
        takenAtTimestamp: nowIso,
        aiAssigned: true,
        aiAssignmentReason: reasonSummary,
        aiConfidence: confidence,
        aiAssignedAt: nowIso,
        push_sent: true,
      }),
    });

    if (putRes.status === 412) {
      console.log(`[AI-ASSIGN] ETag mismatch attempt ${attempt} for alert ${alertId}`);
      if (attempt < 2) continue; // re-fetch and retry once
      return false;
    }
    if (!putRes.ok) return false;

    // Assignment succeeded — persist side-effects fire-and-forget.
    const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();
    await Promise.allSettled([
      fetch(`${env.FB_DB_URL}users/${supervisor.uid}/aiCooldownUntil.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(cooldownUntil),
      }),
      fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          event: 'assigned_worker',
          supervisorId: supervisor.uid,
          supervisorName: supervisor.name,
          reason: reasonSummary,
          confidence,
          actionId,
          timestamp: nowIso,
        }),
      }),
      fetch(`${env.FB_DB_URL}ai_decisions/${alertId}.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          alertId,
          assignedTo: supervisor.uid,
          assignedToName: supervisor.name,
          confidence,
          reasonSummary,
          breakdown: supervisor.reasons || [],
          decisionMode: 'worker_auto',
          actionId,
          timestamp: nowIso,
          // Full candidate list so the app can show "why not others".
          consideredCandidates: allCandidates.map((c) => ({
            supervisorId: c.uid,
            name: c.name,
            score: c.score,
            reasons: c.reasons || [],
            distanceKm: c.distanceKm ?? null,
            skipReason: c.skipReason ?? null,
          })),
        }),
      }),
    ]);

    let transferNotificationId = null;
    if (supervisor.crossFactoryTransfer) {
      const alertFactory = supervisor.alertFactoryName || current.usine || '';
      const donorFactory = supervisor.donorFactoryName || supervisor.factoryName || supervisor.factoryId || '';
      const distanceText =
        typeof supervisor.distanceKm === 'number'
          ? ` (${supervisor.distanceKm.toFixed(1)} km away)`
          : '';
      const transferMessage =
        `You are being transferred from ${donorFactory || 'your factory'} ` +
        `to ${alertFactory || 'another factory'} for ${current.type || 'an alert'}${distanceText}.`;
      try {
        const notifRes = await fetch(`${env.FB_DB_URL}notifications/${supervisor.uid}.json?auth=${token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            type: 'cross_factory_transfer',
            alertId: String(alertId),
            alertType: current.type || 'alert',
            alertDescription: current.description || '',
            alertFactory,
            donorFactory,
            distanceKm: supervisor.distanceKm ?? null,
            message: transferMessage,
            timestamp: nowIso,
            status: 'pending',
            buzz: true,
            pushSent: false,
          }),
        });
        if (notifRes.ok) {
          const notifData = await notifRes.json().catch(() => null);
          transferNotificationId = notifData?.name || null;
        }
      } catch (e) {
        console.error('[AI-ASSIGN] Cross-factory notification write failed: ' + e.message);
      }
    }

    if (supervisor.fcmToken) {
      const isTransfer = supervisor.crossFactoryTransfer === true;
      const fcmTitle = isTransfer ? 'Cross-factory transfer' : 'AI Assignment';
      const fcmBody = isTransfer
        ? `Transfer to ${supervisor.alertFactoryName || current.usine || 'the alert factory'}: ${current.type || 'alert'}`
        : `Auto-assigned: ${current.type || 'alert'}${current.usine ? ` at ${current.usine}` : ''}`;
      const fcmSent = await sendFcm(
        supervisor.fcmToken,
        fcmTitle,
        fcmBody,
        {
          type: isTransfer ? 'cross_factory_transfer' : 'ai_assigned',
          alertId: String(alertId),
          recipientId: String(supervisor.uid),
          reason: reasonSummary,
          usine: String(current.usine || ''),
          donorFactory: String(supervisor.donorFactoryName || supervisor.factoryName || supervisor.factoryId || ''),
          distanceKm: supervisor.distanceKm == null ? '' : String(supervisor.distanceKm),
        },
        env,
      );
      if (fcmSent && transferNotificationId) {
        await fetch(`${env.FB_DB_URL}notifications/${supervisor.uid}/${transferNotificationId}.json?auth=${token}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pushSent: true, pushSentAt: nowIso }),
        });
      }
    }
    return true;
  }
  return false;
}

async function runAIAssignments(env, ctx) {
  const token = ctx?.token ?? (await getFirebaseToken(env));
  let alertsMap, usersMap, factoriesMap, activeShift;
  if (ctx) {
    alertsMap = ctx.alertsMap;
    usersMap = ctx.usersMap;
    factoriesMap = ctx.factoriesMap || ctx.factories || {};
    activeShift = ctx.targetShift ?? ctx.activeShift ?? null;
  } else {
    const [ar, ur, sr, fr] = await Promise.all([
      fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}shifts.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}factories.json?auth=${token}`),
    ]);
    if (!ar.ok || !ur.ok) return;
    alertsMap = (await ar.json()) || {};
    usersMap = (await ur.json()) || {};
    const shiftsMap = sr.ok ? ((await sr.json()) || {}) : {};
    factoriesMap = fr.ok ? ((await fr.json()) || {}) : {};
    activeShift = pickActiveShift(shiftsMap, new Date());
  }
  const proximityUsersMap = _usersMapWithFactories(usersMap, factoriesMap);
  const capabilities = commanderCapabilities(activeShift);
  const aiCommander = capabilities.aiCommander;
  const shiftRandomize = !!(activeShift && activeShift.randomize === true);
  const shiftMaxSupervisors =
    activeShift && Number.isFinite(Number(activeShift.maxSupervisors))
      ? Number(activeShift.maxSupervisors)
      : null;
  const shiftSupervisorIds = new Set(
    (activeShift && activeShift.supervisors && typeof activeShift.supervisors === 'object'
      ? Object.keys(activeShift.supervisors)
      : []),
  );
  const crossFactoryMaxDistanceKm =
    activeShift && Number.isFinite(Number(activeShift.crossFactoryMaxDistanceKm)) &&
    Number(activeShift.crossFactoryMaxDistanceKm) > 0
      ? Number(activeShift.crossFactoryMaxDistanceKm)
      : null;
  if (aiCommander && !capabilities.handleAssignments) {
    await writeShiftAiLog(env, token, activeShift?.id, {
      kind: 'skipped',
      reason: `Assignments were skipped because "Handle Assignments" is disabled for shift "${activeShift?.name || activeShift?.id || 'Unknown'}".`,
    });
    return 0;
  }
  let feedbackSummary = {};
  try {
    const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${token}`);
    if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
  } catch (e) {}
  let reinforcementAdjustments = {};
  try {
    const adjRes = await fetch(`${env.FB_DB_URL}ai_feedback/adjustments.json?auth=${token}`);
    if (adjRes.ok) reinforcementAdjustments = (await adjRes.json()) || {};
  } catch (_) {}
  const supStats = buildSupStats(alertsMap);
  const busy = new Set();
  for (const a of Object.values(alertsMap)) {
    if (a.status === 'en_cours') {
      if (a.superviseurId) busy.add(a.superviseurId);
      if (a.assistantId) busy.add(a.assistantId);
    }
  }
  const byFactory = {};
  for (const [id, a] of Object.entries(alertsMap)) {
    if (a.status !== 'disponible' || a.superviseurId) continue;
    const fid = aiResolveFactory(a);
    if (!fid) continue;
    if (!byFactory[fid]) byFactory[fid] = [];
    byFactory[fid].push({ id, ...a });
  }
  if (Object.keys(byFactory).length === 0) return;
  const now = Date.now();
  const factoryIds = Object.keys(byFactory);
  let assignedCount = 0;
  for (let i = 0; i < Math.min(factoryIds.length, 20); i++) {
    if (assignedCount >= 1) break;
    const factoryId = factoryIds[i];
    let enabled = false;
    if (aiCommander) {
      // AI Shift Commander overrides per-factory toggle.
      enabled = true;
    } else {
      const enaRes = await fetch(`${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`);
      enabled = enaRes.ok ? await enaRes.json() : false;
    }
    if (enabled !== true) continue;
    let factoryAlerts = byFactory[factoryId];
    factoryAlerts.sort((a, b) => {
      const ap = a.isEscalated ? 2 : (a.isCritical ? 1 : 0);
      const bp = b.isEscalated ? 2 : (b.isCritical ? 1 : 0);
      if (ap !== bp) return bp - ap;
      return (Date.parse(a.timestamp || '') || 0) - (Date.parse(b.timestamp || '') || 0);
    });
    const alert = factoryAlerts[0];
    if (!alert) continue;
    let gate1Result = null;
    let alertFactoryLocation = null;
    let alertFactoryLocationResolved = false;
    const crossFactoryBlockLogKeys = new Set();
    const logCrossFactoryBlocked = async (gate, details, reason) => {
      const key = `${factoryId}:${gate}:${details?.supervisorId || 'factory'}`;
      if (crossFactoryBlockLogKeys.has(key)) return;
      crossFactoryBlockLogKeys.add(key);
      await writeShiftAiLog(env, token, activeShift?.id, {
        kind: 'cross_factory_blocked',
        alertLabel: `${alert.type || 'Alert'}${alert.usine ? ` • ${alert.usine}` : ''}`,
        factory: alert.usine || factoryId,
        gate,
        details,
        reason,
      });
    };
    const candidates = [];
    for (const [uid, u] of Object.entries(usersMap)) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      if (!AI_ACTIVE_STATUSES.has(String(u.status || '').toLowerCase())) continue;
      if (busy.has(uid)) continue;
      const cooldown = Date.parse(String(u.aiCooldownUntil || ''));
      if (!isNaN(cooldown) && cooldown > now) continue;
      const userFactory = aiResolveFactory(u);
      let distanceKm = null;
      let currentLocation = null;

      if (aiCommander) {
        // Under AI Commander, ONLY assign supervisors in this shift's roster.
        // Cross-factory transfers are only allowed when enabled for the shift
        // and the overload/donor/proximity gates below pass.
        if (!shiftSupervisorIds.has(uid)) continue;
        if (!userFactory) continue;
        const isCrossFactory = userFactory !== factoryId;

        if (isCrossFactory) {
          if (!capabilities.handleCrossFactoryTransfer) continue;

          gate1Result ??= _crossFactoryGate1(alertsMap, usersMap, factoryId);
          if (!gate1Result.allowed) {
            await logCrossFactoryBlocked(
              'gate_1_alert_factory_overwhelmed',
              gate1Result.details,
              `Cross-factory transfer blocked: alert factory has ${gate1Result.details.criticalUnclaimedAlerts} critical unclaimed alert(s) and ${gate1Result.details.activeSupervisors} active supervisor(s).`,
            );
            continue;
          }

          const gate2Result = _crossFactoryGate2(alertsMap, usersMap, { ...u, uid, factoryId: userFactory });
          if (!gate2Result.allowed) {
            await logCrossFactoryBlocked(
              'gate_2_donor_factory_quiet',
              gate2Result.details,
              `Cross-factory transfer blocked: donor factory ${gate2Result.details.donorFactory || 'unknown'} is not quiet enough or would be left unstaffed.`,
            );
            continue;
          }

          currentLocation = _freshLatLng(u.currentLocation, MAX_LOCATION_AGE_MS, now);
          if (!currentLocation) {
            await logCrossFactoryBlocked(
              'gate_3_proximity_scoring',
              {
                supervisorId: uid,
                donorFactory: userFactory,
                reason: 'missing_or_stale_supervisor_gps',
                maxLocationAgeMs: MAX_LOCATION_AGE_MS,
                updatedAt: u.currentLocation?.updatedAt ?? null,
              },
              `Cross-factory transfer blocked: ${u.fullName || uid} has no fresh GPS location.`,
            );
            continue;
          }

          if (!alertFactoryLocationResolved) {
            alertFactoryLocation = inferFactoryLocation(proximityUsersMap, factoryId, MAX_LOCATION_AGE_MS);
            alertFactoryLocationResolved = true;
          }
          if (alertFactoryLocation) {
            distanceKm = haversineDistance(
              currentLocation.lat,
              currentLocation.lng,
              alertFactoryLocation.lat,
              alertFactoryLocation.lng,
            );
          }

          // PM-configured shift threshold: reject cross-factory candidates whose
          // distance to the alert factory exceeds the limit. Missing distance
          // (no factory anchor or no GPS) is treated as a fail when the PM has
          // explicitly opted into a cap.
          if (crossFactoryMaxDistanceKm != null) {
            if (typeof distanceKm !== 'number' || !Number.isFinite(distanceKm)) {
              await logCrossFactoryBlocked(
                'gate_4_distance_threshold',
                {
                  supervisorId: uid,
                  donorFactory: userFactory,
                  maxDistanceKm: crossFactoryMaxDistanceKm,
                  reason: 'distance_unavailable',
                },
                `Cross-factory transfer blocked: cannot measure distance for ${u.fullName || uid} and shift requires <= ${crossFactoryMaxDistanceKm.toFixed(1)} km.`,
              );
              continue;
            }
            if (distanceKm > crossFactoryMaxDistanceKm) {
              await logCrossFactoryBlocked(
                'gate_4_distance_threshold',
                {
                  supervisorId: uid,
                  donorFactory: userFactory,
                  distanceKm,
                  maxDistanceKm: crossFactoryMaxDistanceKm,
                },
                `Cross-factory transfer blocked: ${u.fullName || uid} is ${distanceKm.toFixed(1)} km away (shift limit ${crossFactoryMaxDistanceKm.toFixed(1)} km).`,
              );
              continue;
            }
          }
        }
      } else {
        // Normal mode: same factory only.
        if (!userFactory || userFactory !== factoryId) continue;
      }

      candidates.push({
        ...u,
        uid,
        factoryId: userFactory,
        factoryName: u.usine || null,
        isCrossFactory: aiCommander && userFactory !== factoryId,
        distanceKm,
        currentLocation,
      });
    }
    if (candidates.length === 0) continue;
    const recentCounts = {};
    for (const a of Object.values(alertsMap)) {
      if (a.superviseurId && a.takenAtTimestamp && (now - new Date(a.takenAtTimestamp).getTime()) < 10 * 60 * 1000) {
        recentCounts[a.superviseurId] = (recentCounts[a.superviseurId] || 0) + 1;
      }
    }
    const scored = candidates.map((u) => {
      const recent = recentCounts[u.uid] || 0;
      const adj = reinforcementAdjustments[u.uid] || 0;
      const { score, reasons } = scoreSupervisor(
        { ...u, uid: u.uid, name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(), fcmToken: u.fcmToken },
        alert,
        supStats,
        feedbackSummary,
        recent,
        now,
        { isCommander: aiCommander, reinforcementAdjustment: adj },
      );
      return {
        uid: u.uid,
        name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(),
        fcmToken: u.fcmToken,
        factoryId: u.factoryId || null,
        factoryName: u.factoryName || u.usine || null,
        score,
        reasons: [
          ...reasons,
          ...(u.isCrossFactory
            ? [
                typeof u.distanceKm === 'number'
                  ? `Cross-factory distance ${u.distanceKm.toFixed(1)} km`
                  : 'Cross-factory distance unavailable; score fallback',
              ]
            : []),
        ],
        isCrossFactory: u.isCrossFactory === true,
        distanceKm: u.distanceKm,
        currentLocation: u.currentLocation,
      };
    });

    // Step 1: sort by score so the confidence calculation reflects the true best candidates.
    scored.sort((a, b) => b.score - a.score);
    const scoreSorted = [...scored];
    const crossFactoryOnly = scored.length > 0 && scored.every((candidate) => candidate.isCrossFactory);
    if (crossFactoryOnly) {
      const withDistance = scored
        .filter((candidate) => typeof candidate.distanceKm === 'number' && Number.isFinite(candidate.distanceKm))
        .sort((a, b) => (a.distanceKm - b.distanceKm) || (b.score - a.score));
      const withoutDistance = scored.filter(
        (candidate) => !(typeof candidate.distanceKm === 'number' && Number.isFinite(candidate.distanceKm)),
      );
      scored.splice(
        0,
        scored.length,
        ...(withDistance.length > 0 ? [...withDistance, ...withoutDistance] : scoreSorted),
      );
    }

    // Step 2: check confidence floor against the sorted pool BEFORE any shuffle.
    // This ensures a randomly-ordered low-score pick can never falsely block a valid pool.
    const topSum = scoreSorted.slice(0, 3).reduce((s, c) => s + c.score, 0);
    const confidence = topSum > 0 ? Math.min(scoreSorted[0].score / topSum, 1.0) : 1.0;
    // Step 3: optionally shuffle so the AI Commander picks randomly from the confident pool.
    if (shiftRandomize && !crossFactoryOnly) {
      for (let k = scored.length - 1; k > 0; k--) {
        const j = Math.floor(Math.random() * (k + 1));
        const tmp = scored[k]; scored[k] = scored[j]; scored[j] = tmp;
      }
    }
    const best = scored[0];
    if (best?.isCrossFactory) {
      best.crossFactoryTransfer = true;
      best.alertFactoryId = factoryId;
      best.alertFactoryName = alert.usine || factoryId;
      best.donorFactoryName = best.factoryName || best.factoryId || null;
      best.criticalAlertCount =
        gate1Result?.details?.criticalUnclaimedAlerts ??
        _factoryAlertCounts(alertsMap, factoryId).criticalUnclaimed;
    }
    let reasonSummary = best.reasons.join(' • ');
    if (aiCommander) {
      reasonSummary = `[Shift "${activeShift.name || activeShift.id}"] ` + reasonSummary;
    }
    const ok = await aiAssignAlert(alert.id, best, reasonSummary, confidence, env, token, scored);
    if (ok) {
      const transferUsed =
        aiCommander &&
        capabilities.handleCrossFactoryTransfer &&
        best.factoryId &&
        best.factoryId !== factoryId;
      const detailParts = [
        `Auto-assigned "${alert.type || 'alert'}"`,
        alert.usine ? `for ${alert.usine}` : null,
        `to ${best.name}.`,
        transferUsed
            ? `Cross-factory transfer used from ${best.factoryName || best.factoryId} to ${alert.usine || factoryId}${typeof best.distanceKm === 'number' ? ` (${best.distanceKm.toFixed(1)} km)` : ''}.`
            : 'Assignment stayed within the allowed factory scope.',
        `Confidence ${(confidence * 100).toFixed(0)}%.`,
        `Reasoning: ${best.reasons.join(' | ') || 'No score breakdown provided.'}`,
      ].filter(Boolean);
      await writeShiftAiLog(env, token, activeShift?.id, {
        kind: transferUsed ? 'cross_factory_transfer' : 'assigned',
        alertLabel: `${alert.type || 'Alert'}${alert.usine ? ` • ${alert.usine}` : ''}`,
        supervisorName: best.name,
        supervisorId: best.uid,
        factory: alert.usine || null,
        confidence,
        details: transferUsed
          ? {
              distanceKm: best.distanceKm ?? null,
              supervisorName: best.name,
              alertFactory: alert.usine || factoryId,
              donorFactory: best.factoryName || best.factoryId || null,
              criticalAlertCount: best.criticalAlertCount ?? null,
            }
          : null,
        reason: detailParts.join(' '),
      });
      busy.add(best.uid);
      assignedCount++;
    }
  }
  return assignedCount;
}

// ============ Shift collaboration auto-approve ============
// When AI Shift Commander is on, auto-approve collaboration requests that
// have all assistant approvals but are awaiting PM approval. Also handles
// cross-factory transfers without human intervention.
const COLLAB_LONG_FIX_MINUTES = 180;
const COLLAB_OVERLOAD_UNCLAIMED = 3;
const COLLAB_OVERLOAD_ESCALATED = 2;
const COLLAB_OVERLOAD_SCORE = 5;

function _collabDecisionAccepted(decision) {
  if (!decision) return false;
  if (typeof decision === 'string') return decision === 'accepted';
  if (typeof decision === 'object') return decision.status === 'accepted';
  return false;
}

function _collabAcceptedCollaborators(req = {}) {
  const accepted = [];
  const targetIds = Array.isArray(req.targetSupervisorIds) ? req.targetSupervisorIds : [];
  const targetNames = Array.isArray(req.targetSupervisorNames) ? req.targetSupervisorNames : [];
  for (let i = 0; i < targetIds.length; i++) {
    const supId = String(targetIds[i] || '');
    const supName = String(targetNames[i] || '');
    const decision = req.assistantDecisions?.[supId] || 'pending';
    if (_collabDecisionAccepted(decision)) {
      accepted.push({ id: supId, name: supName || supId });
    }
  }
  if (
    accepted.length === 0 &&
    req.assistantId &&
    req.assistantName &&
    req.assistantDecision === 'accepted'
  ) {
    accepted.push({
      id: String(req.assistantId),
      name: String(req.assistantName),
    });
  }
  return accepted;
}

function _buildAssistantAlertSuspensionPatch() {
  return {
    status: 'disponible',
    superviseurId: null,
    superviseurName: null,
    takenAtTimestamp: null,
    aiAssigned: false,
    aiAssignmentReason: null,
    aiConfidence: null,
    aiAssignedAt: null,
  };
}

async function suspendAcceptedAssistantAlerts(env, token, acceptedCollaborators = [], alertsMap = {}, {
  activeShift = null,
  collaborationRequestId = null,
} = {}) {
  const nowIso = new Date().toISOString();
  const suspended = [];

  for (const collaborator of acceptedCollaborators || []) {
    const assistantId = String(collaborator?.id || '');
    if (!assistantId) continue;
    const ownedAlerts = Object.entries(alertsMap || {}).filter(
      ([, alert]) =>
        alert &&
        typeof alert === 'object' &&
        String(alert.status || '').toLowerCase() === 'en_cours' &&
        String(alert.superviseurId || '') === assistantId,
    );

    for (const [alertId] of ownedAlerts) {
      try {
        const patch = _buildAssistantAlertSuspensionPatch();
        const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        });
        if (!patchRes.ok) {
          console.error(
            `[AI-COLLAB] Failed to suspend alert ${alertId} for assistant ${assistantId}: HTTP ${patchRes.status}`,
          );
          continue;
        }

        if (alertsMap?.[alertId]) {
          Object.assign(alertsMap[alertId], patch);
        }
        suspended.push({ assistantId, alertId });

        try {
          await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              event: 'suspended_for_collaboration',
              assistantId,
              assistantName: collaborator?.name || null,
              collaborationRequestId,
              shiftId: activeShift?.id || null,
              timestamp: nowIso,
              reason:
                'AI Shift Commander suspended the assistant\'s existing claimed alert before auto-approving collaboration.',
            }),
          });
        } catch (historyErr) {
          console.error(
            `[AI-COLLAB] Failed to write suspension history for alert ${alertId}: ${historyErr.message}`,
          );
        }
      } catch (err) {
        console.error(
          `[AI-COLLAB] Failed to suspend alert ${alertId} for assistant ${assistantId}: ${err.message}`,
        );
      }
    }
  }

  return suspended;
}

function _collabAlertFactory(req = {}, alert = {}) {
  return aiResolveFactory(alert) || aiResolveFactory(req) || aiSanitizeFactoryId(req.factoryName || '');
}

function _collabAlertFactoryName(req = {}, alert = {}) {
  return String(alert?.usine || alert?.factoryName || req?.usine || req?.factoryName || _collabAlertFactory(req, alert) || '');
}

function _collabAlertIsCritical(req = {}, alert = {}) {
  return alert?.isCritical === true || req?.isCritical === true || req?.alertIsCritical === true;
}

function _collabFactoryLoad(alertsMap = {}, factoryId, now = Date.now()) {
  const fid = aiSanitizeFactoryId(factoryId);
  const load = {
    factoryId: fid,
    factoryName: fid,
    active: 0,
    unclaimed: 0,
    escalated: 0,
    critical: 0,
    staleUnclaimed: 0,
    oldestUnattendedMin: 0,
    score: 0,
    overloaded: false,
  };
  if (!fid) return load;

  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    const alertFid = aiResolveFactory(alert);
    if (!alertFid || alertFid !== fid) continue;
    if (alert.usine && load.factoryName === fid) load.factoryName = String(alert.usine);

    const status = String(alert.status || '').toLowerCase();
    if (status === 'validee' || status === 'cancelled' || status === 'canceled') continue;

    load.active++;
    if (alert.isCritical === true) load.critical++;
    if (alert.isEscalated === true) load.escalated++;

    if (status === 'disponible') {
      load.unclaimed++;
      const ts = _toMs(alert.timestamp);
      if (ts != null) {
        const ageMin = Math.max(0, Math.floor((now - ts) / 60000));
        if (ageMin > load.oldestUnattendedMin) load.oldestUnattendedMin = ageMin;
        if (ageMin >= 30) load.staleUnclaimed++;
      }
    }
  }

  load.score =
    load.unclaimed +
    load.escalated * 2 +
    load.critical * 1.5 +
    load.staleUnclaimed;
  load.overloaded =
    load.unclaimed >= COLLAB_OVERLOAD_UNCLAIMED ||
    load.escalated >= COLLAB_OVERLOAD_ESCALATED ||
    load.score >= COLLAB_OVERLOAD_SCORE;
  return load;
}

function _collabLoadReason(load) {
  const parts = [
    `${load.unclaimed} unclaimed`,
    `${load.escalated} escalated`,
    `${load.critical} critical`,
  ];
  if (load.oldestUnattendedMin > 0) {
    parts.push(`oldest unattended ${load.oldestUnattendedMin} min`);
  }
  return `${load.factoryName || load.factoryId} is overloaded: ${parts.join(', ')}.`;
}

function _collabWindowPressure(alertsMap = {}, factoryId, startMs, endMs) {
  const fid = aiSanitizeFactoryId(factoryId);
  const pressure = { unclaimed: 0, escalated: 0, slow: 0, score: 0 };
  if (!fid || startMs == null || endMs == null) return pressure;
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    const alertFid = aiResolveFactory(alert);
    if (!alertFid || alertFid !== fid) continue;
    const ts = _toMs(alert.timestamp);
    if (ts == null || ts < startMs || ts > endMs) continue;
    const status = String(alert.status || '').toLowerCase();
    if (status === 'disponible') pressure.unclaimed++;
    if (alert.isEscalated === true) pressure.escalated++;
    const elapsed = Number(alert.elapsedTime);
    if (Number.isFinite(elapsed) && elapsed >= 60) pressure.slow++;
  }
  pressure.score = pressure.unclaimed + pressure.escalated * 2 + pressure.slow;
  return pressure;
}

function _collabDurationMin(req = {}, alert = {}) {
  const elapsed = Number(alert?.elapsedTime);
  if (Number.isFinite(elapsed) && elapsed > 0) return elapsed;
  const startMs =
    _toMs(alert?.takenAtTimestamp) ??
    _toMs(req?.pmApprovedAt) ??
    _toMs(req?.approvedAt) ??
    _toMs(req?.assistantRespondedAt) ??
    _toMs(req?.timestamp);
  const endMs =
    _toMs(alert?.resolvedAt) ??
    _toMs(alert?.validatedAt) ??
    _toMs(alert?.closedAt) ??
    _toMs(req?.completedAt);
  if (startMs == null || endMs == null || endMs <= startMs) return null;
  return Math.round((endMs - startMs) / 60000);
}

function buildCollaborationLearning(reqs = {}, alertsMap = {}, usersMap = {}, now = Date.now()) {
  const learning = {
    generatedAt: new Date(now).toISOString(),
    longFixMinutes: COLLAB_LONG_FIX_MINUTES,
    pairs: {},
    assistantFactories: {},
  };

  const ensurePair = (key, requesterId, assistantId, assistantName, assistantFactoryId) => {
    if (!learning.pairs[key]) {
      learning.pairs[key] = {
        requesterId,
        assistantId,
        assistantName,
        assistantFactoryId,
        approved: 0,
        longFixes: 0,
        crossFactoryLongFixes: 0,
        overloadAfter: 0,
        worstDurationMin: 0,
        lastConcern: null,
      };
    }
    return learning.pairs[key];
  };
  const ensureFactory = (factoryId, factoryName) => {
    const fid = aiSanitizeFactoryId(factoryId);
    if (!fid) return null;
    if (!learning.assistantFactories[fid]) {
      learning.assistantFactories[fid] = {
        factoryId: fid,
        factoryName: factoryName || fid,
        approved: 0,
        longFixes: 0,
        overloadAfter: 0,
        worstDurationMin: 0,
      };
    }
    return learning.assistantFactories[fid];
  };

  for (const [reqId, req] of Object.entries(reqs || {})) {
    if (!req || typeof req !== 'object') continue;
    if (req.pmApproved !== true && req.status !== 'approved') continue;
    const alert = alertsMap?.[req.alertId] || {};
    const alertFactoryId = _collabAlertFactory(req, alert);
    const durationMin = _collabDurationMin(req, alert);
    const accepted = _collabAcceptedCollaborators(req);
    if (accepted.length === 0) continue;
    const startMs =
      _toMs(req.pmApprovedAt) ??
      _toMs(req.approvedAt) ??
      _toMs(req.assistantRespondedAt) ??
      _toMs(req.timestamp) ??
      _toMs(alert.takenAtTimestamp) ??
      _toMs(alert.timestamp);
    const endMs =
      _toMs(alert.resolvedAt) ??
      _toMs(alert.validatedAt) ??
      (startMs != null && durationMin != null ? startMs + durationMin * 60000 : null);

    for (const collaborator of accepted) {
      const user = usersMap?.[collaborator.id] || {};
      const assistantFactoryId = aiResolveFactory(user);
      if (!assistantFactoryId) continue;
      const assistantFactoryName = user.usine || user.factoryName || assistantFactoryId;
      const crossFactory = alertFactoryId && assistantFactoryId && alertFactoryId !== assistantFactoryId;
      const pairKey = `${req.requesterId || 'unknown'}|${collaborator.id}`;
      const pair = ensurePair(
        pairKey,
        String(req.requesterId || ''),
        collaborator.id,
        collaborator.name,
        assistantFactoryId,
      );
      const factory = ensureFactory(assistantFactoryId, assistantFactoryName);
      pair.approved++;
      if (factory) factory.approved++;

      if (durationMin != null && durationMin >= COLLAB_LONG_FIX_MINUTES) {
        const pressure = _collabWindowPressure(alertsMap, assistantFactoryId, startMs, endMs);
        pair.longFixes++;
        if (crossFactory) pair.crossFactoryLongFixes++;
        if (pressure.score > 0) pair.overloadAfter++;
        pair.worstDurationMin = Math.max(pair.worstDurationMin, durationMin);
        pair.lastConcern =
          `Request ${reqId} took ${Math.round(durationMin)} min` +
          (pressure.score > 0
            ? ` and ${assistantFactoryName} saw ${pressure.unclaimed} unclaimed, ${pressure.escalated} escalated, ${pressure.slow} slow alerts during that window.`
            : '.');

        if (factory) {
          factory.longFixes++;
          if (pressure.score > 0) factory.overloadAfter++;
          factory.worstDurationMin = Math.max(factory.worstDurationMin, durationMin);
        }
      }
    }
  }

  return learning;
}

function mergeCollaborationLearning(current = {}, prior = {}) {
  const merged = {
    generatedAt: current.generatedAt || new Date().toISOString(),
    longFixMinutes: COLLAB_LONG_FIX_MINUTES,
    pairs: { ...(prior?.pairs || {}) },
    assistantFactories: { ...(prior?.assistantFactories || {}) },
  };

  for (const [key, cur] of Object.entries(current?.pairs || {})) {
    const old = merged.pairs[key];
    if (!old) {
      merged.pairs[key] = cur;
      continue;
    }
    merged.pairs[key] = {
      ...old,
      ...cur,
      approved: Math.max(Number(old.approved || 0), Number(cur.approved || 0)),
      longFixes: Math.max(Number(old.longFixes || 0), Number(cur.longFixes || 0)),
      crossFactoryLongFixes: Math.max(
        Number(old.crossFactoryLongFixes || 0),
        Number(cur.crossFactoryLongFixes || 0),
      ),
      overloadAfter: Math.max(Number(old.overloadAfter || 0), Number(cur.overloadAfter || 0)),
      worstDurationMin: Math.max(
        Number(old.worstDurationMin || 0),
        Number(cur.worstDurationMin || 0),
      ),
      lastConcern: cur.lastConcern || old.lastConcern || null,
    };
  }

  for (const [key, cur] of Object.entries(current?.assistantFactories || {})) {
    const old = merged.assistantFactories[key];
    if (!old) {
      merged.assistantFactories[key] = cur;
      continue;
    }
    merged.assistantFactories[key] = {
      ...old,
      ...cur,
      approved: Math.max(Number(old.approved || 0), Number(cur.approved || 0)),
      longFixes: Math.max(Number(old.longFixes || 0), Number(cur.longFixes || 0)),
      overloadAfter: Math.max(Number(old.overloadAfter || 0), Number(cur.overloadAfter || 0)),
      worstDurationMin: Math.max(
        Number(old.worstDurationMin || 0),
        Number(cur.worstDurationMin || 0),
      ),
    };
  }

  return merged;
}

function _collabLearningRisk(req = {}, accepted = [], usersMap = {}, learning = {}) {
  let best = null;
  for (const collaborator of accepted) {
    const user = usersMap?.[collaborator.id] || {};
    const assistantFactoryId = aiResolveFactory(user);
    if (!assistantFactoryId) continue;
    const pairKey = `${req.requesterId || 'unknown'}|${collaborator.id}`;
    const pair = learning?.pairs?.[pairKey];
    const factory = learning?.assistantFactories?.[assistantFactoryId];
    const pairRisk =
      pair &&
      pair.crossFactoryLongFixes > 0 &&
      (pair.overloadAfter > 0 || pair.longFixes / Math.max(1, pair.approved) >= 0.5);
    const factoryRisk =
      factory &&
      factory.longFixes >= 2 &&
      factory.longFixes / Math.max(1, factory.approved) >= 0.5 &&
      factory.overloadAfter > 0;
    if (!pairRisk && !factoryRisk) continue;

    const risk = {
      collaborator,
      assistantFactoryId,
      assistantFactoryName: user.usine || user.factoryName || assistantFactoryId,
      confidence: Math.min(
        0.95,
        0.7 +
          (pair?.crossFactoryLongFixes || 0) * 0.08 +
          (pair?.overloadAfter || 0) * 0.07 +
          (factory?.overloadAfter || 0) * 0.03,
      ),
      reason:
        pair?.lastConcern ||
        `Past cross-factory collaborations involving ${user.usine || collaborator.name || collaborator.id} repeatedly ran long and were followed by factory pressure.`,
      worstDurationMin: Math.max(pair?.worstDurationMin || 0, factory?.worstDurationMin || 0),
    };
    if (!best || risk.confidence > best.confidence) best = risk;
  }
  return best;
}

function evaluateShiftCollaborationDecision(reqId, req, {
  acceptedCollaborators,
  alertsMap = {},
  usersMap = {},
  learning = {},
  confidence = 1,
  activeShift = null,
} = {}) {
  const alert = alertsMap?.[req.alertId] || {};
  const alertFactoryId = _collabAlertFactory(req, alert);
  const alertFactoryName = _collabAlertFactoryName(req, alert);
  const isCritical = _collabAlertIsCritical(req, alert);
  const crossFactoryAssistants = [];

  for (const collaborator of acceptedCollaborators || []) {
    const user = usersMap?.[collaborator.id] || {};
    const assistantFactoryId = aiResolveFactory(user);
    if (!assistantFactoryId || !alertFactoryId || assistantFactoryId === alertFactoryId) continue;
    crossFactoryAssistants.push({
      ...collaborator,
      factoryId: assistantFactoryId,
      factoryName: user.usine || user.factoryName || assistantFactoryId,
    });
  }

  if (!isCritical && crossFactoryAssistants.length > 0) {
    for (const assistant of crossFactoryAssistants) {
      const load = _collabFactoryLoad(alertsMap, assistant.factoryId);
      if (load.overloaded) {
        return {
          action: 'decline',
          confidence: Math.max(confidence, 0.92),
          reason:
            `AI Shift Commander declined this non-critical cross-factory collaboration to protect the whole company. ` +
            `${_collabLoadReason(load)} Pulling ${assistant.name || 'the assistant'} from that factory would likely leave unattended alerts waiting longer.`,
          checks: {
            rule: 'assistant_factory_overloaded',
            requestId: reqId,
            alertFactoryId,
            alertFactoryName,
            assistantFactoryId: assistant.factoryId,
            assistantFactoryName: assistant.factoryName,
            load,
          },
        };
      }
    }

    const learnedRisk = _collabLearningRisk(req, crossFactoryAssistants, usersMap, learning);
    if (learnedRisk) {
      return {
        action: 'decline',
        confidence: Math.max(confidence, learnedRisk.confidence),
        reason:
          `AI Shift Commander declined this non-critical cross-factory collaboration based on learned operational patterns. ` +
          `${learnedRisk.reason} The request can be retried if the alert becomes critical or the assistant factory stabilizes.`,
        checks: {
          rule: 'learned_long_fix_overload_risk',
          requestId: reqId,
          alertFactoryId,
          alertFactoryName,
          assistantFactoryId: learnedRisk.assistantFactoryId,
          assistantFactoryName: learnedRisk.assistantFactoryName,
          worstDurationMin: learnedRisk.worstDurationMin,
        },
      };
    }
  }

  const shiftName = activeShift?.name || activeShift?.id || 'active shift';
  return {
    action: 'approve',
    confidence,
    reason:
      `Auto-approved by AI Shift Commander during "${shiftName}" after company-wide load and learning checks. ` +
      (crossFactoryAssistants.length > 0
        ? `Cross-factory assistance is allowed because the alert ${isCritical ? 'is critical' : 'is not blocked by overload or learned risk'}.`
        : 'Collaboration stays within the alert factory.'),
    checks: {
      rule: 'approved_company_wide',
      requestId: reqId,
      alertFactoryId,
      alertFactoryName,
      crossFactory: crossFactoryAssistants.length > 0,
      critical: isCritical,
    },
  };
}

async function processShiftCollaborations(env, ctx) {
  const activeShift = ctx?.targetShift ?? ctx?.activeShift;
  const capabilities = commanderCapabilities(activeShift);
  if (!capabilities.aiCommander) return 0;

  const token = ctx?.token ?? (await getFirebaseToken(env));
  if (!capabilities.handleCollaborations) {
    await writeShiftAiLog(env, token, activeShift?.id, {
      kind: 'skipped',
      reason: `Collaboration approvals were skipped because "Handle Collaborations" is disabled for shift "${activeShift?.name || activeShift?.id || 'Unknown'}".`,
    });
    return 0;
  }
  const res = await fetch(`${env.FB_DB_URL}collaboration_requests.json?auth=${token}`);
  if (!res.ok) return 0;
  const reqs = (await res.json()) || {};
  const alertsMap = ctx?.alertsMap || {};
  const usersMap = ctx?.usersMap || {};
  let priorLearning = {};
  try {
    const learningRes = await fetch(`${env.FB_DB_URL}ai_collaboration_learning/latest.json?auth=${token}`);
    if (learningRes.ok) priorLearning = (await learningRes.json()) || {};
  } catch (_) {}
  const learning = mergeCollaborationLearning(
    buildCollaborationLearning(reqs, alertsMap, usersMap),
    priorLearning,
  );
  try {
    await fetch(`${env.FB_DB_URL}ai_collaboration_learning/latest.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(learning),
    });
  } catch (_) {}
  const minConfidence =
    typeof activeShift?.aiConfidence === 'number' ? Number(activeShift.aiConfidence) : 0.65;

  let processed = 0;
  for (const [reqId, req] of Object.entries(reqs)) {
    if (processed >= 5) break;
    if (!req || typeof req !== 'object') continue;
    if (req.status === 'approved' || req.status === 'rejected') continue;
    if (req.pmApproved === true) continue;
    if (req.requiresPMApproval === false) continue;

    const assistantDecisions = req.assistantDecisions
      ? Object.values(req.assistantDecisions)
      : [];
    const acceptedCount = assistantDecisions.filter(
      (d) => d && (d === 'accepted' || d.status === 'accepted'),
    ).length;
    const hasTopLevelAcceptance = req.assistantDecision === 'accepted';
    if (acceptedCount === 0 && !hasTopLevelAcceptance) continue;
    const denominator = assistantDecisions.length > 0 ? assistantDecisions.length : 1;
    const collabConfidence = Math.min(
      1,
      acceptedCount > 0 ? acceptedCount / denominator : 1,
    );
    if (collabConfidence < minConfidence) continue;
    const acceptedCollaborators = _collabAcceptedCollaborators(req);
    const nowIso = new Date().toISOString();
    const decision = evaluateShiftCollaborationDecision(reqId, req, {
      acceptedCollaborators,
      alertsMap,
      usersMap,
      learning,
      confidence: collabConfidence,
      activeShift,
    });
    if (decision.action === 'decline') {
      const patch = {
        status: 'rejected',
        pmApproved: false,
        pmApprovedBy: 'ai_shift_commander',
        pmApprovedShiftId: activeShift.id,
        pmDecision: 'declined',
        rejectedBy: 'ai_shift_commander',
        rejectedAt: nowIso,
        rejectionReason: decision.reason,
        aiDecision: 'declined',
        aiConfidence: Number(decision.confidence.toFixed(4)),
        aiReason: decision.reason,
        aiChecks: decision.checks,
      };
      const [patchRes] = await Promise.all([
        fetch(`${env.FB_DB_URL}collaboration_requests/${reqId}.json?auth=${token}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        }),
        req.alertId
          ? fetch(`${env.FB_DB_URL}alerts/${req.alertId}.json?auth=${token}`, {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ collaborationRequestId: null }),
            })
          : Promise.resolve({ ok: true }),
      ]);
      if (patchRes.ok) {
        processed++;
        await writeShiftAiLog(env, token, activeShift.id, {
          kind: 'collaboration_declined',
          alertLabel:
            req.alertTitle ||
            req.alertLabel ||
            req.alertType ||
            req.alertId ||
            'Collaboration request',
          supervisorName: req.requesterName || req.requesterFullName || null,
          supervisorId: req.requesterId || null,
          factory: req.factoryName || req.usine || null,
          confidence: decision.confidence,
          reason: `Declined collaboration request ${reqId}. ${decision.reason}`,
        });
        const notifyTargets = new Map();
        if (req.requesterId) notifyTargets.set(String(req.requesterId), 'requester');
        for (const collaborator of acceptedCollaborators) {
          if (collaborator.id) notifyTargets.set(String(collaborator.id), 'assistant');
        }
        for (const [uid, role] of notifyTargets.entries()) {
          await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              type: 'collaboration_rejected',
              collabRequestId: reqId,
              collaborationId: reqId,
              alertId: req.alertId || null,
              message:
                role === 'requester'
                  ? `AI Shift Commander declined your collaboration request. Reason: ${decision.reason}`
                  : `AI Shift Commander declined the collaboration request you accepted. Reason: ${decision.reason}`,
              timestamp: nowIso,
              status: 'unread',
              pushSent: false,
            }),
          });
        }
      }
      continue;
    }
    const leadAssistant = acceptedCollaborators[0];
    const suspendedAlerts = await suspendAcceptedAssistantAlerts(
      env,
      token,
      acceptedCollaborators,
      alertsMap,
      {
        activeShift,
        collaborationRequestId: reqId,
      },
    );
    const patch = {
      status: 'approved',
      pmApproved: true,
      pmApprovedBy: 'ai_shift_commander',
      pmApprovedShiftId: activeShift.id,
      pmApprovedAt: nowIso,
      aiDecision: 'approved',
      aiConfidence: Number(decision.confidence.toFixed(4)),
      aiReason: decision.reason,
      aiChecks: decision.checks,
    };
    const [patchRes, alertUpdateRes] = await Promise.all([
      fetch(
        `${env.FB_DB_URL}collaboration_requests/${reqId}.json?auth=${token}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        },
      ),
      req.alertId
        ? fetch(`${env.FB_DB_URL}alerts/${req.alertId}.json?auth=${token}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              collaborators: acceptedCollaborators,
              assistantId: leadAssistant?.id || null,
              assistantName: leadAssistant?.name || null,
            }),
          })
        : Promise.resolve({ ok: true }),
    ]);
    if (patchRes.ok) {
      processed++;
      await writeShiftAiLog(env, token, activeShift.id, {
      kind: 'collaboration',
        alertLabel:
          req.alertTitle ||
          req.alertLabel ||
          req.alertType ||
          req.alertId ||
          'Collaboration request',
        supervisorName: req.requesterName || req.requesterFullName || null,
        supervisorId: req.requesterId || null,
        factory: req.factoryName || req.usine || null,
        confidence: decision.confidence,
        reason:
          `Approved collaboration request ${reqId} for shift "${activeShift.name || activeShift.id}". ` +
          `Assistant approvals: ${acceptedCount}/${denominator}. ` +
          `AI judgement: ${decision.reason} ` +
          `${suspendedAlerts.length > 0
            ? `Suspended ${suspendedAlerts.length} pre-existing claimed alert(s) so assistants start collaboration with a clean workload. `
            : ''}` +
          `Requester: ${req.requesterName || req.requesterFullName || req.requesterId || 'Unknown'}. ` +
          `${acceptedCollaborators.length > 0
            ? (alertUpdateRes.ok
                ? `Attached ${acceptedCollaborators.length} collaborator(s) to alert ${req.alertId || 'unknown'}.`
                : 'Alert collaborator sync failed.')
            : 'No collaborator roster was supplied, so only the collaboration request was approved.'}`,
      });
      // Notify the requester so the UI updates.
      if (req.requesterId) {
        await fetch(
          `${env.FB_DB_URL}notifications/${req.requesterId}.json?auth=${token}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              type: 'collab_auto_approved',
              message: `AI Shift Commander approved your collaboration request. Reason: ${decision.reason}`,
              alertId: req.alertId || null,
              collabRequestId: reqId,
              collaborationId: reqId,
              timestamp: nowIso,
              status: 'unread',
              pushSent: false,
            }),
          },
        );
      }
      if (acceptedCollaborators.length > 0) {
        for (const collaborator of acceptedCollaborators) {
          await fetch(
            `${env.FB_DB_URL}notifications/${collaborator.id}.json?auth=${token}`,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                type: 'collaboration_approved',
                message: `AI Shift Commander approved your collaboration request. You can now assist on this alert. Reason: ${decision.reason}`,
                alertId: req.alertId || null,
                collabRequestId: reqId,
                collaborationId: reqId,
                timestamp: nowIso,
                status: 'unread',
                pushSent: false,
              }),
            },
          );
        }
      }
    }
  }
  return processed;
}

// ============ Workers AI shift handover ============
async function generateShiftHandoverSummary(env, ctx, shift) {
  const alertsMap = ctx?.alertsMap || {};
  // Aggregate alerts that fell within this shift window since shift start.
  const items = [];
  let resolved = 0;
  let pending = 0;
  let critical = 0;
  for (const [, a] of Object.entries(alertsMap)) {
    if (!a) continue;
    const ts = _toMs(a.timestamp);
    if (ts == null) continue;
    // Cap to the last 12 hours to keep the prompt small.
    if (ts < Date.now() - 12 * 60 * 60 * 1000) continue;
    if (a.status === 'validee') resolved++;
    if (a.status !== 'validee') pending++;
    if (a.isCritical === true) critical++;
    if (items.length < 12) {
      items.push({
        type: a.type,
        usine: a.usine,
        status: a.status,
        critical: !!a.isCritical,
        elapsedMin: a.elapsedTime,
        description: (a.description || '').slice(0, 120),
      });
    }
  }
  let summary = `Shift "${shift.name || shift.id}" summary — Resolved: ${resolved}, Pending: ${pending}, Critical: ${critical}.`;
  // Try Workers AI for a richer summary.
  if (env && env.AI && typeof env.AI.run === 'function') {
    try {
      const prompt =
        `You are an industrial shift handover assistant. Write a concise (5 lines max) handover summary for the incoming shift. ` +
        `Resolved: ${resolved}, Pending: ${pending}, Critical: ${critical}. ` +
        `Recent alerts JSON: ${JSON.stringify(items).slice(0, 1800)}. ` +
        `Highlight risks, what needs attention next, and any cross-factory follow-ups.`;
      const out = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
        messages: [
          { role: 'system', content: 'You are concise, factual, and action-oriented.' },
          { role: 'user', content: prompt },
        ],
      });
      const text = out?.response || out?.result?.response;
      if (text && typeof text === 'string') {
        summary = text.trim();
      }
    } catch (e) {
      console.error('[SHIFT-AI] handover failed: ' + e.message);
    }
  }
  return { summary, resolved, pending, critical };
}

// Detects shifts within ~10 minutes of ending with AI Commander enabled and
// generates a handover summary exactly once (idempotent: skips if one was
// already produced within the last 15 minutes).
async function processShiftEnding(env, ctx) {
  const shiftsMap = ctx?.shiftsMap;
  if (!shiftsMap) return 0;
  const now = new Date();
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  let handoverCount = 0;
  for (const [id, shift] of Object.entries(shiftsMap || {})) {
    if (!shift || shift.aiCommander !== true) continue;
    if (!_shiftContainsTime(shift, nowMin)) continue;
    const e = Number(shift.endMinutes ?? 0);
    const s = Number(shift.startMinutes ?? 0);
    const endAbs = e >= s ? e : 1440 + e;
    const nowAbs = nowMin >= s ? nowMin : 1440 + nowMin;
    const minsToEnd = endAbs - nowAbs;
    if (minsToEnd > 10 || minsToEnd < 0) continue;
    // Skip if a handover was already generated within the last 15 minutes.
    const lastIso = shift.lastHandoverAt;
    if (lastIso && Date.now() - Date.parse(lastIso) < 15 * 60 * 1000) continue;
    const result = await generateShiftHandoverSummary(env, ctx, { id, ...shift });
    const nowIso = new Date().toISOString();
    await fetch(`${env.FB_DB_URL}shifts/${id}.json?auth=${ctx.token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        lastHandoverSummary: result.summary,
        lastHandoverAt: nowIso,
      }),
    });
    const supIds =
      shift.supervisors && typeof shift.supervisors === 'object'
        ? Object.keys(shift.supervisors)
        : [];
    for (const uid of supIds) {
      await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${ctx.token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'shift_handover',
          message: `Auto handover for "${shift.name || id}"`,
          alertDescription: result.summary,
          shiftId: id,
          timestamp: nowIso,
          status: 'unread',
        }),
      });
    }
    await writeShiftAiLog(env, ctx.token, id, {
      kind: 'handover',
      confidence: 1,
      reason:
        `Generated live handover for shift "${shift.name || id}". ` +
        `Resolved ${result.resolved}, pending ${result.pending}, critical ${result.critical}. ` +
        `Summary: ${result.summary}`,
    });
    handoverCount++;
  }
  return handoverCount;
}

// ============================================================================
// SHIFT PRESENCE ENGINE
// ============================================================================
// For each active shift, tracks supervisor presence (Active/Inactive/Absent/
// PendingConfirm) and writes per-supervisor state to `shift_presence/{shiftId}`.
// Inactivity = no claim/resolve activity for >= PRESENCE_INACTIVITY_MS.
// On crossing that threshold, a Confirm Presence FCM is sent and the
// supervisor is placed in `pending_confirm` for PRESENCE_CONFIRM_WINDOW_MS.
// If no confirmation arrives, status flips to `inactive`.

const PRESENCE_INACTIVITY_MS = 60 * 60 * 1000; // 1 hour
const PRESENCE_CONFIRM_WINDOW_MS = 30 * 60 * 1000; // 30 minutes
const PRESENCE_ABSENT_GRACE_MS = 5 * 60 * 1000; // 5-minute join grace at shift start

function _lastSupervisorActivity(alertsMap, supervisorId) {
  let latest = 0;
  for (const a of Object.values(alertsMap || {})) {
    if (!a) continue;
    if (a.superviseurId === supervisorId || a.assistantId === supervisorId) {
      const t = _toMs(a.takenAtTimestamp);
      if (t && t > latest) latest = t;
      const r = _toMs(a.resolvedAt);
      if (r && r > latest) latest = r;
    }
  }
  return latest > 0 ? latest : null;
}

async function _readPresenceMap(env, token, shiftId) {
  try {
    const url = `${env.FB_DB_URL}shift_presence/${shiftId}.json?auth=${token}`;
    const res = await fetch(url);
    if (!res.ok) return {};
    const data = await res.json();
    return (data && typeof data === 'object') ? data : {};
  } catch (_) {
    return {};
  }
}

async function _patchPresence(env, token, shiftId, supervisorId, payload) {
  try {
    const url = `${env.FB_DB_URL}shift_presence/${shiftId}/${supervisorId}.json?auth=${token}`;
    await fetch(url, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.warn('[PRESENCE] patch failed: ' + e.message);
  }
}

async function _sendConfirmPresenceFcm(env, user, shift) {
  const fcmToken = user?.fcmToken;
  if (!fcmToken) return false;
  const title = 'AI Shift Commander';
  const body = "We haven't seen activity from you in a while. Are you still on shift?";
  const result = await sendFcmDetailed(
    fcmToken,
    title,
    body,
    {
      type: 'confirm_presence',
      notifType: 'confirm_presence',
      shiftId: shift.id || '',
      shiftName: shift.name || '',
      requestedAt: new Date().toISOString(),
    },
    env,
    { uid: user._uid || '' },
  );
  return !!result.ok;
}

// Runs every cron tick. Returns the number of presence transitions written.
async function runShiftPresenceCheck(env, ctx) {
  const shiftsMap = ctx?.shiftsMap;
  const usersMap = ctx?.usersMap || {};
  const alertsMap = ctx?.alertsMap || {};
  const token = ctx?.token;
  if (!shiftsMap || !token) return 0;
  const now = new Date();
  const nowMs = now.getTime();
  const nowIso = now.toISOString();
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();

  let transitions = 0;

  for (const [shiftId, shift] of Object.entries(shiftsMap)) {
    if (!shift || !_shiftContainsTime(shift, nowMin)) continue;
    const supsRaw = shift.supervisors && typeof shift.supervisors === 'object'
      ? shift.supervisors
      : {};
    const supEntries = Object.entries(supsRaw);
    if (supEntries.length === 0) continue;

    // Determine shift start in absolute ms for absent grace.
    const startMin = Number(shift.startMinutes ?? 0);
    const endMin = Number(shift.endMinutes ?? 0);
    const minutesIntoShift = (() => {
      if (endMin >= startMin) return nowMin - startMin;
      return nowMin >= startMin ? nowMin - startMin : 1440 - startMin + nowMin;
    })();

    const existing = await _readPresenceMap(env, token, shiftId);
    const seenInExisting = new Set();
    const presenceSnapshotEntries = [];
    let snapshotShouldFire = false;

    for (const [uid, supEntry] of supEntries) {
      seenInExisting.add(uid);
      const user = usersMap[uid] || {};
      const supName =
        (supEntry && (supEntry.name || supEntry.fullName)) ||
        (user.firstName ? `${user.firstName} ${user.lastName || ''}`.trim() : '') ||
        uid;
      const factory =
        (supEntry && supEntry.factory) ||
        user.usine || user.factoryName || '';
      const current = existing[uid] || {};
      const currentStatus = String(current.status || '').toLowerCase();
      const lastActivityMs = _lastSupervisorActivity(alertsMap, uid);
      const lastActivityIso = lastActivityMs
        ? new Date(lastActivityMs).toISOString()
        : null;
      const idleMs = lastActivityMs ? (nowMs - lastActivityMs) : null;
      const confirmedAtMs = _toMs(current.confirmedAt);
      const confirmRequestedAtMs = _toMs(current.confirmRequestedAt);
      const confirmExpiresAtMs = _toMs(current.confirmExpiresAt);

      let nextStatus = 'active';
      const payload = {
        name: supName,
        factory,
      };

      const hasFcm = !!user.fcmToken;
      const hasEverBeenSeen =
        confirmedAtMs || lastActivityMs || _toMs(current.joinedAt);

      if (!hasFcm) {
        // No token at all – absent.
        nextStatus = 'absent';
      } else if (!hasEverBeenSeen && minutesIntoShift * 60 * 1000 > PRESENCE_ABSENT_GRACE_MS) {
        // Shift has been running for more than the grace period and this
        // supervisor has shown zero activity — absent.
        nextStatus = 'absent';
      } else if (currentStatus === 'pending_confirm' && confirmExpiresAtMs && nowMs > confirmExpiresAtMs) {
        // Confirm window elapsed without a tap → inactive.
        nextStatus = 'inactive';
        payload.inactiveSince = current.inactiveSince || nowIso;
        payload.confirmRequestedAt = null;
        payload.confirmExpiresAt = null;
      } else if (currentStatus === 'pending_confirm') {
        // Still waiting on the user.
        nextStatus = 'pending_confirm';
      } else if (confirmedAtMs && nowMs - confirmedAtMs < PRESENCE_INACTIVITY_MS) {
        // Recently tapped Confirm Presence — keep active.
        nextStatus = 'active';
      } else if (idleMs != null && idleMs >= PRESENCE_INACTIVITY_MS) {
        // 1h+ idle. Send a Confirm Presence push and enter pending.
        const sent = await _sendConfirmPresenceFcm(env, { ...user, _uid: uid }, { id: shiftId, ...shift });
        nextStatus = 'pending_confirm';
        payload.confirmRequestedAt = nowIso;
        payload.confirmExpiresAt = new Date(nowMs + PRESENCE_CONFIRM_WINDOW_MS).toISOString();
        payload.inactiveSince = null;
        if (!sent) {
          // FCM failed — promote directly to inactive so PM sees the state.
          nextStatus = 'inactive';
          payload.inactiveSince = nowIso;
        }
      } else if (idleMs == null && !confirmedAtMs && minutesIntoShift * 60 * 1000 > PRESENCE_ABSENT_GRACE_MS) {
        // In shift, has FCM, never claimed/resolved anything, no confirm yet.
        // Mark inactive after the join grace window (one-time bookkeeping).
        nextStatus = 'inactive';
        payload.inactiveSince = current.inactiveSince || nowIso;
      } else {
        nextStatus = 'active';
      }

      // Track status duration for the UI.
      const prevStatus = currentStatus;
      let anchorMs;
      switch (nextStatus) {
        case 'active':
          anchorMs = confirmedAtMs || lastActivityMs || _toMs(current.joinedAt) || nowMs;
          break;
        case 'pending_confirm':
          anchorMs = _toMs(payload.confirmRequestedAt) || confirmRequestedAtMs || nowMs;
          break;
        case 'inactive':
          anchorMs = _toMs(payload.inactiveSince) || _toMs(current.inactiveSince) || nowMs;
          break;
        case 'absent':
        default:
          anchorMs = _toMs(current.joinedAt) || nowMs;
          break;
      }
      const statusDurationSeconds = Math.max(0, Math.floor((nowMs - anchorMs) / 1000));

      payload.status = nextStatus;
      payload.lastActiveAt = lastActivityIso || current.lastActiveAt || null;
      payload.joinedAt = current.joinedAt || nowIso;
      payload.statusDurationSeconds = statusDurationSeconds;

      if (prevStatus !== nextStatus) {
        transitions++;
      }

      // First-time write OR status transition triggers presence_snapshot emission.
      if (!existing[uid] || prevStatus !== nextStatus) {
        snapshotShouldFire = true;
      }

      await _patchPresence(env, token, shiftId, uid, payload);

      presenceSnapshotEntries.push({
        name: supName,
        factory,
        status: nextStatus,
      });
    }

    // Clean up presence rows for supervisors no longer in the roster.
    for (const oldUid of Object.keys(existing)) {
      if (!seenInExisting.has(oldUid)) {
        try {
          await fetch(`${env.FB_DB_URL}shift_presence/${shiftId}/${oldUid}.json?auth=${token}`, {
            method: 'DELETE',
          });
        } catch (_) {}
      }
    }

    // Write a single AI Commander log when presence state meaningfully changes.
    if (snapshotShouldFire && presenceSnapshotEntries.length > 0) {
      const active = presenceSnapshotEntries.filter((p) => p.status === 'active').length;
      const pending = presenceSnapshotEntries.filter((p) => p.status === 'pending_confirm').length;
      const inactive = presenceSnapshotEntries.filter((p) => p.status === 'inactive').length;
      const absent = presenceSnapshotEntries.filter((p) => p.status === 'absent').length;
      const activeNames = presenceSnapshotEntries
        .filter((p) => p.status === 'active')
        .map((p) => p.name)
        .filter(Boolean);
      const absentNames = presenceSnapshotEntries
        .filter((p) => p.status === 'absent')
        .map((p) => p.name)
        .filter(Boolean);
      const inactiveNames = presenceSnapshotEntries
        .filter((p) => p.status === 'inactive')
        .map((p) => p.name)
        .filter(Boolean);
      const headline =
        `Presence snapshot: ${active} active, ${inactive} inactive, ${absent} absent` +
        (pending > 0 ? `, ${pending} awaiting confirmation` : '') +
        ` (${presenceSnapshotEntries.length} on roster).`;
      const detailLines = [
        `Active (${active}): ${activeNames.join(', ') || '—'}`,
        `Inactive (${inactive}): ${inactiveNames.join(', ') || '—'}`,
        `Absent (${absent}): ${absentNames.join(', ') || '—'}`,
      ];
      await writeShiftAiLog(env, token, shiftId, {
        kind: 'presence_snapshot',
        reason: headline,
        details: detailLines.join('\n'),
        confidence: 1,
      });
    }
  }
  return transitions;
}

async function handleShiftAiAction(request, env) {
  // This endpoint runs shift evaluations and triggers Llama-based handover
  // summary generation, so it gets full guard treatment.
  const guard = await _securityGuard(request, env, {
    endpoint: 'shift-ai-action',
    requireBody: true,
    textFields: ['shiftId', 'action'],
  });
  if (!guard.ok) return guard.response;

  try {
    const body = guard.body || {};
    const action = String(body?.action || 'evaluate').toLowerCase();
    const shiftId = body?.shiftId ? String(body.shiftId) : null;
    const coreCtx = await loadCoreData(env);
    let shift = null;
    if (shiftId && coreCtx.shiftsMap?.[shiftId]) {
      shift = { id: shiftId, ...coreCtx.shiftsMap[shiftId] };
    } else {
      shift = coreCtx.activeShift;
    }

    if (action === 'evaluate' || action === 'created' || action === 'updated') {
      const targetShiftId = shift?.id ?? null;
      const actionCtx = shift ? cloneCtxWithShift(coreCtx, shift) : coreCtx;
      if (targetShiftId) {
        await writeShiftAiLog(env, coreCtx.token, targetShiftId, {
          kind: action,
          reason: `AI Shift Commander received "${action}" for shift "${shift?.name || targetShiftId}" and started a live evaluation cycle.`,
        });
      }
      // Re-run AI assignment + collaboration approval immediately.
      const assignedCount = await runAIAssignments(env, actionCtx);
      const collaborationCount = await processShiftCollaborations(env, actionCtx);
      if (targetShiftId && assignedCount === 0 && collaborationCount === 0) {
        await writeShiftAiLog(env, coreCtx.token, targetShiftId, {
          kind: 'idle',
          reason:
            `Evaluation finished for shift "${shift?.name || targetShiftId}" with no new assignments or collaboration approvals to apply.`,
        });
      }
      return new Response(
        JSON.stringify({
          ok: true,
          action,
          shiftId: shift?.id ?? null,
          assignedCount,
          collaborationCount,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (action === 'handover') {
      if (!shift) {
        return new Response(JSON.stringify({ ok: false, error: 'No shift' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      const result = await generateShiftHandoverSummary(env, coreCtx, shift);
      const nowIso = new Date().toISOString();
      // Persist last handover on the shift node.
      await fetch(`${env.FB_DB_URL}shifts/${shift.id}.json?auth=${coreCtx.token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          lastHandoverSummary: result.summary,
          lastHandoverAt: nowIso,
        }),
      });
      // Notify each shift supervisor with the summary.
      const supIds =
        shift.supervisors && typeof shift.supervisors === 'object'
          ? Object.keys(shift.supervisors)
          : [];
      for (const uid of supIds) {
        await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${coreCtx.token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            type: 'shift_handover',
            message: `Handover for "${shift.name || shift.id}"`,
            alertDescription: result.summary,
            shiftId: shift.id,
            timestamp: nowIso,
            status: 'unread',
          }),
        });
      }
      await writeShiftAiLog(env, coreCtx.token, shift.id, {
        kind: 'handover',
        confidence: 1,
        reason:
          `Generated on-demand handover for shift "${shift.name || shift.id}". ` +
          `Resolved ${result.resolved}, pending ${result.pending}, critical ${result.critical}. ` +
          `Summary: ${result.summary}`,
      });
      return new Response(
        JSON.stringify({
          ok: true,
          summary: result.summary,
          stats: {
            resolved: result.resolved,
            pending: result.pending,
            critical: result.critical,
          },
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(JSON.stringify({ ok: false, error: 'Unknown action' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: e.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ /suggest-assignee (scoring restored) ============
async function handleSuggestAssignee(request, env) {
  const guard = await _securityGuard(request, env, {
    endpoint: 'suggest-assignee',
  });
  if (!guard.ok) return guard.response;

  try {
    const url = new URL(request.url);
    // We sanitize the query-string alertId so a crafted parameter cannot
    // smuggle path-traversal tokens into the downstream Firebase REST call.
    const alertId = _securitySanitizeText(
      String(url.searchParams.get('alertId') || '').trim(),
      256,
    );
    if (!alertId) {
      return new Response(JSON.stringify({ error: 'alertId required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const coreCtx = await loadCoreData(env);
    const alert = coreCtx.alertsMap?.[alertId];
    if (!alert) {
      return new Response(JSON.stringify({ error: 'alert not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    let feedbackSummary = {};
    try {
      const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${coreCtx.token}`);
      if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
    } catch (e) {}
    const supStats = buildSupStats(coreCtx.alertsMap || {});
    const busy = new Set();
    for (const a of Object.values(coreCtx.alertsMap || {})) {
      if (a?.status === 'en_cours') {
        if (a.superviseurId) busy.add(a.superviseurId);
        if (a.assistantId) busy.add(a.assistantId);
      }
    }
    const targetFid = aiResolveFactory(alert);
    const now = Date.now();
    const candidates = [];
    for (const [uid, u] of Object.entries(coreCtx.usersMap || {})) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      const userFid = aiResolveFactory(u);
      if (!targetFid || !userFid || userFid !== targetFid) continue;
      const recent = Object.values(coreCtx.alertsMap || {}).filter(
        (a) =>
          a.superviseurId === uid &&
          a.takenAtTimestamp &&
          now - new Date(a.takenAtTimestamp).getTime() < 10 * 60 * 1000,
      ).length;
      const cand = {
        uid,
        name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(),
        fcmToken: u.fcmToken,
        usine: u.usine,
        factoryId: u.factoryId,
        status: u.status,
        busy: busy.has(uid),
      };
      const { score, reasons } = scoreSupervisor(
        { ...cand, uid },
        alert,
        supStats,
        feedbackSummary,
        recent,
        now,
      );
      candidates.push({ ...cand, score, reasons });
    }
    candidates.sort((a, b) => b.score - a.score);
    const top3 = candidates.slice(0, 3);
    const topSum = top3.reduce((s, c) => s + c.score, 0);
    const best = top3[0];
    const confidence = best && topSum > 0 ? Math.min(1.0, best.score / topSum) : 0;
    return new Response(
      JSON.stringify({
        alertId,
        best: best
          ? {
              uid: best.uid,
              name: best.name,
              score: best.score,
              reasons: best.reasons,
              busy: best.busy,
              status: best.status,
            }
          : null,
        confidence: Number(confidence.toFixed(2)),
        confidencePct: Math.round(confidence * 100),
        runners: top3.slice(1).map((c) => ({
          uid: c.uid,
          name: c.name,
          score: c.score,
          busy: c.busy,
        })),
        candidateCount: candidates.length,
        generatedAt: new Date().toISOString(),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ /config placeholder ============
function handleConfigRequest() {
  return new Response(JSON.stringify({ message: 'Config endpoint deprecated' }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ============ Health monitoring helper ============
// Persists a single rolling "last cron run" snapshot under
// workers/health/lastRun. Now also includes `securityActions` — the total
// number of security blocks (rate-limit hits, prompt-injection rejections,
// anomaly-triggered records) seen during the run. The developer UI subscribes
// to this node and surfaces every counter in real time.
async function _writeCronHealth(token, env, {
  runStart,
  assignmentsMade,
  collaborationsApproved,
  handoversGenerated,
  errors,
  securityActions,
  lstmPredictions,
}) {
  if (!token || !env?.FB_DB_URL) return;
  try {
    await fetch(`${env.FB_DB_URL}workers/health/lastRun.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        timestamp: new Date().toISOString(),
        assignmentsMade,
        collaborationsApproved,
        handoversGenerated,
        errors,
        durationMs: Date.now() - runStart,
        // New: security agent telemetry. Field is always present so the
        // Flutter side can deserialize without conditional decoding.
        securityActions: Number(securityActions || 0),
        lstmPredictions: Number(lstmPredictions || 0),
      }),
    });
  } catch (e) {
    console.error('[CRON] Health write failed: ' + e.message);
  }
}

// ============ Main export ============
export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        const runStart = Date.now();
        const healthErrors = [];
        let assignmentsMade = 0;
        let collaborationsApproved = 0;
        let handoversGenerated = 0;
        let securityActions = 0;
        let lstmPredictions = 0;
        let cronToken;
        let lockUrl;

        // Reset the per-run security counter at the START of each tick.
        // HTTP handlers that block requests between cron ticks will have
        // bumped this counter; we want the *current* tick's number, so we
        // capture the existing value and reset to zero now. The captured
        // total still flows into the health pulse — see step 3 below.
        const carriedOverActions = _securityGetActions();
        _securityResetActions();

        // ── Step 1: acquire cron lock to prevent overlapping executions ─────────
        // Uses ETag optimistic locking on a Firebase node. If the last lock
        // timestamp is < 55 s old, another execution is still in flight — skip.
        try {
          cronToken = await getFirebaseToken(env);
          lockUrl = `${env.FB_DB_URL}cron_lock/ai.json?auth=${cronToken}`;
          const lockGet = await fetch(lockUrl, { headers: { 'X-Firebase-ETag': 'true' } });
          const lockEtag = lockGet.ok ? lockGet.headers.get('ETag') : null;
          const lockData = lockGet.ok ? (await lockGet.json()) : null;
          if (lockData && typeof lockData.ts === 'number' && Date.now() - lockData.ts < 55000) {
            console.log('[CRON] Skipping: another execution in flight (' + (Date.now() - lockData.ts) + 'ms ago)');
            return;
          }
          const lockPut = await fetch(lockUrl, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'if-match': lockEtag ?? '*' },
            body: JSON.stringify({ ts: Date.now() }),
          });
          if (lockPut.status === 412) {
            console.log('[CRON] Skipping: concurrent execution acquired lock');
            return;
          }
        } catch (e) {
          console.warn('[CRON] Lock acquisition failed, proceeding anyway: ' + e.message);
          healthErrors.push('lock: ' + e.message);
        }

        // ── Step 2: load shared data and run all cron tasks ──────────────────────
        let coreCtx;
        try {
          coreCtx = await loadCoreData(env);
        } catch (e) {
          console.error('[CRON] Failed to load core data: ' + e.message);
          healthErrors.push('loadCoreData: ' + e.message);
          await _writeCronHealth(cronToken, env, {
            runStart,
            assignmentsMade,
            collaborationsApproved,
            handoversGenerated,
            errors: healthErrors,
            securityActions: carriedOverActions,
            lstmPredictions,
          });
          if (lockUrl) fetch(lockUrl, { method: 'DELETE' }).catch(() => {});
          return;
        }

        const runValidation = _cronEvery(runStart, VALIDATION_CRON_INTERVAL_MIN);
        const runPredictive = _cronEvery(runStart, PREDICTIVE_CRON_INTERVAL_MIN);
        const runLstm = LSTM_CRON_ENABLED && runPredictive && _cronEvery(runStart, LSTM_CRON_INTERVAL_MIN);
        const runSecurityScan = _cronEvery(runStart, SECURITY_SCAN_INTERVAL_MIN);

        try { await checkEscalations(env, coreCtx); }
        catch (e) { console.error('[CRON] checkEscalations: ' + e.message); healthErrors.push('checkEscalations: ' + e.message); }

        try { assignmentsMade = (await runAIAssignments(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] runAIAssignments: ' + e.message); healthErrors.push('runAIAssignments: ' + e.message); }

        try { collaborationsApproved = (await processShiftCollaborations(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] processShiftCollaborations: ' + e.message); healthErrors.push('processShiftCollaborations: ' + e.message); }

        try { handoversGenerated = (await processShiftEnding(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] processShiftEnding: ' + e.message); healthErrors.push('processShiftEnding: ' + e.message); }

        try { await runShiftPresenceCheck(env, coreCtx); }
        catch (e) { console.error('[CRON] runShiftPresenceCheck: ' + e.message); healthErrors.push('runShiftPresenceCheck: ' + e.message); }

        if (runValidation) {
          try { await validatePredictions(env, coreCtx); }
          catch (e) { console.error('[CRON] validatePredictions: ' + e.message); healthErrors.push('validatePredictions: ' + e.message); }
        }

        let basePredictiveModel = null;
        if (runPredictive) {
          try {
            basePredictiveModel = buildPredictiveModel(coreCtx.alertsMap || {});
            await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`, {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(basePredictiveModel),
            });
          } catch (e) {
            console.error('[CRON] buildPredictiveModel: ' + e.message);
            healthErrors.push('buildPredictiveModel: ' + e.message);
          }
        }

        if (runLstm) {
          try {
            const lstmForecasts = await _runLstmForecast(env, coreCtx);
            lstmPredictions = lstmForecasts.length;
            if (lstmForecasts.length > 0) {
              await fetch(`${env.FB_DB_URL}ai_predictions/lstm.json?auth=${coreCtx.token}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  generatedAt: new Date().toISOString(),
                  predictions: lstmForecasts,
                }),
              });

              let latestModel = basePredictiveModel;
              try {
                const latestRes = await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`);
                if (latestRes.ok) {
                  const latestData = await latestRes.json();
                  if (latestData && typeof latestData === 'object') latestModel = latestData;
                }
              } catch (_) {}

              let lstmPayload = { predictions: lstmForecasts, generatedAt: new Date().toISOString() };
              try {
                const lstmRes = await fetch(`${env.FB_DB_URL}ai_predictions/lstm.json?auth=${coreCtx.token}`);
                if (lstmRes.ok) {
                  const lstmData = await lstmRes.json();
                  if (lstmData && typeof lstmData === 'object') lstmPayload = lstmData;
                }
              } catch (_) {}

              const enriched = _mergeLstmIntoPredictiveModel(latestModel || {}, lstmPayload);
              await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(enriched),
              });
              }
          } catch (e) {
            console.error('[LSTM] Forecast cycle failed: ' + e.message);
          }
        }

        // ── Step 2b: Security AI agent — anomaly scan ──────────────────────────
        // Runs after the core data is fully loaded so it sees the same
        // alertsMap / usersMap the rest of the pipeline saw. Returns the
        // number of security actions it took (logged blocks). Errors here
        // are swallowed — the security scan must never break the cron run.
        if (runSecurityScan) {
          try {
            await _runSecurityAnomalyScan(env, coreCtx);
          } catch (e) {
            console.error('[CRON] securityAnomalyScan: ' + e.message);
            healthErrors.push('securityScan: ' + e.message);
          }
        }

        try {
          await _securityFlushSiemOutbox(env, coreCtx);
        } catch (e) {
          console.error('[CRON] securitySiemExport: ' + e.message);
          healthErrors.push('securitySiemExport: ' + e.message);
        }

        // Capture the final total: blocks accumulated from inter-cron
        // HTTP handlers plus blocks the cron itself took inside the scan.
        securityActions = carriedOverActions + _securityGetActions();

        // ── Step 3: write health pulse ────────────────────────────────────────────
        await _writeCronHealth(coreCtx.token, env, {
          runStart,
          assignmentsMade,
          collaborationsApproved,
          handoversGenerated,
          errors: healthErrors,
          securityActions,
          lstmPredictions,
        });

        // ── Step 4: release lock ──────────────────────────────────────────────────
        if (lockUrl) fetch(lockUrl, { method: 'DELETE' }).catch(() => {});
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // ── LSTM prediction endpoint ─────────────────────────────────────────
    if (url.pathname === '/predict-lstm') {
      const guard = await _securityGuard(request, env, {
        endpoint: 'predict-lstm',
        requireBody: true,
      });
      if (!guard.ok) return guard.response;

      try {
        const hfUrl = 'https://kubixdesiney-alertsys-lstm.hf.space/predict';
        const raw = await fetch(hfUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ features: guard.body.features }),
        });
        const data = await raw.json();
        return new Response(JSON.stringify(data), {
          status: raw.ok ? 200 : raw.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (e) {
        return new Response(JSON.stringify({ ok: false, error: 'LSTM model unreachable' }), {
          status: 502,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // /config is dirt-cheap but we still apply a rate limit to keep an
    // attacker from using it as a heartbeat probe.
    if (url.pathname === '/config') {
      const g = await _securityGuard(request, env, { endpoint: 'config' });
      if (!g.ok) return g.response;
      return handleConfigRequest();
    }

    // /security-status — read-only diagnostic endpoint used by the
    // Developer tab in the admin app. Rate-limited because it touches RTDB.
    if (url.pathname === '/security-status') {
      const g = await _securityGuard(request, env, { endpoint: 'security-status' });
      if (!g.ok) return g.response;
      return handleSecurityStatus(env);
    }

    if (url.pathname === '/ai-proxy') return handleAiProxy(request, env);
    if (url.pathname === '/ai-suggest') return handleAiSuggest(request, env);
    if (url.pathname === '/predict') return handlePredictions(request, env);
    if (url.pathname === '/briefing') return handleBriefing(request, env);
    if (url.pathname === '/suggest-assignee') return handleSuggestAssignee(request, env);
    if (url.pathname === '/auto-fix') return handleAutoFix(request, env);
    if (url.pathname === '/auto-fix-full') return handleAutoFixFull(request, env);
    if (url.pathname === '/shift-ai-action') return handleShiftAiAction(request, env);
    if (url.pathname === '/validate-predictions') return handleValidatePredictions(request, env);

    // /ai-retry kicks off a full AI assignment pass. Pre-rate-limit-guard
    // is critical here — it touches Llama and writes to RTDB. Without the
    // guard an attacker could trigger overlapping expensive runs.
    if (url.pathname === '/ai-retry') {
      const g = await _securityGuard(request, env, { endpoint: 'ai-retry' });
      if (!g.ok) return g.response;
      ctx.waitUntil(runAIAssignments(env, null));
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Default trigger: run AI/security work only. Notification fan-out is handled by cloudflare_notify_worker.js.
    const defaultGuard = await _securityGuard(request, env, {
      endpoint: 'default',
    });
    if (!defaultGuard.ok) return defaultGuard.response;
    try {
      const coreCtx = await loadCoreData(env);
      await checkEscalations(env, coreCtx);
      await runAIAssignments(env, coreCtx);
      await processShiftCollaborations(env, coreCtx);
      await runShiftPresenceCheck(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error: ' + e.message);
    }
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};

// Test-only named exports
export {
  aiSanitizeFactoryId,
  aiResolveFactory,
  buildSupStats,
  scoreSupervisor,
  inferFactoryLocation,
  haversineDistance,
  runAIAssignments,
  checkEscalations,
  buildPredictiveModel,
  notifTitle,
  base64UrlEncode,
  getFcmRecipientsForFactory,
  getFcmTokensForFactory,
  sendFcmDetailed,
  _toMs,
  _briefingDateKey,
  _aggregateWeek,
  _briefingFactorySlug,
  _topSupervisorWeek,
  _typeName,
  pickActiveShift,
  _shiftContainsTime,
  _writeCronHealth,
  validatePredictions,
  _historyKey,
  _buildDailyFeatures,
  _fitGlobalScaler,
  _scaleFeatures,
  _runLstmForecast,
  processShiftCollaborations,
  suspendAcceptedAssistantAlerts,
  _buildAssistantAlertSuspensionPatch,
  _securityDetectPromptInjection,
  _securityEventToEcsDocument,
  _securityBuildElasticBulkNdjson,
  _securityFlushSiemOutbox,
  _securityElasticConfig,
};
