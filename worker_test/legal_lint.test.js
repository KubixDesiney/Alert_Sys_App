// Legal pack: the consistency linter's pure helpers, the store worker's
// LEGAL_PUBLISH gate on /legal, and the embedded-markdown renderer.
import worker, { legalPublishEnabled, renderMarkdownDoc } from '../cloudflare_store_worker.js';
import { LEGAL_DOCS } from '../store_legal_content.js';
import {
  findPlaceholders,
  findNameViolations,
  findForbiddenClaims,
  checkCrossReferences,
  lintLegalDocs,
  isMostlyUppercase,
} from '../tool/legal_lint.mjs';

describe('findPlaceholders', () => {
  test('lists unresolved markers with line numbers', () => {
    const text = 'ok line\n[[PLACEHOLDER: governing law]] here\nplain\ntwo [[PLACEHOLDER: a]] [[PLACEHOLDER: b]]';
    const found = findPlaceholders(text);
    expect(found).toHaveLength(3);
    expect(found[0]).toMatchObject({ line: 2 });
    expect(found[1].line).toBe(4);
    expect(findPlaceholders('[[PLACEHOLDER]] without colon')).toHaveLength(0);
    expect(findPlaceholders('')).toHaveLength(0);
  });
});

describe('findNameViolations', () => {
  test('flags misspelled/misspaced company names', () => {
    expect(findNameViolations('Signed by Kubix Desiney.')).toHaveLength(1);
    expect(findNameViolations('per kubixdesiney policy')).toHaveLength(1);
    expect(findNameViolations('KubixDesiney provides the Service.')).toHaveLength(0);
  });

  test('allows ALL-CAPS company name only inside all-caps disclaimer lines', () => {
    expect(findNameViolations('KUBIXDESINEY DISCLAIMS ALL OTHER WARRANTIES, WHETHER EXPRESS OR IMPLIED.')).toHaveLength(0);
    expect(findNameViolations('Contact KUBIXDESINEY for details.')).toHaveLength(1);
  });

  test('flags the hyphenated and stale product forms', () => {
    expect(findNameViolations('SIAS - Smart Industrial Alert System is great')).toHaveLength(1);
    expect(findNameViolations('SIAS — Smart Industrial Alert System is great')).toHaveLength(0);
    expect(findNameViolations('the Smart Industrial Alert (SIA) app')).toHaveLength(1);
    expect(findNameViolations('Smart Industrial Alert - SIA v2')).toHaveLength(1);
  });

  test('isMostlyUppercase requires substance, not just shouting a word', () => {
    expect(isMostlyUppercase('NO WARRANTY OF ANY KIND WHATSOEVER')).toBe(true);
    expect(isMostlyUppercase('OK')).toBe(false);
    expect(isMostlyUppercase('normal sentence')).toBe(false);
  });
});

describe('findForbiddenClaims', () => {
  test('blocks certification claims in any casing', () => {
    expect(findForbiddenClaims('We are SOC 2 certified.')).toHaveLength(1);
    expect(findForbiddenClaims('SIAS is SOC 2 Type II certified today')).toHaveLength(1);
    expect(findForbiddenClaims('iso 27001 certified infrastructure')).toHaveLength(1);
    expect(findForbiddenClaims('ISO 27001 compliant hosting')).toHaveLength(1);
    expect(findForbiddenClaims('SOC 2 is on our roadmap.')).toHaveLength(0);
    expect(findForbiddenClaims('pursuing ISO 27001 certification')).toHaveLength(0);
  });

  test('blocks bare "guarantee" but allows money-back/uptime/disclaimer contexts', () => {
    expect(findForbiddenClaims('We guarantee zero downtime.')).toHaveLength(1);
    expect(findForbiddenClaims('30-day money-back guarantee applies.')).toHaveLength(0);
    expect(findForbiddenClaims('does not guarantee any outcome')).toHaveLength(0);
    expect(findForbiddenClaims('uptime guarantee of 99.9%')).toHaveLength(0);
    expect(findForbiddenClaims('any guarantee at all', { file: 'SLA.md' })).toHaveLength(0);
  });

  test('context window spans hard-wrapped lines', () => {
    const wrapped = 'Customer may request a full refund of its first payment.\nThis guarantee applies once per Customer.';
    expect(findForbiddenClaims(wrapped)).toHaveLength(0);
  });
});

describe('checkCrossReferences', () => {
  test('MSA must reference DPA.md and SLA.md', () => {
    expect(checkCrossReferences({ 'MSA.md': 'incorporates DPA.md and SLA.md' })).toHaveLength(0);
    const missing = checkCrossReferences({ 'MSA.md': 'standalone text' });
    expect(missing).toHaveLength(2);
    expect(checkCrossReferences({ 'EULA.md': 'no msa here' })).toHaveLength(0);
  });
});

describe('lintLegalDocs on the real pack', () => {
  test('current drafts have zero blocking violations', async () => {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const dir = path.join(process.cwd(), 'docs', 'legal');
    const files = {};
    for (const name of fs.readdirSync(dir).filter((f) => f.endsWith('.md'))) {
      files[name] = fs.readFileSync(path.join(dir, name), 'utf8');
    }
    const { violations, placeholders } = lintLegalDocs(files);
    expect(violations).toEqual([]);
    expect(placeholders.length).toBeGreaterThan(0); // counsel work is honestly outstanding
  });
});

describe('/legal routes gated by LEGAL_PUBLISH', () => {
  const get = (p, env = {}) => worker.fetch(new Request(`https://sias-store.example${p}`), env);

  test('gate helper only accepts the literal "true"', () => {
    expect(legalPublishEnabled({ LEGAL_PUBLISH: 'true' })).toBe(true);
    expect(legalPublishEnabled({ LEGAL_PUBLISH: 'TRUE' })).toBe(false);
    expect(legalPublishEnabled({ LEGAL_PUBLISH: '1' })).toBe(false);
    expect(legalPublishEnabled({})).toBe(false);
    expect(legalPublishEnabled(undefined)).toBe(false);
  });

  test('404s everywhere without the env flag', async () => {
    expect((await get('/legal')).status).toBe(404);
    expect((await get('/legal/privacy')).status).toBe(404);
    expect((await get('/legal/terms')).status).toBe(404);
    expect((await get('/legal/privacy', { LEGAL_PUBLISH: 'false' })).status).toBe(404);
  });

  test('serves index and documents when enabled; unknown slug still 404s', async () => {
    const env = { LEGAL_PUBLISH: 'true' };
    const idx = await get('/legal', env);
    expect(idx.status).toBe(200);
    expect(await idx.text()).toContain('Legal documents');
    const privacy = await get('/legal/privacy', env);
    expect(privacy.status).toBe(200);
    const body = await privacy.text();
    expect(body).toContain('Privacy Policy');
    expect(body).toContain('requires review by qualified counsel');
    expect((await get('/legal/nonexistent', env)).status).toBe(404);
  });

  test('landing footer links appear only when published', async () => {
    const off = await get('/', {}).then((r) => r.text());
    expect(off).not.toContain('/legal/privacy');
    const on = await get('/', { LEGAL_PUBLISH: 'true' }).then((r) => r.text());
    expect(on).toContain('/legal/privacy');
    expect(on).toContain('/legal/terms');
  });
});

describe('renderMarkdownDoc', () => {
  test('escapes HTML before rendering markdown', () => {
    const out = renderMarkdownDoc('# Title\n\n<script>alert(1)</script> and **bold**');
    expect(out).toContain('<h1>Title</h1>');
    expect(out).not.toContain('<script>');
    expect(out).toContain('&lt;script&gt;');
    expect(out).toContain('<strong>bold</strong>');
  });

  test('renders blockquotes, lists, hr and code', () => {
    const out = renderMarkdownDoc('> **DRAFT** banner\n\n---\n\n1. first\n2. second\n\n- a\n- b\n\n`inline` code');
    expect(out).toContain('<blockquote><strong>DRAFT</strong> banner</blockquote>');
    expect(out).toContain('<hr>');
    expect(out).toContain('<ol><li>first</li><li>second</li></ol>');
    expect(out).toContain('<ul><li>a</li><li>b</li></ul>');
    expect(out).toContain('<code>inline</code>');
  });

  test('embedded documents match their docs/legal sources byte-for-byte', async () => {
    const fs = await import('node:fs');
    const path = await import('node:path');
    for (const doc of Object.values(LEGAL_DOCS)) {
      const src = fs.readFileSync(path.join(process.cwd(), 'docs', 'legal', doc.sourceFile), 'utf8');
      expect(doc.markdown).toBe(src);
    }
  });
});
