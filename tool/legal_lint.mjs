#!/usr/bin/env node
// =============================================================================
// Legal-pack consistency linter — keeps docs/legal/*.md coherent and honest.
// =============================================================================
// Checks (npm run legal:lint):
//   1. Unresolved [[PLACEHOLDER: ...]] markers → counted WARNING list (exit 0).
//      These are counsel's decisions to make; the linter's job is to surface
//      them, not to block CI on them.
//   2. Company/product naming — only "KubixDesiney" and the em-dash product
//      form "SIAS — Smart Industrial Alert System" are allowed → VIOLATION.
//   3. Forbidden claims — "SOC 2 certified" / "ISO 27001 certified" anywhere,
//      and "guarantee" outside the SLA / money-back / uptime contexts
//      → VIOLATION. (SOC 2 / ISO 27001 are roadmap items; claiming them is a
//      misrepresentation.)
//   4. Cross-reference integrity — the MSA must reference DPA.md and SLA.md
//      → VIOLATION when missing.
//   5. Published-copy drift — when store_legal_content.js (the copy served by
//      the store worker's gated /legal routes) no longer matches docs/legal
//      → WARNING to re-run `npm run legal:embed`.
// Exit code: 1 on any VIOLATION; 0 otherwise (warnings included).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const PLACEHOLDER_RE = /\[\[PLACEHOLDER:[^\]]*\]\]/g;

/** All unresolved [[PLACEHOLDER: ...]] markers with their line numbers. */
export function findPlaceholders(text) {
  const out = [];
  const lines = String(text ?? '').split('\n');
  lines.forEach((line, i) => {
    for (const m of line.matchAll(PLACEHOLDER_RE)) {
      out.push({ line: i + 1, marker: m[0].length > 90 ? `${m[0].slice(0, 87)}...` : m[0] });
    }
  });
  return out;
}

// Naming: every "kubix...desiney"-shaped token must be exactly "KubixDesiney",
// and the long product form must use the em dash. The stale pre-rename product
// names are flagged outright.
const NAME_CHECKS = [
  {
    // "KUBIXDESINEY" is fine inside conventional ALL-CAPS disclaimer text.
    re: /kubix[\s_-]+desiney|kubixdesiney/gi,
    ok: (m, line) => m === 'KubixDesiney' || (m === 'KUBIXDESINEY' && isMostlyUppercase(line)),
    hint: 'company name must be exactly "KubixDesiney"',
  },
  {
    re: /SIAS\s+-\s+Smart Industrial Alert System/g,
    ok: () => false,
    hint: 'product long form must use an em dash: "SIAS — Smart Industrial Alert System"',
  },
  {
    re: /Smart Industrial Alert\s*(\(SIA\)|-\s*SIA\b)/g,
    ok: () => false,
    hint: 'stale pre-rename product name — use "SIAS — Smart Industrial Alert System"',
  },
];

/** True when a line is conventional ALL-CAPS legal text (disclaimers). */
export function isMostlyUppercase(line) {
  const letters = String(line ?? '').replace(/[^a-zA-Z]/g, '');
  if (letters.length < 12) return false;
  const upper = letters.replace(/[^A-Z]/g, '').length;
  return upper / letters.length > 0.9;
}

/** Naming violations (wrong company casing/spacing, stale or hyphenated product forms). */
export function findNameViolations(text) {
  const out = [];
  const lines = String(text ?? '').split('\n');
  lines.forEach((line, i) => {
    for (const check of NAME_CHECKS) {
      for (const m of line.matchAll(check.re)) {
        if (!check.ok(m[0], line)) out.push({ line: i + 1, found: m[0], hint: check.hint });
      }
    }
  });
  return out;
}

const CERT_CLAIM_RE = /\b(SOC\s*2(\s+Type\s+(1|2|I|II))?|ISO\/?\s*27001)([\s-]+\w+){0,2}?[\s-]+(certified|certification\s+held|compliant)\b/gi;
const GUARANTEE_RE = /\bguarantees?\b/gi;
const GUARANTEE_ALLOWED_CONTEXT = /money[\s-]?back|refund|first\s+payment|service credit|uptime|no\s+guarantee|not\s+guarantee|cannot\s+guarantee|does\s+not\s+guarantee/i;

/** Forbidden marketing/legal claims. `file` exempts SLA.md's uptime language. */
export function findForbiddenClaims(text, { file = '' } = {}) {
  const out = [];
  const lines = String(text ?? '').split('\n');
  const isSla = /(^|\/)SLA\.md$/i.test(file);
  lines.forEach((line, i) => {
    for (const m of line.matchAll(CERT_CLAIM_RE)) {
      out.push({ line: i + 1, found: m[0], hint: 'SOC 2 / ISO 27001 are roadmap only — never claim certification' });
    }
    // Legal prose hard-wraps at ~80 cols, so the qualifying context ("refund",
    // "money-back", …) often sits on the previous or next physical line.
    const window = `${lines[i - 1] ?? ''} ${line} ${lines[i + 1] ?? ''}`;
    if (!isSla && !GUARANTEE_ALLOWED_CONTEXT.test(window)) {
      for (const m of line.matchAll(GUARANTEE_RE)) {
        out.push({ line: i + 1, found: m[0], hint: '"guarantee" only in SLA / money-back / disclaimer contexts' });
      }
    }
  });
  return out;
}

/** MSA must reference the DPA and the SLA it claims to incorporate. */
export function checkCrossReferences(files) {
  const out = [];
  const msaName = Object.keys(files).find((f) => /(^|\/)MSA\.md$/i.test(f));
  if (!msaName) return out;
  const msa = files[msaName];
  if (!/DPA\.md/.test(msa)) out.push({ file: msaName, hint: 'MSA must reference DPA.md' });
  if (!/SLA\.md/.test(msa)) out.push({ file: msaName, hint: 'MSA must reference SLA.md' });
  return out;
}

/** Full lint over {fileName: text}. Returns violations (blocking) + warnings. */
export function lintLegalDocs(files) {
  const violations = [];
  const placeholders = [];
  for (const [file, text] of Object.entries(files)) {
    for (const p of findPlaceholders(text)) placeholders.push({ file, ...p });
    for (const v of findNameViolations(text)) violations.push({ file, kind: 'naming', ...v });
    for (const v of findForbiddenClaims(text, { file })) violations.push({ file, kind: 'claim', ...v });
  }
  for (const v of checkCrossReferences(files)) violations.push({ kind: 'xref', ...v });
  return { violations, placeholders };
}

async function main() {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const legalDir = path.join(root, 'docs', 'legal');
  const files = {};
  for (const name of fs.readdirSync(legalDir).filter((f) => f.endsWith('.md')).sort()) {
    files[name] = fs.readFileSync(path.join(legalDir, name), 'utf8');
  }

  const { violations, placeholders } = lintLegalDocs(files);

  // Drift check: the copy embedded in the store worker vs the current drafts.
  const warnings = [];
  try {
    const { LEGAL_DOCS } = await import(pathToFileURL(path.join(root, 'store_legal_content.js')).href);
    for (const doc of Object.values(LEGAL_DOCS)) {
      const current = files[doc.sourceFile];
      if (current !== undefined && current !== doc.markdown) {
        warnings.push(`store_legal_content.js is stale for ${doc.sourceFile} — run \`npm run legal:embed\``);
      }
    }
  } catch {
    warnings.push('store_legal_content.js missing or unreadable — run `npm run legal:embed`');
  }

  console.log(`legal:lint — ${Object.keys(files).length} documents checked\n`);
  if (violations.length) {
    console.log(`✗ ${violations.length} violation(s):`);
    for (const v of violations) {
      console.log(`  ${v.file ?? ''}${v.line ? `:${v.line}` : ''}  [${v.kind}] ${v.found ? `"${v.found}" — ` : ''}${v.hint}`);
    }
    console.log('');
  }
  if (placeholders.length) {
    console.log(`⚠ ${placeholders.length} unresolved [[PLACEHOLDER]] marker(s) awaiting counsel (see docs/legal/COUNSEL_BRIEF.md):`);
    for (const p of placeholders) console.log(`  ${p.file}:${p.line}  ${p.marker}`);
    console.log('');
  }
  for (const w of warnings) console.log(`⚠ ${w}`);
  if (!violations.length) {
    console.log(`✓ No blocking violations. ${placeholders.length} placeholder(s), ${warnings.length} warning(s).`);
  }
  process.exit(violations.length ? 1 : 0);
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
