#!/usr/bin/env node
// =============================================================================
// Kubix chat analytics — turns a CSV export of the sias_chats data table into
// an operator-readable quality report.
// =============================================================================
// Usage: node tool/kubix_chat_report.mjs path/to/sias_chats.csv [--top 15]
//
// Expected columns (header names are matched case-insensitively and tolerate
// the n8n data-table export variants): sessionId, message, reply, escalated,
// createdAt (or created_at / date / timestamp). Extra columns are ignored.
// Pure Node — no network, no dependencies; helpers are unit-tested in
// worker_test/kubix_chat_report.test.js.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** RFC-4180-ish CSV parser: quoted fields, escaped quotes, CRLF. Returns an
 *  array of row objects keyed by the (trimmed) header names. */
export function parseCsv(text) {
  const rows = [];
  let field = '';
  let record = [];
  let inQuotes = false;
  const src = String(text ?? '');
  const pushField = () => { record.push(field); field = ''; };
  const pushRecord = () => {
    if (record.length > 1 || record[0] !== '') rows.push(record);
    record = [];
  };
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (inQuotes) {
      if (c === '"') {
        if (src[i + 1] === '"') { field += '"'; i++; } else inQuotes = false;
      } else field += c;
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ',') {
      pushField();
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && src[i + 1] === '\n') i++;
      pushField();
      pushRecord();
    } else {
      field += c;
    }
  }
  if (field !== '' || record.length) { pushField(); pushRecord(); }
  if (rows.length === 0) return [];
  const headers = rows[0].map((h) => h.trim());
  return rows.slice(1).map((r) => {
    const obj = {};
    headers.forEach((h, i) => { obj[h] = r[i] ?? ''; });
    return obj;
  });
}

const FIELD_ALIASES = {
  sessionId: ['sessionid', 'session_id', 'session'],
  message: ['message', 'question', 'user_message', 'input'],
  reply: ['reply', 'answer', 'bot_reply', 'response', 'output'],
  escalated: ['escalated', 'escalation', 'is_escalated'],
  createdAt: ['createdat', 'created_at', 'date', 'timestamp', 'at', 'created'],
};

/** Maps arbitrary export headers onto the canonical chat-row shape. */
export function normalizeRow(raw) {
  const lower = {};
  for (const [k, v] of Object.entries(raw || {})) lower[k.trim().toLowerCase()] = v;
  const pick = (canon) => {
    for (const alias of FIELD_ALIASES[canon]) {
      if (lower[alias] !== undefined && lower[alias] !== '') return lower[alias];
    }
    return '';
  };
  const escRaw = String(pick('escalated')).trim().toLowerCase();
  return {
    sessionId: String(pick('sessionId')).trim(),
    message: String(pick('message')),
    reply: String(pick('reply')),
    escalated: ['true', '1', 'yes', 'y'].includes(escRaw),
    createdAt: String(pick('createdAt')).trim(),
  };
}

export function dayOf(createdAt) {
  const d = new Date(createdAt);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

/** Distinct sessions seen per calendar day (UTC), sorted chronologically. */
export function sessionsPerDay(rows) {
  const byDay = new Map();
  for (const r of rows) {
    const day = dayOf(r.createdAt);
    if (!day || !r.sessionId) continue;
    if (!byDay.has(day)) byDay.set(day, new Set());
    byDay.get(day).add(r.sessionId);
  }
  return [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, set]) => ({ day, sessions: set.size }));
}

/** Fraction of sessions that hit at least one escalation (0..1). */
export function escalationRate(rows) {
  const sessions = new Set();
  const escalated = new Set();
  for (const r of rows) {
    if (!r.sessionId) continue;
    sessions.add(r.sessionId);
    if (r.escalated) escalated.add(r.sessionId);
  }
  return sessions.size === 0 ? 0 : escalated.size / sessions.size;
}

const STOPWORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'to', 'of', 'in', 'on', 'for', 'with', 'at', 'by',
  'is', 'are', 'was', 'be', 'been', 'do', 'does', 'did', 'can', 'could', 'will', 'would',
  'i', 'we', 'you', 'it', 'my', 'our', 'your', 'me', 'us', 'this', 'that', 'these', 'those',
  'how', 'what', 'when', 'where', 'why', 'who', 'which', 'not', 'no', 'yes', 'have', 'has',
  'le', 'la', 'les', 'un', 'une', 'des', 'de', 'du', 'et', 'ou', 'est', 'sont', 'je', 'nous',
  'vous', 'il', 'elle', 'mon', 'ma', 'mes', 'notre', 'votre', 'ce', 'cette', 'ces', 'que',
  'qui', 'quoi', 'comment', 'pourquoi', 'dans', 'sur', 'pour', 'avec', 'pas', 'ne',
]);

/** Most frequent non-stopword words across user messages. */
export function topQuestionWords(rows, limit = 15) {
  const counts = new Map();
  for (const r of rows) {
    const words = String(r.message).toLowerCase().match(/[a-zà-ÿ0-9][a-zà-ÿ0-9'-]{2,}/gi) || [];
    for (const w of words) {
      if (STOPWORDS.has(w)) continue;
      counts.set(w, (counts.get(w) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, limit)
    .map(([word, count]) => ({ word, count }));
}

export function medianReplyLength(rows) {
  const lengths = rows.map((r) => String(r.reply).length).filter((n) => n > 0).sort((a, b) => a - b);
  if (lengths.length === 0) return 0;
  const mid = Math.floor(lengths.length / 2);
  return lengths.length % 2 ? lengths[mid] : Math.round((lengths[mid - 1] + lengths[mid]) / 2);
}

export function buildReport(rows, { top = 15 } = {}) {
  return {
    totalMessages: rows.length,
    totalSessions: new Set(rows.map((r) => r.sessionId).filter(Boolean)).size,
    sessionsPerDay: sessionsPerDay(rows),
    escalationRate: escalationRate(rows),
    topQuestionWords: topQuestionWords(rows, top),
    medianReplyLength: medianReplyLength(rows),
  };
}

function main() {
  const argv = process.argv.slice(2);
  const csvPath = argv.find((a) => !a.startsWith('--'));
  const topIdx = argv.indexOf('--top');
  const top = topIdx >= 0 ? Number(argv[topIdx + 1]) || 15 : 15;
  if (!csvPath) {
    console.error('Usage: node tool/kubix_chat_report.mjs <sias_chats.csv> [--top 15]');
    process.exit(1);
  }
  if (!fs.existsSync(csvPath)) {
    console.error(`✗ File not found: ${csvPath}`);
    process.exit(1);
  }
  const rows = parseCsv(fs.readFileSync(csvPath, 'utf8')).map(normalizeRow);
  const report = buildReport(rows, { top });

  console.log('Kubix chat report');
  console.log('─'.repeat(46));
  console.log(`Messages          ${report.totalMessages}`);
  console.log(`Sessions          ${report.totalSessions}`);
  console.log(`Escalation rate   ${(report.escalationRate * 100).toFixed(1)}% of sessions`);
  console.log(`Median reply      ${report.medianReplyLength} chars`);
  console.log('\nSessions per day');
  for (const { day, sessions } of report.sessionsPerDay) {
    console.log(`  ${day}  ${'█'.repeat(Math.min(sessions, 40))} ${sessions}`);
  }
  console.log('\nTop question words');
  for (const { word, count } of report.topQuestionWords) {
    console.log(`  ${word.padEnd(20)} ${count}`);
  }
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) main();
