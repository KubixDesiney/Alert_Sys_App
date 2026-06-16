// Guardian joint Fix <-> Review collaboration loop.
// =================================================
// This is the "advanced" core: TWO independent AIs (any providers from
// guardian_providers.mjs) plus the real validator work TOGETHER in rounds:
//
//   1. Fix AI proposes a patch (full-file replacement blocks).
//   2. Review AI critiques it -> structured VERDICT: APPROVE | REVISE + notes.
//   3. If APPROVE, the real validator runs (node --check / tests). A validator
//      failure re-enters the loop as a critique -> the validator is a third
//      participant, not an afterthought.
//   4. Fix AI revises using the critique. Repeat until APPROVE + validator-green
//      or maxRounds is hit.
//
// Pure builders/parsers are exported and unit-tested (worker_test/joint_fix.test.js);
// callModel is injected so tests need no network. A CLI at the bottom lets the
// GitHub Actions drill run it for real.

import { callModel } from './guardian_providers.mjs';

/** Parse Fix-AI output into [{path, content}] from <<<FILE path>>> ... <<<END>>> blocks. */
export function parseFixResponse(text) {
  if (!text || typeof text !== 'string') return [];
  const out = [];
  const re = /<<<FILE\s+([^\n>]+)>>>\n?([\s\S]*?)\n?<<<END>>>/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const path = m[1].trim();
    let content = m[2];
    if (content.endsWith('\n')) content = content.slice(0, -1);
    if (path) out.push({ path, content });
  }
  return out;
}

/** Parse Review-AI output into a structured verdict. */
export function parseReviewVerdict(text) {
  const raw = String(text || '');
  const m = raw.match(/VERDICT\s*:\s*(APPROVE|REVISE|REJECT)/i);
  const word = (m && m[1].toUpperCase()) || (/\bapprove(d)?\b/i.test(raw) && !/\brevise|reject/i.test(raw) ? 'APPROVE' : 'REVISE');
  const approved = word === 'APPROVE';
  let critique = raw;
  if (m) critique = raw.slice(m.index + m[0].length).trim() || raw.trim();
  return { approved, verdict: word, critique: critique.trim(), raw };
}

export function buildFixPrompt({ failure, files, priorCritique, round }) {
  const fileDump = Object.entries(files || {})
    .map(([p, c]) => `<<<FILE ${p}>>>\n${c}\n<<<END>>>`)
    .join('\n\n');
  return [
    `You are the FIX engineer in a two-AI repair team. Round ${round}.`,
    `A failure was detected in the Smart Industrial Alert codebase. Repair it with the SMALLEST correct change.`,
    '',
    `FAILURE / DIAGNOSTIC:\n${failure}`,
    priorCritique ? `\nThe REVIEW engineer (or the validator) rejected your last attempt:\n${priorCritique}\nAddress this precisely.` : '',
    '',
    `CURRENT FILE(S):\n${fileDump}`,
    '',
    'Respond with ONLY the corrected file(s), each as exactly:',
    '<<<FILE relative/path>>>',
    '<full corrected file content>',
    '<<<END>>>',
    'No prose, no explanation, no markdown fences. Preserve everything except the minimal fix.',
  ].filter(Boolean).join('\n');
}

export function buildReviewPrompt({ failure, proposal, files }) {
  const proposed = (proposal || [])
    .map((f) => `<<<FILE ${f.path}>>>\n${f.content}\n<<<END>>>`)
    .join('\n\n');
  return [
    'You are the REVIEW engineer in a two-AI repair team. Be strict and independent.',
    `Judge whether the proposed patch correctly and safely fixes the failure with minimal blast radius.`,
    '',
    `FAILURE / DIAGNOSTIC:\n${failure}`,
    '',
    `PROPOSED PATCH:\n${proposed}`,
    '',
    'Check: does it actually fix the failure? Is it syntactically valid? Does it avoid unrelated changes, secrets, or unsafe edits?',
    'Reply with the FIRST line exactly:',
    'VERDICT: APPROVE   (if you would merge it as-is)',
    'or',
    'VERDICT: REVISE    (if anything is wrong)',
    'Then, if REVISE, give a short, specific critique the fix engineer can act on.',
  ].join('\n');
}

/**
 * Run the joint loop. Injected `call` defaults to callModel.
 */
export async function runJointFix(o) {
  const { failure, files, fix, review, validate, maxRounds = 3, call = callModel, log = () => {} } = o;
  const transcript = [];
  let priorCritique = '';
  let working = { ...files };

  for (let round = 1; round <= maxRounds; round++) {
    log(`round ${round}: fix engineer (${fix.provider}/${fix.model || 'default'}) proposing patch`);
    const fixText = await call({
      provider: fix.provider, model: fix.model, apiKey: fix.apiKey, baseUrl: fix.baseUrl,
      system: 'You output only corrected source files in the requested block format.',
      user: buildFixPrompt({ failure, files: working, priorCritique, round }),
    });
    transcript.push({ round, role: 'fix', text: fixText });
    const proposal = parseFixResponse(fixText);
    if (!proposal.length) {
      priorCritique = 'Your previous response contained no parseable <<<FILE>>> block. Re-send the full corrected file(s).';
      log(`round ${round}: no file block parsed, asking again`);
      continue;
    }

    log(`round ${round}: review engineer (${review.provider}/${review.model || 'default'}) judging`);
    const reviewText = await call({
      provider: review.provider, model: review.model, apiKey: review.apiKey, baseUrl: review.baseUrl,
      system: 'You are a strict, independent code reviewer. First line must be the VERDICT.',
      user: buildReviewPrompt({ failure, proposal, files: working }),
    });
    transcript.push({ round, role: 'review', text: reviewText });
    const verdict = parseReviewVerdict(reviewText);

    if (!verdict.approved) {
      priorCritique = verdict.critique || 'Reviewer requested changes.';
      log(`round ${round}: REVISE -> ${priorCritique.slice(0, 140)}`);
      continue;
    }

    const candidate = { ...working };
    for (const f of proposal) candidate[f.path] = f.content;

    if (validate) {
      log(`round ${round}: APPROVE -> running validator`);
      const v = await validate(candidate);
      transcript.push({ round, role: 'validate', text: v.detail || (v.ok ? 'ok' : 'failed') });
      if (!v.ok) {
        priorCritique = `The validator rejected the approved patch:\n${v.detail || 'validation failed'}`;
        working = candidate;
        log(`round ${round}: validator FAILED -> back to fix engineer`);
        continue;
      }
    }

    log(`round ${round}: APPROVED and validated`);
    return { ok: true, rounds: round, files: candidate, proposal, verdict, transcript };
  }

  return { ok: false, rounds: maxRounds, files: working, transcript, reason: 'max_rounds_exhausted' };
}

// ---- CLI (used by .github/workflows/guardian-drill.yml) ----
function argMap(argv) {
  const m = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const k = argv[i].slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
      m[k] = v;
    }
  }
  return m;
}

async function mainCli() {
  const fs = await import('node:fs');
  const { checkSyntaxContent } = await import('./guardian_drill.mjs');
  const args = argMap(process.argv.slice(2));
  const targets = (args.files || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!targets.length) {
    console.error('usage: guardian_joint_fix.mjs --files a.js,b.js [--failure "..."] [--max 3]');
    process.exit(2);
  }
  const failure = args.failure || process.env.GUARDIAN_FAILURE || `Build/check failing in: ${targets.join(', ')}`;
  const files = {};
  for (const t of targets) files[t] = fs.readFileSync(t, 'utf8');

  const fix = {
    provider: process.env.GUARDIAN_FIX_PROVIDER || 'anthropic',
    model: process.env.GUARDIAN_FIX_MODEL || '',
    apiKey: process.env.GUARDIAN_FIX_API_KEY || process.env.ANTHROPIC_API_KEY || '',
    baseUrl: process.env.GUARDIAN_FIX_BASE_URL || '',
  };
  const review = {
    provider: process.env.GUARDIAN_REVIEW_PROVIDER || 'openai',
    model: process.env.GUARDIAN_REVIEW_MODEL || '',
    apiKey: process.env.GUARDIAN_REVIEW_API_KEY || process.env.OPENAI_API_KEY || '',
    baseUrl: process.env.GUARDIAN_REVIEW_BASE_URL || '',
  };

  const validate = async (candidate) => {
    for (const [p, c] of Object.entries(candidate)) {
      const r = checkSyntaxContent(p, c);
      if (!r.ok && !r.skipped) return { ok: false, detail: `node --check ${p}: ${r.detail}` };
    }
    return { ok: true };
  };

  const res = await runJointFix({
    failure, files, fix, review, validate,
    maxRounds: Number(args.max || 3),
    log: (l) => console.log(`[joint] ${l}`),
  });

  if (res.ok) {
    for (const [p, c] of Object.entries(res.files)) fs.writeFileSync(p, c);
    console.log(`[joint] SUCCESS in ${res.rounds} round(s); wrote ${Object.keys(res.files).length} file(s).`);
    process.exit(0);
  } else {
    console.error(`[joint] FAILED after ${res.rounds} round(s): ${res.reason}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  mainCli().catch((e) => { console.error('[joint] crashed:', e); process.exit(3); });
}
