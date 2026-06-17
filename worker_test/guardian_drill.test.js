import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { injectFault, checkSyntaxContent, checkSyntax } from '../tool/guardian_drill.mjs';

describe('injectFault', () => {
  test('removes the last closing brace and reports it', () => {
    const r = injectFault('function f() { return 1; }');
    expect(r.ok).toBe(true);
    expect(r.bracket).toBe('}');
    expect(r.broken).toBe('function f() { return 1; ');
    expect((r.broken.match(/}/g) || []).length).toBe(0);
  });

  test('falls back to ) or ] when no } present', () => {
    expect(injectFault('const a = (1 + 2);').bracket).toBe(')');
    expect(injectFault('const a = [1, 2];').bracket).toBe(']');
  });

  test('rejects empty / bracketless input', () => {
    expect(injectFault('').ok).toBe(false);
    expect(injectFault('no brackets here').ok).toBe(false);
    expect(injectFault(null).ok).toBe(false);
  });

  test('the injected content is genuinely unbalanced', () => {
    const src = 'export function f() {\n  return { a: 1 };\n}\n';
    const r = injectFault(src);
    const opens = (r.broken.match(/[{([]/g) || []).length;
    const closes = (r.broken.match(/[)\]}]/g) || []).length;
    expect(closes).toBe(opens - 1);
  });
});

describe('checkSyntaxContent (ESM-aware)', () => {
  const tmp = (name) => path.join(os.tmpdir(), `gdrill_${Date.now()}_${name}`);

  test('valid ES module passes', () => {
    const r = checkSyntaxContent(tmp('ok.mjs'), 'export const x = 1;\n');
    expect(r.ok).toBe(true);
  });

  test('unclosed ES module fails', () => {
    const r = checkSyntaxContent(tmp('bad.mjs'), 'export function f() {\n  return 1;\n');
    expect(r.ok).toBe(false);
    expect(r.detail).toMatch(/SyntaxError|Unexpected/i);
  });

  test('export-bearing .js with an unclosed brace is caught (CJS would miss it)', () => {
    const r = checkSyntaxContent(tmp('export.js'), 'export function f() {\n  return 1;\n');
    expect(r.ok).toBe(false);
  });

  test('non-JS path is skipped (treated ok)', () => {
    const r = checkSyntaxContent(tmp('readme.md'), '# not code {');
    expect(r.skipped).toBe(true);
    expect(r.ok).toBe(true);
  });
});

describe('checkSyntax round-trips with injectFault on disk', () => {
  const p = path.join(os.tmpdir(), `gdrill_rt_${Date.now()}.mjs`);

  afterAll(() => { try { fs.rmSync(p, { force: true }); } catch (_) {} });

  test('valid -> inject -> broken -> restore -> valid', () => {
    const original = 'export function f() {\n  return 1 + 2;\n}\n';
    fs.writeFileSync(p, original);
    expect(checkSyntax(p).ok).toBe(true);

    const broken = injectFault(fs.readFileSync(p, 'utf8')).broken;
    fs.writeFileSync(p, broken);
    expect(checkSyntax(p).ok).toBe(false);

    fs.writeFileSync(p, original);
    expect(checkSyntax(p).ok).toBe(true);
  });
});
