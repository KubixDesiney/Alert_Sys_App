// Invoice-led sales mode: quote intake validation, the quote_requested payload,
// the shared pricing module round-trip (worker and quote tool must serve
// identical figures), the /api/quote route, and the quote PDF tool.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { jest } from '@jest/globals';
import worker, {
  PLAN_CATALOG as WORKER_CATALOG,
  planPrice as workerPlanPrice,
  salesMode,
  validateQuoteIntake,
  quoteEventPayload,
} from '../cloudflare_store_worker.js';
import { PLAN_CATALOG, planPrice, listPrice } from '../pricing.mjs';
import {
  parseQuoteArgs,
  buildQuoteModel,
  formatAmount,
  generateQuotePdf,
} from '../tool/generate_quote.mjs';

const intake = (over = {}) => ({
  name: 'Amine Ben Salah',
  email: 'a.bensalah@nagati.example',
  company: 'Nagati Steel Works',
  country: 'Tunisia',
  factories: '2-3',
  plan: 'growth',
  billing: 'annual',
  notes: 'Siemens S7 estate',
  phone: '+216 12 345 678',
  currency: 'TND',
  ...over,
});

describe('sales mode', () => {
  test('defaults to quote; card restores checkout; junk falls back to quote', () => {
    expect(salesMode({})).toBe('quote');
    expect(salesMode(undefined)).toBe('quote');
    expect(salesMode({ SALES_MODE: 'quote' })).toBe('quote');
    expect(salesMode({ SALES_MODE: 'card' })).toBe('card');
    expect(salesMode({ SALES_MODE: 'CARD' })).toBe('card');
    expect(salesMode({ SALES_MODE: 'bitcoin' })).toBe('quote');
  });
});

describe('quote intake validation', () => {
  test('accepts a complete intake with phone and currency', () => {
    const v = validateQuoteIntake(intake());
    expect(v.ok).toBe(true);
    expect(v.clean.phone).toBe('+216 12 345 678');
    expect(v.clean.currency).toBe('TND');
    expect(v.clean.billing).toBe('annual');
    expect(v.clean.method).toBeUndefined();
  });

  test('unknown currency coerces to USD; missing phone is empty', () => {
    const v = validateQuoteIntake(intake({ currency: 'gbp', phone: undefined }));
    expect(v.ok).toBe(true);
    expect(v.clean.currency).toBe('USD');
    expect(v.clean.phone).toBe('');
    expect(validateQuoteIntake(intake({ currency: 'eur' })).clean.currency).toBe('EUR');
  });

  test('keeps the same rejection rules as the checkout intake', () => {
    expect(validateQuoteIntake(intake({ email: 'nope' })).ok).toBe(false);
    expect(validateQuoteIntake(intake({ plan: 'platinum' })).ok).toBe(false);
    expect(validateQuoteIntake(intake({ billing: 'weekly' })).ok).toBe(false);
    expect(validateQuoteIntake(null).ok).toBe(false);
  });

  test('monthly billing preference survives (no ClicToPay annual coercion)', () => {
    const v = validateQuoteIntake(intake({ billing: 'monthly' }));
    expect(v.ok).toBe(true);
    expect(v.clean.billing).toBe('monthly');
  });
});

describe('quote_requested payload', () => {
  test('carries the same customer shape as purchase_completed plus phone', () => {
    const { clean } = validateQuoteIntake(intake());
    const out = quoteEventPayload(clean, 'NSW#7K2F', 'qr_abc', 1780000000000);
    expect(out).toMatchObject({
      source: 'sias-store',
      eventId: 'qr_abc',
      type: 'quote_requested',
      tenantCode: 'NSW#7K2F',
      plan: 'growth',
      billing: 'annual',
      requestedCurrency: 'TND',
    });
    expect(out.occurredAt).toBe(new Date(1780000000000).toISOString());
    expect(out.customer).toEqual({
      name: 'Amine Ben Salah',
      email: 'a.bensalah@nagati.example',
      company: 'Nagati Steel Works',
      country: 'Tunisia',
      factories: '2-3',
      notes: 'Siemens S7 estate',
      phone: '+216 12 345 678',
    });
    expect(out.listPrice.usdCents).toBe(PLAN_CATALOG.growth.annual);
    expect(out.listPrice.tnd).toBe(PLAN_CATALOG.growth.tndAnnual);
  });

  test('monthly TND list price uses the monthly dinar figure', () => {
    const { clean } = validateQuoteIntake(intake({ billing: 'monthly', plan: 'starter' }));
    const out = quoteEventPayload(clean, 'X#Y', 'qr_x', 1780000000000);
    expect(out.listPrice.usdCents).toBe(PLAN_CATALOG.starter.monthly);
    expect(out.listPrice.tnd).toBe(PLAN_CATALOG.starter.tndMonthly);
  });
});

describe('pricing module round-trip', () => {
  test('worker and pricing.mjs export the exact same catalog object', () => {
    expect(WORKER_CATALOG).toBe(PLAN_CATALOG);
    expect(workerPlanPrice('growth', 'annual')).toEqual(planPrice('growth', 'annual'));
  });

  test('listPrice matches the catalog in every currency', () => {
    expect(listPrice('starter', 'monthly', 'USD')).toBe(590);
    expect(listPrice('starter', 'annual', 'USD')).toBe(5880);
    expect(listPrice('growth', 'annual', 'TND')).toBe(PLAN_CATALOG.growth.tndAnnual);
    expect(listPrice('growth', 'monthly', 'TND')).toBe(PLAN_CATALOG.growth.tndMonthly);
    expect(listPrice('growth', 'annual', 'EUR')).toBeNull();
    expect(listPrice('nope', 'annual', 'USD')).toBeNull();
  });
});

describe('/api/quote route', () => {
  const post = (body, env = {}) =>
    worker.fetch(
      new Request('https://sias-store.example/api/quote', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': `q-${Math.random()}` },
        body: typeof body === 'string' ? body : JSON.stringify(body),
      }),
      env,
    );

  test('rejects junk bodies with 400', async () => {
    const res = await post('{not json');
    expect(res.status).toBe(400);
    const bad = await post(intake({ email: 'nope' }));
    expect(bad.status).toBe(400);
  });

  test('returns 503 when the intake webhook is unconfigured', async () => {
    const res = await post(intake());
    expect(res.status).toBe(503);
  });

  test('forwards a quote_requested event and returns the tenant code', async () => {
    const realFetch = global.fetch;
    const calls = [];
    global.fetch = jest.fn(async (url, init) => {
      calls.push({ url, body: JSON.parse(init.body) });
      return new Response('{}', { status: 200 });
    });
    try {
      const res = await post(intake(), {
        N8N_INTAKE_WEBHOOK_URL: 'https://n8n.example/webhook/intake',
        N8N_WEBHOOK_AUTH: 'tok',
      });
      expect(res.status).toBe(200);
      const data = await res.json();
      expect(data.ok).toBe(true);
      expect(data.tenantCode).toMatch(/^NSW#[A-HJ-NP-Z2-9]{4}$/);
      expect(calls).toHaveLength(1);
      expect(calls[0].url).toBe('https://n8n.example/webhook/intake');
      expect(calls[0].body.type).toBe('quote_requested');
      expect(calls[0].body.eventId).toMatch(/^qr_[0-9a-f-]{36}$/);
      expect(calls[0].body.customer.company).toBe('Nagati Steel Works');
    } finally {
      global.fetch = realFetch;
    }
  });
});

describe('storefront sales-mode rendering', () => {
  const get = (pathName, env = {}) =>
    worker.fetch(new Request(`https://sias-store.example${pathName}`), env).then((r) => r.text());

  test('/config reports the active sales mode', async () => {
    const res = await worker.fetch(new Request('https://sias-store.example/config'), {});
    const data = await res.json();
    expect(data.salesMode).toBe('quote');
    const card = await worker.fetch(new Request('https://sias-store.example/config'), { SALES_MODE: 'card' });
    expect((await card.json()).salesMode).toBe('card');
  });

  test('quote mode: landing CTAs read "Get a quote" and FAQ covers invoicing', async () => {
    const htmlText = await get('/', {});
    expect(htmlText).toContain('Get a quote');
    expect(htmlText).toContain('How does invoicing work?');
    expect(htmlText).not.toContain('Choose Growth');
  });

  test('card mode: landing keeps the original checkout CTAs', async () => {
    const htmlText = await get('/', { SALES_MODE: 'card' });
    expect(htmlText).toContain('Choose Growth');
    expect(htmlText).toContain('How can we pay from Tunisia?');
    expect(htmlText).not.toContain('How does invoicing work?');
  });

  test('quote mode: /buy renders the quote form (currency + phone, no card rails)', async () => {
    const htmlText = await get('/buy?plan=growth&billing=annual', {});
    expect(htmlText).toContain('Request my quote');
    expect(htmlText).toContain('f-currency');
    expect(htmlText).toContain('f-phone');
    expect(htmlText).not.toContain('Continue to secure checkout');
    expect(htmlText).not.toContain('name="method"');
  });

  test('card mode: /buy renders the original checkout form', async () => {
    const htmlText = await get('/buy?plan=growth&billing=annual', { SALES_MODE: 'card' });
    expect(htmlText).toContain('Continue to secure checkout');
    expect(htmlText).toContain('name="method"');
    expect(htmlText).not.toContain('Request my quote');
  });
});

describe('quote PDF tool', () => {
  const args = {
    company: 'Nagati Steel Works',
    contact: 'Amine Ben Salah',
    email: 'a.bensalah@nagati.example',
    plan: 'growth',
    billing: 'annual',
    currency: 'USD',
    'discount-pct': '10',
    'valid-days': '30',
  };

  test('parseQuoteArgs handles flags with and without values', () => {
    const parsed = parseQuoteArgs(['--company', 'Acme', '--dry-run', '--plan', 'starter']);
    expect(parsed).toEqual({ company: 'Acme', 'dry-run': true, plan: 'starter' });
  });

  test('buildQuoteModel is deterministic with injected clock and rng', () => {
    const model = buildQuoteModel(args, { nowMs: 1780000000000, rand: () => 0 });
    expect(model.tenantCode).toBe('NSW#AAAA');
    expect(model.listPrice).toBe(11880);
    expect(model.discount).toBe(1188);
    expect(model.total).toBe(10692);
    expect(model.currency).toBe('USD');
    expect(model.issuedAt).toBe(new Date(1780000000000).toISOString());
    expect(model.validUntil).toBe(new Date(1780000000000 + 30 * 86400000).toISOString());
    expect(model.quoteNumber).toMatch(/^SIAS-Q-NSW-AAAA-\d{8}$/);
  });

  test('TND quotes pull dinar figures from the shared catalog', () => {
    const model = buildQuoteModel({ ...args, currency: 'TND', 'discount-pct': '0' }, { rand: () => 0 });
    expect(model.listPrice).toBe(PLAN_CATALOG.growth.tndAnnual);
    expect(model.total).toBe(PLAN_CATALOG.growth.tndAnnual);
  });

  test('EUR requires an explicit amount; bad inputs throw readable errors', () => {
    expect(() => buildQuoteModel({ ...args, currency: 'EUR' })).toThrow(/--amount/);
    expect(buildQuoteModel({ ...args, currency: 'EUR', amount: '9800', 'discount-pct': '0' }).total).toBe(9800);
    expect(() => buildQuoteModel({ ...args, plan: 'platinum' })).toThrow(/--plan/);
    expect(() => buildQuoteModel({ ...args, email: 'junk' })).toThrow(/--email/);
    expect(() => buildQuoteModel({ ...args, 'discount-pct': '90' })).toThrow(/--discount-pct/);
    expect(() => buildQuoteModel({ ...args, 'valid-days': '900' })).toThrow(/--valid-days/);
  });

  test('formatAmount renders USD with $ and other currencies with a suffix', () => {
    expect(formatAmount(5880, 'USD')).toBe('$5,880');
    expect(formatAmount(35880, 'TND')).toBe('35,880 TND');
    expect(formatAmount(5292.5, 'USD')).toBe('$5,292.5');
  });

  test('generateQuotePdf writes a >10KB PDF plus a faithful JSON sidecar', async () => {
    const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sias-quote-'));
    try {
      const model = buildQuoteModel(args, { nowMs: 1780000000000, rand: () => 0 });
      const { pdfPath, jsonPath } = await generateQuotePdf(model, outDir);
      expect(fs.existsSync(pdfPath)).toBe(true);
      expect(fs.statSync(pdfPath).size).toBeGreaterThan(10 * 1024);
      expect(fs.readFileSync(pdfPath).subarray(0, 5).toString()).toBe('%PDF-');
      const sidecar = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
      expect(sidecar.quoteNumber).toBe(model.quoteNumber);
      expect(sidecar.total).toBe(10692);
      expect(sidecar.company).toBe('Nagati Steel Works');
      expect(sidecar.tenantCode).toBe('NSW#AAAA');
    } finally {
      fs.rmSync(outDir, { recursive: true, force: true });
    }
  }, 20000);
});
