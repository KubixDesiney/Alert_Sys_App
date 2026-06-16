#!/usr/bin/env node
// Guardian drill: inject a REAL fault, then restore/verify.
// =========================================================
// --inject  --target <file>   : save the original, then remove a closing bracket
//                               so the file is genuinely broken (real syntax error).
// --restore --target <file>   : restore the exact original from the saved copy.
// --verify  --target <file>   : `node --check` the file; exit 0 if valid, 1 if broken.
//
// The saved original lives next to the repo under .guardian-drill/, so the
// workflow's always() safety step can restore main even if the AI fix fails.
//
// injectFault() is pure and unit-tested (worker_test/joint_fix.test.js covers the
// loop; this file is exercised live in CI and by the local verify run).

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const SAVE_DIR = '.guardian-drill';

/** Remove the last closing bracket to create a real "missing bracket" syntax error. */
export function injectFault(content) {
  if (typeof content !== 'string' || !content.length) return { ok: false, reason: 'empty' };
  for (const ch of ['}', ')', ']']) {
    const idx = content.lastIndexOf(ch);
    if (idx !== -1) {
      return {
        ok: true,
        bracket: ch,
        index: idx,
        broken: content.slice(0, idx) + content.slice(idx + 1),
      };
    }
  }
  return { ok: false, reason: 'no_bracket' };
}

function savePathFor(target) {
  const base = target.replace(/[\\/]/g, '__');
  return path.join(SAVE_DIR, base + '.orig');
}

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

function doInject(target) {
  const original = fs.readFileSync(target, 'utf8');
  const res = injectFault(original);
  if (!res.ok) {
    console.error(`[drill] cannot inject into ${target}: ${res.reason}`);
    process.exit(2);
  }
  fs.mkdirSync(SAVE_DIR, { recursive: true });
  fs.writeFileSync(savePathFor(target), original);
  fs.writeFileSync(target, res.broken);
  console.log(`[drill] injected fault into ${target}: removed a '${res.bracket}' at offset ${res.index}.`);
  console.log(`[drill] original saved to ${savePathFor(target)}`);
}

function doRestore(target) {
  const save = savePathFor(target);
  if (!fs.existsSync(save)) {
    console.error(`[drill] no saved original at ${save}; nothing to restore.`);
    process.exit(2);
  }
  fs.writeFileSync(target, fs.readFileSync(save, 'utf8'));
  fs.rmSync(save, { force: true });
  console.log(`[drill] restored ${target} from saved original.`);
}

// Node treats a plain `.js` file as CommonJS and will NOT flag an unclosed brace
// in `export`-bearing code. So for ES-module syntax we node --check a temporary
// `.mjs` copy, which parses in module mode and reliably catches the break.
export function checkSyntaxContent(filePath, content) {
  if (!/\.(mjs|js|cjs)$/.test(filePath)) return { ok: true, skipped: true };
  const isEsm = filePath.endsWith('.mjs') || /^\s*(export|import)\s/m.test(content);
  const tmp = `${filePath}.guardian-check.${isEsm ? 'mjs' : 'cjs'}`;
  fs.writeFileSync(tmp, content);
  try {
    execSync(`node --check "${tmp}"`, { stdio: 'pipe' });
    return { ok: true };
  } catch (e) {
    return { ok: false, detail: String(e.stderr || e.message).slice(0, 400) };
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

export function checkSyntax(target) {
  if (!/\.(mjs|js|cjs)$/.test(target)) return { ok: true, skipped: true };
  return checkSyntaxContent(target, fs.readFileSync(target, 'utf8'));
}

function doVerify(target) {
  const r = checkSyntax(target);
  if (r.skipped) {
    console.log(`[drill] verify: ${target} is not JS; skipping node --check (treated as ok).`);
    process.exit(0);
  }
  if (r.ok) {
    console.log(`[drill] verify: ${target} is syntactically valid.`);
    process.exit(0);
  }
  console.error(`[drill] verify: ${target} is BROKEN:\n${r.detail}`);
  process.exit(1);
}

function mainCli() {
  const args = argMap(process.argv.slice(2));
  const target = args.target;
  if (!target) {
    console.error('usage: guardian_drill.mjs --inject|--restore|--verify --target <file>');
    process.exit(2);
  }
  if (args.inject) return doInject(target);
  if (args.restore) return doRestore(target);
  if (args.verify) return doVerify(target);
  console.error('[drill] specify one of --inject | --restore | --verify');
  process.exit(2);
}

if (import.meta.url === `file://${process.argv[1]}`) mainCli();
