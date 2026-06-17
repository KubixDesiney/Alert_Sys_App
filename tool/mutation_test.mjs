#!/usr/bin/env node
// Zero-dependency mutation tester.
// =================================
// Mutation testing is the gold standard beyond line coverage: it changes the code
// in small ways ("mutants") and checks that the test suite NOTICES (fails). A mutant
// that survives = a real gap your line-coverage number hides.
//
// This implementation has no external deps (no Stryker): it applies a curated set
// of operators to ONE target file at a time, runs a test command per mutant, and
// reports the mutation score. The original is always restored (even on crash).
//
// Usage:
//   node tool/mutation_test.mjs --target <file> --cmd "<test command>" [--max N] [--bail]
// Example:
//   node tool/mutation_test.mjs --target tool/guardian_preflight.mjs \
//     --cmd "npm test -- worker_test/guardian_preflight.test.js"
//
// generateMutants() is pure and unit-tested (worker_test/mutation_test.test.js).

import fs from 'node:fs';
import { execSync } from 'node:child_process';

// Each operator flips a small piece of logic. Order matters only for reporting.
export const OPERATORS = [
  { name: '>=->>',        re: />=/g,        to: '>' },
  { name: '<=-><',        re: /<=/g,        to: '<' },
  { name: '===->!==',     re: /===/g,       to: '!==' },
  { name: '!==->===',     re: /!==/g,       to: '===' },
  { name: '&&->||',       re: /&&/g,        to: '||' },
  { name: '||->&&',       re: /\|\|/g,      to: '&&' },
  { name: 'true->false',  re: /\btrue\b/g,  to: 'false' },
  { name: 'false->true',  re: /\bfalse\b/g, to: 'true' },
];

/**
 * Produce one mutant per operator-occurrence in the source.
 * @returns {{op:string,index:number,line:number,mutated:string}[]}
 */
export function generateMutants(source, { max = 0 } = {}) {
  const mutants = [];
  if (typeof source !== 'string' || !source) return mutants;
  for (const op of OPERATORS) {
    const re = new RegExp(op.re.source, 'g');
    let m;
    while ((m = re.exec(source)) !== null) {
      const idx = m.index;
      const mutated = source.slice(0, idx) + op.to + source.slice(idx + m[0].length);
      const line = source.slice(0, idx).split('\n').length;
      mutants.push({ op: op.name, index: idx, line, mutated });
      if (re.lastIndex === idx) re.lastIndex++; // never loop on a zero-width match
    }
  }
  mutants.sort((a, b) => a.index - b.index);
  return max > 0 ? mutants.slice(0, max) : mutants;
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

function runCmd(cmd) {
  try {
    execSync(cmd, { stdio: 'pipe' });
    return 0;
  } catch (e) {
    return e.status || 1;
  }
}

function mainCli() {
  const args = argMap(process.argv.slice(2));
  const target = args.target;
  const cmd = args.cmd;
  if (!target || !cmd) {
    console.error('usage: mutation_test.mjs --target <file> --cmd "<test command>" [--max N] [--bail]');
    process.exit(2);
  }
  const original = fs.readFileSync(target, 'utf8');
  const mutants = generateMutants(original, { max: Number(args.max || 0) });
  if (!mutants.length) {
    console.log(`[mutation] no mutable tokens found in ${target}`);
    process.exit(0);
  }

  console.log(`[mutation] ${target}: ${mutants.length} mutants, running "${cmd}" for each`);
  // Confirm the suite is GREEN on the original first — otherwise scores are meaningless.
  if (runCmd(cmd) !== 0) {
    console.error('[mutation] baseline test run FAILED on the unmutated file; fix tests first.');
    process.exit(1);
  }

  const backup = `${target}.mutorig`;
  fs.writeFileSync(backup, original);
  let killed = 0;
  const survived = [];
  try {
    for (let i = 0; i < mutants.length; i++) {
      const mu = mutants[i];
      fs.writeFileSync(target, mu.mutated);
      const exit = runCmd(cmd);
      if (exit !== 0) {
        killed++;
      } else {
        survived.push(mu);
      }
      fs.writeFileSync(target, original); // restore between mutants
      process.stdout.write(exit !== 0 ? '.' : 'S');
      if (args.bail && survived.length) break;
    }
  } finally {
    fs.writeFileSync(target, original); // belt-and-suspenders restore
    fs.rmSync(backup, { force: true });
  }

  const total = killed + survived.length;
  const score = total ? Math.round((killed / total) * 1000) / 10 : 0;
  console.log(`\n[mutation] killed ${killed}/${total}  score ${score}%`);
  if (survived.length) {
    console.log('[mutation] survivors (test gaps):');
    for (const s of survived.slice(0, 25)) console.log(`  line ${s.line}: ${s.op}`);
  }
  const floor = Number(args.floor || 0);
  if (floor && score < floor) {
    console.error(`[mutation] score ${score}% below floor ${floor}%`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) mainCli();
