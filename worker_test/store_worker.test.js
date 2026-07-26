// Tests for the SIAS store worker — plan catalog, tenant codes, intake
// validation, Stripe checkout params, webhook signature verification, and the
// Stripe-event -> n8n intake payload mapping.
import crypto from 'node:crypto';
import {
  PLAN_CATALOG,
  planPrice,
  tenantInitials,
  makeTenantCode,
  validateIntake,
  validateOrderIntake,
  checkoutParams,
  parseStripeSigHeader,
  timingSafeEqualHex,
  verifyStripeSignature,
  purchaseEventPayload,
  rateLimited,
  TND_CURRENCY_CODE,
  tndMinorUnits,
  clictopayRegisterParams,
  clictopayPaid,
  merchantParamsToObject,
  ctpPurchasePayload,
  clipText,
  validateChatRequest,
  buildForwardPayload,
  orderPlacedPayload,
  orderConfirmedPayload,
  paymentPaidPayload,
  paymentApprovedPayload,
  signSessionCookie,
  verifySessionCookie,
  timingSafeEqualText,
  supabaseInsertOrderBody,
  supabaseTransitionOrder,
  dispatchPaidProvisioning,
  escapeHtml,
} from '../cloudflare_store_worker.js';

const intake = (over = {}) => ({
  name: 'Amine Ben Salah',
  email: 'a.bensalah@nagati.example',
  company: 'Nagati Steel Works',
  country: 'Tunisia',
  factories: '2-3',
  plan: 'growth',
  billing: 'annual',
  notes: 'Siemens S7 estate',
  pmName: 'Sonia Trabelsi',
  pmEmail: 'production@nagati.example',
  supervisorName: 'Karim Aloui',
  supervisorEmail: 'supervisor@nagati.example',
  paymentMethod: 'bank_transfer',
  ...over,
});

describe('plan catalog and pricing', () => {
  test('annual price is cheaper than 12x monthly for every plan', () => {
    for (const def of Object.values(PLAN_CATALOG)) {
      expect(def.annual).toBeLessThan(def.monthly * 12);
      expect(def.annual).toBeGreaterThan(0);
    }
  });

  test('planPrice returns correct per-month figures', () => {
    expect(planPrice('starter', 'monthly')).toEqual({ unitAmount: 59000, interval: 'month', perMonth: 590 });
    expect(planPrice('starter', 'annual')).toEqual({ unitAmount: 588000, interval: 'year', perMonth: 490 });
    expect(planPrice('growth', 'annual').perMonth).toBe(990);
    expect(planPrice('nope', 'monthly')).toBeNull();
  });
});

describe('tenant codes', () => {
  test('initials from multi-word company names', () => {
    expect(tenantInitials('Nagati Steel Works')).toBe('NSW');
    expect(tenantInitials('acme corp international group extra')).toBe('ACIG');
  });

  test('single-word and empty companies still produce initials', () => {
    expect(tenantInitials('Acme')).toBe('ACME');
    expect(tenantInitials('')).toBe('SIAS');
    expect(tenantInitials('  --  ')).toBe('SIAS');
  });

  test('makeTenantCode format is INITIALS#XXXX with injected rng', () => {
    expect(makeTenantCode('Nagati Steel Works', () => 0)).toBe('NSW#AAAA');
    expect(makeTenantCode('Acme')).toMatch(/^ACME#[A-HJ-NP-Z2-9]{4}$/);
  });
});

describe('intake validation', () => {
  test('accepts a complete intake and normalizes email', () => {
    const v = validateIntake(intake({ email: 'A.BenSalah@Nagati.Example' }));
    expect(v.ok).toBe(true);
    expect(v.errors).toEqual([]);
    expect(v.clean.email).toBe('a.bensalah@nagati.example');
  });

  test('rejects bad email, missing company, unknown plan, bad billing', () => {
    expect(validateIntake(intake({ email: 'not-an-email' })).ok).toBe(false);
    expect(validateIntake(intake({ company: 'X' })).ok).toBe(false);
    expect(validateIntake(intake({ plan: 'platinum' })).ok).toBe(false);
    expect(validateIntake(intake({ billing: 'weekly' })).ok).toBe(false);
    expect(validateIntake(null).ok).toBe(false);
  });

  test('coerces unknown factory bucket to 1 and clips long fields', () => {
    const v = validateIntake(intake({ factories: '999', notes: 'x'.repeat(500) }));
    expect(v.ok).toBe(true);
    expect(v.clean.factories).toBe('1');
    expect(v.clean.notes.length).toBe(200);
  });
});

describe('checkout params', () => {
  test('growth + annual builds a yearly subscription with metadata', () => {
    const { clean } = validateIntake(intake());
    const p = checkoutParams(clean, 'NSW#7K2F', 'https://sias-store.example');
    expect(p.get('mode')).toBe('subscription');
    expect(p.get('line_items[0][price_data][unit_amount]')).toBe('1188000');
    expect(p.get('line_items[0][price_data][recurring][interval]')).toBe('year');
    expect(p.get('line_items[0][price_data][currency]')).toBe('usd');
    expect(p.get('customer_email')).toBe('a.bensalah@nagati.example');
    expect(p.get('metadata[tenant_code]')).toBe('NSW#7K2F');
    expect(p.get('metadata[company]')).toBe('Nagati Steel Works');
    expect(p.get('subscription_data[metadata][tenant_code]')).toBe('NSW#7K2F');
    expect(p.get('success_url')).toBe('https://sias-store.example/success?session_id={CHECKOUT_SESSION_ID}');
    expect(p.get('cancel_url')).toBe('https://sias-store.example/cancel');
    expect(p.get('tax_id_collection[enabled]')).toBe('true');
  });

  test('starter + monthly uses the monthly unit amount', () => {
    const { clean } = validateIntake(intake({ plan: 'starter', billing: 'monthly' }));
    const p = checkoutParams(clean, 'ACME#AAAA', 'https://x.example');
    expect(p.get('line_items[0][price_data][unit_amount]')).toBe('59000');
    expect(p.get('line_items[0][price_data][recurring][interval]')).toBe('month');
  });
});

describe('stripe webhook signature', () => {
  const secret = 'whsec_test_secret_123';
  const sign = (payload, t) =>
    crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');

  test('parseStripeSigHeader extracts t and v1', () => {
    const h = 't=1700000000,v1=' + 'a'.repeat(64) + ',v0=ignored';
    const parsed = parseStripeSigHeader(h);
    expect(parsed.t).toBe(1700000000);
    expect(parsed.v1).toEqual(['a'.repeat(64)]);
    expect(parseStripeSigHeader('garbage').t).toBeNull();
    expect(parseStripeSigHeader(null).v1).toEqual([]);
  });

  test('valid signature verifies, tampered payload does not', async () => {
    const payload = JSON.stringify({ id: 'evt_1', type: 'checkout.session.completed' });
    const t = Math.floor(Date.now() / 1000);
    const header = `t=${t},v1=${sign(payload, t)}`;
    await expect(verifyStripeSignature(payload, header, secret)).resolves.toBe(true);
    await expect(verifyStripeSignature(payload + ' ', header, secret)).resolves.toBe(false);
    await expect(verifyStripeSignature(payload, header, 'whsec_wrong')).resolves.toBe(false);
    await expect(verifyStripeSignature(payload, header, '')).resolves.toBe(false);
  });

  test('stale timestamps are rejected by tolerance', async () => {
    const payload = '{}';
    const t = Math.floor(Date.now() / 1000) - 3600;
    const header = `t=${t},v1=${sign(payload, t)}`;
    await expect(verifyStripeSignature(payload, header, secret)).resolves.toBe(false);
    await expect(
      verifyStripeSignature(payload, header, secret, { nowMs: t * 1000 + 1000 }),
    ).resolves.toBe(true);
  });

  test('timingSafeEqualHex compares strictly', () => {
    expect(timingSafeEqualHex('abcd', 'abcd')).toBe(true);
    expect(timingSafeEqualHex('abcd', 'abce')).toBe(false);
    expect(timingSafeEqualHex('abcd', 'abc')).toBe(false);
    expect(timingSafeEqualHex(null, 'abc')).toBe(false);
  });
});

describe('purchase event payload mapping', () => {
  const sessionEvent = {
    id: 'evt_42',
    type: 'checkout.session.completed',
    created: 1780000000,
    data: {
      object: {
        id: 'cs_test_abc',
        customer: 'cus_9',
        subscription: 'sub_9',
        amount_total: 1188000,
        currency: 'usd',
        customer_details: { email: 'buyer@nagati.example', address: { country: 'TN' } },
        metadata: {
          tenant_code: 'NSW#7K2F',
          plan: 'growth',
          billing: 'annual',
          contact_name: 'Amine Ben Salah',
          company: 'Nagati Steel Works',
          factories: '2-3',
          notes: 'Siemens S7 estate',
        },
      },
    },
  };

  test('checkout.session.completed maps to purchase_completed', () => {
    const out = purchaseEventPayload(sessionEvent);
    expect(out.type).toBe('purchase_completed');
    expect(out.source).toBe('sias-store');
    expect(out.eventId).toBe('evt_42');
    expect(out.tenantCode).toBe('NSW#7K2F');
    expect(out.plan).toBe('growth');
    expect(out.billing).toBe('annual');
    expect(out.amountTotal).toBe(1188000);
    expect(out.customer.email).toBe('buyer@nagati.example');
    expect(out.customer.company).toBe('Nagati Steel Works');
    expect(out.stripe.sessionId).toBe('cs_test_abc');
    expect(out.stripe.subscriptionId).toBe('sub_9');
    expect(out.occurredAt).toBe(new Date(1780000000 * 1000).toISOString());
  });

  test('invoice.payment_failed maps to payment_failed; other events are ignored', () => {
    const failed = purchaseEventPayload({
      id: 'evt_43',
      type: 'invoice.payment_failed',
      created: 1780000100,
      data: { object: { id: 'in_1', customer: 'cus_9', subscription: 'sub_9', customer_email: 'buyer@nagati.example', amount_due: 119000, currency: 'usd' } },
    });
    expect(failed.type).toBe('payment_failed');
    expect(failed.stripe.invoiceId).toBe('in_1');
    expect(purchaseEventPayload({ id: 'evt_44', type: 'customer.updated', data: { object: {} } })).toBeNull();
    expect(purchaseEventPayload(null)).toBeNull();
  });
});

describe('clictopay (TND rail)', () => {
  const env = {
    CLICTOPAY_USER: 'smt_user',
    CLICTOPAY_PASSWORD: 'smt_pass',
  };

  test('every plan carries TND annual pricing cheaper than 12x TND monthly', () => {
    for (const def of Object.values(PLAN_CATALOG)) {
      expect(def.tndAnnual).toBeGreaterThan(0);
      expect(def.tndAnnual).toBeLessThan(def.tndMonthly * 12);
    }
  });

  test('tndMinorUnits converts dinars to millimes by default', () => {
    expect(tndMinorUnits(17880)).toBe(17880000);
    expect(tndMinorUnits(17880, 2)).toBe(1788000);
    expect(TND_CURRENCY_CODE).toBe('788');
  });

  test('validateIntake forces annual billing for clictopay and rejects unknown methods', () => {
    const v = validateIntake(intake({ method: 'clictopay', billing: 'monthly' }));
    expect(v.ok).toBe(true);
    expect(v.clean.billing).toBe('annual');
    expect(validateIntake(intake({})).clean.method).toBe('stripe');
    expect(validateIntake(intake({ method: 'bitcoin' })).ok).toBe(false);
  });

  test('register params carry amount in millimes, TND currency, and jsonParams metadata', () => {
    const { clean } = validateIntake(intake({ method: 'clictopay', plan: 'starter' }));
    const reg = clictopayRegisterParams(clean, 'NSW#7K2F', 'https://sias-store.example', env, 1780000000000);
    expect(reg.amountDinars).toBe(17880);
    expect(reg.params.get('amount')).toBe('17880000');
    expect(reg.params.get('currency')).toBe('788');
    expect(reg.params.get('userName')).toBe('smt_user');
    expect(reg.params.get('returnUrl')).toBe('https://sias-store.example/clictopay/return');
    expect(reg.params.get('failUrl')).toBe('https://sias-store.example/cancel');
    expect(reg.orderNumber).toMatch(/^SIAS-NSW-7K2F-[A-Z0-9]+$/);
    const jp = JSON.parse(reg.params.get('jsonParams'));
    expect(jp.tenant_code).toBe('NSW#7K2F');
    expect(jp.plan).toBe('starter');
    expect(jp.billing).toBe('annual');
    expect(jp.email).toBe('a.bensalah@nagati.example');
  });

  test('amount exponent is configurable via env', () => {
    const { clean } = validateIntake(intake({ method: 'clictopay', plan: 'starter' }));
    const reg = clictopayRegisterParams(clean, 'NSW#7K2F', 'https://x.example', { ...env, CLICTOPAY_AMOUNT_EXPONENT: '2' });
    expect(reg.params.get('amount')).toBe('1788000');
  });

  test('clictopayPaid accepts only orderStatus 2 with errorCode 0', () => {
    expect(clictopayPaid({ errorCode: 0, orderStatus: 2 })).toBe(true);
    expect(clictopayPaid({ orderStatus: 2 })).toBe(true);
    expect(clictopayPaid({ errorCode: 0, orderStatus: 0 })).toBe(false);
    expect(clictopayPaid({ errorCode: 0, orderStatus: 6 })).toBe(false);
    expect(clictopayPaid({ errorCode: 5, orderStatus: 2 })).toBe(false);
    expect(clictopayPaid(null)).toBe(false);
  });

  test('ctp purchase payload maps merchantOrderParams into the n8n intake shape', () => {
    const status = {
      errorCode: 0,
      orderStatus: 2,
      amount: 17880000,
      orderNumber: 'SIAS-NSW-7K2F-XYZ',
      merchantOrderParams: [
        { name: 'tenant_code', value: 'NSW#7K2F' },
        { name: 'plan', value: 'starter' },
        { name: 'contact_name', value: 'Amine Ben Salah' },
        { name: 'company', value: 'Nagati Steel Works' },
        { name: 'email', value: 'a.bensalah@nagati.example' },
        { name: 'factories', value: '2-3' },
      ],
    };
    const out = ctpPurchasePayload('abc-123-def-456', status, 1780000000000);
    expect(out.type).toBe('purchase_completed');
    expect(out.payment).toBe('clictopay');
    expect(out.eventId).toBe('ctp_abc-123-def-456');
    expect(out.currency).toBe('tnd');
    expect(out.billing).toBe('annual');
    expect(out.amountTotal).toBe(17880000);
    expect(out.tenantCode).toBe('NSW#7K2F');
    expect(out.customer.email).toBe('a.bensalah@nagati.example');
    expect(out.customer.company).toBe('Nagati Steel Works');
    expect(out.clictopay.orderNumber).toBe('SIAS-NSW-7K2F-XYZ');
    expect(out.occurredAt).toBe(new Date(1780000000000).toISOString());
    expect(merchantParamsToObject(undefined)).toEqual({});
  });

  test('stripe purchase payload is tagged with payment=stripe', () => {
    const out = purchaseEventPayload({
      id: 'evt_9',
      type: 'checkout.session.completed',
      created: 1780000000,
      data: { object: { id: 'cs_x', metadata: {} } },
    });
    expect(out.payment).toBe('stripe');
  });
});

describe('rate limiting', () => {
  test('allows up to the limit then blocks within the window', () => {
    const key = `test:${Math.random()}`;
    const now = 1_780_000_000_000;
    expect(rateLimited(key, 3, now)).toBe(false);
    expect(rateLimited(key, 3, now + 1)).toBe(false);
    expect(rateLimited(key, 3, now + 2)).toBe(false);
    expect(rateLimited(key, 3, now + 3)).toBe(true);
    expect(rateLimited(key, 3, now + 61000)).toBe(false);
  });
});

describe('clipText', () => {
  test('trims and truncates strings', () => {
    expect(clipText('  hello  ', 3)).toBe('hel');
  });
  test('non-string input is empty string', () => {
    expect(clipText(undefined, 10)).toBe('');
    expect(clipText(42, 10)).toBe('');
    expect(clipText(null, 10)).toBe('');
  });
});

describe('validateChatRequest', () => {
  const base = () => ({
    message: 'Hello Kubix',
    sessionId: 'abc-123.xyz_9',
    tenantCode: 'NSW#7K2F',
    company: 'Nagati Steel Works',
    userName: 'Amine',
    plan: 'growth',
  });

  test('accepts a well-formed request and clips optional context fields', () => {
    const r = validateChatRequest(base());
    expect(r.ok).toBe(true);
    expect(r.value).toEqual({
      message: 'Hello Kubix',
      sessionId: 'abc-123.xyz_9',
      tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel Works',
      userName: 'Amine',
      plan: 'growth',
    });
  });

  test('rejects a non-object body', () => {
    expect(validateChatRequest(null).ok).toBe(false);
    expect(validateChatRequest('x').ok).toBe(false);
    expect(validateChatRequest(undefined).ok).toBe(false);
  });

  test('rejects an empty message', () => {
    expect(validateChatRequest({ ...base(), message: '   ' }).ok).toBe(false);
  });

  test('rejects a message over 2000 characters', () => {
    expect(validateChatRequest({ ...base(), message: 'a'.repeat(2001) }).ok).toBe(false);
  });

  test('accepts a message at exactly 2000 characters', () => {
    expect(validateChatRequest({ ...base(), message: 'a'.repeat(2000) }).ok).toBe(true);
  });

  test('rejects a missing sessionId', () => {
    const { sessionId, ...rest } = base();
    expect(validateChatRequest(rest).ok).toBe(false);
  });

  test('rejects a sessionId over 80 characters', () => {
    expect(validateChatRequest({ ...base(), sessionId: 'a'.repeat(81) }).ok).toBe(false);
  });

  test('rejects a sessionId with disallowed characters', () => {
    expect(validateChatRequest({ ...base(), sessionId: 'abc 123' }).ok).toBe(false);
    expect(validateChatRequest({ ...base(), sessionId: 'abc/123' }).ok).toBe(false);
    expect(validateChatRequest({ ...base(), sessionId: '<script>' }).ok).toBe(false);
  });

  test('clips oversized optional context fields instead of rejecting', () => {
    const r = validateChatRequest({ ...base(), company: 'x'.repeat(200), tenantCode: 'y'.repeat(80) });
    expect(r.ok).toBe(true);
    expect(r.value.company.length).toBe(120);
    expect(r.value.tenantCode.length).toBe(40);
  });

  test('missing optional context fields default to empty strings', () => {
    const r = validateChatRequest({ message: 'hi', sessionId: 'abc' });
    expect(r.ok).toBe(true);
    expect(r.value.tenantCode).toBe('');
    expect(r.value.company).toBe('');
    expect(r.value.userName).toBe('');
    expect(r.value.plan).toBe('');
  });
});

describe('buildForwardPayload', () => {
  test('shapes exactly the n8n webhook payload', () => {
    const value = {
      message: 'hi', sessionId: 's1', tenantCode: 't', company: 'c', userName: 'u', plan: 'p',
    };
    expect(buildForwardPayload(value)).toEqual(value);
  });
});

describe('manual-approval order intake', () => {
  test('accepts a complete order intake', () => {
    const v = validateOrderIntake(intake({ plan: 'starter' }));
    expect(v.ok).toBe(true);
    expect(v.errors).toEqual([]);
    expect(v.clean.email).toBe('a.bensalah@nagati.example');
    expect(v.clean.plan).toBe('starter');
  });

  test('rejects missing required fields', () => {
    expect(validateOrderIntake(intake({ name: '' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ email: 'invalid' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ company: 'X' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ plan: 'platinum' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ billing: 'weekly' })).ok).toBe(false);
  });

  test('accepts optional phone and notes', () => {
    const v = validateOrderIntake(intake({ phone: '+216 21 234 567', notes: 'Custom integration needed' }));
    expect(v.ok).toBe(true);
    expect(v.clean.phone).toBe('+216 21 234 567');
    expect(v.clean.notes).toBe('Custom integration needed');
  });

  test('requires exactly one PM and one distinct supervisor account', () => {
    const buyerAsPm = validateOrderIntake(intake({ pmName: '', pmEmail: '' }));
    expect(buyerAsPm.ok).toBe(true);
    expect(buyerAsPm.clean.pmEmail).toBe('a.bensalah@nagati.example');
    expect(validateOrderIntake(intake({ supervisorName: '' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ supervisorEmail: 'bad' })).ok).toBe(false);
    expect(validateOrderIntake(intake({ supervisorEmail: 'production@nagati.example' })).ok).toBe(false);
  });

  test('orderPlacedPayload shapes the correct n8n event', () => {
    const v = validateOrderIntake(intake({ plan: 'starter' }));
    const payload = orderPlacedPayload(v.clean, 'NSW#7K2F');
    expect(payload.type).toBe('order_placed');
    expect(payload.tenantCode).toBe('NSW#7K2F');
    expect(payload.planName).toBe('Starter');
    expect(payload.billing).toBe('annual');
    expect(payload.company).toBe('Nagati Steel Works');
  });

  test('confirmation and paid payloads are stable, distinct n8n events', () => {
    const order = {
      id: 1,
      tenant_code: 'NSW#7K2F',
      company: 'Nagati',
      contact_name: 'Amine',
      email: 'a@n.com',
      plan: 'growth',
      billing: 'annual',
      country: 'Tunisia',
      factories: '2-3',
      phone: '+216',
      notes: 'test',
    };
    const confirmed = orderConfirmedPayload(order);
    const paid = paymentPaidPayload(order);
    expect(confirmed.type).toBe('order_confirmed');
    expect(paid.type).toBe('payment_paid');
    expect(confirmed.eventId).not.toBe(paid.eventId);
    expect(paid.tenantCode).toBe('NSW#7K2F');
    expect(paid.planName).toBe('Growth');
    expect(paymentApprovedPayload(order).type).toBe('payment_paid');
  });

  test('supabaseInsertOrderBody formats order for Supabase table', () => {
    const v = validateOrderIntake(intake({ plan: 'starter' }));
    const body = supabaseInsertOrderBody(v.clean, 'NSW#7K2F');
    expect(body.tenant_code).toBe('NSW#7K2F');
    expect(body.status).toBe('under_review');
    expect(body.company).toBe('Nagati Steel Works');
    expect(body.plan).toBe('starter');
    expect(body.pm_email).toBe('production@nagati.example');
    expect(body.supervisor_email).toBe('supervisor@nagati.example');
    expect(body.full_package).toBe(false);
  });
});

describe('session cookie signing and verification', () => {
  test('signs and verifies a valid session cookie', async () => {
    const secret = 'test-secret-key-12345';
    const token = await signSessionCookie(secret);
    expect(typeof token).toBe('string');
    expect(token.split('.')).toHaveLength(2);
    const valid = await verifySessionCookie(token, secret);
    expect(valid).toBe(true);
  });

  test('rejects an invalid token', async () => {
    const secret = 'test-secret-key-12345';
    const valid = await verifySessionCookie('invalid-token-here', secret);
    expect(valid).toBe(false);
  });

  test('rejects a token signed with a different secret', async () => {
    const secret1 = 'secret-one';
    const secret2 = 'secret-two';
    const token = await signSessionCookie(secret1);
    const valid = await verifySessionCookie(token, secret2);
    expect(valid).toBe(false);
  });

  test('accepts a token inside its eight-hour lifetime', async () => {
    const secret = 'test-secret-key-12345';
    const nowMs = Date.now();
    const token = await signSessionCookie(secret, nowMs - 60_000);
    const valid = await verifySessionCookie(token, secret, nowMs);
    expect(valid).toBe(true);
  });

  test('rejects expired tokens', async () => {
    const secret = 'test-secret-key-12345';
    const nowMs = Date.now();
    const token = await signSessionCookie(secret, nowMs - 9 * 60 * 60 * 1000);
    const valid = await verifySessionCookie(token, secret, nowMs);
    expect(valid).toBe(false);
  });

  test('uses constant-time normalized text comparison', async () => {
    await expect(timingSafeEqualText('same', 'same')).resolves.toBe(true);
    await expect(timingSafeEqualText('same', 'different')).resolves.toBe(false);
  });
});

describe('admin dashboard output safety', () => {
  test('escapes untrusted order fields before rendering', () => {
    expect(escapeHtml('<img src=x onerror=alert(1)>')).toBe('&lt;img src=x onerror=alert(1)&gt;');
    expect(escapeHtml('"quoted" & company')).toBe('&quot;quoted&quot; &amp; company');
  });
});

describe('durable paid-order dispatch', () => {
  test('uses a compare-and-set Supabase transition', async () => {
    const previousFetch = global.fetch;
    const calls = [];
    global.fetch = async (url, init) => {
      calls.push({ url, init });
      return {
        ok: true,
        status: 200,
        json: async () => [{ id: 42, status: 'confirmed' }],
      };
    };
    try {
      const result = await supabaseTransitionOrder(
        'https://db.example',
        'service-key',
        '42',
        ['under_review'],
        'confirmed',
        { confirmed_at: '2026-07-26T00:00:00.000Z' },
      );
      expect(result.ok).toBe(true);
      expect(calls[0].url).toContain('id=eq.42');
      expect(calls[0].url).toContain('status=in.(under_review)');
      expect(calls[0].init.headers.Prefer).toBe('return=representation');
    } finally {
      global.fetch = previousFetch;
    }
  });

  test('repository dispatch contains identifiers only, never buyer PII', async () => {
    const previousFetch = global.fetch;
    let sent;
    global.fetch = async (_url, init) => {
      sent = JSON.parse(init.body);
      return { ok: true, status: 204 };
    };
    try {
      const result = await dispatchPaidProvisioning({
        PROVISIONING_GITHUB_REPOSITORY: 'kubix/sias',
        PROVISIONING_GITHUB_TOKEN: 'token',
      }, {
        id: 42,
        tenant_code: 'NSW#7K2F',
        email: 'buyer@example.com',
        pm_email: 'pm@example.com',
      });
      expect(result.ok).toBe(true);
      expect(sent).toEqual({
        event_type: 'sias_order_paid',
        client_payload: { orderId: '42', tenantCode: 'NSW#7K2F' },
      });
      expect(JSON.stringify(sent)).not.toContain('@');
    } finally {
      global.fetch = previousFetch;
    }
  });
});
