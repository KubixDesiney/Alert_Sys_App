// =============================================================================
// SIAS Store Worker — B2B storefront, Stripe checkout, purchase intake webhook
// =============================================================================
// The commercial front door of SIAS. Serves the marketing/landing site, runs
// Stripe Checkout for self-serve purchases, and forwards verified purchase
// events to the n8n "purchase intake" workflow (WF1) which provisions the
// customer's dedicated instance, creates their Kubix Copilot agent, and sends
// the Brevo activation email.
//
// Routes:
//   GET  /                    landing page (product, pricing, FAQ)
//   GET  /buy?plan=&billing=  intake form + order summary
//   POST /api/checkout        validate intake -> create Stripe Checkout Session
//   GET  /api/session?id=     minimal session status for the success page
//   GET  /success             post-payment confirmation (fetches /api/session)
//   GET  /cancel              redirect back to /#pricing
//   POST /api/stripe-webhook  signature-verified Stripe events -> n8n WF1
//   GET  /config              status probe (never exposes secret values)
//
// Secrets (wrangler secret put --config wrangler.store.toml):
//   STRIPE_SECRET_KEY       sk_live_/sk_test_ key used server-side only
//   STRIPE_WEBHOOK_SECRET   whsec_ signing secret for /api/stripe-webhook
//   N8N_INTAKE_WEBHOOK_URL  n8n WF1 webhook that receives purchase events
//   N8N_WEBHOOK_AUTH        optional bearer token sent to the n8n webhook
// Vars: SALES_EMAIL, STORE_RATE_LIMIT
//
// Design notes:
//   - No customer data is stored in this worker; Stripe session metadata is the
//     source of truth until n8n persists the record.
//   - The tenant code (e.g. "NSW#7K2F") is generated at checkout time and rides
//     Stripe metadata end-to-end, so the buyer's Kubix Copilot identity is
//     stable from the very first receipt.
//   - Webhook forward failures return 500 so Stripe retries with backoff; n8n
//     must dedupe on eventId.
// =============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// --- Plan catalog (single source of truth; amounts in USD cents) -------------
export const PLAN_CATALOG = Object.freeze({
  starter: Object.freeze({
    id: 'starter',
    name: 'Starter',
    tagline: 'One plant, the full platform',
    monthly: 59000, // $590/mo
    annual: 588000, // $5,880/yr == $490/mo
    tndMonthly: 1790, // TND, informational
    tndAnnual: 17880, // TND, ClicToPay annual prepay
    factories: '1 factory',
    seats: 'Up to 10 supervisor seats',
    features: Object.freeze([
      'Dedicated isolated instance',
      'Real-time alert lifecycle + mobile apps',
      'AI dispatch & escalations',
      'Voice claiming (lock-screen)',
      'Kubix Copilot included',
      'Email support',
    ]),
  }),
  growth: Object.freeze({
    id: 'growth',
    name: 'Growth',
    tagline: 'Multi-site operations on autopilot',
    monthly: 119000, // $1,190/mo
    annual: 1188000, // $11,880/yr == $990/mo
    tndMonthly: 3590, // TND, informational
    tndAnnual: 35880, // TND, ClicToPay annual prepay
    factories: 'Up to 3 factories',
    seats: 'Up to 30 supervisor seats',
    features: Object.freeze([
      'Everything in Starter',
      'SCADA / PLC / MQTT / historian connectors',
      'AI failure forecaster + morning briefings',
      'AI shift commander + handovers',
      'Hardware lab (ESP32/Arduino bindings)',
      'Priority support',
    ]),
  }),
});

export function planPrice(plan, billing) {
  const def = PLAN_CATALOG[plan];
  if (!def) return null;
  if (billing === 'annual') {
    return { unitAmount: def.annual, interval: 'year', perMonth: def.annual / 1200 };
  }
  return { unitAmount: def.monthly, interval: 'month', perMonth: def.monthly / 100 };
}

// --- ClicToPay (SMT, Tunisia) ---------------------------------------------------
// BPC-style gateway: register.do returns { orderId, formUrl } -> redirect buyer;
// getOrderStatusExtended.do verifies payment on return (orderStatus 2 = paid).
// Amounts are in TND minor units (millimes, exponent 3 — configurable via
// CLICTOPAY_AMOUNT_EXPONENT because gateway contracts vary; verify with a small
// test payment before go-live). ClicToPay has no native subscriptions, so it is
// offered as annual prepay only; monthly billing requires Stripe.
export const TND_CURRENCY_CODE = '788';

export function tndMinorUnits(dinars, exponent = 3) {
  return Math.round(Number(dinars) * Math.pow(10, Number(exponent)));
}

export function clictopayRegisterParams(clean, tenantCode, origin, env = {}, nowMs = Date.now()) {
  const def = PLAN_CATALOG[clean.plan];
  const exponent = Number(env.CLICTOPAY_AMOUNT_EXPONENT ?? 3);
  const orderNumber = `SIAS-${tenantCode.replace('#', '-')}-${nowMs.toString(36).toUpperCase()}`;
  const p = new URLSearchParams();
  p.set('userName', env.CLICTOPAY_USER || '');
  p.set('password', env.CLICTOPAY_PASSWORD || '');
  p.set('orderNumber', orderNumber);
  p.set('amount', String(tndMinorUnits(def.tndAnnual, exponent)));
  p.set('currency', TND_CURRENCY_CODE);
  p.set('returnUrl', `${origin}/clictopay/return`);
  p.set('failUrl', `${origin}/cancel`);
  p.set('description', `SIAS ${def.name} - 12 months - ${tenantCode}`);
  p.set('language', 'en');
  p.set('jsonParams', JSON.stringify({
    tenant_code: tenantCode,
    plan: clean.plan,
    billing: 'annual',
    contact_name: clean.name,
    company: clean.company,
    country: clean.country || 'Tunisia',
    factories: clean.factories,
    notes: clean.notes,
    email: clean.email,
    payment: 'clictopay',
  }));
  return { params: p, orderNumber, amountDinars: def.tndAnnual };
}

export function clictopayPaid(status) {
  const code = Number(status?.errorCode ?? 0);
  const orderStatus = Number(status?.orderStatus ?? status?.OrderStatus ?? -1);
  return code === 0 && orderStatus === 2;
}

export function merchantParamsToObject(merchantOrderParams) {
  const out = {};
  for (const it of Array.isArray(merchantOrderParams) ? merchantOrderParams : []) {
    if (it && typeof it.name === 'string') out[it.name] = String(it.value ?? '');
  }
  return out;
}

export function ctpPurchasePayload(orderId, status, nowMs = Date.now()) {
  const m = merchantParamsToObject(status?.merchantOrderParams);
  return {
    source: 'sias-store',
    eventId: `ctp_${orderId}`,
    type: 'purchase_completed',
    occurredAt: new Date(nowMs).toISOString(),
    payment: 'clictopay',
    tenantCode: m.tenant_code || '',
    plan: m.plan || '',
    billing: 'annual',
    amountTotal: Number(status?.amount ?? 0),
    currency: 'tnd',
    customer: {
      name: m.contact_name || '',
      email: m.email || '',
      company: m.company || '',
      country: m.country || 'Tunisia',
      factories: m.factories || '',
      notes: m.notes || '',
    },
    clictopay: { orderId, orderNumber: status?.orderNumber || '' },
  };
}

// --- Tenant code --------------------------------------------------------------
// "Kubix · <COMPANY INITIALS>#<CODE>" is the buyer's agent identity. Generated
// once at checkout, stable across Stripe -> n8n -> Brevo -> portal.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O/1/I/L lookalikes

export function tenantInitials(company) {
  const words = String(company || '').toUpperCase().split(/[^A-Z0-9]+/).filter(Boolean);
  let ini = words.map((w) => w[0]).join('').slice(0, 4);
  if (ini.length < 2) ini = (words[0] || 'SIAS').slice(0, 4);
  return ini || 'SIAS';
}

export function makeTenantCode(company, rand = Math.random) {
  let code = '';
  for (let i = 0; i < 4; i++) {
    code += CODE_ALPHABET[Math.floor(rand() * CODE_ALPHABET.length) % CODE_ALPHABET.length];
  }
  return `${tenantInitials(company)}#${code}`;
}

// --- Intake validation ---------------------------------------------------------
const clip = (s, n) => String(s ?? '').trim().slice(0, n);
const FACTORY_BUCKETS = ['1', '2-3', '4-10', '10+'];

export function validateIntake(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const errors = [];
  const clean = {
    name: clip(src.name, 80),
    email: clip(src.email, 120).toLowerCase(),
    company: clip(src.company, 80),
    country: clip(src.country, 56),
    factories: clip(src.factories, 8),
    plan: clip(src.plan, 12),
    billing: clip(src.billing, 8),
    method: clip(src.method, 12) || 'stripe',
    notes: clip(src.notes, 200),
  };
  if (clean.name.length < 2) errors.push('Enter your full name.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(clean.email)) errors.push('Enter a valid work email.');
  if (clean.company.length < 2) errors.push('Enter your company name.');
  if (!PLAN_CATALOG[clean.plan]) errors.push('Pick a plan.');
  if (!['monthly', 'annual'].includes(clean.billing)) errors.push('Pick a billing cycle.');
  if (!['stripe', 'clictopay'].includes(clean.method)) errors.push('Pick a payment method.');
  if (clean.method === 'clictopay') clean.billing = 'annual'; // no recurring on ClicToPay
  if (!FACTORY_BUCKETS.includes(clean.factories)) clean.factories = '1';
  return { ok: errors.length === 0, errors, clean };
}

// --- Stripe Checkout Session params (pure, testable) ---------------------------
export function checkoutParams(clean, tenantCode, origin) {
  const price = planPrice(clean.plan, clean.billing);
  const def = PLAN_CATALOG[clean.plan];
  const p = new URLSearchParams();
  p.set('mode', 'subscription');
  p.set('line_items[0][quantity]', '1');
  p.set('line_items[0][price_data][currency]', 'usd');
  p.set('line_items[0][price_data][unit_amount]', String(price.unitAmount));
  p.set('line_items[0][price_data][recurring][interval]', price.interval);
  p.set('line_items[0][price_data][product_data][name]', `SIAS ${def.name} — dedicated instance`);
  p.set(
    'line_items[0][price_data][product_data][description]',
    `${def.factories}, ${def.seats.toLowerCase()}, Kubix Copilot included`,
  );
  p.set('customer_email', clean.email);
  p.set('billing_address_collection', 'required');
  p.set('tax_id_collection[enabled]', 'true');
  p.set('allow_promotion_codes', 'true');
  p.set('success_url', `${origin}/success?session_id={CHECKOUT_SESSION_ID}`);
  p.set('cancel_url', `${origin}/cancel`);
  const meta = {
    tenant_code: tenantCode,
    plan: clean.plan,
    billing: clean.billing,
    contact_name: clean.name,
    company: clean.company,
    country: clean.country,
    factories: clean.factories,
    notes: clean.notes,
  };
  for (const [k, v] of Object.entries(meta)) if (v) p.set(`metadata[${k}]`, v);
  p.set('subscription_data[metadata][tenant_code]', tenantCode);
  p.set('subscription_data[metadata][plan]', clean.plan);
  return p;
}

// --- Stripe webhook signature verification -------------------------------------
export function parseStripeSigHeader(header) {
  const out = { t: null, v1: [] };
  for (const part of String(header || '').split(',')) {
    const idx = part.indexOf('=');
    if (idx < 0) continue;
    const k = part.slice(0, idx).trim();
    const v = part.slice(idx + 1).trim();
    if (k === 't' && /^\d+$/.test(v)) out.t = Number(v);
    else if (k === 'v1' && /^[0-9a-f]{64}$/i.test(v)) out.v1.push(v.toLowerCase());
  }
  return out;
}

export function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifyStripeSignature(payload, header, secret, opts = {}) {
  const { toleranceSec = 300, nowMs = Date.now() } = opts;
  const { t, v1 } = parseStripeSigHeader(header);
  if (!t || v1.length === 0 || !secret) return false;
  if (Math.abs(nowMs / 1000 - t) > toleranceSec) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(`${t}.${payload}`));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return v1.some((sig) => timingSafeEqualHex(sig, hex));
}

// --- Stripe event -> n8n intake payload (pure, testable) ------------------------
export function purchaseEventPayload(event) {
  const type = event?.type;
  const obj = event?.data?.object || {};
  const at = new Date((event?.created || Math.floor(Date.now() / 1000)) * 1000).toISOString();
  if (type === 'checkout.session.completed') {
    const m = obj.metadata || {};
    return {
      source: 'sias-store',
      eventId: event.id || '',
      type: 'purchase_completed',
      occurredAt: at,
      payment: 'stripe',
      tenantCode: m.tenant_code || '',
      plan: m.plan || '',
      billing: m.billing || '',
      amountTotal: obj.amount_total ?? null,
      currency: obj.currency || 'usd',
      customer: {
        name: m.contact_name || '',
        email: obj.customer_details?.email || obj.customer_email || '',
        company: m.company || '',
        country: m.country || obj.customer_details?.address?.country || '',
        factories: m.factories || '',
        notes: m.notes || '',
      },
      stripe: {
        sessionId: obj.id || '',
        customerId: obj.customer || '',
        subscriptionId: obj.subscription || '',
      },
    };
  }
  if (type === 'invoice.payment_failed') {
    return {
      source: 'sias-store',
      eventId: event.id || '',
      type: 'payment_failed',
      occurredAt: at,
      payment: 'stripe',
      amountDue: obj.amount_due ?? null,
      currency: obj.currency || 'usd',
      customer: { email: obj.customer_email || '' },
      stripe: {
        customerId: obj.customer || '',
        subscriptionId: obj.subscription || '',
        invoiceId: obj.id || '',
      },
    };
  }
  return null;
}

// --- Kubix Copilot chat proxy (pure helpers exported + unit-tested) --------
const MAX_MESSAGE_LEN = 2000;
const MAX_SESSION_ID_LEN = 80;
const SESSION_ID_RE = /^[A-Za-z0-9._-]+$/;

export function clipText(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

/** Validates + clips a raw /api/kubix request body. */
export function validateChatRequest(body) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Invalid request body.' };

  const message = typeof body.message === 'string' ? body.message.trim() : '';
  if (!message || message.length > MAX_MESSAGE_LEN) {
    return { ok: false, error: `message must be 1-${MAX_MESSAGE_LEN} characters.` };
  }

  const sessionId = typeof body.sessionId === 'string' ? body.sessionId.trim() : '';
  if (!sessionId || sessionId.length > MAX_SESSION_ID_LEN || !SESSION_ID_RE.test(sessionId)) {
    return { ok: false, error: 'sessionId must be 1-80 chars of letters, digits, dot, underscore, or dash.' };
  }

  return {
    ok: true,
    value: {
      message,
      sessionId,
      tenantCode: clipText(body.tenantCode, 40),
      company: clipText(body.company, 120),
      userName: clipText(body.userName, 80),
      plan: clipText(body.plan, 30),
    },
  };
}

/** Shapes the exact payload forwarded to the n8n Kubix chat webhook. */
export function buildForwardPayload(value) {
  return {
    message: value.message,
    sessionId: value.sessionId,
    tenantCode: value.tenantCode,
    company: value.company,
    userName: value.userName,
    plan: value.plan,
  };
}


// --- Tiny in-memory rate limit (per isolate; Stripe is the real gate) -----------
const _hits = new Map();
export function rateLimited(key, limit = 10, nowMs = Date.now(), windowMs = 60000) {
  const arr = (_hits.get(key) || []).filter((ts) => nowMs - ts < windowMs);
  arr.push(nowMs);
  _hits.set(key, arr);
  if (_hits.size > 2000) _hits.delete(_hits.keys().next().value);
  return arr.length > limit;
}

// --- HTTP helpers ---------------------------------------------------------------
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
  });
}

function html(markup, status = 200) {
  return new Response(markup, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
      'X-Frame-Options': 'DENY',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
    },
  });
}

// --- API handlers ---------------------------------------------------------------
async function handleCheckout(request, env, url) {
  const ip = request.headers.get('cf-connecting-ip') || 'anon';
  const limit = Number(env.STORE_RATE_LIMIT || 10);
  if (rateLimited(`co:${ip}`, limit)) {
    return json({ ok: false, error: 'Too many attempts — try again in a minute.' }, 429);
  }
  if (!env.STRIPE_SECRET_KEY) {
    return json({ ok: false, error: 'Checkout is not configured yet. Email us and we will set you up directly.' }, 503);
  }
  let raw;
  try { raw = await request.json(); } catch { return json({ ok: false, error: 'Invalid request body.' }, 400); }
  const v = validateIntake(raw);
  if (!v.ok) return json({ ok: false, error: v.errors.join(' ') }, 400);
  const tenantCode = makeTenantCode(v.clean.company);

  if (v.clean.method === 'clictopay') {
    if (!env.CLICTOPAY_USER || !env.CLICTOPAY_PASSWORD) {
      return json({ ok: false, error: 'Tunisian card payments are not configured yet — pay by international card or email us for a TND invoice.' }, 503);
    }
    const reg = clictopayRegisterParams(v.clean, tenantCode, url.origin, env);
    const r = await clictopayApi(env, 'register.do', reg.params);
    if (!r.formUrl || (r.errorCode && Number(r.errorCode) !== 0)) {
      const msg = r.errorMessage || 'The ClicToPay gateway rejected the request. Try again or contact us.';
      return json({ ok: false, error: msg }, 502);
    }
    return json({ ok: true, url: r.formUrl, tenantCode, orderId: r.orderId || '' });
  }

  const params = checkoutParams(v.clean, tenantCode, url.origin);
  const res = await fetch('https://api.stripe.com/v1/checkout/sessions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
  });
  const session = await res.json().catch(() => ({}));
  if (!res.ok || !session.url) {
    const msg = session?.error?.message || 'Payment provider rejected the request. Try again or contact us.';
    return json({ ok: false, error: msg }, 502);
  }
  return json({ ok: true, url: session.url, tenantCode });
}

async function handleSessionStatus(url, env) {
  const id = url.searchParams.get('id') || '';
  if (!/^cs_[a-zA-Z0-9_]{8,}$/.test(id)) return json({ ok: false, error: 'Bad session id.' }, 400);
  if (!env.STRIPE_SECRET_KEY) return json({ ok: false, error: 'Not configured.' }, 503);
  const res = await fetch(`https://api.stripe.com/v1/checkout/sessions/${id}`, {
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
  });
  const s = await res.json().catch(() => ({}));
  if (!res.ok) return json({ ok: false, error: 'Session not found.' }, 404);
  return json({
    ok: true,
    status: s.status || '',
    paymentStatus: s.payment_status || '',
    email: s.customer_details?.email || s.customer_email || '',
    name: s.metadata?.contact_name || '',
    company: s.metadata?.company || '',
    tenantCode: s.metadata?.tenant_code || '',
    plan: s.metadata?.plan || '',
    billing: s.metadata?.billing || '',
  });
}

async function clictopayApi(env, method, params) {
  const base = (env.CLICTOPAY_BASE || 'https://ipay.clictopay.com/payment/rest').replace(/\/$/, '');
  const res = await fetch(`${base}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  return res.json().catch(() => ({}));
}

async function clictopayOrderStatus(env, orderId) {
  const p = new URLSearchParams();
  p.set('userName', env.CLICTOPAY_USER || '');
  p.set('password', env.CLICTOPAY_PASSWORD || '');
  p.set('orderId', orderId);
  return clictopayApi(env, 'getOrderStatusExtended.do', p);
}

const CTP_ORDER_ID = /^[A-Za-z0-9-]{8,64}$/;

async function handleClictopayReturn(url, env) {
  const orderId = url.searchParams.get('orderId') || '';
  if (!CTP_ORDER_ID.test(orderId) || !env.CLICTOPAY_USER) {
    return Response.redirect(`${url.origin}/cancel`, 302);
  }
  const status = await clictopayOrderStatus(env, orderId);
  if (!clictopayPaid(status)) return Response.redirect(`${url.origin}/cancel`, 302);
  // Forward to n8n intake (best effort — n8n dedupes on eventId "ctp_<orderId>",
  // so a buyer refreshing the return URL can never double-provision).
  if (env.N8N_INTAKE_WEBHOOK_URL) {
    const headers = { 'Content-Type': 'application/json' };
    if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;
    try {
      await fetch(env.N8N_INTAKE_WEBHOOK_URL, {
        method: 'POST', headers, body: JSON.stringify(ctpPurchasePayload(orderId, status)),
      });
    } catch { /* money is in the gateway; ops reconciles from the ClicToPay back office */ }
  }
  return Response.redirect(`${url.origin}/success?ctp_order=${encodeURIComponent(orderId)}`, 302);
}

async function handleCtpOrderStatus(url, env) {
  const orderId = url.searchParams.get('id') || '';
  if (!CTP_ORDER_ID.test(orderId)) return json({ ok: false, error: 'Bad order id.' }, 400);
  if (!env.CLICTOPAY_USER) return json({ ok: false, error: 'Not configured.' }, 503);
  const status = await clictopayOrderStatus(env, orderId);
  if (!clictopayPaid(status)) return json({ ok: false, error: 'Order not found or unpaid.' }, 404);
  const m = merchantParamsToObject(status?.merchantOrderParams);
  return json({
    ok: true,
    status: 'complete',
    paymentStatus: 'paid',
    email: m.email || '',
    name: m.contact_name || '',
    company: m.company || '',
    tenantCode: m.tenant_code || '',
    plan: m.plan || '',
    billing: 'annual',
  });
}

async function handleKubixChat(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (rateLimited(`kx:${ip}`, 20)) {
    return json({ ok: false, error: 'Too many messages. Please wait a moment and try again.' }, 429);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, error: 'Invalid JSON body.' }, 400);
  }

  const validated = validateChatRequest(body);
  if (!validated.ok) {
    return json({ ok: false, error: validated.error }, 400);
  }

  if (!env.N8N_CHAT_WEBHOOK_URL) {
    return json({ ok: false, error: 'Kubix is not configured for this instance yet.' }, 503);
  }

  const payload = buildForwardPayload(validated.value);
  const headers = { 'Content-Type': 'application/json' };
  if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  let upstream;
  try {
    upstream = await fetch(env.N8N_CHAT_WEBHOOK_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch {
    clearTimeout(timeout);
    return json({ ok: false, error: 'Kubix is busy, try again in a moment.' }, 502);
  }
  clearTimeout(timeout);

  if (!upstream.ok) {
    return json({ ok: false, error: 'Kubix is busy, try again in a moment.' }, 502);
  }

  let data;
  try {
    data = await upstream.json();
  } catch {
    return json({ ok: false, error: 'Kubix is busy, try again in a moment.' }, 502);
  }

  return json({ ok: true, reply: data.reply, escalated: !!data.escalated, agent: data.agent });
}


async function handleStripeWebhook(request, env) {
  const payload = await request.text();
  const ok = await verifyStripeSignature(
    payload, request.headers.get('stripe-signature'), env.STRIPE_WEBHOOK_SECRET,
  );
  if (!ok) return json({ ok: false, error: 'Invalid signature.' }, 400);
  let event;
  try { event = JSON.parse(payload); } catch { return json({ ok: false, error: 'Bad payload.' }, 400); }
  const mapped = purchaseEventPayload(event);
  if (!mapped) return json({ received: true, ignored: true });
  if (!env.N8N_INTAKE_WEBHOOK_URL) {
    // Not wired to n8n yet: acknowledge so Stripe doesn't retry-storm during setup.
    return json({ received: true, forwarded: false });
  }
  const headers = { 'Content-Type': 'application/json' };
  if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;
  let fwd;
  try {
    fwd = await fetch(env.N8N_INTAKE_WEBHOOK_URL, {
      method: 'POST', headers, body: JSON.stringify(mapped),
    });
  } catch {
    return json({ ok: false, error: 'Intake forward failed.' }, 500);
  }
  if (!fwd.ok) return json({ ok: false, error: 'Intake forward failed.' }, 500);
  return json({ received: true, forwarded: true });
}

// --- Router -----------------------------------------------------------------------
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const { pathname } = url;
    try {
      if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });
      if (pathname === '/config') {
        return json({
          ok: true,
          worker: 'sias-store',
          stripe: !!env.STRIPE_SECRET_KEY,
          webhookSecret: !!env.STRIPE_WEBHOOK_SECRET,
          clictopay: !!(env.CLICTOPAY_USER && env.CLICTOPAY_PASSWORD),
          n8nIntake: !!env.N8N_INTAKE_WEBHOOK_URL,
          kubixChat: !!env.N8N_CHAT_WEBHOOK_URL,
        });
      }
      if (pathname === '/api/checkout' && request.method === 'POST') return handleCheckout(request, env, url);
      if (pathname === '/api/session' && request.method === 'GET') return handleSessionStatus(url, env);
      if (pathname === '/api/ctp-order' && request.method === 'GET') return handleCtpOrderStatus(url, env);
      if (pathname === '/api/kubix' && request.method === 'POST') return handleKubixChat(request, env);
      if (pathname === '/api/stripe-webhook' && request.method === 'POST') return handleStripeWebhook(request, env);
      if (pathname === '/clictopay/return') return handleClictopayReturn(url, env);
      if (pathname === '/buy') return html(buyPage(url, env));
      if (pathname === '/copilot') return html(copilotPage());
      if (pathname === '/success') return html(successPage(env));
      if (pathname === '/cancel') return Response.redirect(`${url.origin}/#pricing`, 302);
      return html(landingPage(env));
    } catch (e) {
      return json({ ok: false, error: String(e?.message || e) }, 500);
    }
  },
};

// =============================================================================
// Pages
// =============================================================================
function salesEmail(env) {
  return env?.SALES_EMAIL || 'chefbriotemendez@gmail.com';
}

function money(cents) {
  return '$' + (cents / 100).toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function page(title, description, body, extraHead = '') {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${description}">
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:type" content="website">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%23F59E0B' d='M12 2a7 7 0 0 0-7 7v3.3L3.3 16a1 1 0 0 0 .9 1.5h15.6a1 1 0 0 0 .9-1.5L19 12.3V9a7 7 0 0 0-7-7Zm0 20a3 3 0 0 0 2.8-2H9.2A3 3 0 0 0 12 22Z'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<style>${BASE_CSS}</style>${extraHead}
</head>
<body>${body}</body>
</html>`;
}

function landingPage(env) {
  return page(
    'SIAS — Smart Industrial Alert System',
    'Real-time factory alert supervision: AI dispatch, voice-first claiming, SCADA/PLC integration and self-grading failure forecasts. Dedicated instance per customer.',
    landingBody(env),
  );
}

function buyPage(url, env) {
  const plan = PLAN_CATALOG[url.searchParams.get('plan')] ? url.searchParams.get('plan') : 'growth';
  const billing = url.searchParams.get('billing') === 'annual' ? 'annual' : 'monthly';
  return page(
    'Get SIAS — checkout',
    'Tell us about your plant and continue to secure checkout.',
    buyBody(plan, billing, env),
  );
}

function successPage(env) {
  return page(
    'Welcome aboard — SIAS',
    'Payment confirmed. Your dedicated SIAS instance is being provisioned.',
    successBody(env),
  );
}

function landingBody(env) {
  const mail = salesEmail(env);
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/"><span class="mark">&#9650;</span>SIAS</a>
  <nav class="navlinks">
    <a class="hideM" href="#features">Product</a>
    <a class="hideM" href="#integrations">Integrations</a>
    <a class="hideM" href="#kubix">Kubix Copilot</a>
    <a class="hideM" href="/copilot">Copilot chat</a>
    <a class="hideM" href="#security">Security</a>
    <a href="#pricing">Pricing</a>
    <a class="btn btn-amber btn-sm" href="/buy?plan=growth&billing=annual">Get SIAS</a>
  </nav>
</div></header>

<main>
<div class="wrap">
  <div class="hero">
    <div>
      <span class="eyebrow">Smart Industrial Alert System</span>
      <h1>Every factory alert.<br>Caught, claimed, resolved &mdash; and learned from.</h1>
      <p class="lead">SIAS is the real-time supervision platform for industrial plants: AI-dispatched alerts, voice-first claiming from a locked phone, SCADA-to-shop-floor integration, and a failure forecaster that trains on your own history and grades itself daily.</p>
      <div class="ctas">
        <a class="btn btn-amber" href="#pricing">Get SIAS &mdash; from $490/mo</a>
        <a class="btn btn-ghost" href="#how">How buying works</a>
      </div>
      <p class="sub">Dedicated isolated instance per customer &middot; live within 1 business day &middot; EN / FR</p>
    </div>
    <div class="card console" aria-label="Live alert console preview">
      <div class="chead"><span class="dotr"></span> LIVE &middot; Plant floor &mdash; Line 3 <span style="margin-left:auto" class="dim">SIAS console</span></div>
      <div class="alertrow">
        <div class="sev r">&#9888;</div>
        <div><div class="t1">Maintenance &mdash; Conveyor B &middot; Station 12</div>
        <div class="t2">ALT-2841 &middot; raised 14s ago &middot; source: scada:opcua</div>
        <span class="chip ai">AI &rarr; assigned S. Karim &middot; confidence 0.92</span> <span class="chip crit">CRITICAL</span></div>
      </div>
      <div class="alertrow">
        <div class="sev a">&#9881;</div>
        <div><div class="t1">Quality drift &mdash; Line 1 &middot; Station 4</div>
        <div class="t2">ALT-2840 &middot; claimed by voice from lock screen &middot; 2m</div>
        <span class="chip ai">en cours &middot; M. Bouazizi</span></div>
      </div>
      <div class="alertrow">
        <div class="sev g">&#10003;</div>
        <div><div class="t1">Resource shortage &mdash; Packaging &middot; Station 7</div>
        <div class="t2">ALT-2837 &middot; resolved in 11 min &middot; validated</div>
        <span class="chip ok">resolved &middot; fed back to the model</span></div>
      </div>
      <div class="cfoot">&#9889; Forecast: 78% risk of product-defect alerts on MACH-041 within 24h &mdash; maintenance pre-briefed</div>
    </div>
  </div>

  <div class="stats">
    <div class="stat"><div class="n">~1.5s</div><div class="l">median alert push to phones</div></div>
    <div class="stat"><div class="n">24/7</div><div class="l">AI shift commander</div></div>
    <div class="stat"><div class="n">466</div><div class="l">automated tests in CI</div></div>
    <div class="stat"><div class="n">7</div><div class="l">edge services per instance</div></div>
    <div class="stat"><div class="n">EN&middot;FR</div><div class="l">fully bilingual, runtime switch</div></div>
  </div>
</div>

<section id="features"><div class="wrap">
  <div class="shead"><span class="eyebrow">Platform</span>
    <h2 style="margin-top:14px">Built for the plant floor, not the boardroom demo</h2>
    <p>Every capability below ships in your instance on day one &mdash; this is running software, not a roadmap.</p>
  </div>
  <div class="grid3">
    <div class="card feat"><div class="ic">&#129302;</div><h3>AI dispatch &amp; shift commander</h3><p>Scores every supervisor on history, workload, location and feedback, assigns in seconds, and can run entire shifts autonomously &mdash; with every decision explained and logged.</p></div>
    <div class="card feat"><div class="ic">&#128200;</div><h3>Forecasts that earn trust</h3><p>A gradient-boosted model trains on your alert history in seconds, forecasts next-24h machine risk, then grades its own accuracy against what actually happened &mdash; daily.</p></div>
    <div class="card feat"><div class="ic">&#127908;</div><h3>Voice-first operations</h3><p>Claim, resolve and escalate hands-free &mdash; even from a locked phone. Offline speech recognition with speaker verification, in English and French.</p></div>
    <div class="card feat"><div class="ic">&#128268;</div><h3>Plugs into your estate</h3><p>OPC-UA, Modbus, MQTT, REST, PI and Ignition historians, plus ESP32/Arduino edge kits. Configured self-service from your console. SIAS observes &mdash; it never touches control loops.</p></div>
    <div class="card feat"><div class="ic">&#128246;</div><h3>Built for bad networks</h3><p>Offline-aware mobile apps, queued sync, cached roles and durable retries. The plant floor does not stop when the Wi-Fi does &mdash; neither does SIAS.</p></div>
    <div class="card feat"><div class="ic">&#128737;</div><h3>A command console you own</h3><p>Your SuperAdmin cockpit: live fleet monitor, security feed, hardware lab, custom alert types, model training and account provisioning &mdash; on your dedicated instance.</p></div>
  </div>
</div></section>

<section id="integrations" style="padding-top:0"><div class="wrap">
  <div class="shead"><span class="eyebrow">Integrations</span>
    <h2 style="margin-top:14px">Speaks fluent factory</h2>
    <p>Cloud-pull, edge-push or broker-based &mdash; your IT team connects the estate without us on the phone.</p>
  </div>
  <div class="logos">
    <span>OPC-UA</span><span>Modbus</span><span>MQTT</span><span>REST APIs</span><span>OSIsoft PI</span><span>Ignition</span><span>ESP32 / Arduino</span><span>SCIM 2.0 (Okta &middot; Entra)</span><span>Firebase Auth + MFA</span>
  </div>
</div></section>

<section id="kubix"><div class="wrap"><div class="kubix">
  <div>
    <span class="eyebrow">Included with every purchase</span>
    <h2 style="margin-top:14px">Meet your Kubix Copilot</h2>
    <p class="mut" style="margin-top:16px;font-size:17px">The moment you buy, a named AI engineer is created for your company &mdash; trained on SIAS internals, your plan, and your integration stack. It guides activation, wires your SCADA/PLC/ESP32 connections, answers the 2am questions, and escalates to a human engineer when it should.</p>
    <ul class="plan" style="border:none;padding:22px 0 0;background:none;box-shadow:none">
      <li style="list-style:none;font-size:14.5px;color:var(--ink2);display:flex;gap:10px;margin-bottom:10px"><span class="ck" style="color:var(--amber2);font-weight:700">&#10003;</span> Knows your instance, tenant code and configuration</li>
      <li style="list-style:none;font-size:14.5px;color:var(--ink2);display:flex;gap:10px;margin-bottom:10px"><span class="ck" style="color:var(--amber2);font-weight:700">&#10003;</span> Generates gateway snippets for your exact hardware</li>
      <li style="list-style:none;font-size:14.5px;color:var(--ink2);display:flex;gap:10px"><span class="ck" style="color:var(--amber2);font-weight:700">&#10003;</span> Onboards supervisors, PMs and IT &mdash; in EN or FR</li>
    </ul>
  </div>
  <div class="card chatcard">
    <div class="kbadge"><div class="av">K</div><div><div class="nm">Kubix &middot; NSW#7K2F</div><div class="st">&#9679; online &mdash; your dedicated copilot</div></div></div>
    <div class="msg user">How do I wire our Siemens S7 line into SIAS?</div>
    <div class="msg bot">Three steps, about 20 minutes:<ol><li>Enable the <b>OPC-UA connector</b> in your console (Infrastructure &rarr; Connectors)</li><li>I generate your gateway snippet with your ingest key baked in</li><li>We run a live <b>Verify link test</b> together</li></ol>Want me to prep the snippet for Line 2 now?</div>
    <div class="msg user">Yes &mdash; and set the alert type to maintenance.</div>
    <div class="msg bot">Done. Snippet ready &mdash; alerts from Line 2 will arrive tagged <b>maintenance</b>, routed by AI dispatch. I will watch the first 10 packets with you.</div>
  </div>
</div></div></section>

<section id="security" style="padding-top:0"><div class="wrap">
  <div class="shead"><span class="eyebrow">Security &amp; trust</span>
    <h2 style="margin-top:14px">Engineered like you will audit it &mdash; because you will</h2>
    <p>Industrial buyers audit before they buy. SIAS is built and operated for that scrutiny.</p>
  </div>
  <ul class="seclist">
    <li class="card"><span class="ck">&#10003;</span><span><b>Dedicated isolated instance</b> per customer &mdash; your data never shares a database, auth realm or edge service with anyone else&rsquo;s.</span></li>
    <li class="card"><span class="ck">&#10003;</span><span><b>Enforced service authentication</b> &mdash; identity-token verification is required on every backend service, not optional.</span></li>
    <li class="card"><span class="ck">&#10003;</span><span><b>MFA + SCIM 2.0 provisioning</b> &mdash; plug in Okta or Microsoft Entra; joiners and leavers sync automatically.</span></li>
    <li class="card"><span class="ck">&#10003;</span><span><b>Daily encrypted snapshots</b> to object storage with a 365-day alert retention policy you control.</span></li>
    <li class="card"><span class="ck">&#10003;</span><span><b>PII separated and access-scoped</b> &mdash; personal data lives apart from operational data with strict role rules.</span></li>
    <li class="card"><span class="ck">&#10003;</span><span><b>Independent security review</b> &mdash; externally scanned and fully remediated (July 2026). Whitepaper on request.</span></li>
  </ul>
</div></section>

<section id="how"><div class="wrap">
  <div class="shead"><span class="eyebrow">How buying works</span>
    <h2 style="margin-top:14px">From card to control room in four steps</h2>
  </div>
  <div class="steps">
    <div class="card step"><div class="n">STEP 01</div><h3>Buy &amp; tell us about your plant</h3><p>Pick a plan, fill in five fields, pay by card or request an invoice. VAT handled at checkout.</p></div>
    <div class="card step"><div class="n">STEP 02</div><h3>We provision your instance</h3><p>A dedicated, isolated SIAS deployment &mdash; database, auth, edge services &mdash; spun up for your company within 1 business day.</p></div>
    <div class="card step"><div class="n">STEP 03</div><h3>Claim your Owner console</h3><p>You receive a one-time activation link (never a password). Set your password + MFA and the instance is yours.</p></div>
    <div class="card step"><div class="n">STEP 04</div><h3>Kubix onboards your team</h3><p>Your copilot introduces itself, invites your Production Managers, and wires your first integration with you.</p></div>
  </div>
</div></section>

<section id="pricing" style="padding-top:0"><div class="wrap">
  <div class="shead" style="text-align:center;margin-left:auto;margin-right:auto"><span class="eyebrow">Pricing</span>
    <h2 style="margin-top:14px">One instance. One price. Everything included.</h2>
    <div class="toggle" role="tablist">
      <button type="button" id="bt-monthly" onclick="setBilling('monthly')">Monthly</button>
      <button type="button" id="bt-annual" class="on" onclick="setBilling('annual')">Annual <span class="save">&nbsp;save 17%</span></button>
    </div>
  </div>
  <div class="plans">
    <div class="card plan">
      <h3>Starter</h3><div class="tag">One plant, the full platform</div>
      <div class="price" data-monthly="$590" data-annual="$490">$490<small>/mo</small></div>
      <div class="bill" data-monthly="billed monthly &middot; cancel anytime" data-annual="$5,880 billed annually">$5,880 billed annually</div>
      <ul>
        <li><span class="ck">&#10003;</span>1 factory &middot; up to 10 supervisor seats</li>
        <li><span class="ck">&#10003;</span>Dedicated isolated instance</li>
        <li><span class="ck">&#10003;</span>Real-time alerts + AI dispatch &amp; escalations</li>
        <li><span class="ck">&#10003;</span>Voice claiming from the lock screen</li>
        <li><span class="ck">&#10003;</span>Kubix Copilot included</li>
        <li><span class="ck">&#10003;</span>Email support</li>
      </ul>
      <a class="btn btn-ghost buylink" data-plan="starter" href="/buy?plan=starter&billing=annual">Choose Starter</a>
    </div>
    <div class="card plan hot">
      <div class="pop">Most popular</div>
      <h3>Growth</h3><div class="tag">Multi-site operations on autopilot</div>
      <div class="price" data-monthly="$1,190" data-annual="$990">$990<small>/mo</small></div>
      <div class="bill" data-monthly="billed monthly &middot; cancel anytime" data-annual="$11,880 billed annually">$11,880 billed annually</div>
      <ul>
        <li><span class="ck">&#10003;</span>Up to 3 factories &middot; 30 supervisor seats</li>
        <li><span class="ck">&#10003;</span>Everything in Starter</li>
        <li><span class="ck">&#10003;</span>SCADA / PLC / MQTT / historian connectors</li>
        <li><span class="ck">&#10003;</span>AI failure forecaster + morning briefings</li>
        <li><span class="ck">&#10003;</span>AI shift commander + handovers</li>
        <li><span class="ck">&#10003;</span>Priority support</li>
      </ul>
      <a class="btn btn-amber buylink" data-plan="growth" href="/buy?plan=growth&billing=annual">Choose Growth</a>
    </div>
    <div class="card plan">
      <h3>Enterprise</h3><div class="tag">For groups and regulated estates</div>
      <div class="price">Custom</div>
      <div class="bill">annual contract &middot; procurement-friendly</div>
      <ul>
        <li><span class="ck">&#10003;</span>Unlimited factories &amp; seats</li>
        <li><span class="ck">&#10003;</span>SCIM / SSO (Okta, Entra)</li>
        <li><span class="ck">&#10003;</span>99.9% uptime SLA + status page</li>
        <li><span class="ck">&#10003;</span>Dedicated onboarding engineer</li>
        <li><span class="ck">&#10003;</span>Security review &amp; RFP support</li>
        <li><span class="ck">&#10003;</span>Custom data residency options</li>
      </ul>
      <a class="btn btn-ghost" href="mailto:${mail}?subject=SIAS%20Enterprise%20inquiry">Talk to sales</a>
    </div>
  </div>
  <p class="dim" style="text-align:center;margin-top:22px;font-size:13px">Prices in USD, excl. VAT (collected at checkout where applicable). Tunisian companies can pay in TND by local card via ClicToPay (annual billing). Every plan runs on its own dedicated instance &mdash; 30-day money-back guarantee on your first payment.</p>
</div></section>

<section id="faq" style="padding-top:0"><div class="wrap" style="max-width:760px">
  <div class="shead"><span class="eyebrow">FAQ</span><h2 style="margin-top:14px">Questions factories ask us</h2></div>
  <details><summary>How fast can we go live?</summary><div class="a">Your dedicated instance is provisioned within 1 business day of purchase. Most plants have supervisors claiming real alerts the same week, including their first SCADA or MQTT connector &mdash; your Kubix Copilot drives that timeline with you.</div></details>
  <details><summary>Do you have access to our production data?</summary><div class="a">Your instance is isolated per customer &mdash; separate database, auth realm and edge services. KubixDesiney operates the infrastructure (updates, backups, monitoring) but your operational data is yours: export it anytime, and alert retention policy is under your control.</div></details>
  <details><summary>What hardware do we need?</summary><div class="a">None to start &mdash; supervisors use their phones and alerts can be raised manually or from your existing SCADA/PLC/historian systems. Optional ESP32/Arduino edge kits can be bound to machines through the built-in hardware lab.</div></details>
  <details><summary>Can our teams use it in French?</summary><div class="a">Yes &mdash; the entire product is bilingual English/French with instant runtime switching, down to notifications and PDF reports.</div></details>
  <details><summary>Does the AI take actions on our machines?</summary><div class="a">Never. SIAS observes and orchestrates people &mdash; it reads from your estate (OPC-UA, Modbus, MQTT, historians) and never writes to control loops. AI decisions are logged with reasons and confidence, and every autonomous capability has an off switch in your console.</div></details>
  <details><summary>What happens if we outgrow our plan?</summary><div class="a">Upgrade in place &mdash; same instance, higher limits, prorated by Stripe. Moving to Enterprise adds SSO/SCIM, an SLA and a dedicated onboarding engineer without migration.</div></details>
  <details><summary>How can we pay from Tunisia?</summary><div class="a">Two rails: international cards in USD through Stripe (monthly or annual), or Tunisian CB cards in TND through ClicToPay, the national gateway operated by SMT (annual billing). Pick your rail at checkout &mdash; both trigger the same instant provisioning.</div></details>
</div></section>

<div class="cta-band"><div class="wrap"><div class="card">
  <h2>Your plant&rsquo;s next alert could be the last one nobody caught.</h2>
  <p class="mut" style="margin:16px auto 30px;max-width:36em">Buy today, get your activation email tomorrow, and let Kubix walk your team in.</p>
  <a class="btn btn-amber" href="/buy?plan=growth&billing=annual">Get SIAS now</a>
</div></div></div>
</main>

<footer><div class="wrap">
  <span><b style="color:var(--ink2)">SIAS</b> &mdash; Smart Industrial Alert System &middot; by KubixDesiney</span>
  <span><a href="#pricing">Pricing</a> &middot; <a href="/copilot">Kubix Copilot</a> &middot; <a href="#security">Security</a> &middot; <a href="mailto:${mail}">${mail}</a></span>
  <span>&copy; 2026 KubixDesiney. All rights reserved.</span>
</div></footer>

<script>
var billing = 'annual';
function setBilling(b) {
  billing = b;
  document.getElementById('bt-monthly').className = b === 'monthly' ? 'on' : '';
  document.getElementById('bt-annual').className = b === 'annual' ? 'on' : '';
  document.querySelectorAll('.price[data-monthly]').forEach(function (el) {
    el.innerHTML = el.getAttribute('data-' + b) + '<small>/mo</small>';
  });
  document.querySelectorAll('.bill[data-monthly]').forEach(function (el) {
    el.textContent = el.getAttribute('data-' + b);
  });
  document.querySelectorAll('.buylink').forEach(function (el) {
    el.href = '/buy?plan=' + el.getAttribute('data-plan') + '&billing=' + b;
  });
}
</script>`;
}

function buyBody(plan, billing, env) {
  const mail = salesEmail(env);
  const catalogLite = {};
  for (const [k, v] of Object.entries(PLAN_CATALOG)) {
    catalogLite[k] = { name: v.name, monthly: v.monthly, annual: v.annual, tndAnnual: v.tndAnnual, factories: v.factories, seats: v.seats };
  }
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/"><span class="mark">&#9650;</span>SIAS</a>
  <nav class="navlinks"><a href="/#pricing">&larr; Back to pricing</a></nav>
</div></header>

<main class="wrap buywrap">
  <div>
    <span class="eyebrow">Secure checkout</span>
    <h2 style="margin:16px 0 8px">Tell us about your plant</h2>
    <p class="mut" style="margin-bottom:28px">Five fields. This is what names your instance, your Kubix Copilot, and your activation email.</p>
    <form id="intake" onsubmit="return submitIntake(event)">
      <div class="formgrid">
        <div class="field"><label for="f-name">Full name</label><input id="f-name" name="name" required maxlength="80" placeholder="Amine Ben Salah" autocomplete="name"></div>
        <div class="field"><label for="f-email">Work email</label><input id="f-email" name="email" type="email" required maxlength="120" placeholder="a.bensalah@company.com" autocomplete="email"></div>
        <div class="field"><label for="f-company">Company</label><input id="f-company" name="company" required maxlength="80" placeholder="Nagati Steel Works" autocomplete="organization"></div>
        <div class="field"><label for="f-country">Country</label><input id="f-country" name="country" maxlength="56" placeholder="Tunisia" autocomplete="country-name"></div>
        <div class="field"><label for="f-factories">Number of factories</label>
          <select id="f-factories" name="factories">
            <option value="1">1</option><option value="2-3">2&ndash;3</option><option value="4-10">4&ndash;10</option><option value="10+">More than 10</option>
          </select></div>
        <div class="field"><label for="f-notes">Anything we should know? <span class="dim">(optional)</span></label><input id="f-notes" name="notes" maxlength="200" placeholder="Existing SCADA, timeline, constraints..."></div>
      </div>
      <div class="err" id="err"></div>
      <button class="btn btn-amber" type="submit" id="paybtn" style="margin-top:26px;width:100%">Continue to secure checkout &rarr;</button>
      <p class="dim" style="font-size:12.5px;margin-top:14px;text-align:center">Payments handled by Stripe (international) or ClicToPay / SMT (Tunisia) &mdash; card details never touch our servers. Prefer an invoice? <a href="mailto:${mail}?subject=SIAS%20invoice%20request">Email us</a>.</p>
    </form>
  </div>

  <div class="card sumcard">
    <h3 id="sum-plan">Growth</h3>
    <p class="dim" id="sum-tag" style="font-size:13px;margin-top:2px"></p>
    <div class="radio2" style="margin-top:16px">
      <label><input type="radio" name="method" value="stripe" onchange="setMethod('stripe')"><span>&#127758; International card &middot; USD</span></label>
      <label><input type="radio" name="method" value="clictopay" onchange="setMethod('clictopay')"><span>&#127481;&#127475; Carte tunisienne &middot; TND</span></label>
    </div>
    <p class="dim" id="method-note" style="font-size:12px;margin:2px 0 4px"></p>
    <div class="radio2">
      <label id="lbl-monthly"><input type="radio" name="billing" value="monthly" onchange="setBill('monthly')"><span>Monthly</span></label>
      <label><input type="radio" name="billing" value="annual" onchange="setBill('annual')"><span>Annual &middot; save 17%</span></label>
    </div>
    <div class="sumline"><span>Dedicated isolated instance</span><span>included</span></div>
    <div class="sumline"><span>Kubix Copilot</span><span>included</span></div>
    <div class="sumline"><span id="sum-scope"></span><span>&nbsp;</span></div>
    <div class="sumline total"><span id="sum-cycle">Due today</span><span id="sum-price"></span></div>
    <p class="dim" style="font-size:12.5px;margin-top:14px">Then your instance is provisioned within 1 business day and your activation email lands in your inbox. 30-day money-back guarantee.</p>
  </div>
</main>

<script>
var CATALOG = ${JSON.stringify(catalogLite)};
var state = { plan: '${plan}', billing: '${billing}', method: 'stripe' };
function fmt(cents) { return '$' + (cents / 100).toLocaleString('en-US', { maximumFractionDigits: 0 }); }
function fmtTnd(d) { return d.toLocaleString('en-US') + ' TND'; }
function render() {
  var p = CATALOG[state.plan];
  var ctp = state.method === 'clictopay';
  if (ctp) state.billing = 'annual';
  document.getElementById('sum-plan').textContent = 'SIAS ' + p.name;
  document.getElementById('sum-tag').textContent = p.factories + ' \\u00b7 ' + p.seats;
  document.getElementById('sum-scope').textContent = p.factories + ', ' + p.seats.toLowerCase();
  var isAnnual = state.billing === 'annual';
  document.getElementById('sum-cycle').textContent = isAnnual ? 'Due today (12 months)' : 'Due today (first month)';
  document.getElementById('sum-price').textContent = ctp ? fmtTnd(p.tndAnnual) : (isAnnual ? fmt(p.annual) : fmt(p.monthly));
  document.getElementById('method-note').textContent = ctp
    ? 'Tunisian CB cards via ClicToPay (SMT) \\u2014 charged in TND, annual billing only.'
    : 'Cards worldwide via Stripe \\u2014 monthly or annual, VAT handled at checkout.';
  var mLbl = document.getElementById('lbl-monthly');
  mLbl.style.opacity = ctp ? '.4' : '1';
  mLbl.style.pointerEvents = ctp ? 'none' : 'auto';
  document.querySelectorAll('input[name="billing"]').forEach(function (r) { r.checked = r.value === state.billing; });
  document.querySelectorAll('input[name="method"]').forEach(function (r) { r.checked = r.value === state.method; });
}
function setBill(b) { state.billing = b; render(); }
function setMethod(m) { state.method = m; render(); }
function submitIntake(ev) {
  ev.preventDefault();
  var btn = document.getElementById('paybtn');
  var err = document.getElementById('err');
  err.style.display = 'none';
  btn.disabled = true;
  btn.textContent = 'Preparing secure checkout\\u2026';
  var body = {
    name: document.getElementById('f-name').value,
    email: document.getElementById('f-email').value,
    company: document.getElementById('f-company').value,
    country: document.getElementById('f-country').value,
    factories: document.getElementById('f-factories').value,
    notes: document.getElementById('f-notes').value,
    plan: state.plan,
    billing: state.billing,
    method: state.method,
  };
  fetch('/api/checkout', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (d.ok && d.url) { window.location.href = d.url; return; }
      throw new Error(d.error || 'Something went wrong.');
    })
    .catch(function (e) {
      err.textContent = e.message;
      err.style.display = 'block';
      btn.disabled = false;
      btn.textContent = 'Continue to secure checkout \\u2192';
    });
  return false;
}
render();
</script>`;
}

function successBody(env) {
  const mail = salesEmail(env);
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/"><span class="mark">&#9650;</span>SIAS</a>
</div></header>

<main class="okpage">
  <div class="big">&#10003;</div>
  <span class="eyebrow">Payment confirmed</span>
  <h2 style="margin:18px 0 10px">Welcome aboard.</h2>
  <p class="mut" id="ok-line">Your dedicated SIAS instance is being provisioned.</p>
  <div class="nextsteps">
    <div class="card"><div class="n">1</div><div><b>Your Stripe receipt</b><br><span class="mut" style="font-size:14px">Already on its way to your inbox.</span></div></div>
    <div class="card"><div class="n">2</div><div><b>Activation email &mdash; within 1 business day</b><br><span class="mut" style="font-size:14px">A one-time link to claim your Owner console: you set your password and MFA. We never send passwords by email.</span></div></div>
    <div class="card"><div class="n">3</div><div><b>Kubix Copilot introduces itself</b><br><span class="mut" style="font-size:14px" id="ok-kubix">Your named AI engineer will guide activation, team invites and your first integration.</span></div></div>
  </div>
  <a class="btn btn-amber" id="ok-chat" style="display:none;margin-top:30px" href="/copilot">Chat with Kubix now &rarr;</a>
  <p class="dim" style="margin-top:30px;font-size:13.5px">Nothing after a day? Check spam, or write to <a href="mailto:${mail}">${mail}</a> &mdash; a human answers.</p>
</main>

<script>
(function () {
  var m = window.location.search.match(/session_id=([A-Za-z0-9_]+)/);
  var c = window.location.search.match(/ctp_order=([A-Za-z0-9-]+)/);
  if (!m && !c) return;
  fetch(m ? '/api/session?id=' + m[1] : '/api/ctp-order?id=' + c[1])
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (!d.ok) return;
      if (d.company && d.tenantCode) {
        document.getElementById('ok-line').textContent =
          'Your dedicated SIAS instance ' + d.tenantCode + ' is being provisioned for ' + d.company + '.';
        document.getElementById('ok-kubix').textContent =
          'Kubix \\u00b7 ' + d.tenantCode + ' will email ' + (d.email || 'you') + ' to guide activation, team invites and your first integration.';
        var b = document.getElementById('ok-chat');
        b.href = '/copilot?tenant=' + encodeURIComponent(d.tenantCode) + '&company=' + encodeURIComponent(d.company) + '&name=' + encodeURIComponent(d.name || '') + '&plan=' + encodeURIComponent(d.plan || '');
        b.style.display = 'inline-flex';
      }
    })
    .catch(function () {});
})();
</script>`;
}

function copilotPage() {
  return page(
    'Kubix Copilot \u2014 SIAS',
    'Chat with your dedicated SIAS engineer: activation, integrations, anything.',
    copilotBody(),
  );
}

function copilotBody() {
  return `
<div class="kx-app">
  <div class="kx-header">
    <div class="kx-avatar">K</div>
    <div class="kx-header-text">
      <div class="kx-header-name"><span id="kx-agent-name">Kubix Copilot</span><span class="kx-online-dot"></span></div>
      <div class="kx-header-sub">Your dedicated SIAS engineer</div>
    </div>
    <a class="kx-back" href="/">← Home</a>
  </div>
  <div class="kx-messages" id="kx-messages"></div>
  <form class="kx-input-bar" id="kx-form">
    <textarea class="kx-input" id="kx-input" rows="1" placeholder="Ask Kubix anything about your SIAS instance…"></textarea>
    <button class="kx-send" id="kx-send" type="submit">Send</button>
  </form>
</div>
<script>${COPILOT_CLIENT_JS}</script>`;
}

const COPILOT_CLIENT_JS = `
(function () {
  var params = new URLSearchParams(location.search);
  var ctx = {
    tenant: params.get('tenant') || '',
    company: params.get('company') || '',
    name: params.get('name') || '',
    plan: params.get('plan') || '',
  };
  var STORAGE_KEY = 'kubix_copilot_v1';
  var state = loadState();

  function loadState() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.sessionId) return parsed;
      }
    } catch (_) {}
    return { sessionId: (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random()), transcript: [] };
  }
  function saveState() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (_) {}
  }

  var els = {
    agentName: document.getElementById('kx-agent-name'),
    messages: document.getElementById('kx-messages'),
    form: document.getElementById('kx-form'),
    input: document.getElementById('kx-input'),
    send: document.getElementById('kx-send'),
  };
  els.agentName.textContent = ctx.tenant ? ('Kubix · ' + ctx.tenant) : 'Kubix Copilot';

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function renderMarkdown(raw) {
    var text = escapeHtml(raw == null ? '' : raw);
    text = text.replace(/\`\`\`([\\s\\S]*?)\`\`\`/g, function (_, code) {
      return '<pre class="kx-code"><code>' + code.replace(/^\\n/, '') + '</code></pre>';
    });
    text = text.replace(/\`([^\`\\n]+)\`/g, '<code>$1</code>');
    text = text.replace(/^### (.*)$/gm, '<h3>$1</h3>');
    text = text.replace(/^## (.*)$/gm, '<h2>$1</h2>');
    text = text.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
    text = text.replace(/(^|\\n)((?:\\d+\\. .*(?:\\n|$))+)/g, function (_, pre, block) {
      var items = block.trim().split('\\n').map(function (l) { return l.replace(/^\\d+\\.\\s*/, ''); });
      return pre + '<ol>' + items.map(function (i) { return '<li>' + i + '</li>'; }).join('') + '</ol>';
    });
    text = text.replace(/(^|\\n)((?:[-*] .*(?:\\n|$))+)/g, function (_, pre, block) {
      var items = block.trim().split('\\n').map(function (l) { return l.replace(/^[-*]\\s*/, ''); });
      return pre + '<ul>' + items.map(function (i) { return '<li>' + i + '</li>'; }).join('') + '</ul>';
    });
    text = text.replace(/\\n{2,}/g, '</p><p>');
    text = '<p>' + text.replace(/\\n/g, '<br>') + '</p>';
    return text;
  }

  function addBubble(role, html, opts) {
    opts = opts || {};
    var wrap = document.createElement('div');
    wrap.className = 'kx-msg kx-msg-' + role + (opts.error ? ' kx-msg-error' : '');
    var bubble = document.createElement('div');
    bubble.className = 'kx-bubble';
    bubble.innerHTML = html;
    wrap.appendChild(bubble);
    els.messages.appendChild(wrap);
    if (opts.escalated) {
      var banner = document.createElement('div');
      banner.className = 'kx-escalated-banner';
      banner.textContent = 'A human engineer has been looped in and will follow up by email.';
      els.messages.appendChild(banner);
    }
    els.messages.scrollTop = els.messages.scrollHeight;
    return wrap;
  }

  function renderTranscript() {
    els.messages.innerHTML = '';
    state.transcript.forEach(function (m) {
      addBubble(m.role, m.role === 'bot' ? renderMarkdown(m.text) : '<p>' + escapeHtml(m.text) + '</p>', { escalated: m.escalated });
    });
  }
  renderTranscript();

  var pending = false;
  var typingEl = null;

  function showTyping() {
    typingEl = document.createElement('div');
    typingEl.className = 'kx-msg kx-msg-bot';
    typingEl.innerHTML = '<div class="kx-bubble kx-typing"><span></span><span></span><span></span></div>';
    els.messages.appendChild(typingEl);
    els.messages.scrollTop = els.messages.scrollHeight;
  }
  function hideTyping() {
    if (typingEl) { typingEl.remove(); typingEl = null; }
  }
  function setPending(p) {
    pending = p;
    els.input.disabled = p;
    els.send.disabled = p;
  }

  function sendMessage(text) {
    state.transcript.push({ role: 'user', text: text });
    saveState();
    addBubble('user', '<p>' + escapeHtml(text) + '</p>');
    setPending(true);
    showTyping();
    fetch('/api/kubix', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: text,
        sessionId: state.sessionId,
        tenantCode: ctx.tenant,
        company: ctx.company,
        userName: ctx.name,
        plan: ctx.plan,
      }),
    }).then(function (res) {
      return res.json().catch(function () { return null; }).then(function (data) { return { res: res, data: data }; });
    }).then(function (r) {
      hideTyping();
      if (!r.res.ok || !r.data || r.data.ok === false) {
        var msg = (r.data && r.data.error) || 'Something went wrong. Please try again.';
        addBubble('bot', '<p>' + escapeHtml(msg) + '</p>', { error: true });
        state.transcript.push({ role: 'bot', text: msg, error: true });
        saveState();
        return;
      }
      addBubble('bot', renderMarkdown(r.data.reply || ''), { escalated: !!r.data.escalated });
      state.transcript.push({ role: 'bot', text: r.data.reply || '', escalated: !!r.data.escalated });
      saveState();
    }).catch(function () {
      hideTyping();
      addBubble('bot', '<p>Kubix is unreachable right now. Please try again shortly.</p>', { error: true });
    }).finally(function () {
      setPending(false);
      els.input.focus();
    });
  }

  els.form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (pending) return;
    var text = els.input.value.trim();
    if (!text) return;
    els.input.value = '';
    sendMessage(text);
  });

  els.input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (els.form.requestSubmit) els.form.requestSubmit();
      else els.form.dispatchEvent(new Event('submit', { cancelable: true }));
    }
  });
})();
`;

const BASE_CSS = `
:root{
  --bg:#0A0F1C; --bg2:#0D1526; --panel:rgba(148,163,184,.06); --panel2:rgba(148,163,184,.10);
  --line:rgba(148,163,184,.16); --line2:rgba(148,163,184,.28);
  --ink:#E7EDF7; --ink2:#9FB0C7; --ink3:#64748B;
  --amber:#F59E0B; --amber2:#FBBF24; --cyan:#38BDF8; --red:#F87171; --green:#34D399;
  --radius:14px; --max:1120px;
}
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth}
body{background:var(--bg);color:var(--ink);font:400 16px/1.65 'Inter',system-ui,sans-serif;-webkit-font-smoothing:antialiased;overflow-x:hidden}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;
  background:
    radial-gradient(900px 500px at 85% -10%, rgba(56,189,248,.10), transparent 60%),
    radial-gradient(700px 420px at 0% 10%, rgba(245,158,11,.07), transparent 55%),
    repeating-linear-gradient(0deg, rgba(148,163,184,.035) 0 1px, transparent 1px 56px),
    repeating-linear-gradient(90deg, rgba(148,163,184,.035) 0 1px, transparent 1px 56px)}
main,header.nav,footer{position:relative;z-index:1}
.wrap{max-width:var(--max);margin:0 auto;padding:0 24px}
h1,h2,h3,.logo,.price{font-family:'Space Grotesk','Inter',sans-serif}
h1{font-size:clamp(34px,5vw,58px);line-height:1.08;letter-spacing:-.02em;font-weight:700}
h2{font-size:clamp(26px,3.4vw,38px);line-height:1.15;letter-spacing:-.015em;font-weight:600}
h3{font-size:19px;font-weight:600}
a{color:var(--cyan);text-decoration:none}
.mut{color:var(--ink2)} .dim{color:var(--ink3)}
.nav{position:sticky;top:0;backdrop-filter:blur(14px);background:rgba(10,15,28,.78);border-bottom:1px solid var(--line)}
.nav .wrap{display:flex;align-items:center;gap:28px;height:66px}
.logo{display:flex;align-items:center;gap:10px;font-weight:700;font-size:19px;color:var(--ink);letter-spacing:.01em}
.logo .mark{width:30px;height:30px;border-radius:8px;background:linear-gradient(135deg,var(--amber),#D97706);display:grid;place-items:center;color:#1a1204;font-size:15px}
.navlinks{display:flex;gap:22px;margin-left:auto;align-items:center}
.navlinks a{color:var(--ink2);font-size:14.5px;font-weight:500}
.navlinks a:hover{color:var(--ink)}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;border-radius:11px;font-weight:600;font-size:15px;
  padding:13px 24px;border:1px solid transparent;cursor:pointer;transition:.18s;white-space:nowrap}
.btn-amber{background:linear-gradient(135deg,var(--amber2),var(--amber));color:#1a1204;box-shadow:0 6px 26px rgba(245,158,11,.28)}
.btn-amber:hover{transform:translateY(-1px);box-shadow:0 10px 32px rgba(245,158,11,.38)}
.btn-ghost{border-color:var(--line2);color:var(--ink);background:var(--panel)}
.btn-ghost:hover{background:var(--panel2)}
.btn-sm{padding:9px 18px;font-size:14px;border-radius:9px}
.eyebrow{display:inline-flex;align-items:center;gap:8px;font-size:12.5px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;
  color:var(--amber2);background:rgba(245,158,11,.09);border:1px solid rgba(245,158,11,.25);padding:7px 14px;border-radius:999px}
.hero{padding:84px 0 60px;display:grid;grid-template-columns:1.05fr .95fr;gap:56px;align-items:center}
.hero p.lead{font-size:18.5px;color:var(--ink2);margin:22px 0 32px;max-width:34em}
.hero .ctas{display:flex;gap:14px;flex-wrap:wrap}
.hero .sub{margin-top:16px;font-size:13.5px;color:var(--ink3)}
.card{background:linear-gradient(180deg,rgba(148,163,184,.09),rgba(148,163,184,.04));border:1px solid var(--line);border-radius:var(--radius);}
.console{padding:0;overflow:hidden;box-shadow:0 30px 80px rgba(2,6,17,.6)}
.console .chead{display:flex;align-items:center;gap:10px;padding:13px 18px;border-bottom:1px solid var(--line);font-size:13px;color:var(--ink2)}
.dotr{width:9px;height:9px;border-radius:50%;background:var(--red);box-shadow:0 0 10px rgba(248,113,113,.8);animation:pulse 1.6s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
.alertrow{display:flex;gap:12px;align-items:flex-start;padding:14px 18px;border-bottom:1px solid var(--line)}
.alertrow:last-child{border-bottom:none}
.sev{flex:0 0 auto;margin-top:3px;width:34px;height:34px;border-radius:9px;display:grid;place-items:center;font-size:15px}
.sev.r{background:rgba(248,113,113,.14);color:var(--red)} .sev.a{background:rgba(245,158,11,.14);color:var(--amber2)} .sev.g{background:rgba(52,211,153,.14);color:var(--green)}
.alertrow .t1{font-size:14.5px;font-weight:600}
.alertrow .t2{font-size:12.5px;color:var(--ink3);margin-top:2px}
.chip{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;font-weight:600;padding:3px 10px;border-radius:999px;margin-top:7px}
.chip.ai{background:rgba(56,189,248,.12);color:var(--cyan);border:1px solid rgba(56,189,248,.25)}
.chip.ok{background:rgba(52,211,153,.12);color:var(--green);border:1px solid rgba(52,211,153,.25)}
.chip.crit{background:rgba(248,113,113,.12);color:var(--red);border:1px solid rgba(248,113,113,.3)}
.cfoot{padding:12px 18px;background:rgba(56,189,248,.06);font-size:12.5px;color:var(--ink2);display:flex;gap:8px;align-items:center}
.stats{display:grid;grid-template-columns:repeat(5,1fr);gap:1px;background:var(--line);border:1px solid var(--line);border-radius:var(--radius);overflow:hidden;margin:26px 0 0}
.stat{background:var(--bg2);padding:22px 18px;text-align:center}
.stat .n{font-family:'Space Grotesk';font-size:26px;font-weight:700;color:var(--amber2)}
.stat .l{font-size:12.5px;color:var(--ink3);margin-top:4px}
section{padding:76px 0}
.shead{max-width:640px;margin-bottom:44px}
.shead p{color:var(--ink2);margin-top:14px;font-size:17px}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.feat{padding:26px 24px}
.feat .ic{width:42px;height:42px;border-radius:11px;display:grid;place-items:center;font-size:19px;margin-bottom:16px;background:rgba(245,158,11,.1);color:var(--amber2);border:1px solid rgba(245,158,11,.2)}
.feat h3{margin-bottom:8px}
.feat p{font-size:14.5px;color:var(--ink2)}
.logos{display:flex;flex-wrap:wrap;gap:12px}
.logos span{font-size:13.5px;font-weight:600;color:var(--ink2);border:1px solid var(--line);background:var(--panel);border-radius:999px;padding:9px 18px}
.steps{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;counter-reset:step}
.step{padding:24px 22px;position:relative}
.step .n{font-family:'Space Grotesk';font-weight:700;font-size:13px;color:var(--amber2);letter-spacing:.12em;margin-bottom:10px}
.step p{font-size:14px;color:var(--ink2);margin-top:6px}
.kubix{display:grid;grid-template-columns:1fr 1fr;gap:52px;align-items:center}
.chatcard{padding:20px}
.msg{max-width:88%;border-radius:13px;padding:12px 16px;font-size:14px;margin-bottom:12px;line-height:1.55}
.msg.user{background:rgba(56,189,248,.10);border:1px solid rgba(56,189,248,.2);margin-left:auto}
.msg.bot{background:var(--panel2);border:1px solid var(--line)}
.msg.bot ol{margin:8px 0 4px 18px}
.kbadge{display:flex;align-items:center;gap:10px;margin-bottom:16px}
.kbadge .av{width:38px;height:38px;border-radius:11px;background:linear-gradient(135deg,#38BDF8,#6366F1);display:grid;place-items:center;font-weight:700;color:#fff;font-family:'Space Grotesk'}
.kbadge .nm{font-size:14.5px;font-weight:600}
.kbadge .st{font-size:12px;color:var(--green)}
.seclist{list-style:none;display:grid;grid-template-columns:1fr 1fr;gap:14px}
.seclist li{display:flex;gap:12px;align-items:flex-start;font-size:14.5px;color:var(--ink2);padding:16px 18px}
.seclist .ck{color:var(--green);font-weight:700;flex:0 0 auto}
.toggle{display:inline-flex;background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:4px;gap:2px;margin:26px 0 34px}
.toggle button{border:none;background:transparent;color:var(--ink2);font:600 14px 'Inter';padding:9px 20px;border-radius:999px;cursor:pointer}
.toggle button.on{background:linear-gradient(135deg,var(--amber2),var(--amber));color:#1a1204}
.toggle .save{font-size:11.5px;font-weight:700;color:var(--green)}
.plans{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;align-items:stretch}
.plan{padding:30px 28px;display:flex;flex-direction:column;position:relative}
.plan.hot{border-color:rgba(245,158,11,.55);box-shadow:0 20px 60px rgba(245,158,11,.10)}
.plan .pop{position:absolute;top:-13px;left:50%;transform:translateX(-50%);background:linear-gradient(135deg,var(--amber2),var(--amber));color:#1a1204;font-size:11.5px;font-weight:700;letter-spacing:.08em;padding:5px 14px;border-radius:999px;text-transform:uppercase}
.plan h3{font-size:21px}
.plan .tag{font-size:13.5px;color:var(--ink3);margin-top:3px}
.price{font-size:44px;font-weight:700;margin-top:20px;letter-spacing:-.02em}
.price small{font-size:15px;color:var(--ink3);font-weight:500;font-family:'Inter'}
.plan .bill{font-size:12.5px;color:var(--ink3);min-height:18px;margin-top:2px}
.plan ul{list-style:none;margin:22px 0 26px;display:grid;gap:10px}
.plan ul li{font-size:14px;color:var(--ink2);display:flex;gap:10px}
.plan ul .ck{color:var(--amber2);font-weight:700}
.plan .btn{margin-top:auto}
faq-x{display:block}
details{border:1px solid var(--line);border-radius:12px;background:var(--panel);margin-bottom:12px;overflow:hidden}
summary{cursor:pointer;padding:18px 22px;font-weight:600;font-size:15.5px;list-style:none;display:flex;justify-content:space-between;gap:14px}
summary::after{content:'+';color:var(--amber2);font-size:20px;font-weight:600}
details[open] summary::after{content:'\\2212'}
details .a{padding:0 22px 18px;color:var(--ink2);font-size:14.5px}
footer{border-top:1px solid var(--line);padding:44px 0;margin-top:30px}
footer .wrap{display:flex;flex-wrap:wrap;gap:20px;align-items:center;justify-content:space-between;font-size:13.5px;color:var(--ink3)}
.cta-band{padding:64px 0;text-align:center}
.cta-band .card{padding:56px 32px;background:linear-gradient(160deg,rgba(245,158,11,.10),rgba(56,189,248,.06))}
.formgrid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.field{display:flex;flex-direction:column;gap:7px}
.field.full{grid-column:1/-1}
.field label{font-size:13px;font-weight:600;color:var(--ink2)}
.field input,.field select,.field textarea{background:var(--bg2);border:1px solid var(--line2);border-radius:10px;color:var(--ink);
  font:400 15px 'Inter';padding:12px 14px;outline:none;transition:.15s}
.field input:focus,.field select:focus,.field textarea:focus{border-color:var(--amber);box-shadow:0 0 0 3px rgba(245,158,11,.15)}
.field textarea{resize:vertical;min-height:84px}
.err{display:none;background:rgba(248,113,113,.1);border:1px solid rgba(248,113,113,.35);color:#FCA5A5;border-radius:10px;padding:12px 16px;font-size:14px;margin-top:16px}
.buywrap{display:grid;grid-template-columns:1.1fr .9fr;gap:32px;align-items:start;padding:56px 0}
.sumcard{padding:26px;position:sticky;top:90px}
.sumline{display:flex;justify-content:space-between;font-size:14px;color:var(--ink2);padding:9px 0;border-bottom:1px dashed var(--line)}
.sumline.total{font-size:16px;font-weight:700;color:var(--ink);border-bottom:none;padding-top:14px}
.radio2{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:14px 0 6px}
.radio2 label{border:1px solid var(--line2);border-radius:10px;padding:12px 14px;cursor:pointer;font-size:13.5px;text-align:center;font-weight:600;color:var(--ink2)}
.radio2 input{display:none}
.radio2 input:checked+span{color:var(--amber2)}
.radio2 label:has(input:checked){border-color:var(--amber);background:rgba(245,158,11,.08);color:var(--amber2)}
.okpage{max-width:640px;margin:0 auto;padding:80px 24px;text-align:center}
.okpage .big{width:74px;height:74px;border-radius:50%;background:rgba(52,211,153,.14);border:1px solid rgba(52,211,153,.4);display:grid;place-items:center;font-size:32px;color:var(--green);margin:0 auto 26px}
.nextsteps{text-align:left;margin-top:36px;display:grid;gap:12px}
.nextsteps .card{padding:18px 20px;display:flex;gap:14px;align-items:flex-start}
.nextsteps .n{flex:0 0 auto;width:26px;height:26px;border-radius:50%;background:rgba(245,158,11,.14);color:var(--amber2);display:grid;place-items:center;font-size:13px;font-weight:700}
/* Kubix Copilot chat page */
.kx-app { max-width: 760px; margin: 0 auto; padding: 24px; display: flex; flex-direction: column; height: 100vh; }
.kx-header { display: flex; align-items: center; gap: 12px; padding: 14px 4px 18px; border-bottom: 1px solid var(--line); }
.kx-avatar {
  width: 42px; height: 42px; border-radius: 10px; flex-shrink: 0;
  background: linear-gradient(135deg, var(--amber), #D97706);
  display: flex; align-items: center; justify-content: center; font-family: 'Space Grotesk',ui-monospace,monospace;
  font-weight: 800; color: #14171c; font-size: 15px;
}
.kx-header-text { flex: 1; min-width: 0; }
.kx-header-name { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 15px; }
.kx-online-dot { width: 8px; height: 8px; border-radius: 999px; background: var(--green); box-shadow: 0 0 0 3px rgba(34,197,94,0.18); }
.kx-header-sub { color: var(--ink3); font-size: 12.5px; margin-top: 2px; }
.kx-back { color: var(--ink3); font-size: 13px; }
.kx-messages { flex: 1; overflow-y: auto; padding: 20px 4px; display: flex; flex-direction: column; gap: 12px; }
.kx-msg { display: flex; }
.kx-msg-user { justify-content: flex-end; }
.kx-msg-bot { justify-content: flex-start; }
.kx-bubble {
  max-width: 78%; padding: 12px 15px; border-radius: 12px; font-size: 14.5px; word-wrap: break-word;
}
.kx-msg-user .kx-bubble { background: var(--amber); color: #14171c; border-bottom-right-radius: 3px; }
.kx-msg-bot .kx-bubble { background: var(--bg2); border: 1px solid var(--line); border-bottom-left-radius: 3px; }
.kx-msg-error .kx-bubble { background: rgba(248,113,113,.14); border: 1px solid rgba(239,68,68,0.4); color: #fecaca; }
.kx-bubble p { margin: 0 0 8px; }
.kx-bubble p:last-child { margin-bottom: 0; }
.kx-bubble h2, .kx-bubble h3 { margin: 10px 0 6px; }
.kx-bubble ul, .kx-bubble ol { margin: 4px 0 10px; padding-left: 20px; }
.kx-bubble code { font-family: 'Space Grotesk',ui-monospace,monospace; background: rgba(255,255,255,0.08); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
.kx-bubble pre.kx-code { background: #0b0d10; border: 1px solid var(--line); border-radius: 8px; padding: 12px; overflow-x: auto; margin: 8px 0; }
.kx-bubble pre.kx-code code { background: none; padding: 0; }
.kx-typing { display: flex; gap: 4px; padding: 14px 15px; }
.kx-typing span { width: 6px; height: 6px; border-radius: 999px; background: var(--ink3); animation: kx-bounce 1.2s infinite ease-in-out; }
.kx-typing span:nth-child(2) { animation-delay: 0.15s; }
.kx-typing span:nth-child(3) { animation-delay: 0.3s; }
@keyframes kx-bounce { 0%, 60%, 100% { transform: translateY(0); opacity: 0.5; } 30% { transform: translateY(-5px); opacity: 1; } }
.kx-escalated-banner {
  align-self: stretch; background: rgba(245,158,11,.12); border: 1px solid rgba(245,158,11,0.4);
  color: #fcd34d; font-size: 13px; padding: 10px 14px; border-radius: 8px; margin: -2px 0 4px;
}
.kx-input-bar { display: flex; gap: 10px; padding: 14px 4px 4px; border-top: 1px solid var(--line); }
.kx-input {
  flex: 1; resize: none; background: var(--bg2); border: 1px solid var(--line); color: var(--ink);
  border-radius: 10px; padding: 12px 14px; font-family: 'Inter',sans-serif; font-size: 14.5px; max-height: 140px;
}
.kx-input:focus { outline: none; border-color: var(--amber); }
.kx-send {
  border: none; background: var(--amber); color: #14171c; border-radius: 10px; padding: 0 20px;
  font-weight: 700; cursor: pointer; font-size: 14px;
}
.kx-send:disabled { opacity: 0.5; cursor: default; }


@media(max-width:960px){
  .hero,.kubix,.buywrap{grid-template-columns:1fr;gap:36px}
  .grid3,.steps,.plans{grid-template-columns:1fr}
  .stats{grid-template-columns:repeat(2,1fr)}
  .seclist{grid-template-columns:1fr}
  .navlinks a.hideM{display:none}
  .formgrid{grid-template-columns:1fr}
  .sumcard{position:static}
}
`;
// eof
