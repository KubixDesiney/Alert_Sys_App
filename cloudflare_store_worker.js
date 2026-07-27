// =============================================================================
// SIAS Store Worker — B2B storefront and controlled provisioning entry point
// =============================================================================
// The commercial front door of SIAS. The active B2B flow records private orders
// in Supabase, lets the founder Accept or mark them Paid, and dispatches a
// fail-closed GitHub provisioning job after payment. Legacy card/quote routes
// remain available behind SALES_MODE for compatibility.
//
// Routes:
//   GET  /                    landing page (product, pricing, FAQ)
//   GET  /buy?plan=&billing=  intake form + order summary
//   POST /api/order           create an under-review B2B order
//   GET  /api/session?id=     minimal session status for the success page
//   GET  /admin               private Accept/Paid orders dashboard
//   POST /admin/accept        under_review -> confirmed
//   POST /admin/paid          confirmed/review -> automatic provisioning
//   GET  /config              status probe (never exposes secret values)
//
// Secrets (wrangler secret put --config wrangler.store.toml):
//   SUPABASE_URL / SUPABASE_SERVICE_KEY
//   FOUNDER_PASSWORD / SESSION_SECRET
//   N8N_ORDER_WEBHOOK_URL / N8N_CONFIRMED_WEBHOOK_URL / N8N_PAID_WEBHOOK_URL
//   PROVISIONING_GITHUB_TOKEN / PROVISIONING_GITHUB_REPOSITORY
// =============================================================================

import { PLAN_CATALOG, planPrice, TND_CURRENCY_CODE, tndMinorUnits, listPrice } from './pricing.mjs';
import { LEGAL_DOCS } from './store_legal_content.js';

// Prices live in pricing.mjs (shared with tool/generate_quote.mjs); re-exported
// here so worker tests and any other importer keep a single entry point.
export { PLAN_CATALOG, planPrice, TND_CURRENCY_CODE, tndMinorUnits, listPrice };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// --- Sales mode ----------------------------------------------------------------
// "quote" (default): the storefront is invoice-led — /buy collects the same
// intake but submits a quote request; card rails (Stripe/ClicToPay) stay
// deployed-but-parked. "card" restores the original self-serve checkout.
export function salesMode(env) {
  return String(env?.SALES_MODE || 'quote').toLowerCase() === 'card' ? 'card' : 'quote';
}

// --- Legal publishing gate -------------------------------------------------------
// The /legal routes serve the embedded legal documents ONLY once counsel has
// signed off and LEGAL_PUBLISH is flipped to "true" — publishing becomes a
// one-var change instead of a code change. Until then: 404, no footer links.
export function legalPublishEnabled(env) {
  return String(env?.LEGAL_PUBLISH || '') === 'true';
}

// --- ClicToPay (SMT, Tunisia) ---------------------------------------------------
// BPC-style gateway: register.do returns { orderId, formUrl } -> redirect buyer;
// getOrderStatusExtended.do verifies payment on return (orderStatus 2 = paid).
// Amounts are in TND minor units (millimes, exponent 3 — configurable via
// CLICTOPAY_AMOUNT_EXPONENT because gateway contracts vary; verify with a small
// test payment before go-live). ClicToPay has no native subscriptions, so it is
// offered as annual prepay only; monthly billing requires Stripe.

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

function secureRandom() {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return value[0] / 0x1_0000_0000;
}

export function makeTenantCode(company, rand = secureRandom) {
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

// --- Quote intake (invoice-led sales mode) --------------------------------------
// Same shape as the checkout intake plus an optional phone and a preferred
// currency; no payment method — nothing here ever collects money.
const QUOTE_CURRENCIES = ['USD', 'TND', 'EUR'];

export function validateQuoteIntake(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const base = validateIntake({ ...src, method: 'stripe' }); // method is checkout-only
  const clean = { ...base.clean };
  delete clean.method;
  clean.billing = ['monthly', 'annual'].includes(clip(src.billing, 8)) ? clip(src.billing, 8) : clean.billing;
  clean.phone = clip(src.phone, 32);
  const cur = clip(src.currency, 3).toUpperCase();
  clean.currency = QUOTE_CURRENCIES.includes(cur) ? cur : 'USD';
  return { ok: base.errors.length === 0, errors: base.errors, clean };
}

/** Shapes the quote_requested event forwarded to n8n WF1. The customer block is
 *  identical to purchase_completed's so WF1 can convert a quote into a customer
 *  record with the same downstream mapping. n8n dedupes on eventId. */
export function quoteEventPayload(clean, tenantCode, eventId, nowMs = Date.now()) {
  const price = planPrice(clean.plan, clean.billing);
  return {
    source: 'sias-store',
    eventId,
    type: 'quote_requested',
    occurredAt: new Date(nowMs).toISOString(),
    tenantCode,
    plan: clean.plan,
    billing: clean.billing,
    requestedCurrency: clean.currency,
    // Indicative list prices only — the actual quote is prepared by sales.
    listPrice: {
      usdCents: price ? price.unitAmount : null,
      tnd: listPrice(clean.plan, clean.billing, 'TND'),
    },
    customer: {
      name: clean.name,
      email: clean.email,
      company: clean.company,
      country: clean.country,
      factories: clean.factories,
      notes: clean.notes,
      phone: clean.phone,
    },
  };
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

/** Validates a /api/kubix-feedback body: per-reply thumbs up/down verdicts. */
export function validateFeedbackRequest(body) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Invalid request body.' };
  const sessionId = typeof body.sessionId === 'string' ? body.sessionId.trim() : '';
  if (!sessionId || sessionId.length > MAX_SESSION_ID_LEN || !SESSION_ID_RE.test(sessionId)) {
    return { ok: false, error: 'sessionId must be 1-80 chars of letters, digits, dot, underscore, or dash.' };
  }
  const idx = Number(body.messageIndex);
  if (!Number.isInteger(idx) || idx < 0 || idx > 999) {
    return { ok: false, error: 'messageIndex must be an integer between 0 and 999.' };
  }
  if (body.verdict !== 'up' && body.verdict !== 'down') {
    return { ok: false, error: "verdict must be 'up' or 'down'." };
  }
  return { ok: true, value: { sessionId, messageIndex: idx, verdict: body.verdict } };
}


// --- Order intake (manual-approval sales mode) ----------------------------------
// The store records both delivery seats up front so Paid can provision the
// tenant without a second round trip or operator copy/paste.
export function validateOrderIntake(raw) {
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
    phone: clip(src.phone, 32),
    notes: clip(src.notes, 200),
    pmName: clip(src.pmName || src.name, 80),
    pmEmail: clip(src.pmEmail || src.email, 120).toLowerCase(),
    supervisorName: clip(src.supervisorName, 80),
    supervisorEmail: clip(src.supervisorEmail, 120).toLowerCase(),
    paymentMethod: clip(src.paymentMethod, 24) || 'bank_transfer',
  };
  const validEmail = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
  if (clean.name.length < 2) errors.push('Enter your full name.');
  if (!validEmail(clean.email)) errors.push('Enter a valid work email.');
  if (clean.company.length < 2) errors.push('Enter your company name.');
  if (!PLAN_CATALOG[clean.plan]) errors.push('Pick a plan.');
  if (!['monthly', 'annual'].includes(clean.billing)) errors.push('Pick a billing cycle.');
  if (clean.pmName.length < 2) errors.push('Enter the Production Manager name.');
  if (!validEmail(clean.pmEmail)) errors.push('Enter a valid Production Manager email.');
  if (clean.supervisorName.length < 2) errors.push('Enter the supervisor name.');
  if (!validEmail(clean.supervisorEmail)) errors.push('Enter a valid supervisor email.');
  if (clean.pmEmail && clean.pmEmail === clean.supervisorEmail) {
    errors.push('Production Manager and supervisor must use different email addresses.');
  }
  if (!['bank_transfer', 'manual'].includes(clean.paymentMethod)) {
    errors.push('Pick a valid payment method.');
  }
  if (!FACTORY_BUCKETS.includes(clean.factories)) clean.factories = '1';
  return { ok: errors.length === 0, errors, clean };
}

/** Shapes the order_placed event forwarded to n8n WF5. */
export function orderPlacedPayload(clean, tenantCode, nowMs = Date.now()) {
  const def = PLAN_CATALOG[clean.plan];
  const price = listPrice(clean.plan, clean.billing, 'USD');
  return {
    source: 'sias-store',
    eventId: `ord_${tenantCode.replace('#', '_')}`,
    type: 'order_placed',
    occurredAt: new Date(nowMs).toISOString(),
    tenantCode,
    company: clean.company,
    name: clean.name,
    email: clean.email,
    planName: def?.name || clean.plan,
    billing: clean.billing,
    amountDisplay: price ? `$${price}/month` : 'custom',
    paymentInstructions: 'Your order is under review. We will contact you after it is accepted.',
    country: clean.country,
    factories: clean.factories,
    phone: clean.phone,
    notes: clean.notes,
    paymentMethod: clean.paymentMethod,
    seats: {
      productionManager: { name: clean.pmName, email: clean.pmEmail },
      supervisor: { name: clean.supervisorName, email: clean.supervisorEmail },
    },
  };
}

/** Shapes the order_confirmed event sent when the founder presses Accept. */
export function orderConfirmedPayload(order, nowMs = Date.now()) {
  const def = PLAN_CATALOG[order.plan];
  const price = listPrice(order.plan, order.billing, 'USD');
  return {
    source: 'sias-store',
    eventId: `confirmed_${order.id || order.tenant_code?.replace('#', '_')}`,
    type: 'order_confirmed',
    occurredAt: new Date(nowMs).toISOString(),
    tenantCode: order.tenant_code,
    company: order.company,
    name: order.contact_name,
    email: order.email,
    planName: def?.name || order.plan,
    billing: order.billing,
    amountDisplay: price ? `$${price}/month` : 'custom',
    country: order.country,
    factories: order.factories,
    phone: order.phone,
    notes: order.notes,
    paymentMethod: order.payment_method || 'bank_transfer',
    message: 'Your SIAS order is confirmed. KubixDesiney will contact you shortly to discuss payment details.',
  };
}

/** Shapes the payment_paid event sent after a durable provisioning dispatch. */
export function paymentPaidPayload(order, nowMs = Date.now()) {
  return {
    ...orderConfirmedPayload(order, nowMs),
    eventId: `paid_${order.id || order.tenant_code?.replace('#', '_')}`,
    type: 'payment_paid',
    message: 'Payment is confirmed. Your dedicated SIAS instance and two activation emails are being prepared now.',
  };
}

// Compatibility export for integrations migrating from the first dashboard.
export const paymentApprovedPayload = paymentPaidPayload;

// --- Session cookie signing and verification -----------------------------------
const ADMIN_SESSION_MS = 8 * 60 * 60 * 1000;

function bytesToBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/g, '');
}

function base64UrlToBytes(value) {
  const padded = value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - value.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function hmacHex(secret, value) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(value));
  return [...new Uint8Array(sig)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** Constant-time text comparison after hashing both values to equal length. */
export async function timingSafeEqualText(left, right) {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(String(left || ''))),
    crypto.subtle.digest('SHA-256', enc.encode(String(right || ''))),
  ]);
  const av = new Uint8Array(a);
  const bv = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < av.length; i += 1) diff |= av[i] ^ bv[i];
  return diff === 0;
}

/** Signs a short-lived, nonce-bearing admin session token. */
export async function signSessionCookie(secret, nowMs = Date.now(), ttlMs = ADMIN_SESSION_MS) {
  const payload = { iat: nowMs, exp: nowMs + ttlMs, nonce: crypto.randomUUID() };
  const encoded = bytesToBase64Url(new TextEncoder().encode(JSON.stringify(payload)));
  return `${encoded}.${await hmacHex(secret, encoded)}`;
}

/** Verifies signature and explicit expiry; no deterministic daily token reuse. */
export async function verifySessionCookie(token, secret, nowMs = Date.now()) {
  if (!token || typeof token !== 'string' || !secret) return false;
  const [encoded, signature, extra] = token.split('.');
  if (!encoded || !signature || extra) return false;
  if (!await timingSafeEqualText(signature, await hmacHex(secret, encoded))) return false;
  try {
    const payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(encoded)));
    if (!Number.isFinite(payload.iat) || !Number.isFinite(payload.exp)) return false;
    if (payload.iat > nowMs + 60_000 || payload.exp <= nowMs) return false;
    if (payload.exp - payload.iat > ADMIN_SESSION_MS) return false;
    return typeof payload.nonce === 'string' && payload.nonce.length >= 16;
  } catch {
    return false;
  }
}

// --- Supabase order operations --------------------------------------------------
export const ORDER_STATUSES = Object.freeze([
  'awaiting_payment',
  'under_review',
  'confirmed',
  'provisioning_queued',
  'provisioning',
  'active',
  'provisioning_failed',
  'rejected',
]);

/** Builds the request body to insert an order into Supabase sias_orders table. */
export function supabaseInsertOrderBody(clean, tenantCode) {
  return {
    tenant_code: tenantCode,
    company: clean.company,
    contact_name: clean.name,
    email: clean.email,
    phone: clean.phone || null,
    country: clean.country || null,
    factories: clean.factories,
    plan: clean.plan,
    billing: clean.billing,
    currency: 'USD',
    amount_display: PLAN_CATALOG[clean.plan] ? `$${listPrice(clean.plan, clean.billing, 'USD')}` : 'custom',
    notes: clean.notes || null,
    pm_name: clean.pmName,
    pm_email: clean.pmEmail,
    supervisor_name: clean.supervisorName,
    supervisor_email: clean.supervisorEmail,
    payment_method: clean.paymentMethod,
    full_package: clean.plan === 'growth',
    status: 'under_review',
  };
}

/** Fetches orders from Supabase (for the admin dashboard). */
export async function supabaseGetOrders(supabaseUrl, supabaseServiceKey) {
  const res = await fetch(
    `${supabaseUrl}/rest/v1/sias_orders?order=created_at.desc&limit=100`,
    {
      headers: {
        Authorization: `Bearer ${supabaseServiceKey}`,
        apikey: supabaseServiceKey,
      },
    },
  );
  if (!res.ok) return null;
  return res.json().catch(() => null);
}

export async function supabaseGetOrderById(supabaseUrl, supabaseServiceKey, orderId) {
  const res = await fetch(
    `${supabaseUrl}/rest/v1/sias_orders?id=eq.${encodeURIComponent(orderId)}&limit=1`,
    {
      headers: {
        Authorization: `Bearer ${supabaseServiceKey}`,
        apikey: supabaseServiceKey,
      },
    },
  );
  if (!res.ok) return null;
  const rows = await res.json().catch(() => []);
  return Array.isArray(rows) ? rows[0] || null : null;
}

/** Compare-and-set transition. Returning zero rows means another request won. */
export async function supabaseTransitionOrder(
  supabaseUrl,
  supabaseServiceKey,
  orderId,
  fromStatuses,
  status,
  extraPatch = {},
) {
  if (!ORDER_STATUSES.includes(status)) return { ok: false, reason: 'invalid_status' };
  const allowed = fromStatuses.filter((value) => ORDER_STATUSES.includes(value));
  if (!allowed.length) return { ok: false, reason: 'invalid_transition' };
  const patch = { ...extraPatch, status, updated_at: new Date().toISOString() };
  const res = await fetch(
    `${supabaseUrl}/rest/v1/sias_orders?id=eq.${encodeURIComponent(orderId)}&status=in.(${allowed.join(',')})&select=*`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${supabaseServiceKey}`,
        apikey: supabaseServiceKey,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify(patch),
    },
  );
  if (!res.ok) return { ok: false, reason: 'upstream_error', status: res.status };
  const rows = await res.json().catch(() => []);
  if (!Array.isArray(rows) || rows.length !== 1) return { ok: false, reason: 'conflict' };
  return { ok: true, order: rows[0] };
}

/** Dispatches a paid order without putting buyer PII in GitHub event metadata. */
export async function dispatchPaidProvisioning(env, order) {
  const repository = String(env.PROVISIONING_GITHUB_REPOSITORY || '').trim();
  const token = String(env.PROVISIONING_GITHUB_TOKEN || '').trim();
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository) || !token) {
    return { ok: false, error: 'Provisioning dispatcher is not configured.' };
  }
  const response = await fetch(`https://api.github.com/repos/${repository}/dispatches`, {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'User-Agent': 'sias-store-provisioner',
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({
      event_type: 'sias_order_paid',
      client_payload: {
        orderId: String(order.id),
        tenantCode: String(order.tenant_code),
      },
    }),
  });
  return response.ok
    ? { ok: true }
    : { ok: false, error: `Provisioning dispatch failed (${response.status}).` };
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
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...CORS,
    },
  });
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/** Builds the strict CSP for a page response. Scripts run only with the
 *  per-response nonce (no 'unsafe-inline' for script-src — every inline event
 *  handler was refactored to addEventListener); styles allow inline + Google
 *  Fonts; everything else is same-origin. */
export function contentSecurityPolicy(nonce) {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}'`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    'font-src https://fonts.gstatic.com',
    "img-src 'self' data:",
    "connect-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; ');
}

function html(markup, status = 200, { privatePage = false } = {}) {
  // One nonce per response, stamped onto every <script> tag we emit. The CSP
  // header and the body are cached together, so they always agree.
  const nonce = crypto.randomUUID().replace(/-/g, '');
  return new Response(markup.replaceAll('<script>', `<script nonce="${nonce}">`), {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': privatePage ? 'no-store, private' : 'public, max-age=300',
      'Content-Security-Policy': contentSecurityPolicy(nonce),
      'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
      'X-Frame-Options': 'DENY',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
    },
  });
}

// --- RFC 9116 security.txt --------------------------------------------------------
export function securityTxt(env, nowMs = Date.now()) {
  const expires = new Date(nowMs + 365 * 86400000).toISOString();
  return [
    `Contact: mailto:${salesEmail(env)}`,
    `Expires: ${expires}`,
    'Preferred-Languages: en, fr',
    'Canonical: https://sias-store.aziz-nagati01.workers.dev/.well-known/security.txt',
  ].join('\n') + '\n';
}

// --- Server-side markdown renderer (legal documents) -----------------------------
// Escape-first, same philosophy as the copilot chat renderer: the source is
// trusted repo markdown, but rendering stays injection-safe by construction.
export function renderMarkdownDoc(raw) {
  let text = String(raw ?? '').replace(/\r\n/g, '\n').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
  text = text.replace(/```([\s\S]*?)```/g, (_, code) => `\n<pre class="ldoc-code"><code>${code.replace(/^\n/, '')}</code></pre>\n`);
  text = text.replace(/`([^`\n]+)`/g, '<code>$1</code>');
  text = text.replace(/^### (.*)$/gm, '<h3>$1</h3>');
  text = text.replace(/^## (.*)$/gm, '<h2>$1</h2>');
  text = text.replace(/^# (.*)$/gm, '<h1>$1</h1>');
  text = text.replace(/^ *---+ *$/gm, '<hr>');
  text = text.replace(/(^|\n)((?:&gt; ?.*(?:\n|$))+)/g, (_, pre, block) => {
    const inner = block.trim().split('\n').map((l) => l.replace(/^&gt; ?/, '')).join('<br>');
    return `${pre}<blockquote>${inner}</blockquote>\n`;
  });
  text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  text = text.replace(/(^|\n)((?:\d+\. .*(?:\n|$))+)/g, (_, pre, block) => {
    const items = block.trim().split('\n').map((l) => l.replace(/^\d+\.\s*/, ''));
    return `${pre}<ol>${items.map((i) => `<li>${i}</li>`).join('')}</ol>\n`;
  });
  text = text.replace(/(^|\n)((?:[-*] .*(?:\n|$))+)/g, (_, pre, block) => {
    const items = block.trim().split('\n').map((l) => l.replace(/^[-*]\s*/, ''));
    return `${pre}<ul>${items.map((i) => `<li>${i}</li>`).join('')}</ul>\n`;
  });
  return text
    .split(/\n{2,}/)
    .map((block) => {
      const b = block.trim();
      if (!b) return '';
      if (/^<(h[1-6]|ul|ol|pre|blockquote|hr)/.test(b)) return b;
      return `<p>${b.replace(/\n/g, '<br>')}</p>`;
    })
    .filter(Boolean)
    .join('\n');
}

function legalChrome(inner, env) {
  const mail = salesEmail(env);
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <nav class="navlinks"><a href="/legal">Legal</a><a href="/#pricing">Pricing</a></nav>
</div></header>
<main class="wrap ldocwrap">${inner}</main>
<footer><div class="wrap">
  <span><b style="color:var(--ink2)">SIAS</b> &mdash; Smart Industrial Alert System &middot; by KubixDesiney</span>
  <span><a href="/legal/privacy">Privacy</a> &middot; <a href="/legal/terms">Terms</a> &middot; <a href="mailto:${mail}">${mail}</a></span>
  <span>&copy; 2026 KubixDesiney. All rights reserved.</span>
</div></footer>`;
}

function handleLegal(pathname, env) {
  if (!legalPublishEnabled(env)) return new Response('Not found', { status: 404 });
  if (pathname === '/legal' || pathname === '/legal/') {
    const list = Object.entries(LEGAL_DOCS)
      .map(([slug, d]) => `<li class="card" style="padding:18px 22px;margin-bottom:12px;list-style:none"><a href="/legal/${slug}" style="font-weight:600">${d.title}</a></li>`)
      .join('');
    return html(page(
      'Legal — SIAS',
      'Legal documents for SIAS — Smart Industrial Alert System.',
      legalChrome(`<span class="eyebrow">Legal</span><h1 style="margin:16px 0 24px">Legal documents</h1><ul style="padding:0">${list}</ul>`, env),
    ));
  }
  const doc = LEGAL_DOCS[pathname.replace(/^\/legal\//, '')];
  if (!doc) return new Response('Not found', { status: 404 });
  return html(page(
    `${doc.title} — SIAS`,
    `${doc.title} for SIAS — Smart Industrial Alert System.`,
    legalChrome(`<article class="ldoc">${renderMarkdownDoc(doc.markdown)}</article>`, env),
  ));
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

// Invoice-led rail: validates the same intake shape, generates the tenant code,
// and forwards a quote_requested event to n8n WF1. Never touches money.
async function handleQuote(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || 'anon';
  const limit = Number(env.STORE_RATE_LIMIT || 10);
  if (rateLimited(`q:${ip}`, limit)) {
    return json({ ok: false, error: 'Too many attempts — try again in a minute.' }, 429);
  }
  let raw;
  try { raw = await request.json(); } catch { return json({ ok: false, error: 'Invalid request body.' }, 400); }
  const v = validateQuoteIntake(raw);
  if (!v.ok) return json({ ok: false, error: v.errors.join(' ') }, 400);
  if (!env.N8N_INTAKE_WEBHOOK_URL) {
    return json({ ok: false, error: 'Quote requests are not configured yet — email us and we will send yours directly.' }, 503);
  }
  const tenantCode = makeTenantCode(v.clean.company);
  const payload = quoteEventPayload(v.clean, tenantCode, `qr_${crypto.randomUUID()}`);
  const headers = { 'Content-Type': 'application/json' };
  if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;
  let fwd;
  try {
    fwd = await fetch(env.N8N_INTAKE_WEBHOOK_URL, { method: 'POST', headers, body: JSON.stringify(payload) });
  } catch {
    return json({ ok: false, error: 'We could not record your request — please retry or email us.' }, 502);
  }
  if (!fwd.ok) return json({ ok: false, error: 'We could not record your request — please retry or email us.' }, 502);
  return json({ ok: true, tenantCode });
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

// Thumbs up/down on Kubix replies — forwarded to the n8n feedback workflow so
// the agent's answers can be graded and improved. Fire-and-forget quality data;
// never blocks or alters the chat itself.
async function handleKubixFeedback(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (rateLimited(`kxf:${ip}`, 20)) {
    return json({ ok: false, error: 'Too many requests. Please wait a moment.' }, 429);
  }
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const validated = validateFeedbackRequest(body);
  if (!validated.ok) return json({ ok: false, error: validated.error }, 400);
  if (!env.N8N_FEEDBACK_WEBHOOK_URL) {
    return json({ ok: false, error: 'Feedback is not configured for this instance yet.' }, 503);
  }
  const headers = { 'Content-Type': 'application/json' };
  if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  let upstream;
  try {
    upstream = await fetch(env.N8N_FEEDBACK_WEBHOOK_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ source: 'sias-store', at: new Date().toISOString(), ...validated.value }),
      signal: controller.signal,
    });
  } catch {
    clearTimeout(timeout);
    return json({ ok: false, error: 'Could not record feedback right now.' }, 502);
  }
  clearTimeout(timeout);
  if (!upstream.ok) return json({ ok: false, error: 'Could not record feedback right now.' }, 502);
  return json({ ok: true });
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

// Manual-approval order intake ------------------------------------------------
async function handleOrderIntake(request, env, url) {
  const ip = request.headers.get('cf-connecting-ip') || 'anon';
  const limit = Number(env.STORE_RATE_LIMIT || 10);
  if (rateLimited(`ord:${ip}`, limit)) {
    return json({ ok: false, error: 'Too many attempts — try again in a minute.' }, 429);
  }
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_KEY) {
    return json({ ok: false, error: 'Order system is not configured yet. Email us and we will set you up directly.' }, 503);
  }
  let raw;
  try { raw = await request.json(); } catch { return json({ ok: false, error: 'Invalid request body.' }, 400); }
  const v = validateOrderIntake(raw);
  if (!v.ok) return json({ ok: false, error: v.errors.join(' ') }, 400);
  const tenantCode = makeTenantCode(v.clean.company);
  const orderBody = supabaseInsertOrderBody(v.clean, tenantCode);
  let insertRes;
  try {
    insertRes = await fetch(`${env.SUPABASE_URL}/rest/v1/sias_orders`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
        apikey: env.SUPABASE_SERVICE_KEY,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify(orderBody),
    });
  } catch {
    return json({ ok: false, error: 'Could not save your order. Please try again.' }, 502);
  }
  if (!insertRes.ok) {
    const errorMsg = insertRes.status === 409
      ? 'This tenant code already exists. Please contact us.'
      : 'Could not save your order. Please try again.';
    return json({ ok: false, error: errorMsg }, 502);
  }
  // The order is already durable, so a notification outage must not invite a
  // duplicate browser retry. Return success with an operator-visible warning.
  const notification = env.N8N_ORDER_WEBHOOK_URL
    ? await sendOrderWebhook(env, env.N8N_ORDER_WEBHOOK_URL, orderPlacedPayload(v.clean, tenantCode))
    : { ok: false, error: 'Order-received email webhook is not configured.' };
  return json({
    ok: true,
    tenantCode,
    message: 'Order received. Your SIAS request is under review and your tenant code is reserved.',
    warning: notification.ok ? undefined : notification.error,
    kubixChatUrl: `${url.origin}/copilot?tenant=${tenantCode}&company=${encodeURIComponent(v.clean.company)}&name=${encodeURIComponent(v.clean.name)}&plan=${v.clean.plan}`,
  });
}

// Founder orders dashboard ---------------------------------------------------
function adminCookie(request) {
  const raw = request.headers.get('cookie') || '';
  const pair = raw.split(';').map((part) => part.trim()).find((part) => part.startsWith('__admin='));
  return pair ? pair.slice('__admin='.length) : '';
}

async function adminAuthorized(request, env) {
  return !!env.SESSION_SECRET
    && !!adminCookie(request)
    && await verifySessionCookie(adminCookie(request), env.SESSION_SECRET);
}

function validAdminMutation(request) {
  const origin = request.headers.get('origin');
  const customHeader = request.headers.get('x-sias-admin-action');
  return origin === new URL(request.url).origin && customHeader === '1';
}

async function sendOrderWebhook(env, webhookUrl, payload) {
  if (!webhookUrl) return { ok: false, error: 'Order email webhook is not configured.' };
  const headers = { 'Content-Type': 'application/json' };
  if (env.N8N_WEBHOOK_AUTH) headers.Authorization = `Bearer ${env.N8N_WEBHOOK_AUTH}`;
  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
    return response.ok
      ? { ok: true }
      : { ok: false, error: `Order email webhook failed (${response.status}).` };
  } catch {
    return { ok: false, error: 'Order email webhook could not be reached.' };
  }
}

async function handleAdminLogin(request, env, url) {
  if (request.method === 'GET') {
    // GET /admin with valid cookie → dashboard
    if (await adminAuthorized(request, env)) {
      const orders = await supabaseGetOrders(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY);
      return html(ordersDashboard(orders || [], env, url.origin), 200, { privatePage: true });
    }
    // GET /admin without cookie → login form
    return html(adminLoginPage(), 200, { privatePage: true });
  }
  // POST /admin (login attempt)
  const ip = request.headers.get('cf-connecting-ip') || 'anon';
  if (rateLimited(`login:${ip}`, 5)) {
    return json({ ok: false, error: 'Too many login attempts. Try again in a minute.' }, 429);
  }
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: 'Invalid request.' }, 400); }
  const password = String(body?.password || '').trim();
  if (!password || !env.FOUNDER_PASSWORD || !env.SESSION_SECRET
      || !await timingSafeEqualText(password, env.FOUNDER_PASSWORD)) {
    return json({ ok: false, error: 'Invalid password.' }, 401);
  }
  const token = await signSessionCookie(env.SESSION_SECRET);
  const response = json({ ok: true, message: 'Logged in.' });
  response.headers.set('Set-Cookie', `__admin=${token}; Path=/admin; HttpOnly; Secure; SameSite=Strict; Max-Age=${ADMIN_SESSION_MS / 1000}`);
  return response;
}

async function readAdminOrderAction(request, env) {
  if (!await adminAuthorized(request, env)) {
    return { response: json({ ok: false, error: 'Unauthorized.' }, 401) };
  }
  if (!validAdminMutation(request)) {
    return { response: json({ ok: false, error: 'Invalid admin action origin.' }, 403) };
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return { response: json({ ok: false, error: 'Invalid request.' }, 400) };
  }
  const orderId = String(body?.orderId || '').trim();
  if (!/^[A-Za-z0-9-]{1,80}$/.test(orderId)) {
    return { response: json({ ok: false, error: 'Missing or invalid orderId.' }, 400) };
  }
  const order = await supabaseGetOrderById(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, orderId);
  if (!order) return { response: json({ ok: false, error: 'Order not found.' }, 404) };
  return { order };
}

async function handleAdminAccept(request, env) {
  const action = await readAdminOrderAction(request, env);
  if (action.response) return action.response;
  let { order } = action;
  // Never fall back to the legacy "approved" workflow: it used payment copy
  // and could make an Accept action look like money was received.
  const webhookUrl = env.N8N_CONFIRMED_WEBHOOK_URL;
  if (!webhookUrl) {
    return json({ ok: false, error: 'Confirmation email webhook is not configured.' }, 503);
  }
  if (['provisioning_queued', 'provisioning', 'active'].includes(order.status)) {
    return json({ ok: true, message: 'This order has already moved beyond confirmation.' });
  }
  if (order.status !== 'confirmed') {
    const transition = await supabaseTransitionOrder(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_KEY,
      order.id,
      ['awaiting_payment', 'under_review'],
      'confirmed',
      { confirmed_at: new Date().toISOString() },
    );
    if (!transition.ok) {
      const status = transition.reason === 'conflict' ? 409 : 502;
      return json({ ok: false, error: 'Order status changed; refresh and try again.' }, status);
    }
    order = transition.order;
  }
  const notification = await sendOrderWebhook(env, webhookUrl, orderConfirmedPayload(order));
  if (!notification.ok) return json({ ok: false, error: notification.error }, 502);
  return json({ ok: true, message: 'Order confirmed and confirmation email sent.' });
}

async function handleAdminPaid(request, env) {
  const action = await readAdminOrderAction(request, env);
  if (action.response) return action.response;
  let { order } = action;
  if (['provisioning_queued', 'provisioning', 'active'].includes(order.status)) {
    return json({ ok: true, message: 'Payment is already recorded and provisioning is in progress.' });
  }
  const queued = await supabaseTransitionOrder(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_KEY,
    order.id,
    ['awaiting_payment', 'under_review', 'confirmed', 'provisioning_failed'],
    'provisioning_queued',
    {
      paid_at: new Date().toISOString(),
      provisioning_error: null,
    },
  );
  if (!queued.ok) {
    const status = queued.reason === 'conflict' ? 409 : 502;
    return json({ ok: false, error: 'Order status changed; refresh and try again.' }, status);
  }
  order = queued.order;
  let dispatched;
  try {
    dispatched = await dispatchPaidProvisioning(env, order);
  } catch {
    dispatched = { ok: false, error: 'Provisioning dispatch could not be reached.' };
  }
  if (!dispatched.ok) {
    await supabaseTransitionOrder(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_KEY,
      order.id,
      ['provisioning_queued'],
      'provisioning_failed',
      { provisioning_error: clip(dispatched.error, 500) },
    );
    return json({ ok: false, error: `${dispatched.error} The order is safe to retry.` }, 502);
  }
  const started = await supabaseTransitionOrder(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_KEY,
    order.id,
    ['provisioning_queued'],
    'provisioning',
    { provisioning_started_at: new Date().toISOString() },
  );
  if (started.ok) order = started.order;

  const webhookUrl = env.N8N_PAID_WEBHOOK_URL;
  const notification = webhookUrl
    ? await sendOrderWebhook(env, webhookUrl, paymentPaidPayload(order))
    : { ok: false, error: 'Payment email webhook is not configured.' };
  return json({
    ok: true,
    message: 'Payment recorded. Automatic provisioning has started.',
    warning: notification.ok ? undefined : notification.error,
  });
}

async function handleAdminApprove(request, env) {
  // Backward-compatible endpoint: old dashboard clients map Approve to Accept,
  // never directly to Paid/provisioning.
  if (!await adminAuthorized(request, env)) {
    return json({ ok: false, error: 'Unauthorized.' }, 401);
  }
  return json({ ok: false, error: 'This endpoint was replaced by Accept and Paid. Refresh the dashboard.' }, 410);
}

async function handleAdminLogout(request, env) {
  const response = json({ ok: true, message: 'Logged out.' });
  response.headers.set('Set-Cookie', '__admin=; Path=/admin; HttpOnly; Secure; SameSite=Strict; Max-Age=0');
  return response;
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
          salesMode: salesMode(env),
          stripe: !!env.STRIPE_SECRET_KEY,
          webhookSecret: !!env.STRIPE_WEBHOOK_SECRET,
          clictopay: !!(env.CLICTOPAY_USER && env.CLICTOPAY_PASSWORD),
          n8nIntake: !!env.N8N_INTAKE_WEBHOOK_URL,
          kubixChat: !!env.N8N_CHAT_WEBHOOK_URL,
          kubixFeedback: !!env.N8N_FEEDBACK_WEBHOOK_URL,
          hasSupabase: !!(env.SUPABASE_URL && env.SUPABASE_SERVICE_KEY),
          hasFounderAuth: !!env.FOUNDER_PASSWORD && !!env.SESSION_SECRET,
          hasOrderWebhook: !!env.N8N_ORDER_WEBHOOK_URL,
          hasConfirmedWebhook: !!env.N8N_CONFIRMED_WEBHOOK_URL,
          hasPaidWebhook: !!env.N8N_PAID_WEBHOOK_URL,
          hasProvisioningDispatcher: !!env.PROVISIONING_GITHUB_TOKEN && !!env.PROVISIONING_GITHUB_REPOSITORY,
        });
      }
      if (pathname === '/.well-known/security.txt') {
        return new Response(securityTxt(env), {
          headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'public, max-age=86400' },
        });
      }
      if (pathname === '/api/checkout' && request.method === 'POST') return handleCheckout(request, env, url);
      if (pathname === '/api/quote' && request.method === 'POST') return handleQuote(request, env);
      if (pathname === '/api/session' && request.method === 'GET') return handleSessionStatus(url, env);
      if (pathname === '/api/ctp-order' && request.method === 'GET') return handleCtpOrderStatus(url, env);
      if (pathname === '/api/kubix' && request.method === 'POST') return handleKubixChat(request, env);
      if (pathname === '/api/kubix-feedback' && request.method === 'POST') return handleKubixFeedback(request, env);
      if (pathname === '/api/stripe-webhook' && request.method === 'POST') return handleStripeWebhook(request, env);
      if (pathname === '/api/order' && request.method === 'POST') return handleOrderIntake(request, env, url);
      if (pathname === '/admin' && (request.method === 'GET' || request.method === 'POST')) return handleAdminLogin(request, env, url);
      if (pathname === '/admin/accept' && request.method === 'POST') return handleAdminAccept(request, env);
      if (pathname === '/admin/paid' && request.method === 'POST') return handleAdminPaid(request, env);
      if (pathname === '/admin/approve' && request.method === 'POST') return handleAdminApprove(request, env);
      if (pathname === '/admin/logout' && request.method === 'POST') return handleAdminLogout(request, env);
      if (pathname === '/clictopay/return') return handleClictopayReturn(url, env);
      if (pathname === '/legal' || pathname.startsWith('/legal/')) return handleLegal(pathname, env);
      if (pathname === '/buy') return html(buyPage(url, env));
      if (pathname === '/copilot') return html(copilotPage(url));
      if (pathname === '/welcome') return html(welcomePage(env));
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

const UI_ICON_PATHS = Object.freeze({
  alert: '<path d="M12 3 2.7 20h18.6L12 3Z"/><path d="M12 9v4.7"/><path d="M12 17.2h.01"/>',
  arrow: '<path d="M5 12h13"/><path d="m14 7 5 5-5 5"/>',
  bank: '<path d="m3 9 9-5 9 5"/><path d="M5 10v7M9.5 10v7M14.5 10v7M19 10v7"/><path d="M3 20h18"/>',
  bolt: '<path d="m13 2-8 12h7l-1 8 8-12h-7l1-8Z"/>',
  brain: '<path d="M9.5 4.5A3.5 3.5 0 0 0 6 8v.4a3.5 3.5 0 0 0-1 6.7V16a4 4 0 0 0 4 4h1V5.5a1 1 0 0 0-.5-1Z"/><path d="M14.5 4.5A3.5 3.5 0 0 1 18 8v.4a3.5 3.5 0 0 1 1 6.7V16a4 4 0 0 1-4 4h-1V5.5a1 1 0 0 1 .5-1Z"/><path d="M7 10h3M14 10h3M7 15h3M14 15h3"/>',
  chart: '<path d="M4 19V5"/><path d="M4 19h16"/><path d="m7 15 3-4 3 2 5-7"/><path d="M18 6v4M18 6h-4"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/><path d="M10 10h4v4h-4z"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M9 21h6"/>',
  network: '<rect x="3" y="4" width="6" height="5" rx="1"/><rect x="15" y="4" width="6" height="5" rx="1"/><rect x="9" y="15" width="6" height="5" rx="1"/><path d="M6 9v3h12V9M12 12v3"/>',
  pulse: '<path d="M3 12h4l2-5 4 10 2-5h6"/>',
  radio: '<circle cx="12" cy="12" r="2"/><path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.5 5.5a9 9 0 0 0 0 13M18.5 5.5a9 9 0 0 1 0 13"/>',
  shield: '<path d="M12 3 5 6v5c0 4.7 2.8 8.2 7 10 4.2-1.8 7-5.3 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-5"/>',
  wrench: '<path d="M14.5 6.5a4 4 0 0 0-5.3 5.3L4 17l3 3 5.2-5.2a4 4 0 0 0 5.3-5.3l-2.7 2.7-3-3 2.7-2.7Z"/>',
});

function uiIcon(name, className = 'ui-icon') {
  const paths = UI_ICON_PATHS[name] || UI_ICON_PATHS.pulse;
  return `<svg class="${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${paths}</svg>`;
}

function brandLockup() {
  return `<span class="brand-mark" aria-hidden="true">
    <svg viewBox="0 0 40 40" focusable="false">
      <path class="cube-top" d="m20 3 14 8-14 8-14-8 14-8Z"/>
      <path class="cube-left" d="m6 11 14 8v17L6 28V11Z"/>
      <path class="cube-right" d="m34 11-14 8v17l14-8V11Z"/>
      <path class="cube-signal" d="M10.5 24h4l2.1-4.2 3.2 8.1 2.4-4.4h7.2"/>
    </svg>
  </span><span class="brand-word">SIAS</span><span class="brand-by">by Kubix</span>`;
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
<meta name="theme-color" content="#070A0F">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40'%3E%3Crect width='40' height='40' rx='8' fill='%23070A0F'/%3E%3Cpath fill='%23F4B942' d='m20 4 13 7.5L20 19 7 11.5 20 4Z'/%3E%3Cpath fill='%23BE7D16' d='m7 11.5 13 7.5v16L7 27.5v-16Z'/%3E%3Cpath fill='%2346D9E8' d='M33 11.5 20 19v16l13-7.5v-16Z'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<script>document.documentElement.classList.add('js');</script>
<style>${BASE_CSS}</style>${extraHead}
</head>
<body>
  <a class="skip-link" href="#site-content">Skip to content</a>
  <div class="scroll-progress" aria-hidden="true"><span></span></div>
  <div id="site-content" tabindex="-1">${body}</div>
  <script>${SHELL_CLIENT_JS}</script>
</body>
</html>`;
}

function landingPage(env) {
  return page(
    'SIAS — Smart Industrial Alert System',
    'Real-time factory alert supervision: AI dispatch, voice-first claiming, SCADA/PLC integration and self-grading failure forecasts. Dedicated instance per customer.',
    landingBody(env, salesMode(env)),
  );
}

function buyPage(url, env) {
  const plan = PLAN_CATALOG[url.searchParams.get('plan')] ? url.searchParams.get('plan') : 'growth';
  const billing = url.searchParams.get('billing') === 'annual' ? 'annual' : 'monthly';
  const mode = salesMode(env);
  return page(
    mode === 'quote' ? 'Get a SIAS quote' : 'Get SIAS — checkout',
    mode === 'quote'
      ? 'Tell us about your plant — your tailored quote lands in your inbox within 1 business day.'
      : 'Tell us about your plant and continue to secure checkout.',
    buyBody(plan, billing, env, mode),
  );
}

function successPage(env) {
  return page(
    'Welcome aboard — SIAS',
    'Payment confirmed. Your dedicated SIAS instance is being provisioned.',
    successBody(env),
  );
}

function landingBody(env, mode = 'card') {
  const mail = salesEmail(env);
  const quote = mode === 'quote';
  const buyCta = quote ? 'Get a quote' : null;
  return `
<header class="nav storefront-nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <nav class="navlinks">
    <a class="hideM" href="#features">Product</a>
    <a class="hideM" href="#integrations">Integrations</a>
    <a class="hideM" href="#kubix">Kubix Copilot</a>
    <a class="hideM" href="/copilot">Copilot chat</a>
    <a class="hideM" href="#security">Security</a>
    <a href="#pricing">Pricing</a>
    <a class="btn btn-amber btn-sm" data-magnetic href="/buy?plan=growth&billing=annual">Get SIAS ${uiIcon('arrow', 'btn-icon')}</a>
  </nav>
</div></header>

<main class="storefront-main">
<section class="hero-section" aria-labelledby="hero-title">
<div class="wrap">
  <div class="hero">
    <div class="hero-copy" data-reveal="left">
      <span class="eyebrow">${uiIcon('pulse', 'eyebrow-icon')} Smart Industrial Alert System</span>
      <h1 id="hero-title">Every factory signal.<br><span class="signal-text">Caught before it becomes downtime.</span></h1>
      <p class="lead">SIAS is the real-time supervision platform for industrial plants: AI-dispatched alerts, voice-first claiming from a locked phone, SCADA-to-shop-floor integration, and a failure forecaster that trains on your own history and grades itself daily.</p>
      <div class="ctas">
        <a class="btn btn-amber" data-magnetic href="#pricing">Get SIAS &mdash; from $490/mo ${uiIcon('arrow', 'btn-icon')}</a>
        <a class="btn btn-ghost" href="#how">${uiIcon('pulse', 'btn-icon')} See the signal path</a>
      </div>
      <div class="hero-assurance" aria-label="Deployment assurances">
        <span>${uiIcon('shield', 'micro-icon')} Dedicated instance</span>
        <span>${uiIcon('bolt', 'micro-icon')} Live in one business day</span>
        <span class="mono">EN / FR</span>
      </div>
    </div>
    <div class="signal-stage" data-tilt data-reveal="right" role="img" aria-label="Animated SIAS command console showing a machine signal becoming an assigned, claimed, and resolved alert">
      <div class="stage-corner stage-corner-a"></div><div class="stage-corner stage-corner-b"></div>
      <div class="stage-head">
        <div class="stage-title"><span class="live-pip"></span><span class="mono">PLANT TWIN / LINE 03</span></div>
        <div class="stage-health"><span>EDGE</span><b>ONLINE</b><span class="stage-time">14:32:08</span></div>
      </div>
      <div class="stage-body">
        <aside class="stage-rail" aria-hidden="true">
          <div class="rail-readout"><span>INGEST</span><b>842</b><small>evt/min</small></div>
          <div class="rail-readout"><span>LATENCY</span><b>1.5</b><small>seconds</small></div>
          <div class="rail-readout"><span>ASSIGN</span><b>0.92</b><small>confidence</small></div>
          <div class="rail-spectrum"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
        </aside>
        <div class="factory-field">
          <div class="field-grid" aria-hidden="true"></div>
          <svg class="factory-schematic" viewBox="0 0 620 390" aria-hidden="true" focusable="false">
            <defs>
              <linearGradient id="sias-route" x1="0" x2="1">
                <stop offset="0" stop-color="#46D9E8" stop-opacity=".2"/>
                <stop offset=".58" stop-color="#46D9E8"/>
                <stop offset="1" stop-color="#F4B942"/>
              </linearGradient>
              <filter id="sias-soft">
                <feGaussianBlur stdDeviation="3"/>
              </filter>
            </defs>
            <path class="plant-outline" d="M48 75h165l32 28h128l24-22h168v238H397l-28-24H236l-26 24H48Z"/>
            <path class="plant-inner" d="M92 114h104v60H92zM92 220h104v60H92zM246 132h117v128H246zM418 112h92v62h-92zM418 221h92v61h-92z"/>
            <path class="route-base" d="M143 144H248c27 0 20 52 49 52h72c30 0 26-53 57-53h38"/>
            <path class="route-flow" d="M143 144H248c27 0 20 52 49 52h72c30 0 26-53 57-53h38"/>
            <path class="route-base secondary" d="M143 250h64c34 0 31-54 67-54"/>
            <path class="route-flow route-flow-secondary" d="M143 250h64c34 0 31-54 67-54"/>
            <g class="machine-node node-ok" transform="translate(143 144)">
              <circle class="node-halo" r="20"/><rect x="-8" y="-8" width="16" height="16"/><path d="M-4 0h8M0-4v8"/>
            </g>
            <g class="machine-node node-ok" transform="translate(143 250)">
              <circle class="node-halo" r="20"/><rect x="-8" y="-8" width="16" height="16"/><path d="M-4 0h8M0-4v8"/>
            </g>
            <g class="machine-node node-ai" transform="translate(305 196)">
              <circle class="node-halo" r="24"/><path d="M-9-9h18v18H-9zM-4-4h8v8H-4z"/>
            </g>
            <g class="machine-node node-critical" transform="translate(464 143)">
              <circle class="node-ring" r="27"/><circle class="node-halo" r="19"/><path d="M0-10 10 9h-20L0-10ZM0-3v5M0 6h.01"/>
            </g>
            <g class="machine-node node-ok" transform="translate(464 251)">
              <circle class="node-halo" r="20"/><rect x="-8" y="-8" width="16" height="16"/><path d="m-4 0 3 3 6-7"/>
            </g>
            <text x="99" y="128">PRESS 07</text><text x="99" y="234">PACK 02</text>
            <text x="271" y="178">AI ROUTER</text><text x="425" y="126">CONV B12</text><text x="425" y="235">QA GATE</text>
          </svg>
          <div class="scan-beam" aria-hidden="true"></div>
          <div class="alert-ticket">
            <div class="ticket-top">
              <span class="ticket-code">${uiIcon('alert', 'ticket-icon')} ALT-2841</span>
              <span class="chip crit">CRITICAL</span>
            </div>
            <strong>Conveyor B / Station 12</strong>
            <p>Torque anomaly &middot; OPC-UA signal</p>
            <div class="assignment">
              <span class="agent-orb">AI</span>
              <div><small>ASSIGNED TO</small><b>S. Karim</b></div>
              <span class="confidence mono">92%</span>
            </div>
          </div>
        </div>
      </div>
      <div class="signal-lifecycle">
        <div class="lifecycle-track"><span class="lifecycle-runner"></span></div>
        <div class="life-step active"><i>01</i><span>Signal received</span><b>00.0s</b></div>
        <div class="life-step"><i>02</i><span>AI assigned</span><b>00.7s</b></div>
        <div class="life-step"><i>03</i><span>Voice claimed</span><b>08.2s</b></div>
        <div class="life-step resolved"><i>04</i><span>Resolution learned</span><b>11m</b></div>
      </div>
    </div>
  </div>

  <div class="stats" data-reveal="up" aria-label="Platform operating facts">
    <div class="stat"><div class="n">~1.5s</div><div class="l">median alert push to phones</div></div>
    <div class="stat"><div class="n">24/7</div><div class="l">AI shift commander</div></div>
    <div class="stat"><div class="n">466</div><div class="l">automated tests in CI</div></div>
    <div class="stat"><div class="n">7</div><div class="l">edge services per instance</div></div>
    <div class="stat"><div class="n">EN&middot;FR</div><div class="l">fully bilingual, runtime switch</div></div>
  </div>
</div>
</section>

<section id="features" class="foundry-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">01 / SIGNAL ENGINE</div>
  <div class="shead split-head" data-reveal="up"><span class="eyebrow">${uiIcon('chip', 'eyebrow-icon')} Platform</span>
    <h2>Built for the plant floor,<br><span>not the boardroom demo.</span></h2>
    <p>Every capability below ships in your instance on day one &mdash; this is running software, not a roadmap.</p>
  </div>
  <div class="grid3 feature-grid">
    <article class="card feat feat-primary" data-reveal="up"><div class="ic">${uiIcon('brain')}</div><span class="module-id mono">MOD / 01</span><h3>AI dispatch &amp; shift commander</h3><p>Scores every supervisor on history, workload, location and feedback, assigns in seconds, and can run entire shifts autonomously &mdash; with every decision explained and logged.</p><div class="module-trace" aria-hidden="true"></div></article>
    <article class="card feat" data-reveal="up"><div class="ic">${uiIcon('chart')}</div><span class="module-id mono">MOD / 02</span><h3>Forecasts that earn trust</h3><p>A gradient-boosted model trains on your alert history in seconds, forecasts next-24h machine risk, then grades its own accuracy against what actually happened &mdash; daily.</p><div class="module-trace" aria-hidden="true"></div></article>
    <article class="card feat" data-reveal="up"><div class="ic">${uiIcon('mic')}</div><span class="module-id mono">MOD / 03</span><h3>Voice-first operations</h3><p>Claim, resolve and escalate hands-free &mdash; even from a locked phone. Offline speech recognition with speaker verification, in English and French.</p><div class="module-trace" aria-hidden="true"></div></article>
    <article class="card feat" data-reveal="up"><div class="ic">${uiIcon('network')}</div><span class="module-id mono">MOD / 04</span><h3>Plugs into your estate</h3><p>OPC-UA, Modbus, MQTT, REST, PI and Ignition historians, plus ESP32/Arduino edge kits. Configured self-service from your console. SIAS observes &mdash; it never touches control loops.</p><div class="module-trace" aria-hidden="true"></div></article>
    <article class="card feat" data-reveal="up"><div class="ic">${uiIcon('radio')}</div><span class="module-id mono">MOD / 05</span><h3>Built for bad networks</h3><p>Offline-aware mobile apps, queued sync, cached roles and durable retries. The plant floor does not stop when the Wi-Fi does &mdash; neither does SIAS.</p><div class="module-trace" aria-hidden="true"></div></article>
    <article class="card feat" data-reveal="up"><div class="ic">${uiIcon('shield')}</div><span class="module-id mono">MOD / 06</span><h3>A command console you own</h3><p>Your SuperAdmin cockpit: live fleet monitor, security feed, hardware lab, custom alert types, model training and account provisioning &mdash; on your dedicated instance.</p><div class="module-trace" aria-hidden="true"></div></article>
  </div>
</div></section>

<section id="integrations" class="foundry-section integrations-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">02 / INDUSTRIAL I/O</div>
  <div class="shead split-head" data-reveal="up"><span class="eyebrow">${uiIcon('network', 'eyebrow-icon')} Integrations</span>
    <h2>Speaks fluent factory.</h2>
    <p>Cloud-pull, edge-push or broker-based &mdash; your IT team connects the estate without us on the phone.</p>
  </div>
  <div class="protocol-board" data-reveal="up">
    <div class="protocol-core" aria-hidden="true"><span>${uiIcon('pulse')}</span><b>SIAS</b><small>EDGE ROUTER</small></div>
    <div class="logos">
      <span><i></i>OPC-UA</span><span><i></i>Modbus</span><span><i></i>MQTT</span><span><i></i>REST APIs</span><span><i></i>OSIsoft PI</span><span><i></i>Ignition</span><span><i></i>ESP32 / Arduino</span><span><i></i>SCIM 2.0</span><span><i></i>Firebase Auth + MFA</span>
    </div>
  </div>
</div></section>

<section id="kubix" class="foundry-section kubix-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">03 / HUMAN + MACHINE</div>
  <div class="kubix">
  <div data-reveal="left">
    <span class="eyebrow">${uiIcon('brain', 'eyebrow-icon')} Included with every purchase</span>
    <h2>Meet your<br><span>Kubix Copilot.</span></h2>
    <p class="mut" style="margin-top:16px;font-size:17px">The moment you buy, a named AI engineer is created for your company &mdash; trained on SIAS internals, your plan, and your integration stack. It guides activation, wires your SCADA/PLC/ESP32 connections, answers the 2am questions, and escalates to a human engineer when it should.</p>
    <ul class="signal-list">
      <li>${uiIcon('check', 'list-check')} Knows your instance, tenant code and configuration</li>
      <li>${uiIcon('check', 'list-check')} Generates gateway snippets for your exact hardware</li>
      <li>${uiIcon('check', 'list-check')} Onboards supervisors, PMs and IT &mdash; in EN or FR</li>
    </ul>
  </div>
  <div class="chatcard" data-tilt data-reveal="right">
    <div class="chat-chrome mono"><span>SECURE COPILOT CHANNEL</span><span>LATENCY 230ms</span></div>
    <div class="kbadge"><div class="av">${uiIcon('brain')}</div><div><div class="nm">Kubix &middot; NSW#7K2F</div><div class="st"><i></i> online &mdash; your dedicated copilot</div></div></div>
    <div class="msg user">How do I wire our Siemens S7 line into SIAS?</div>
    <div class="msg bot">Three steps, about 20 minutes:<ol><li>Enable the <b>OPC-UA connector</b> in your console (Infrastructure &rarr; Connectors)</li><li>I generate your gateway snippet with your ingest key baked in</li><li>We run a live <b>Verify link test</b> together</li></ol>Want me to prep the snippet for Line 2 now?</div>
    <div class="msg user">Yes &mdash; and set the alert type to maintenance.</div>
    <div class="msg bot">Done. Snippet ready &mdash; alerts from Line 2 will arrive tagged <b>maintenance</b>, routed by AI dispatch. I will watch the first 10 packets with you.</div>
    <a class="chat-launch" href="/copilot">Open secure channel ${uiIcon('arrow', 'btn-icon')}</a>
  </div>
</div></div></section>

<section id="security" class="foundry-section security-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">04 / TRUST BOUNDARY</div>
  <div class="shead split-head" data-reveal="up"><span class="eyebrow">${uiIcon('shield', 'eyebrow-icon')} Security &amp; trust</span>
    <h2>Engineered like you will audit it.<br><span>Because you will.</span></h2>
    <p>Industrial buyers audit before they buy. SIAS is built and operated for that scrutiny.</p>
  </div>
  <ul class="seclist">
    <li data-reveal="up">${uiIcon('shield', 'security-icon')}<span><b>Dedicated isolated instance</b> per customer &mdash; your data never shares a database, auth realm or edge service with anyone else&rsquo;s.</span><em class="mono">ISOLATED</em></li>
    <li data-reveal="up">${uiIcon('lock', 'security-icon')}<span><b>Enforced service authentication</b> &mdash; identity-token verification is required on every backend service, not optional.</span><em class="mono">ENFORCED</em></li>
    <li data-reveal="up">${uiIcon('network', 'security-icon')}<span><b>MFA + SCIM 2.0 provisioning</b> &mdash; plug in Okta or Microsoft Entra; joiners and leavers sync automatically.</span><em class="mono">IDENTITY</em></li>
    <li data-reveal="up">${uiIcon('chip', 'security-icon')}<span><b>Daily encrypted snapshots</b> to object storage with a 365-day alert retention policy you control.</span><em class="mono">RECOVERABLE</em></li>
    <li data-reveal="up">${uiIcon('shield', 'security-icon')}<span><b>PII separated and access-scoped</b> &mdash; personal data lives apart from operational data with strict role rules.</span><em class="mono">SCOPED</em></li>
    <li data-reveal="up">${uiIcon('check', 'security-icon')}<span><b>Independent security review</b> &mdash; externally scanned and fully remediated (July 2026). Whitepaper on request.</span><em class="mono">REVIEWED</em></li>
  </ul>
</div></section>

<section id="how" class="foundry-section process-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">05 / DEPLOYMENT SEQUENCE</div>
  <div class="shead split-head" data-reveal="up"><span class="eyebrow">${uiIcon('bolt', 'eyebrow-icon')} How buying works</span>
    <h2>From ${quote ? 'quote' : 'card'} to control room.<br><span>Four controlled steps.</span></h2>
  </div>
  <div class="steps">
    <article class="step" data-reveal="up"><div class="n">STEP 01</div><div class="step-node">${uiIcon('bank')}</div><h3>${quote ? 'Request your quote' : 'Buy &amp; tell us about your plant'}</h3><p>${quote ? 'Pick a plan, fill in five fields &mdash; your tailored quote and invoice terms land in your inbox within 1 business day.' : 'Pick a plan, fill in five fields, pay by card or request an invoice. VAT handled at checkout.'}</p></article>
    <article class="step" data-reveal="up"><div class="n">STEP 02</div><div class="step-node">${uiIcon('chip')}</div><h3>We provision your instance</h3><p>A dedicated, isolated SIAS deployment &mdash; database, auth, edge services &mdash; spun up for your company within 1 business day.</p></article>
    <article class="step" data-reveal="up"><div class="n">STEP 03</div><div class="step-node">${uiIcon('lock')}</div><h3>Claim your Owner console</h3><p>You receive a one-time activation link (never a password). Set your password + MFA and the instance is yours.</p></article>
    <article class="step" data-reveal="up"><div class="n">STEP 04</div><div class="step-node">${uiIcon('brain')}</div><h3>Kubix onboards your team</h3><p>Your copilot introduces itself, invites your Production Managers, and wires your first integration with you.</p></article>
  </div>
</div></section>

<section id="pricing" class="foundry-section pricing-section"><div class="wrap">
  <div class="section-index mono" aria-hidden="true">06 / INSTANCE CONFIGURATION</div>
  <div class="shead pricing-head" data-reveal="up"><span class="eyebrow">${uiIcon('chip', 'eyebrow-icon')} Pricing</span>
    <h2>One instance. One price.<br><span>Everything included.</span></h2>
    <div class="toggle" role="tablist">
      <button type="button" id="bt-monthly">Monthly</button>
      <button type="button" id="bt-annual" class="on">Annual <span class="save">&nbsp;save 17%</span></button>
    </div>
  </div>
  <div class="plans">
    <article class="plan" data-reveal="up">
      <div class="plan-code mono">CFG / S01</div><h3>Starter</h3><div class="tag">One plant, the full platform</div>
      <div class="price" data-monthly="$590" data-annual="$490">$490<small>/mo</small></div>
      <div class="bill" data-monthly="billed monthly &middot; cancel anytime" data-annual="$5,880 billed annually">$5,880 billed annually</div>
      <ul>
        <li>${uiIcon('check', 'list-check')}1 factory &middot; up to 10 supervisor seats</li>
        <li>${uiIcon('check', 'list-check')}Dedicated isolated instance</li>
        <li>${uiIcon('check', 'list-check')}Real-time alerts + AI dispatch &amp; escalations</li>
        <li>${uiIcon('check', 'list-check')}Voice claiming from the lock screen</li>
        <li>${uiIcon('check', 'list-check')}Kubix Copilot included</li>
        <li>${uiIcon('check', 'list-check')}Email support</li>
      </ul>
      <a class="btn btn-ghost buylink" data-plan="starter" href="/buy?plan=starter&billing=annual">${buyCta || 'Choose Starter'} ${uiIcon('arrow', 'btn-icon')}</a>
    </article>
    <article class="plan hot" data-tilt data-reveal="up">
      <div class="pop"><span class="live-pip"></span> Recommended configuration</div>
      <div class="plan-code mono">CFG / G03</div><h3>Growth</h3><div class="tag">Multi-site operations on autopilot</div>
      <div class="price" data-monthly="$1,190" data-annual="$990">$990<small>/mo</small></div>
      <div class="bill" data-monthly="billed monthly &middot; cancel anytime" data-annual="$11,880 billed annually">$11,880 billed annually</div>
      <ul>
        <li>${uiIcon('check', 'list-check')}Up to 3 factories &middot; 30 supervisor seats</li>
        <li>${uiIcon('check', 'list-check')}Everything in Starter</li>
        <li>${uiIcon('check', 'list-check')}SCADA / PLC / MQTT / historian connectors</li>
        <li>${uiIcon('check', 'list-check')}AI failure forecaster + morning briefings</li>
        <li>${uiIcon('check', 'list-check')}AI shift commander + handovers</li>
        <li>${uiIcon('check', 'list-check')}Priority support</li>
      </ul>
      <a class="btn btn-amber buylink" data-magnetic data-plan="growth" href="/buy?plan=growth&billing=annual">${buyCta || 'Choose Growth'} ${uiIcon('arrow', 'btn-icon')}</a>
    </article>
    <article class="plan" data-reveal="up">
      <div class="plan-code mono">CFG / ENT</div><h3>Enterprise</h3><div class="tag">For groups and regulated estates</div>
      <div class="price">Custom</div>
      <div class="bill">annual contract &middot; procurement-friendly</div>
      <ul>
        <li>${uiIcon('check', 'list-check')}Unlimited factories &amp; seats</li>
        <li>${uiIcon('check', 'list-check')}SCIM / SSO (Okta, Entra)</li>
        <li>${uiIcon('check', 'list-check')}99.9% uptime SLA + status page</li>
        <li>${uiIcon('check', 'list-check')}Dedicated onboarding engineer</li>
        <li>${uiIcon('check', 'list-check')}Security review &amp; RFP support</li>
        <li>${uiIcon('check', 'list-check')}Custom data residency options</li>
      </ul>
      <a class="btn btn-ghost" href="mailto:${mail}?subject=SIAS%20Enterprise%20inquiry">Talk to sales ${uiIcon('arrow', 'btn-icon')}</a>
    </article>
  </div>
  <p class="dim pricing-note">${quote
    ? 'List prices in USD, excl. taxes. We invoice by bank transfer in USD, TND or EUR on net-15 terms &mdash; request a quote and it lands in your inbox within 1 business day. Every plan runs on its own dedicated instance with a 30-day money-back guarantee on your first payment.'
    : 'Prices in USD, excl. VAT (collected at checkout where applicable). Tunisian companies can pay in TND by local card via ClicToPay (annual billing). Every plan runs on its own dedicated instance &mdash; 30-day money-back guarantee on your first payment.'}</p>
</div></section>

<section id="faq" class="foundry-section faq-section"><div class="wrap faq-wrap">
  <div class="section-index mono" aria-hidden="true">07 / FIELD NOTES</div>
  <div class="shead split-head" data-reveal="up"><span class="eyebrow">${uiIcon('pulse', 'eyebrow-icon')} FAQ</span><h2>Questions factories ask us.</h2></div>
  <details><summary>How fast can we go live?</summary><div class="a">Your dedicated instance is provisioned within 1 business day of purchase. Most plants have supervisors claiming real alerts the same week, including their first SCADA or MQTT connector &mdash; your Kubix Copilot drives that timeline with you.</div></details>
  <details><summary>Do you have access to our production data?</summary><div class="a">Your instance is isolated per customer &mdash; separate database, auth realm and edge services. KubixDesiney operates the infrastructure (updates, backups, monitoring) but your operational data is yours: export it anytime, and alert retention policy is under your control.</div></details>
  <details><summary>What hardware do we need?</summary><div class="a">None to start &mdash; supervisors use their phones and alerts can be raised manually or from your existing SCADA/PLC/historian systems. Optional ESP32/Arduino edge kits can be bound to machines through the built-in hardware lab.</div></details>
  <details><summary>Can our teams use it in French?</summary><div class="a">Yes &mdash; the entire product is bilingual English/French with instant runtime switching, down to notifications and PDF reports.</div></details>
  <details><summary>Does the AI take actions on our machines?</summary><div class="a">Never. SIAS observes and orchestrates people &mdash; it reads from your estate (OPC-UA, Modbus, MQTT, historians) and never writes to control loops. AI decisions are logged with reasons and confidence, and every autonomous capability has an off switch in your console.</div></details>
  <details><summary>What happens if we outgrow our plan?</summary><div class="a">Upgrade in place &mdash; same instance, higher limits, prorated by Stripe. Moving to Enterprise adds SSO/SCIM, an SLA and a dedicated onboarding engineer without migration.</div></details>
  ${quote
    ? `<details><summary>How does invoicing work?</summary><div class="a">Request a quote and it lands in your inbox within 1 business day. We invoice by bank transfer in USD, TND or EUR on net-15 payment terms &mdash; monthly or annual billing, procurement-friendly paperwork, and your instance is provisioned as soon as the order is confirmed.</div></details>`
    : `<details><summary>How can we pay from Tunisia?</summary><div class="a">Two rails: international cards in USD through Stripe (monthly or annual), or Tunisian CB cards in TND through ClicToPay, the national gateway operated by SMT (annual billing). Pick your rail at checkout &mdash; both trigger the same instant provisioning.</div></details>`}
</div></section>

<div class="cta-band"><div class="wrap"><div class="cta-foundry" data-reveal="up">
  <div class="cta-signal" aria-hidden="true"><span></span><i></i><i></i><i></i></div>
  <span class="eyebrow">${uiIcon('alert', 'eyebrow-icon')} Next signal</span>
  <h2>Your plant&rsquo;s next alert could be<br><span>the last one nobody caught.</span></h2>
  <p class="mut" style="margin:16px auto 30px;max-width:36em">${quote
    ? 'Request your quote today, sign this week, and let Kubix walk your team in.'
    : 'Buy today, get your activation email tomorrow, and let Kubix walk your team in.'}</p>
  <a class="btn btn-amber" data-magnetic href="/buy?plan=growth&billing=annual">${quote ? 'Get a quote' : 'Get SIAS now'} ${uiIcon('arrow', 'btn-icon')}</a>
</div></div></div>
</main>

<footer class="site-footer"><div class="wrap">
  <a class="logo footer-logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <span><a href="#pricing">Pricing</a> &middot; <a href="/copilot">Kubix Copilot</a> &middot; <a href="#security">Security</a>${legalPublishEnabled(env) ? ' &middot; <a href="/legal/privacy">Privacy</a> &middot; <a href="/legal/terms">Terms</a>' : ''} &middot; <a href="mailto:${mail}">${mail}</a></span>
  <span class="mono">&copy; 2026 KUBIXDESINEY / ALL SYSTEMS RESERVED</span>
</div></footer>

<script>
(function () {
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
  document.getElementById('bt-monthly').addEventListener('click', function () { setBilling('monthly'); });
  document.getElementById('bt-annual').addEventListener('click', function () { setBilling('annual'); });
})();
</script>`;
}

function buyBody(plan, billing, env, mode = 'card') {
  const mail = salesEmail(env);
  const quote = mode === 'quote';
  const catalogLite = {};
  for (const [k, v] of Object.entries(PLAN_CATALOG)) {
    catalogLite[k] = { name: v.name, monthly: v.monthly, annual: v.annual, tndAnnual: v.tndAnnual, tndMonthly: v.tndMonthly, factories: v.factories, seats: v.seats };
  }
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <nav class="navlinks"><a href="/#pricing">&larr; Back to pricing</a></nav>
</div></header>

<main class="wrap buywrap">
  <div id="intake-col">
    <span class="eyebrow">${quote ? 'Request a quote' : 'Secure checkout'}</span>
    <h2 style="margin:16px 0 8px">Tell us about your plant</h2>
    <p class="mut" style="margin-bottom:28px">${quote
      ? 'A few fields. This names your instance, your Kubix Copilot &mdash; and the tailored quote that lands in your inbox within 1 business day.'
      : 'Five fields. This is what names your instance, your Kubix Copilot, and your activation email.'}</p>
    <form id="intake">
      <div class="formgrid">
        <div class="field"><label for="f-name">Full name</label><input id="f-name" name="name" required maxlength="80" placeholder="Amine Ben Salah" autocomplete="name"></div>
        <div class="field"><label for="f-email">Work email</label><input id="f-email" name="email" type="email" required maxlength="120" placeholder="a.bensalah@company.com" autocomplete="email"></div>
        <div class="field"><label for="f-company">Company</label><input id="f-company" name="company" required maxlength="80" placeholder="Nagati Steel Works" autocomplete="organization"></div>
        <div class="field"><label for="f-country">Country</label><input id="f-country" name="country" maxlength="56" placeholder="Tunisia" autocomplete="country-name"></div>${quote ? `
        <div class="field"><label for="f-phone">Phone <span class="dim">(optional)</span></label><input id="f-phone" name="phone" maxlength="32" placeholder="+216 12 345 678" autocomplete="tel"></div>
        <div class="field"><label for="f-currency">Preferred quote currency</label>
          <select id="f-currency" name="currency">
            <option value="USD">USD &middot; US Dollar</option><option value="TND">TND &middot; Tunisian Dinar</option><option value="EUR">EUR &middot; Euro</option>
          </select></div>` : ''}
        <div class="field"><label for="f-pm-name">Production Manager name</label><input id="f-pm-name" name="pmName" required maxlength="80" placeholder="Sonia Trabelsi" autocomplete="name"></div>
        <div class="field"><label for="f-pm-email">Production Manager email</label><input id="f-pm-email" name="pmEmail" type="email" required maxlength="120" placeholder="production@company.com" autocomplete="email"></div>
        <div class="field"><label for="f-supervisor-name">Supervisor name</label><input id="f-supervisor-name" name="supervisorName" required maxlength="80" placeholder="Karim Aloui" autocomplete="name"></div>
        <div class="field"><label for="f-supervisor-email">Supervisor email</label><input id="f-supervisor-email" name="supervisorEmail" type="email" required maxlength="120" placeholder="supervisor@company.com" autocomplete="email"></div>
        <div class="field"><label for="f-payment-method">Expected payment method</label>
          <select id="f-payment-method" name="paymentMethod">
            <option value="bank_transfer">Virement / bank transfer</option>
            <option value="manual">Other manual payment</option>
          </select></div>
        <div class="field"><label for="f-factories">Number of factories</label>
          <select id="f-factories" name="factories">
            <option value="1">1</option><option value="2-3">2&ndash;3</option><option value="4-10">4&ndash;10</option><option value="10+">More than 10</option>
          </select></div>
        <div class="field"><label for="f-notes">Anything we should know? <span class="dim">(optional)</span></label><input id="f-notes" name="notes" maxlength="200" placeholder="Existing SCADA, timeline, constraints..."></div>
      </div>
      <div class="err" id="err" role="alert" aria-live="polite"></div>
      <button class="btn btn-amber" type="submit" id="paybtn" style="margin-top:26px;width:100%">${quote ? 'Request my quote &rarr;' : 'Continue to secure checkout &rarr;'}</button>
      <p class="dim" style="font-size:12.5px;margin-top:14px;text-align:center">${quote
        ? 'No card needed. We invoice by bank transfer in USD, TND or EUR on net-15 terms. Questions first? <a href="mailto:' + mail + '?subject=SIAS%20quote%20question">Email us</a>.'
        : 'Payments handled by Stripe (international) or ClicToPay / SMT (Tunisia) &mdash; card details never touch our servers. Prefer an invoice? <a href="mailto:' + mail + '?subject=SIAS%20invoice%20request">Email us</a>.'}</p>
    </form>
    <div class="card okquote" id="quote-ok" hidden style="text-align:center;padding:38px 30px;margin-top:6px">
      <div class="success-glyph">${uiIcon('check')}</div>
      <h3 style="margin:14px 0 8px">Order under review</h3>
      <p class="mut" id="qk-line" style="max-width:34em;margin:0 auto 24px">Your SIAS tenant code is reserved. We will email you when the order is confirmed.</p>
      <a class="btn btn-amber" id="qk-chat" href="/copilot">Chat with Kubix while you wait &rarr;</a>
    </div>
  </div>

  <div class="card sumcard">
    <h3 id="sum-plan">Growth</h3>
    <p class="dim" id="sum-tag" style="font-size:13px;margin-top:2px"></p>${quote ? '' : `
    <div class="radio2" style="margin-top:16px">
      <label><input type="radio" name="method" value="stripe"><span>${uiIcon('globe', 'radio-icon')} International card &middot; USD</span></label>
      <label><input type="radio" name="method" value="clictopay"><span>${uiIcon('bank', 'radio-icon')} Carte tunisienne &middot; TND</span></label>
    </div>`}
    <p class="dim" id="method-note" style="font-size:12px;margin:${quote ? '14px' : '2px'} 0 4px"></p>
    <div class="radio2">
      <label id="lbl-monthly"><input type="radio" name="billing" value="monthly"><span>Monthly</span></label>
      <label><input type="radio" name="billing" value="annual"><span>Annual &middot; save 17%</span></label>
    </div>
    <div class="sumline"><span>Dedicated isolated instance</span><span>included</span></div>
    <div class="sumline"><span>Kubix Copilot</span><span>included</span></div>
    <div class="sumline"><span id="sum-scope"></span><span>&nbsp;</span></div>
    <div class="sumline total"><span id="sum-cycle">${quote ? 'Indicative price' : 'Due today'}</span><span id="sum-price"></span></div>
    <p class="dim" style="font-size:12.5px;margin-top:14px">${quote
      ? 'List price before your tailored quote &mdash; final pricing may reflect onboarding scope, multi-year terms and local taxes. Invoiced, never charged automatically.'
      : 'Then your instance is provisioned within 1 business day and your activation email lands in your inbox. 30-day money-back guarantee.'}</p>
  </div>
</main>

<script>
var CATALOG = ${JSON.stringify(catalogLite)};
var MODE = '${mode}';
var SUBMIT_LABEL = ${JSON.stringify(quote ? 'Request my quote →' : 'Continue to secure checkout →')};
var SUBMIT_BUSY = ${JSON.stringify(quote ? 'Sending your request…' : 'Preparing secure checkout…')};
var state = { plan: '${plan}', billing: '${billing}', method: 'stripe', currency: 'USD' };
function fmt(cents) { return '$' + (cents / 100).toLocaleString('en-US', { maximumFractionDigits: 0 }); }
function fmtTnd(d) { return d.toLocaleString('en-US') + ' TND'; }
function render() {
  var p = CATALOG[state.plan];
  var isQuote = MODE === 'quote';
  var ctp = !isQuote && state.method === 'clictopay';
  if (ctp) state.billing = 'annual';
  document.getElementById('sum-plan').textContent = 'SIAS ' + p.name;
  document.getElementById('sum-tag').textContent = p.factories + ' \\u00b7 ' + p.seats;
  document.getElementById('sum-scope').textContent = p.factories + ', ' + p.seats.toLowerCase();
  var isAnnual = state.billing === 'annual';
  if (isQuote) {
    document.getElementById('sum-cycle').textContent = 'Indicative price' + (isAnnual ? ' (12 months)' : ' (per month)');
    document.getElementById('sum-price').textContent =
      state.currency === 'TND' ? fmtTnd(isAnnual ? p.tndAnnual : p.tndMonthly)
      : state.currency === 'EUR' ? 'Quoted in EUR'
      : fmt(isAnnual ? p.annual : p.monthly);
    document.getElementById('method-note').textContent =
      'Invoice billing \\u00b7 bank transfer \\u00b7 net-15 \\u2014 quoted in ' + state.currency + '.';
  } else {
    document.getElementById('sum-cycle').textContent = isAnnual ? 'Due today (12 months)' : 'Due today (first month)';
    document.getElementById('sum-price').textContent = ctp ? fmtTnd(p.tndAnnual) : (isAnnual ? fmt(p.annual) : fmt(p.monthly));
    document.getElementById('method-note').textContent = ctp
      ? 'Tunisian CB cards via ClicToPay (SMT) \\u2014 charged in TND, annual billing only.'
      : 'Cards worldwide via Stripe \\u2014 monthly or annual, VAT handled at checkout.';
  }
  var mLbl = document.getElementById('lbl-monthly');
  mLbl.style.opacity = ctp ? '.4' : '1';
  mLbl.style.pointerEvents = ctp ? 'none' : 'auto';
  document.querySelectorAll('input[name="billing"]').forEach(function (r) { r.checked = r.value === state.billing; });${quote ? '' : `
  document.querySelectorAll('input[name="method"]').forEach(function (r) { r.checked = r.value === state.method; });`}
}
function submitIntake(ev) {
  ev.preventDefault();
  // Manual-approval sales: every submission is an ORDER (no card rails).
  // -> POST /api/order, which records the order in Supabase and fires the
  //    'order received + payment instructions' email via n8n WF5. The founder
  //    then uses Accept or Paid in the /admin Orders dashboard.
  var btn = document.getElementById('paybtn');
  var err = document.getElementById('err');
  err.style.display = 'none';
  btn.disabled = true;
  btn.classList.add('is-loading');
  btn.setAttribute('aria-busy', 'true');
  btn.textContent = SUBMIT_BUSY;
  var body = {
    name: document.getElementById('f-name').value,
    email: document.getElementById('f-email').value,
    company: document.getElementById('f-company').value,
    country: document.getElementById('f-country').value,
    factories: document.getElementById('f-factories').value,
    notes: document.getElementById('f-notes').value,
    plan: state.plan,
    billing: state.billing,
    phone: (document.getElementById('f-phone') || {}).value || '',
    currency: state.currency || 'USD',
    pmName: document.getElementById('f-pm-name').value,
    pmEmail: document.getElementById('f-pm-email').value,
    supervisorName: document.getElementById('f-supervisor-name').value,
    supervisorEmail: document.getElementById('f-supervisor-email').value,
    paymentMethod: document.getElementById('f-payment-method').value,
  };
  fetch('/api/order', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (d.ok) {
        document.getElementById('intake').hidden = true;
        var ok = document.getElementById('quote-ok');
        ok.hidden = false;
        if (d.warning) window.alert(d.warning);
        if (d.tenantCode) {
          document.getElementById('qk-line').textContent =
            'Order received — your instance ' + d.tenantCode + ' is reserved and under review. We will contact you as soon as it is accepted.';
          var chat = document.getElementById('qk-chat');
          chat.href = '/copilot?tenant=' + encodeURIComponent(d.tenantCode) +
            '&company=' + encodeURIComponent(body.company) + '&name=' + encodeURIComponent(body.name) + '&plan=' + encodeURIComponent(body.plan);
        }
        ok.scrollIntoView({
          behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
          block: 'center'
        });
        return;
      }
      throw new Error(d.error || 'Something went wrong.');
    })
    .catch(function (e) {
      err.textContent = e.message;
      err.style.display = 'block';
      btn.disabled = false;
      btn.classList.remove('is-loading');
      btn.removeAttribute('aria-busy');
      btn.textContent = SUBMIT_LABEL;
    });
  return false;
}
document.getElementById('intake').addEventListener('submit', submitIntake);
document.querySelectorAll('input[name="billing"]').forEach(function (r) {
  r.addEventListener('change', function () { state.billing = r.value; render(); });
});${quote ? `
var curSel = document.getElementById('f-currency');
curSel.addEventListener('change', function () { state.currency = curSel.value; render(); });` : `
document.querySelectorAll('input[name="method"]').forEach(function (r) {
  r.addEventListener('change', function () { state.method = r.value; render(); });
});`}
render();
</script>`;
}

function successBody(env) {
  const mail = salesEmail(env);
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
</div></header>

<main class="okpage">
  <div class="big">${uiIcon('check')}</div>
  <span class="eyebrow">Payment confirmed</span>
  <h2 style="margin:18px 0 10px">Welcome aboard.</h2>
  <p class="mut" id="ok-line">Your dedicated SIAS instance is being provisioned.</p>
  <div class="nextsteps">
    <div class="card"><div class="n">1</div><div><b>Your Stripe receipt</b><br><span class="mut" style="font-size:14px">Already on its way to your inbox.</span></div></div>
    <div class="card"><div class="n">2</div><div><b>Two activation emails &mdash; within 1 business day</b><br><span class="mut" style="font-size:14px">You receive separate one-time links for the Production Manager and Supervisor accounts. You set each password and MFA; we never send passwords by email.</span></div></div>
    <div class="card"><div class="n">3</div><div><b>Kubix Copilot introduces itself</b><br><span class="mut" style="font-size:14px" id="ok-kubix">Your named AI engineer will guide activation, team invites and your first integration.</span></div></div>
  </div>
  <a class="btn btn-amber" id="ok-chat" style="display:none;margin-top:30px" href="/copilot">Chat with Kubix now &rarr;</a>
  <p style="margin-top:26px"><a class="btn btn-ghost" href="/welcome">See what happens next &rarr;</a></p>
  <p class="dim" style="margin-top:22px;font-size:13.5px">Nothing after a day? Check spam, or write to <a href="mailto:${mail}">${mail}</a> &mdash; a human answers.</p>
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

function welcomePage(env) {
  return page(
    'Welcome to SIAS \u2014 what happens next',
    'Your step-by-step path from purchase to a live plant floor: activation, first 30 minutes, first integration, and your Kubix Copilot.',
    welcomeBody(env),
  );
}

function welcomeBody(env) {
  const mail = salesEmail(env);
  return `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <nav class="navlinks"><a href="/copilot">Kubix Copilot</a><a class="btn btn-amber btn-sm" href="/#pricing">Pricing</a></nav>
</div></header>

<main>
<section><div class="wrap" style="max-width:860px">
  <span class="eyebrow">Welcome aboard</span>
  <h1 style="margin-top:16px">What happens after you buy</h1>
  <p class="lead" style="margin-top:14px">Four milestones stand between your order and supervisors claiming real alerts. Here is exactly what each one looks like &mdash; and what we need from you (very little).</p>

  <div class="steps" style="margin-top:40px;grid-template-columns:1fr">
    <div class="card step">
      <div class="n">MILESTONE 01 &middot; within 1 business day</div>
      <h3>Your activation email arrives</h3>
      <p>We provision your dedicated instance &mdash; isolated database, auth realm and edge services &mdash; and email your Owner a <b>one-time activation link</b> (never a password; it expires in about an hour, and we resend on request). Click it, set your password and MFA, and the console is yours.</p>
      <p class="dim" style="margin-top:10px;font-size:13px">Checklist: pick who your Owner is before the email lands &middot; add our address to your allowlist so it never hits spam.</p>
    </div>
    <div class="card step">
      <div class="n">MILESTONE 02 &middot; your first 30 minutes</div>
      <h3>Set up the console</h3>
      <p>From your SuperAdmin console: create your factory hierarchy (plants &rarr; lines &rarr; stations), define your alert types (or keep the standard set), and provision your Production Manager accounts. Supervisors install the mobile app and sign in &mdash; voice enrollment takes each of them under two minutes.</p>
      <p class="dim" style="margin-top:10px;font-size:13px">Checklist: factory map &middot; alert types &middot; PM accounts &middot; supervisor phones enrolled.</p>
    </div>
    <div class="card step">
      <div class="n">MILESTONE 03 &middot; same week</div>
      <h3>Wire your first integration</h3>
      <p>Open Infrastructure &rarr; Connectors and pick your protocol &mdash; OPC-UA, Modbus, MQTT, REST, PI or Ignition. The console generates a ready-to-run gateway snippet with your ingest key baked in, and the <b>Verify link test</b> confirms the handshake live. No hardware? Raise alerts manually or from the mobile app on day one.</p>
      <p class="dim" style="margin-top:10px;font-size:13px">Checklist: one connector verified &middot; first SCADA-raised alert claimed on a phone.</p>
    </div>
    <div class="card step">
      <div class="n">MILESTONE 04 &middot; continuous</div>
      <h3>Meet your Kubix Copilot</h3>
      <p>Kubix already knows your tenant code, plan and integration stack. It walks your team through everything above in English or French, answers the 2am questions, and loops in a human engineer when it should. Once you have a few weeks of alert history, it will nudge you to train the failure forecaster on your own data.</p>
      <a class="btn btn-amber" style="margin-top:16px" href="/copilot">Chat with Kubix &rarr;</a>
    </div>
  </div>

  <p class="dim" style="margin-top:34px;font-size:13.5px">Stuck at any step? Write to <a href="mailto:${mail}">${mail}</a> &mdash; a human answers.</p>
</div></section>
</main>

<footer><div class="wrap">
  <span><b style="color:var(--ink2)">SIAS</b> &mdash; Smart Industrial Alert System &middot; by KubixDesiney</span>
  <span><a href="/#pricing">Pricing</a> &middot; <a href="/copilot">Kubix Copilot</a> &middot; <a href="mailto:${mail}">${mail}</a></span>
  <span>&copy; 2026 KubixDesiney. All rights reserved.</span>
</div></footer>`;
}

// Copilot page chrome i18n \u2014 Kubix itself already answers in the user's
// language; this dictionary only localizes the page shell. Deliberately a tiny
// inline map, not a framework.
export const COPILOT_I18N = Object.freeze({
  en: Object.freeze({
    title: 'Kubix Copilot \u2014 SIAS',
    desc: 'Chat with your dedicated SIAS engineer: activation, integrations, anything.',
    name: 'Kubix Copilot',
    sub: 'Your dedicated SIAS engineer',
    home: '\u2190 Home',
    placeholder: 'Ask Kubix anything about your SIAS instance\u2026',
    send: 'Send',
    escalated: 'A human engineer has been looped in and will follow up by email.',
    unreachable: 'Kubix is unreachable right now. Please try again shortly.',
    generic: 'Something went wrong. Please try again.',
    thumbUp: 'Helpful',
    thumbDown: 'Not helpful',
    thanks: 'Thanks \u2014 noted.',
  }),
  fr: Object.freeze({
    title: 'Kubix Copilot \u2014 SIAS',
    desc: 'Discutez avec votre ing\u00e9nieur SIAS d\u00e9di\u00e9 : activation, int\u00e9grations, tout.',
    name: 'Kubix Copilot',
    sub: 'Votre ing\u00e9nieur SIAS d\u00e9di\u00e9',
    home: '\u2190 Accueil',
    placeholder: 'Posez \u00e0 Kubix toute question sur votre instance SIAS\u2026',
    send: 'Envoyer',
    escalated: 'Un ing\u00e9nieur humain a \u00e9t\u00e9 sollicit\u00e9 et vous r\u00e9pondra par e-mail.',
    unreachable: 'Kubix est injoignable pour le moment. Veuillez r\u00e9essayer sous peu.',
    generic: 'Une erreur est survenue. Veuillez r\u00e9essayer.',
    thumbUp: 'Utile',
    thumbDown: 'Pas utile',
    thanks: 'Merci \u2014 not\u00e9.',
  }),
});

export function copilotLang(url) {
  try {
    return url && url.searchParams.get('lang') === 'fr' ? 'fr' : 'en';
  } catch {
    return 'en';
  }
}

function copilotPage(url) {
  const dict = COPILOT_I18N[copilotLang(url)];
  return page(dict.title, dict.desc, copilotBody(dict));
}

function copilotBody(dict) {
  return `
<div class="kx-app">
  <div class="kx-header">
    <div class="kx-avatar" aria-hidden="true">${uiIcon('brain')}</div>
    <div class="kx-header-text">
      <div class="kx-header-name"><span id="kx-agent-name">${dict.name}</span><span class="kx-online-dot"></span></div>
      <div class="kx-header-sub">${dict.sub}</div>
    </div>
    <a class="kx-back" href="/">${dict.home}</a>
  </div>
  <div class="kx-messages" id="kx-messages"></div>
  <form class="kx-input-bar" id="kx-form">
    <textarea class="kx-input" id="kx-input" rows="1" placeholder="${dict.placeholder}"></textarea>
    <button class="kx-send" id="kx-send" type="submit">${dict.send}</button>
  </form>
</div>
<script>var KX_I18N = ${JSON.stringify(dict)};${COPILOT_CLIENT_JS}</script>`;
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

  function sendFeedback(index, verdict, bar) {
    // Optimistic: the verdict is the user's sentiment — persist it locally and
    // show the thanks state even if the forward is briefly unreachable.
    var m = state.transcript[index];
    if (m) { m.verdict = verdict; saveState(); }
    markFeedback(bar, verdict);
    fetch('/api/kubix-feedback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: state.sessionId, messageIndex: index, verdict: verdict }),
    }).catch(function () {});
  }

  function markFeedback(bar, verdict) {
    bar.className = 'kx-feedback kx-fb-done';
    bar.querySelectorAll('button').forEach(function (b) {
      b.disabled = true;
      b.className = b.getAttribute('data-verdict') === verdict ? 'on' : '';
    });
    var thanks = bar.querySelector('.kx-fb-thanks');
    if (thanks) thanks.textContent = KX_I18N.thanks;
  }

  function feedbackBar(index, verdict) {
    var bar = document.createElement('div');
    bar.className = 'kx-feedback';
    ['up', 'down'].forEach(function (v) {
      var b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('data-verdict', v);
      b.title = v === 'up' ? KX_I18N.thumbUp : KX_I18N.thumbDown;
      b.textContent = v === 'up' ? '\\uD83D\\uDC4D' : '\\uD83D\\uDC4E';
      b.addEventListener('click', function () { sendFeedback(index, v, bar); });
      bar.appendChild(b);
    });
    var thanks = document.createElement('span');
    thanks.className = 'kx-fb-thanks';
    bar.appendChild(thanks);
    if (verdict) markFeedback(bar, verdict);
    return bar;
  }

  function addBubble(role, html, opts) {
    opts = opts || {};
    var wrap = document.createElement('div');
    wrap.className = 'kx-msg kx-msg-' + role + (opts.error ? ' kx-msg-error' : '');
    var bubble = document.createElement('div');
    bubble.className = 'kx-bubble';
    bubble.innerHTML = html;
    wrap.appendChild(bubble);
    if (role === 'bot' && !opts.error && typeof opts.index === 'number') {
      wrap.appendChild(feedbackBar(opts.index, opts.verdict));
    }
    els.messages.appendChild(wrap);
    if (opts.escalated) {
      var banner = document.createElement('div');
      banner.className = 'kx-escalated-banner';
      banner.textContent = KX_I18N.escalated;
      els.messages.appendChild(banner);
    }
    els.messages.scrollTop = els.messages.scrollHeight;
    return wrap;
  }

  function renderTranscript() {
    els.messages.innerHTML = '';
    state.transcript.forEach(function (m, i) {
      addBubble(m.role, m.role === 'bot' ? renderMarkdown(m.text) : '<p>' + escapeHtml(m.text) + '</p>', {
        escalated: m.escalated,
        error: m.error,
        index: m.role === 'bot' && !m.error ? i : undefined,
        verdict: m.verdict,
      });
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
        var msg = (r.data && r.data.error) || KX_I18N.generic;
        addBubble('bot', '<p>' + escapeHtml(msg) + '</p>', { error: true });
        state.transcript.push({ role: 'bot', text: msg, error: true });
        saveState();
        return;
      }
      state.transcript.push({ role: 'bot', text: r.data.reply || '', escalated: !!r.data.escalated });
      saveState();
      addBubble('bot', renderMarkdown(r.data.reply || ''), { escalated: !!r.data.escalated, index: state.transcript.length - 1 });
    }).catch(function () {
      hideTyping();
      addBubble('bot', '<p>' + escapeHtml(KX_I18N.unreachable) + '</p>', { error: true });
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

function adminLoginPage() {
  return page(
    'Orders Dashboard — SIAS',
    'Founder orders dashboard for SIAS',
    `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
</div></header>
<main class="wrap" style="max-width:420px;padding:120px 24px">
  <div class="card" style="padding:40px 32px">
    <h1 style="font-size:24px;margin-bottom:8px">Orders Dashboard</h1>
    <p style="color:var(--ink3);margin-bottom:32px;font-size:15px">Enter your password to manage orders</p>
    <form id="loginForm" style="display:flex;flex-direction:column;gap:16px">
      <div class="field">
        <label>Password</label>
        <input type="password" name="password" required placeholder="Enter password" style="font-size:16px">
      </div>
      <button type="submit" class="btn btn-amber" style="width:100%;margin-top:12px">Sign In</button>
    </form>
    <div id="error" class="err" style="margin-top:16px"></div>
  </div>
</main>
<script>
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const password = new FormData(e.target).get('password');
  const res = await fetch('/admin', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password }) });
  const data = await res.json();
  if (data.ok) {
    window.location.href = '/admin';
  } else {
    document.getElementById('error').textContent = data.error || 'Login failed';
    document.getElementById('error').style.display = 'block';
  }
});
</script>
    `,
  );
}

function ordersDashboard(orders, env, origin) {
  const statusLabel = {
    awaiting_payment: 'Legacy review',
    under_review: 'Under review',
    confirmed: 'Confirmed',
    provisioning_queued: 'Queued',
    provisioning: 'Provisioning',
    active: 'Active',
    provisioning_failed: 'Needs retry',
    rejected: 'Rejected',
  };

  const actionButtons = (order) => {
    const id = escapeHtml(order.id);
    if (order.status === 'under_review' || order.status === 'awaiting_payment') {
      return `
        <button class="btn btn-sm btn-ghost" data-order-action="accept" data-order-id="${id}">Accept</button>
        <button class="btn btn-sm btn-amber" data-order-action="paid" data-order-id="${id}">Paid</button>`;
    }
    if (order.status === 'confirmed') {
      return `
        <button class="btn btn-sm btn-ghost" data-order-action="accept" data-order-id="${id}">Resend email</button>
        <button class="btn btn-sm btn-amber" data-order-action="paid" data-order-id="${id}">Paid</button>`;
    }
    if (order.status === 'provisioning_failed') {
      return `<button class="btn btn-sm btn-amber" data-order-action="paid" data-order-id="${id}">Retry provisioning</button>`;
    }
    return '<span class="dim">—</span>';
  };

  const renderOrder = (order) => {
    const price = PLAN_CATALOG[order.plan];
    const amountDisplay = order.amount_display
      || (price ? `$${listPrice(order.plan, order.billing, 'USD')}` : 'custom');
    const parsedDate = new Date(order.created_at);
    const createdAt = Number.isNaN(parsedDate.getTime()) ? '—' : parsedDate.toLocaleString();
    const fullPackage = order.full_package || order.plan === 'growth';
    return `
    <tr>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:14px">
        <div style="font-weight:600;color:var(--ink)">${escapeHtml(order.company)}</div>
        <div style="font-size:12px;color:var(--ink3);margin-top:2px">${escapeHtml(order.contact_name)} • ${escapeHtml(order.email)}</div>
        <div style="font-size:11px;color:var(--ink3);margin-top:4px">PM: ${escapeHtml(order.pm_email || order.email)} · Supervisor: ${escapeHtml(order.supervisor_email || 'missing')}</div>
      </td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:14px;color:var(--ink2)">${escapeHtml(order.tenant_code)}</td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:14px;color:var(--ink2)">${escapeHtml(price?.name || order.plan)}${fullPackage ? '<div style="font-size:11px;color:var(--cyan)">Adaptive AI</div>' : ''}</td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:14px;color:var(--ink2)">${escapeHtml(amountDisplay)}</td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:13px;color:var(--ink3)">${escapeHtml(order.payment_method || 'bank_transfer')}</td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);font-size:12px">${escapeHtml(createdAt)}</td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line)">
        <span class="chip ${order.status === 'provisioning_failed' ? 'crit' : order.status === 'active' ? 'ok' : 'ai'}" style="font-size:11px;margin:0">${escapeHtml(statusLabel[order.status] || order.status)}</span>
        ${order.provisioning_error ? `<div style="max-width:220px;margin-top:5px;font-size:11px;color:var(--red)">${escapeHtml(order.provisioning_error)}</div>` : ''}
      </td>
      <td style="padding:14px 16px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap">
        ${actionButtons(order)}
      </td>
    </tr>`;
  };

  const renderSection = (title, sectionOrders, color) => sectionOrders.length ? `
    <section style="margin-bottom:36px">
      <h2 style="font-size:16px;font-weight:700;margin-bottom:16px;color:${color}">${escapeHtml(title)} (${sectionOrders.length})</h2>
      <div class="card" style="overflow-x:auto">
        <table style="width:100%;border-collapse:collapse;min-width:1050px">
          <thead><tr style="background:rgba(148,163,184,.06)">
            ${['Company & seats', 'Tenant', 'Plan', 'Amount', 'Payment', 'Created', 'Status', 'Action'].map((heading) => `<th style="padding:12px 16px;text-align:${heading === 'Action' ? 'right' : 'left'};font-size:12px;font-weight:700;color:var(--ink3);text-transform:uppercase;letter-spacing:.05em">${heading}</th>`).join('')}
          </tr></thead>
          <tbody>${sectionOrders.map(renderOrder).join('')}</tbody>
        </table>
      </div>
    </section>` : '';

  const review = orders.filter((order) => ['awaiting_payment', 'under_review'].includes(order.status));
  const confirmed = orders.filter((order) => order.status === 'confirmed');
  const provisioning = orders.filter((order) => ['provisioning_queued', 'provisioning'].includes(order.status));
  const attention = orders.filter((order) => order.status === 'provisioning_failed');
  const active = orders.filter((order) => order.status === 'active');
  const other = orders.filter((order) => ![
    'awaiting_payment', 'under_review', 'confirmed', 'provisioning_queued',
    'provisioning', 'provisioning_failed', 'active',
  ].includes(order.status));

  return page(
    'Orders Dashboard — SIAS',
    'Manage customer orders and approvals',
    `
<header class="nav"><div class="wrap">
  <a class="logo" href="/" aria-label="SIAS home">${brandLockup()}</a>
  <nav class="navlinks"><button id="logout" class="btn btn-ghost btn-sm">Logout</button></nav>
</div></header>
<main class="wrap" style="padding:80px 24px 60px">
  <div style="margin-bottom:48px">
    <h1 style="font-size:28px;margin-bottom:8px">Orders</h1>
    <p style="color:var(--ink2);font-size:15px"><strong>Accept</strong> confirms the order and emails the buyer. <strong>Paid</strong> immediately launches the dedicated SIAS instance, PM account, supervisor account, and delivery emails.</p>
  </div>

  ${renderSection('Under review', review, 'var(--amber2)')}
  ${renderSection('Confirmed — awaiting payment', confirmed, 'var(--cyan)')}
  ${renderSection('Provisioning', provisioning, 'var(--cyan)')}
  ${renderSection('Needs attention', attention, 'var(--red)')}
  ${renderSection('Active instances', active, 'var(--green)')}
  ${renderSection('Other', other, 'var(--ink3)')}
  ${orders.length === 0 ? '<div class="card" style="padding:32px;text-align:center;color:var(--ink2)">No orders yet.</div>' : ''}
</main>
<script>
async function runOrderAction(btn) {
  const action = btn.getAttribute('data-order-action');
  const orderId = btn.getAttribute('data-order-id');
  if (action === 'paid' && !window.confirm('Confirm payment and launch this buyer\\'s dedicated SIAS instance now?')) return;
  btn.disabled = true;
  const previous = btn.textContent;
  btn.textContent = action === 'paid' ? 'Launching…' : 'Sending…';
  const res = await fetch('/admin/' + action, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-SIAS-Admin-Action': '1' },
    body: JSON.stringify({ orderId: orderId })
  });
  const data = await res.json();
  if (data.ok) {
    if (data.warning) window.alert(data.warning);
    window.location.reload();
  } else {
    window.alert('Error: ' + (data.error || 'action failed'));
    btn.disabled = false;
    btn.textContent = previous;
  }
}
document.querySelectorAll('[data-order-action]').forEach(function (button) {
  button.addEventListener('click', function () { runOrderAction(button); });
});
document.getElementById('logout').addEventListener('click', async function () {
  await fetch('/admin/logout', { method: 'POST' });
  window.location.href = '/';
});
</script>
    `,
  );
}

const SHELL_CLIENT_JS = `
(function () {
  var root = document.documentElement;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var hoverFine = window.matchMedia('(hover: hover) and (pointer: fine)');
  var progress = document.querySelector('.scroll-progress span');
  var ticking = false;

  function updateProgress() {
    var doc = document.documentElement;
    var distance = Math.max(1, doc.scrollHeight - window.innerHeight);
    var value = Math.min(1, Math.max(0, window.scrollY / distance));
    if (progress) progress.style.transform = 'scaleX(' + value.toFixed(4) + ')';
    ticking = false;
  }

  window.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(updateProgress);
  }, { passive: true });
  updateProgress();

  var reveals = Array.prototype.slice.call(document.querySelectorAll('[data-reveal]'));
  reveals.forEach(function (el, index) {
    el.style.setProperty('--reveal-delay', Math.min(index % 6 * 45, 225) + 'ms');
  });

  if (!reduceMotion.matches && 'IntersectionObserver' in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -7% 0px' });
    reveals.forEach(function (el) { observer.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('is-visible'); });
  }

  function bindFocalInteractions() {
    if (reduceMotion.matches || !hoverFine.matches) return;

    document.querySelectorAll('[data-tilt]').forEach(function (el) {
      var rect = null;
      var frame = 0;
      var nextX = 0;
      var nextY = 0;
      el.addEventListener('pointerenter', function () {
        rect = el.getBoundingClientRect();
      });
      el.addEventListener('pointermove', function (event) {
        if (!rect) rect = el.getBoundingClientRect();
        nextX = (event.clientX - rect.left) / rect.width - 0.5;
        nextY = (event.clientY - rect.top) / rect.height - 0.5;
        if (frame) return;
        frame = window.requestAnimationFrame(function () {
          el.style.transform = 'perspective(1100px) rotateX(' + (-nextY * 2.4).toFixed(2) + 'deg) rotateY(' + (nextX * 3).toFixed(2) + 'deg) translateZ(0)';
          el.style.setProperty('--pointer-x', ((nextX + 0.5) * 100).toFixed(1) + '%');
          el.style.setProperty('--pointer-y', ((nextY + 0.5) * 100).toFixed(1) + '%');
          frame = 0;
        });
      });
      el.addEventListener('pointerleave', function () {
        rect = null;
        if (frame) window.cancelAnimationFrame(frame);
        frame = 0;
        el.style.transform = '';
      });
    });

    document.querySelectorAll('[data-magnetic]').forEach(function (el) {
      var rect = null;
      el.addEventListener('pointerenter', function () { rect = el.getBoundingClientRect(); });
      el.addEventListener('pointermove', function (event) {
        if (!rect) rect = el.getBoundingClientRect();
        var x = ((event.clientX - rect.left) / rect.width - 0.5) * 7;
        var y = ((event.clientY - rect.top) / rect.height - 0.5) * 5;
        el.style.transform = 'translate3d(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px,0)';
      });
      el.addEventListener('pointerleave', function () {
        rect = null;
        el.style.transform = '';
      });
    });
  }
  bindFocalInteractions();

  var stageClock = document.querySelector('.stage-time');
  if (stageClock && !reduceMotion.matches) {
    window.setInterval(function () {
      stageClock.textContent = new Date().toLocaleTimeString('en-GB', { hour12: false });
    }, 1000);
  }

  reduceMotion.addEventListener('change', function () {
    root.classList.toggle('reduce-motion', reduceMotion.matches);
    if (reduceMotion.matches) {
      document.querySelectorAll('[data-tilt],[data-magnetic]').forEach(function (el) {
        el.style.transform = '';
      });
      reveals.forEach(function (el) { el.classList.add('is-visible'); });
    }
  });
  root.classList.toggle('reduce-motion', reduceMotion.matches);
})();
`;

const BASE_CSS = `
:root{
  /* Shared with kubix-web globals.css - "Molten Amber & Steel".
     One accent (amber). Cyan is telemetry. Red is alert. Rest is steel. */
  --bg:#05070B; --bg2:#080C12; --surface:#0B1118; --surface2:#101923;
  --panel:rgba(174,199,216,.06); --panel2:rgba(174,199,216,.11);
  --line:rgba(174,199,216,.13); --line2:rgba(174,199,216,.25);
  --ink:#F1F4F2; --ink2:#B7C2C8; --ink3:#8B99A3;
  --amber:#F4B942; --amber2:#FFD36B; --cyan:#46D9E8; --red:#FF4D4D; --green:#55D98C;
  --amber-rgb:244,185,66; --cyan-rgb:70,217,232; --alert-rgb:255,77,77;
  --amber-ink:#090B0E;              /* 12.4:1 on amber - never white on amber */
  --r-xs:4px; --r-sm:6px; --r:10px; --r-lg:14px;
  --radius:2px; --max:1240px;       /* storefront keeps its sharper card edge */
  --ease-out:cubic-bezier(.16,1,.3,1); --ease-spring:cubic-bezier(.2,.9,.2,1.18);
  --nav-h:72px;
}
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth}
body{background:var(--bg);color:var(--ink);font:400 16px/1.65 'Archivo',system-ui,sans-serif;-webkit-font-smoothing:antialiased;overflow-x:hidden}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;
  background:
    radial-gradient(900px 500px at 85% -10%, rgba(56,189,248,.10), transparent 60%),
    radial-gradient(700px 420px at 0% 10%, rgba(245,158,11,.07), transparent 55%),
    repeating-linear-gradient(0deg, rgba(148,163,184,.035) 0 1px, transparent 1px 56px),
    repeating-linear-gradient(90deg, rgba(148,163,184,.035) 0 1px, transparent 1px 56px)}
main,header.nav,footer{position:relative;z-index:1}
.wrap{max-width:var(--max);margin:0 auto;padding:0 24px}
h1,h2,h3,.logo,.price{font-family:'Archivo',system-ui,sans-serif}
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
.stat .n{font-family:'IBM Plex Mono';font-size:26px;font-weight:700;color:var(--amber2)}
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
.step .n{font-family:'IBM Plex Mono';font-weight:700;font-size:13px;color:var(--amber2);letter-spacing:.12em;margin-bottom:10px}
.step p{font-size:14px;color:var(--ink2);margin-top:6px}
.kubix{display:grid;grid-template-columns:1fr 1fr;gap:52px;align-items:center}
.chatcard{padding:20px}
.msg{max-width:88%;border-radius:13px;padding:12px 16px;font-size:14px;margin-bottom:12px;line-height:1.55}
.msg.user{background:rgba(56,189,248,.10);border:1px solid rgba(56,189,248,.2);margin-left:auto}
.msg.bot{background:var(--panel2);border:1px solid var(--line)}
.msg.bot ol{margin:8px 0 4px 18px}
.kbadge{display:flex;align-items:center;gap:10px;margin-bottom:16px}
.kbadge .av{width:38px;height:38px;border-radius:11px;background:linear-gradient(135deg,#38BDF8,#6366F1);display:grid;place-items:center;font-weight:700;color:#fff;font-family:'IBM Plex Mono'}
.kbadge .nm{font-size:14.5px;font-weight:600}
.kbadge .st{font-size:12px;color:var(--green)}
.seclist{list-style:none;display:grid;grid-template-columns:1fr 1fr;gap:14px}
.seclist li{display:flex;gap:12px;align-items:flex-start;font-size:14.5px;color:var(--ink2);padding:16px 18px}
.seclist .ck{color:var(--green);font-weight:700;flex:0 0 auto}
.toggle{display:inline-flex;background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:4px;gap:2px;margin:26px 0 34px}
.toggle button{border:none;background:transparent;color:var(--ink2);font:600 14px 'Archivo';padding:9px 20px;border-radius:999px;cursor:pointer}
.toggle button.on{background:linear-gradient(135deg,var(--amber2),var(--amber));color:#1a1204}
.toggle .save{font-size:11.5px;font-weight:700;color:var(--green)}
.plans{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;align-items:stretch}
.plan{padding:30px 28px;display:flex;flex-direction:column;position:relative}
.plan.hot{border-color:rgba(245,158,11,.55);box-shadow:0 20px 60px rgba(245,158,11,.10)}
.plan .pop{position:absolute;top:-13px;left:50%;transform:translateX(-50%);background:linear-gradient(135deg,var(--amber2),var(--amber));color:#1a1204;font-size:11.5px;font-weight:700;letter-spacing:.08em;padding:5px 14px;border-radius:999px;text-transform:uppercase}
.plan h3{font-size:21px}
.plan .tag{font-size:13.5px;color:var(--ink3);margin-top:3px}
.price{font-size:44px;font-weight:700;margin-top:20px;letter-spacing:-.02em}
.price small{font-size:15px;color:var(--ink3);font-weight:500;font-family:'Archivo'}
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
  font:400 15px 'Archivo';padding:12px 14px;outline:none;transition:.15s}
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
  display: flex; align-items: center; justify-content: center; font-family: 'IBM Plex Mono',ui-monospace,monospace;
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
.kx-bubble code { font-family: 'IBM Plex Mono',ui-monospace,monospace; background: rgba(255,255,255,0.08); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
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
.ldocwrap { max-width: 780px; padding-top: 110px; padding-bottom: 70px; }
.ldoc h1 { font-size: 30px; margin: 18px 0 14px; }
.ldoc h2 { font-size: 20px; margin: 28px 0 10px; }
.ldoc h3 { font-size: 16px; margin: 22px 0 8px; }
.ldoc p, .ldoc li { color: var(--ink2); font-size: 14.5px; line-height: 1.65; }
.ldoc p { margin: 0 0 12px; }
.ldoc ul, .ldoc ol { margin: 4px 0 14px; padding-left: 22px; }
.ldoc hr { border: none; border-top: 1px solid var(--line); margin: 26px 0; }
.ldoc blockquote {
  background: rgba(245,158,11,.10); border: 1px solid rgba(245,158,11,.4); color: #fcd34d;
  border-radius: 10px; padding: 12px 16px; margin: 0 0 18px; font-size: 13.5px;
}
.ldoc code { font-family: 'IBM Plex Mono',ui-monospace,monospace; background: rgba(255,255,255,.08); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
.ldoc pre.ldoc-code { background: #0b0d10; border: 1px solid var(--line); border-radius: 8px; padding: 12px; overflow-x: auto; margin: 8px 0 16px; }
.kx-feedback { display: flex; gap: 6px; align-items: center; margin-top: 6px; }
.kx-feedback button {
  border: 1px solid var(--line); background: transparent; border-radius: 8px; padding: 2px 8px;
  font-size: 13px; cursor: pointer; opacity: .55; transition: opacity .15s, border-color .15s;
  filter: grayscale(1);
}
.kx-feedback button:hover { opacity: 1; filter: none; }
.kx-feedback button.on { opacity: 1; filter: none; border-color: var(--amber); background: rgba(245,158,11,.10); }
.kx-feedback button:disabled { cursor: default; }
.kx-fb-done button:not(.on) { opacity: .25; }
.kx-fb-thanks { font-size: 12px; color: var(--ink3); margin-left: 4px; }
.kx-input-bar { display: flex; gap: 10px; padding: 14px 4px 4px; border-top: 1px solid var(--line); }
.kx-input {
  flex: 1; resize: none; background: var(--bg2); border: 1px solid var(--line); color: var(--ink);
  border-radius: 10px; padding: 12px 14px; font-family: 'Archivo',sans-serif; font-size: 14.5px; max-height: 140px;
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

/* -------------------------------------------------------------------------- */
/* Signal Foundry / industrial noir                                           */
/* -------------------------------------------------------------------------- */
html{color-scheme:dark;scroll-padding-top:calc(var(--nav-h) + 18px);scrollbar-color:var(--line2) var(--bg)}
body{min-width:320px;min-height:100%;background:
  radial-gradient(circle at 16% 5%,rgba(var(--cyan-rgb),.065),transparent 30rem),
  radial-gradient(circle at 88% 18%,rgba(var(--amber-rgb),.055),transparent 34rem),
  var(--bg)}
body::before{background:
  linear-gradient(90deg,transparent 0 49.92%,rgba(118,153,174,.045) 50%,transparent 50.08%),
  linear-gradient(0deg,transparent 0 49.92%,rgba(118,153,174,.038) 50%,transparent 50.08%);
  background-size:64px 64px;mask-image:linear-gradient(to bottom,#000,transparent 84%)}
::selection{background:rgba(var(--amber-rgb),.28);color:var(--ink)}
a,button,input,select,textarea,summary{touch-action:manipulation}
button,input,select,textarea{font:inherit}
.mono,.eyebrow,.section-index,.module-id,.plan-code,.chip,.stage-head,.rail-readout,.life-step,.chat-chrome{
  font-family:'IBM Plex Mono',ui-monospace,SFMono-Regular,Consolas,monospace
}
.ui-icon{display:block;width:24px;height:24px;flex:0 0 auto}
.btn-icon{width:18px;height:18px;transition:transform .22s var(--ease-out)}
.micro-icon,.eyebrow-icon{width:16px;height:16px}
.radio-icon{width:18px;height:18px}
.list-check{width:18px;height:18px;color:var(--amber);margin-top:2px}
.skip-link{position:fixed;left:16px;top:12px;z-index:1001;padding:11px 16px;background:var(--amber);color:#16120A;
  font:600 13px 'IBM Plex Mono',monospace;transform:translateY(-180%);transition:transform .2s var(--ease-out)}
.skip-link:focus{transform:translateY(0)}
:focus-visible{outline:2px solid var(--cyan);outline-offset:4px}
.scroll-progress{position:fixed;inset:0 0 auto;z-index:1000;height:2px;pointer-events:none;background:rgba(255,255,255,.035)}
.scroll-progress span{display:block;width:100%;height:100%;transform:scaleX(0);transform-origin:left;background:linear-gradient(90deg,var(--amber),var(--cyan))}
.wrap{width:min(100%,var(--max));padding-inline:32px}
.card{background:linear-gradient(145deg,rgba(18,31,43,.95),rgba(9,15,22,.97));border:1px solid var(--line);border-radius:0}
h1,h2,h3{font-feature-settings:'ss02' 1,'ss03' 1}
h1{font-size:clamp(3.1rem,5.45vw,5.15rem);line-height:.98;letter-spacing:-.055em;font-weight:750}
h2{font-size:clamp(2.35rem,4.25vw,4.25rem);line-height:1.02;letter-spacing:-.045em;font-weight:730}
h2 span,.split-head h2 span,.kubix h2 span,.cta-foundry h2 span{color:var(--ink2);font-weight:500}
h3{font-size:1.18rem;line-height:1.2;letter-spacing:-.02em}
p{max-width:72ch}
.mut{color:var(--ink2)}.dim{color:var(--ink3)}

.nav{z-index:100;min-height:var(--nav-h);margin:0;background:rgba(7,10,15,.88);border-bottom:1px solid var(--line);
  backdrop-filter:blur(18px) saturate(130%)}
.nav::after{content:'';position:absolute;left:0;bottom:-1px;width:23%;height:1px;background:linear-gradient(90deg,var(--amber),transparent)}
.nav .wrap{height:var(--nav-h);gap:28px}
.logo{min-height:48px;gap:10px;white-space:nowrap}
.brand-mark{position:relative;display:grid;place-items:center;width:38px;height:38px;border:1px solid rgba(var(--amber-rgb),.34);
  background:#0A1016;clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,8px 100%,0 calc(100% - 8px))}
.brand-mark svg{width:30px;height:30px;overflow:visible}
.cube-top{fill:var(--amber)}.cube-left{fill:#A96A13}.cube-right{fill:var(--cyan)}
.cube-signal{fill:none;stroke:#071017;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.brand-word{font-size:19px;font-weight:800;letter-spacing:.06em}
.brand-by{padding-left:9px;border-left:1px solid var(--line);color:var(--ink3);font:500 10px 'IBM Plex Mono',monospace;
  text-transform:uppercase;letter-spacing:.08em}
.navlinks{gap:7px}
.navlinks a,.navlinks button{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding-inline:12px;
  color:var(--ink2);font-size:13px;letter-spacing:.01em}
.navlinks a:hover{color:var(--ink)}
.btn{position:relative;min-height:48px;padding:12px 22px;border-radius:0;font-size:14px;letter-spacing:.01em;
  clip-path:polygon(0 0,calc(100% - 10px) 0,100% 10px,100% 100%,10px 100%,0 calc(100% - 10px));
  transition:color .2s var(--ease-out),background .2s var(--ease-out),border-color .2s var(--ease-out),box-shadow .2s var(--ease-out),transform .26s var(--ease-spring)}
.btn:hover .btn-icon,.chat-launch:hover .btn-icon{transform:translateX(3px)}
.btn:active{filter:brightness(.92)}
.btn-amber{color:#181207;background:var(--amber);border-color:var(--amber);box-shadow:0 10px 34px rgba(var(--amber-rgb),.14)}
.btn-amber:hover{background:var(--amber2);box-shadow:0 14px 42px rgba(var(--amber-rgb),.21)}
.btn-ghost{color:var(--ink);background:rgba(10,17,24,.78);border-color:var(--line2)}
.btn-ghost:hover{background:var(--surface2);border-color:rgba(var(--cyan-rgb),.48)}
.btn.is-loading::before{content:'';width:14px;height:14px;flex:0 0 14px;border:1.5px solid currentColor;border-right-color:transparent;
  border-radius:50%;animation:buttonSpin .72s linear infinite}
.btn-sm{min-height:44px;padding:9px 16px;font-size:12.5px}
.eyebrow{min-height:32px;padding:6px 10px;border-radius:0;color:var(--amber2);background:rgba(var(--amber-rgb),.07);
  border:1px solid rgba(var(--amber-rgb),.25);font-size:10.5px;letter-spacing:.12em}

/* Hero signal command scene */
.hero-section{position:relative;padding:0;min-height:calc(100svh - var(--nav-h));display:flex;align-items:center;overflow:clip}
.hero-section::before{content:'LIVE INDUSTRIAL EVENT FABRIC';position:absolute;right:-102px;top:50%;z-index:2;transform:rotate(90deg);
  color:rgba(181,202,213,.33);font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.25em}
.hero{padding:84px 0 54px;grid-template-columns:minmax(0,.84fr) minmax(560px,1.16fr);gap:58px;align-items:center}
.hero-copy{position:relative;z-index:3}
.hero-copy h1{margin-top:20px;max-width:12ch}
.signal-text{display:inline;color:var(--amber);text-shadow:0 0 32px rgba(var(--amber-rgb),.12)}
.hero p.lead{max-width:58ch;margin:26px 0 30px;color:var(--ink2);font-size:17px;line-height:1.7}
.hero .ctas{gap:12px}
.hero-assurance{display:flex;align-items:center;flex-wrap:wrap;gap:10px 18px;margin-top:24px;color:var(--ink3);
  font-size:11.5px}
.hero-assurance span{display:inline-flex;align-items:center;gap:7px;min-height:30px}
.hero-assurance span+span{position:relative}
.hero-assurance span+span::before{content:'';position:absolute;left:-10px;width:1px;height:14px;background:var(--line2)}
.signal-stage{--pointer-x:50%;--pointer-y:50%;position:relative;z-index:2;isolation:isolate;min-width:0;color:var(--ink);
  border:1px solid rgba(128,164,185,.34);background:linear-gradient(145deg,rgba(12,20,28,.98),rgba(5,9,14,.99));
  clip-path:polygon(0 0,calc(100% - 22px) 0,100% 22px,100% 100%,22px 100%,0 calc(100% - 22px));
  box-shadow:0 32px 90px rgba(0,0,0,.48);transform-style:preserve-3d;will-change:transform;
  transition:transform .45s var(--ease-out),border-color .25s ease}
.signal-stage::before{content:'';position:absolute;inset:0;z-index:-2;pointer-events:none;
  background:radial-gradient(420px circle at var(--pointer-x) var(--pointer-y),rgba(var(--cyan-rgb),.09),transparent 48%)}
.signal-stage::after{content:'SIAS / COMMAND FABRIC / 2.4';position:absolute;right:24px;bottom:5px;color:rgba(164,186,198,.35);
  font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.15em}
.stage-corner{position:absolute;z-index:5;width:20px;height:20px;pointer-events:none}
.stage-corner::before,.stage-corner::after{content:'';position:absolute;background:var(--amber)}
.stage-corner::before{width:16px;height:1px}.stage-corner::after{width:1px;height:16px}
.stage-corner-a{left:8px;top:8px}.stage-corner-b{right:8px;bottom:8px;transform:rotate(180deg)}
.stage-head{height:48px;padding:0 20px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--line);
  background:rgba(2,5,8,.52);font-size:10px;letter-spacing:.12em;color:var(--ink3)}
.stage-title,.stage-health{display:flex;align-items:center;gap:10px}
.stage-health b{color:var(--green);font-size:10px}.stage-health span:first-child{padding-right:10px;border-right:1px solid var(--line)}
.live-pip{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--green);box-shadow:0 0 0 4px rgba(85,217,138,.1);
  animation:livePulse 1.8s ease-in-out infinite}
.stage-body{display:grid;grid-template-columns:78px minmax(0,1fr);min-height:405px}
.stage-rail{display:flex;flex-direction:column;border-right:1px solid var(--line);background:rgba(3,7,11,.55)}
.rail-readout{padding:17px 11px;border-bottom:1px solid var(--line)}
.rail-readout span,.rail-readout small{display:block;color:var(--ink3);font-size:7.5px;letter-spacing:.09em}
.rail-readout b{display:block;margin:5px 0 2px;color:var(--cyan);font-size:18px;font-weight:500;font-variant-numeric:tabular-nums}
.rail-spectrum{display:flex;align-items:flex-end;gap:3px;min-height:82px;margin:auto 10px 14px;padding-top:12px;border-bottom:1px solid var(--line2)}
.rail-spectrum i{width:5px;height:42%;transform-origin:bottom;background:linear-gradient(to top,var(--cyan),rgba(var(--cyan-rgb),.08));
  animation:spectrum 1.7s ease-in-out infinite alternate}
.rail-spectrum i:nth-child(2),.rail-spectrum i:nth-child(6){height:72%;animation-delay:-.8s}.rail-spectrum i:nth-child(3){height:48%;animation-delay:-.3s}
.rail-spectrum i:nth-child(4),.rail-spectrum i:nth-child(8){height:88%;animation-delay:-1.2s}.rail-spectrum i:nth-child(5){height:61%;animation-delay:-.55s}
.factory-field{position:relative;min-width:0;overflow:hidden;background:linear-gradient(180deg,rgba(12,23,32,.35),rgba(3,7,11,.35))}
.field-grid{position:absolute;inset:0;background:
  linear-gradient(rgba(92,132,153,.065) 1px,transparent 1px),
  linear-gradient(90deg,rgba(92,132,153,.065) 1px,transparent 1px);
  background-size:26px 26px;mask-image:linear-gradient(135deg,#000,rgba(0,0,0,.38))}
.factory-schematic{position:absolute;inset:18px 6px 64px;width:calc(100% - 12px);height:calc(100% - 82px);overflow:visible}
.plant-outline{fill:rgba(11,22,30,.42);stroke:rgba(122,161,181,.28);stroke-width:1}
.plant-inner{fill:rgba(21,39,51,.24);stroke:rgba(122,161,181,.21);stroke-width:1}
.route-base{fill:none;stroke:rgba(91,125,143,.24);stroke-width:3}.route-base.secondary{stroke-width:2}
.route-flow{fill:none;stroke:url(#sias-route);stroke-width:2;stroke-dasharray:4 11;animation:dataFlow 2.8s linear infinite}
.route-flow-secondary{animation-delay:-1.4s;opacity:.7}
.machine-node{fill:#0C1720;stroke:var(--green);stroke-width:1.5}.machine-node .node-halo{fill:rgba(85,217,138,.045);stroke:rgba(85,217,138,.35)}
.machine-node.node-ai{stroke:var(--cyan)}.machine-node.node-ai .node-halo{fill:rgba(var(--cyan-rgb),.055);stroke:rgba(var(--cyan-rgb),.48)}
.machine-node.node-critical{stroke:var(--red)}.machine-node.node-critical .node-halo{fill:rgba(255,107,103,.08);stroke:var(--red)}
.node-ring{fill:none;stroke:var(--red);stroke-width:1;transform-origin:center;animation:nodePing 2.2s ease-out infinite}
.factory-schematic text{fill:rgba(181,203,214,.53);font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.06em}
.scan-beam{position:absolute;left:0;right:0;top:0;height:52px;pointer-events:none;opacity:.72;
  border-bottom:1px solid rgba(var(--cyan-rgb),.5);background:linear-gradient(to bottom,transparent,rgba(var(--cyan-rgb),.055));
  animation:scanField 5.8s var(--ease-out) infinite}
.alert-ticket{position:absolute;right:18px;bottom:22px;width:min(310px,67%);padding:14px 15px 13px;border:1px solid rgba(255,107,103,.52);
  background:rgba(8,13,19,.94);clip-path:polygon(0 0,calc(100% - 12px) 0,100% 12px,100% 100%,0 100%)}
.alert-ticket::before{content:'';position:absolute;inset:0 auto 0 0;width:2px;background:var(--red)}
.ticket-top{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px}
.ticket-code{display:flex;align-items:center;gap:7px;color:var(--red);font:600 10px 'IBM Plex Mono',monospace;letter-spacing:.08em}
.ticket-icon{width:15px;height:15px}.alert-ticket strong{display:block;font-size:14px}.alert-ticket p{margin-top:2px;color:var(--ink3);font-size:10.5px}
.assignment{display:grid;grid-template-columns:30px 1fr auto;align-items:center;gap:9px;margin-top:11px;padding-top:10px;border-top:1px solid var(--line)}
.agent-orb{display:grid;place-items:center;width:29px;height:29px;background:rgba(var(--cyan-rgb),.1);border:1px solid rgba(var(--cyan-rgb),.42);
  color:var(--cyan);font:600 10px 'IBM Plex Mono',monospace}
.assignment small{display:block;color:var(--ink3);font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.1em}
.assignment b{display:block;margin-top:1px;font-size:11px}.confidence{color:var(--cyan);font-size:12px}
.signal-lifecycle{position:relative;display:grid;grid-template-columns:repeat(4,1fr);gap:1px;padding:18px 18px 21px;border-top:1px solid var(--line);
  background:#080D12}
.lifecycle-track{position:absolute;left:12.5%;right:12.5%;top:12px;height:1px;background:rgba(116,151,170,.27);overflow:visible}
.lifecycle-runner{display:block;width:25%;height:2px;margin-top:-1px;background:linear-gradient(90deg,var(--amber),var(--cyan));
  box-shadow:0 0 12px rgba(var(--cyan-rgb),.36);animation:lifecycleMove 8s var(--ease-out) infinite}
.life-step{display:grid;gap:3px;padding-inline:8px;text-align:center;color:var(--ink3);font-size:10px;letter-spacing:.05em}
.life-step i{display:grid;place-items:center;width:20px;height:20px;margin:-17px auto 5px;border:1px solid var(--line2);background:#080D12;
  color:var(--ink2);font-style:normal;font-size:10px}
.life-step span{font-family:'Archivo',sans-serif;font-size:9.5px;letter-spacing:0}.life-step b{color:var(--cyan);font-weight:500;font-variant-numeric:tabular-nums}
.life-step.resolved b{color:var(--green)}
.stats{margin:0 0 24px;border:1px solid var(--line);border-radius:0;background:var(--line);clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,0 100%)}
.stat{position:relative;padding:20px 14px;background:rgba(8,13,19,.96);text-align:left}
.stat::before{content:'';position:absolute;left:14px;top:0;width:20px;height:1px;background:var(--amber)}
.stat .n{color:var(--ink);font:600 23px 'IBM Plex Mono',monospace;letter-spacing:-.04em}
.stat .l{max-width:18ch;color:var(--ink3);font-size:10px;line-height:1.35}

/* Scroll chapters */
.foundry-section{position:relative;padding:118px 0;border-top:1px solid rgba(123,157,177,.1)}
.foundry-section::before{content:'';position:absolute;left:max(20px,calc((100vw - var(--max))/2 + 32px));top:0;width:72px;height:1px;background:var(--cyan)}
.section-index{margin-bottom:28px;color:var(--ink3);font-size:10px;letter-spacing:.18em}
.split-head{max-width:900px;margin-bottom:56px}
.split-head h2{margin-top:18px}.split-head p{max-width:57ch;margin-top:18px;font-size:16px;line-height:1.7}
.feature-grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:12px}
.feat{position:relative;grid-column:span 4;min-height:310px;padding:28px 26px 36px;overflow:hidden;
  clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,14px 100%,0 calc(100% - 14px));
  transition:transform .26s var(--ease-out),border-color .26s ease,background .26s ease}
.feat-primary{grid-column:span 8;background:
  linear-gradient(115deg,rgba(var(--amber-rgb),.07),transparent 45%),
  linear-gradient(145deg,rgba(18,31,43,.98),rgba(9,15,22,.98))}
.feat:hover{transform:translateY(-4px);border-color:rgba(var(--cyan-rgb),.42);background-color:var(--surface2)}
.feat .ic{width:48px;height:48px;margin-bottom:34px;border-radius:0;color:var(--amber);background:rgba(var(--amber-rgb),.06);
  border:1px solid rgba(var(--amber-rgb),.24);clip-path:polygon(0 0,calc(100% - 9px) 0,100% 9px,100% 100%,0 100%)}
.feat .ic .ui-icon{width:23px;height:23px}.module-id{position:absolute;right:20px;top:20px;color:var(--ink3);font-size:10px;letter-spacing:.14em}
.feat h3{max-width:22ch;margin-bottom:12px;font-size:20px}.feat p{max-width:54ch;color:var(--ink2);font-size:14px;line-height:1.68}
.module-trace{position:absolute;left:0;right:0;bottom:0;height:22px;border-top:1px solid var(--line);
  background:linear-gradient(90deg,transparent 0 8%,rgba(var(--cyan-rgb),.22) 8% 9%,transparent 9% 22%,rgba(var(--amber-rgb),.3) 22% 34%,transparent 34%)}
.integrations-section{padding-top:108px}
.protocol-board{position:relative;display:grid;grid-template-columns:210px 1fr;gap:1px;border:1px solid var(--line);background:var(--line);
  clip-path:polygon(0 0,calc(100% - 16px) 0,100% 16px,100% 100%,0 100%)}
.protocol-core{display:grid;place-items:center;align-content:center;min-height:260px;padding:30px;background:
  radial-gradient(circle,rgba(var(--cyan-rgb),.11),transparent 60%),#091017;text-align:center}
.protocol-core>span{display:grid;place-items:center;width:72px;height:72px;border:1px solid rgba(var(--cyan-rgb),.52);color:var(--cyan);
  transform:rotate(45deg)}.protocol-core>span .ui-icon{width:32px;height:32px;transform:rotate(-45deg)}
.protocol-core b{margin-top:28px;font-size:23px;letter-spacing:.08em}.protocol-core small{margin-top:5px;color:var(--ink3);font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.16em}
.logos{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line)}
.logos span{position:relative;display:flex;align-items:center;gap:12px;min-height:86px;padding:18px 20px;border:0;border-radius:0;background:#0A1118;
  color:var(--ink2);font:500 11px 'IBM Plex Mono',monospace;letter-spacing:.03em}
.logos span:hover{color:var(--ink);background:#0D1720}.logos i{width:7px;height:7px;border:1px solid var(--cyan);transform:rotate(45deg)}
.logos i::after{content:'';display:block;width:3px;height:3px;margin:1px;background:var(--cyan)}
.kubix-section{overflow:hidden}.kubix{grid-template-columns:.86fr 1.14fr;gap:72px}.kubix h2{margin-top:18px}
.signal-list{display:grid;gap:12px;margin-top:28px;list-style:none}
.signal-list li{display:flex;gap:11px;color:var(--ink2);font-size:14px}
.chatcard{position:relative;padding:0 24px 24px;border:1px solid var(--line2);background:linear-gradient(145deg,#0D1821,#080D12);
  clip-path:polygon(0 0,calc(100% - 18px) 0,100% 18px,100% 100%,18px 100%,0 calc(100% - 18px));
  box-shadow:0 34px 90px rgba(0,0,0,.35);transition:transform .45s var(--ease-out)}
.chat-chrome{display:flex;justify-content:space-between;margin:0 -24px 22px;padding:13px 18px;border-bottom:1px solid var(--line);
  color:var(--ink3);font-size:10px;letter-spacing:.1em}.kbadge{margin-bottom:18px}
.kbadge .av{width:44px;height:44px;border-radius:0;background:rgba(var(--cyan-rgb),.09);border:1px solid rgba(var(--cyan-rgb),.42);
  color:var(--cyan);clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,0 100%)}
.kbadge .av .ui-icon{width:23px;height:23px}.kbadge .st{display:flex;align-items:center;gap:6px}.kbadge .st i{width:6px;height:6px;border-radius:50%;background:var(--green)}
.msg{padding:12px 14px;border-radius:0;font-size:13px;line-height:1.6}
.msg.user{background:rgba(var(--cyan-rgb),.065);border-color:rgba(var(--cyan-rgb),.22);clip-path:polygon(8px 0,100% 0,100% 100%,0 100%,0 8px)}
.msg.bot{background:rgba(2,6,9,.55);clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,0 100%)}
.chat-launch{display:flex;align-items:center;justify-content:space-between;min-height:48px;margin-top:18px;padding:11px 14px;border:1px solid rgba(var(--amber-rgb),.34);
  color:var(--amber2);font:600 11px 'IBM Plex Mono',monospace;letter-spacing:.06em}
.security-section{background:linear-gradient(180deg,rgba(255,107,103,.018),transparent 38%)}
.seclist{gap:1px;border:1px solid var(--line);background:var(--line)}
.seclist li{position:relative;display:grid;grid-template-columns:42px 1fr auto;gap:16px;align-items:center;min-height:132px;padding:22px;
  color:var(--ink2);background:#091017}
.seclist li::before{content:'';position:absolute;inset:0 auto 0 0;width:2px;background:transparent;transition:background .2s ease}
.seclist li:hover::before{background:var(--cyan)}
.security-icon{width:34px;height:34px;padding:7px;border:1px solid rgba(var(--cyan-rgb),.27);color:var(--cyan)}
.seclist b{color:var(--ink)}.seclist em{align-self:start;color:var(--ink3);font-size:10px;font-style:normal;letter-spacing:.12em}
.process-section .steps{position:relative;gap:0}.process-section .steps::before{content:'';position:absolute;left:12.5%;right:12.5%;top:62px;height:1px;
  background:linear-gradient(90deg,var(--amber),var(--cyan))}
.process-section .step{padding:0 24px 24px;background:transparent;border:0;text-align:center}
.step-node{position:relative;z-index:2;display:grid;place-items:center;width:58px;height:58px;margin:18px auto 24px;border:1px solid var(--line2);
  color:var(--cyan);background:var(--bg);transform:rotate(45deg)}
.step-node .ui-icon{width:23px;height:23px;transform:rotate(-45deg)}.step .n{font-family:'IBM Plex Mono',monospace;font-size:10px}
.process-section .step h3{font-size:17px}.process-section .step p{margin:10px auto 0;font-size:13px;line-height:1.62}
.pricing-head{max-width:none;margin-bottom:52px;text-align:center}.pricing-head h2{margin-top:18px}
.toggle{border-radius:0;padding:3px;background:#091017}.toggle button{min-height:44px;border-radius:0;font:600 11px 'IBM Plex Mono',monospace;
  text-transform:uppercase;letter-spacing:.06em}.toggle button.on{background:var(--amber)}
.plans{gap:12px}.plan{position:relative;padding:34px 28px 30px;border:1px solid var(--line);background:linear-gradient(155deg,#0D1720,#080D12);
  clip-path:polygon(0 0,calc(100% - 15px) 0,100% 15px,100% 100%,15px 100%,0 calc(100% - 15px))}
.plan::after{content:'';position:absolute;left:28px;top:0;width:42px;height:2px;background:var(--cyan)}
.plan.hot{border-color:rgba(var(--amber-rgb),.64);background:
  linear-gradient(145deg,rgba(var(--amber-rgb),.075),transparent 42%),
  linear-gradient(155deg,#111A20,#080D12);box-shadow:0 30px 80px rgba(0,0,0,.28);transition:transform .45s var(--ease-out)}
.plan.hot::after{width:72px;background:var(--amber)}
.plan .pop{top:-16px;border-radius:0;background:var(--amber);font:700 10px 'IBM Plex Mono',monospace;letter-spacing:.09em;
  clip-path:polygon(0 0,calc(100% - 7px) 0,100% 7px,100% 100%,0 100%);display:flex;align-items:center;gap:7px}
.plan .pop .live-pip{background:#19240F;box-shadow:none}.plan-code{margin-bottom:26px;color:var(--ink3);font-size:10px;letter-spacing:.15em}
.plan h3{font-size:25px}.plan .tag{color:var(--ink3)}.price{font-family:'IBM Plex Mono',monospace;font-size:42px;font-variant-numeric:tabular-nums}
.price small{font-family:'IBM Plex Mono',monospace}.plan ul li{align-items:flex-start}.plan .btn{width:100%}
.pricing-note{max-width:92ch;margin:24px auto 0;text-align:center;font:400 10px/1.6 'IBM Plex Mono',monospace}
.faq-wrap{max-width:820px}.faq-section details{margin-bottom:8px;border-radius:0;background:#091017}
.faq-section summary{min-height:60px;align-items:center;padding:16px 20px;font-size:15px}
.faq-section summary::after{display:grid;place-items:center;width:28px;height:28px;border:1px solid var(--line);font:400 17px 'IBM Plex Mono',monospace}
.faq-section details[open]{border-color:rgba(var(--cyan-rgb),.34);background:#0B141C}
.faq-section details .a{padding:0 62px 20px 20px;line-height:1.7}
.cta-band{padding:18px 0 112px}.cta-foundry{position:relative;overflow:hidden;padding:82px 34px;border:1px solid rgba(var(--amber-rgb),.36);
  background:
  linear-gradient(115deg,rgba(var(--amber-rgb),.08),transparent 42%),
  repeating-linear-gradient(90deg,transparent 0 58px,rgba(119,151,168,.04) 59px),
  #0A1118;clip-path:polygon(0 0,calc(100% - 24px) 0,100% 24px,100% 100%,24px 100%,0 calc(100% - 24px))}
.cta-foundry h2{position:relative;margin-top:20px}.cta-foundry p,.cta-foundry .btn,.cta-foundry .eyebrow{position:relative}
.cta-signal{position:absolute;inset:50% auto auto 50%;width:650px;height:650px;transform:translate(-50%,-50%);border:1px solid rgba(var(--amber-rgb),.1);
  border-radius:50%}.cta-signal span,.cta-signal i{position:absolute;inset:50%;border:1px solid rgba(var(--amber-rgb),.12);border-radius:50%;transform:translate(-50%,-50%)}
.cta-signal span{width:70%;height:70%}.cta-signal i:nth-child(2){width:45%;height:45%}.cta-signal i:nth-child(3){width:22%;height:22%}
.cta-signal i:nth-child(4){width:7px;height:7px;background:var(--amber);border:0;box-shadow:0 0 22px rgba(var(--amber-rgb),.55)}
.site-footer{margin-top:0;background:#05080C}.site-footer .wrap{display:grid;grid-template-columns:auto 1fr auto;gap:28px}
.site-footer .wrap>span:nth-child(2){text-align:center}.footer-logo .brand-by{display:none}.site-footer .mono{font-size:10px;letter-spacing:.09em}

/* Shared premium shell: checkout, Copilot, success, welcome, legal, admin */
.buywrap{padding:92px 32px 80px;gap:46px}.buywrap h2{font-size:clamp(2.2rem,4vw,3.65rem)}
.buywrap form{padding:26px;border:1px solid var(--line);background:#091017;clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,0 100%)}
.formgrid{gap:18px 14px}.field{gap:8px}.field label{color:var(--ink2);font:600 10px 'IBM Plex Mono',monospace;letter-spacing:.05em;text-transform:uppercase}
.field input,.field select,.field textarea{min-height:48px;border-radius:0;border-color:var(--line2);background:#060B10;color:var(--ink);
  font:400 16px 'Archivo',sans-serif;transition:border-color .2s ease,box-shadow .2s ease,background .2s ease}
.field input:hover,.field select:hover,.field textarea:hover{border-color:rgba(var(--cyan-rgb),.46)}
.field input:focus,.field select:focus,.field textarea:focus{border-color:var(--cyan);background:#091119;box-shadow:0 0 0 3px rgba(var(--cyan-rgb),.12)}
.sumcard{top:calc(var(--nav-h) + 22px);padding:28px;border-radius:0;clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,14px 100%,0 calc(100% - 14px))}
.sumcard::before{content:'CONFIGURATION SUMMARY';display:block;margin-bottom:24px;color:var(--ink3);font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.15em}
.sumline{border-color:var(--line);font-size:13px}.radio2 label{min-height:50px;display:grid;place-items:center;border-radius:0;background:#070C11}
.radio2 label span{display:inline-flex;align-items:center;justify-content:center;gap:7px}.radio2 label:has(input:checked){border-color:var(--amber);background:rgba(var(--amber-rgb),.07)}
.err{border-radius:0}.success-glyph{display:grid;place-items:center;width:58px;height:58px;margin:0 auto;color:var(--green);
  border:1px solid rgba(85,217,138,.42);transform:rotate(45deg)}.success-glyph .ui-icon{transform:rotate(-45deg)}
.okpage{padding:110px 24px 90px}.okpage .big{border-radius:0;transform:rotate(45deg);background:rgba(85,217,138,.07)}
.okpage .big .ui-icon{transform:rotate(-45deg)}.nextsteps .card{border-radius:0}
.nextsteps .n{border-radius:0;font-family:'IBM Plex Mono',monospace}
.ldocwrap{padding-top:96px}.ldoc{padding:34px;border:1px solid var(--line);background:#091017}
.ldoc code,.ldoc pre.ldoc-code{font-family:'IBM Plex Mono',monospace}.ldoc blockquote{border-radius:0}
.kx-app{position:relative;max-width:900px;height:100dvh;padding:22px 28px;background:
  linear-gradient(180deg,rgba(var(--cyan-rgb),.035),transparent 28%),
  #080D12;border-inline:1px solid var(--line)}
.kx-app::before{content:'KUBIX / SECURE COPILOT CHANNEL';position:absolute;left:-118px;top:50%;transform:rotate(-90deg);color:var(--ink3);
  font:500 10px 'IBM Plex Mono',monospace;letter-spacing:.15em}
.kx-header{min-height:66px;padding:10px 2px 16px}.kx-avatar{width:46px;height:46px;border-radius:0;color:#161207;background:var(--amber);
  clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,0 100%)}
.kx-avatar .ui-icon{width:23px;height:23px}.kx-header-name{font-size:16px}.kx-back{display:grid;place-items:center;min-width:70px;min-height:44px}
.kx-messages{padding:26px 4px}.kx-bubble{border-radius:0;padding:13px 16px}
.kx-msg-user .kx-bubble{background:var(--amber);clip-path:polygon(8px 0,100% 0,100% 100%,0 100%,0 8px)}
.kx-msg-bot .kx-bubble{background:#0D1720;clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,0 100%)}
.kx-bubble code,.kx-bubble pre.kx-code{font-family:'IBM Plex Mono',monospace}.kx-bubble pre.kx-code{border-radius:0}
.kx-feedback button{min-width:44px;min-height:44px;border-radius:0}.kx-input-bar{padding:14px 2px max(4px,env(safe-area-inset-bottom))}
.kx-input{min-height:50px;border-radius:0;font:400 16px 'Archivo',sans-serif}.kx-send{min-width:92px;min-height:50px;border-radius:0;background:var(--amber);
  clip-path:polygon(0 0,calc(100% - 8px) 0,100% 8px,100% 100%,0 100%)}
table{font-variant-numeric:tabular-nums}th{font-family:'IBM Plex Mono',monospace}

/* Reveal and state motion */
.js [data-reveal]{opacity:0;transition:opacity .65s var(--ease-out) var(--reveal-delay,0ms),transform .7s var(--ease-out) var(--reveal-delay,0ms);will-change:opacity,transform}
.js [data-reveal="up"]{transform:translate3d(0,34px,0)}.js [data-reveal="left"]{transform:translate3d(-34px,0,0)}
.js [data-reveal="right"]{transform:translate3d(34px,0,0)}
.js [data-reveal].is-visible{opacity:1;transform:translate3d(0,0,0)}
@keyframes livePulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.45;transform:scale(.72)}}
@keyframes dataFlow{to{stroke-dashoffset:-60}}
@keyframes nodePing{0%{opacity:.85;transform:scale(.72)}70%,100%{opacity:0;transform:scale(1.4)}}
@keyframes scanField{0%,12%{transform:translateY(-64px);opacity:0}20%{opacity:.75}74%{opacity:.65}86%,100%{transform:translateY(400px);opacity:0}}
@keyframes spectrum{from{transform:scaleY(.35);opacity:.45}to{transform:scaleY(1);opacity:1}}
@keyframes lifecycleMove{0%,8%{transform:translateX(0)}28%{transform:translateX(100%)}52%{transform:translateX(200%)}76%,100%{transform:translateX(300%)}}
@keyframes buttonSpin{to{transform:rotate(1turn)}}

/* 1440 / 1024 / 768 / 375 responsive system */
@media(min-width:1440px){
  :root{--max:1320px}
  .hero{grid-template-columns:minmax(0,.8fr) minmax(620px,1.2fr);gap:74px}
  .signal-stage{transform-origin:center}.stage-body{min-height:430px}
  .foundry-section{padding-block:136px}
}
@media(max-width:1120px){
  .hero-section{min-height:auto}.hero{grid-template-columns:1fr;padding-top:76px;gap:48px}
  .hero-copy{max-width:780px}.hero-copy h1{max-width:13ch}.signal-stage{width:min(100%,860px);margin-inline:auto}
  .kubix{grid-template-columns:1fr;gap:44px}.chatcard{max-width:820px}
  .site-footer .wrap{grid-template-columns:1fr;text-align:center}.site-footer .logo{margin-inline:auto}.site-footer .wrap>span:nth-child(2){text-align:center}
}
@media(max-width:1023px){
  .wrap{padding-inline:28px}.foundry-section{padding-block:104px}
  .feature-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.feat,.feat-primary{grid-column:auto}
  .protocol-board{grid-template-columns:180px 1fr}.logos{grid-template-columns:repeat(2,1fr)}
  .seclist{grid-template-columns:1fr}.plans{grid-template-columns:1fr}.plan{max-width:680px;width:100%;margin-inline:auto}
  .process-section .steps{grid-template-columns:repeat(2,1fr);gap:34px 0}.process-section .steps::before{display:none}
  .buywrap{grid-template-columns:1fr}.sumcard{position:static}
}
@media(max-width:767px){
  :root{--nav-h:64px}.wrap{padding-inline:20px}
  .nav .wrap{height:var(--nav-h);padding-inline:16px}.brand-by{display:none}.navlinks{gap:4px}.navlinks a{padding-inline:8px}
  .navlinks .btn{padding-inline:14px}.hero{padding:62px 0 34px;gap:36px}
  h1{font-size:clamp(2.65rem,12vw,4.1rem)}h2{font-size:clamp(2rem,9vw,3.25rem)}
  .hero p.lead{font-size:16px}.hero .ctas{display:grid}.hero .ctas .btn{width:100%}
  .hero-assurance{gap:8px 14px}.signal-stage{clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,14px 100%,0 calc(100% - 14px))}
  .stage-health>span:first-child{display:none}.stage-body{grid-template-columns:1fr;min-height:360px}.stage-rail{display:none}
  .factory-schematic{inset:4px -48px 80px;width:calc(100% + 96px);height:calc(100% - 84px)}.alert-ticket{right:12px;bottom:16px;width:calc(100% - 24px)}
  .signal-lifecycle{grid-template-columns:repeat(2,1fr);gap:20px 1px;padding-top:22px}.lifecycle-track{display:none}.life-step i{margin:0 auto 4px}
  .stats{grid-template-columns:repeat(2,1fr)}.stats .stat:last-child{grid-column:1/-1}
  .foundry-section{padding-block:84px}.section-index{margin-bottom:20px}.split-head{margin-bottom:38px}
  .feature-grid{grid-template-columns:1fr}.feat{min-height:auto}.protocol-board{grid-template-columns:1fr}.protocol-core{min-height:210px}
  .logos{grid-template-columns:1fr 1fr}.logos span{min-height:70px;padding:14px;font-size:10px}
  .kubix{gap:34px}.chatcard{padding-inline:16px}.chat-chrome{margin-inline:-16px}.msg{max-width:94%}
  .seclist li{grid-template-columns:38px 1fr;min-height:126px}.seclist em{display:none}
  .process-section .steps{grid-template-columns:1fr}.process-section .step{text-align:left;display:grid;grid-template-columns:58px 1fr;column-gap:18px}
  .process-section .step .n,.process-section .step p{grid-column:2}.step-node{grid-row:1/4;margin:10px 0}.process-section .step h3{align-self:end}
  .pricing-head{text-align:left}.toggle{width:100%;display:grid;grid-template-columns:1fr 1fr}.toggle button{width:100%}
  .faq-section details .a{padding-right:20px}.cta-foundry{padding:64px 20px}.cta-foundry h2 br{display:none}
  .formgrid{grid-template-columns:1fr}.buywrap{padding:64px 20px}.buywrap form{padding:20px 16px}
  .radio2{grid-template-columns:1fr}.kx-app{padding-inline:16px;border:0}.kx-app::before{display:none}.kx-bubble{max-width:88%}
  .ldoc{padding:24px 18px}.ldocwrap{padding-inline:18px}
}
@media(max-width:479px){
  .wrap{padding-inline:18px}.logo{gap:8px}.brand-mark{width:36px;height:36px}.brand-word{font-size:17px}
  .navlinks>a:not(.btn){display:none}.navlinks .btn{min-width:108px}
  .hero-copy h1{font-size:clamp(2.5rem,12vw,3.2rem)}.hero-assurance span+span::before{display:none}
  .stage-head{padding-inline:12px}.stage-title .mono{font-size:10px}.stage-time{display:none}.stage-body{min-height:350px}
  .alert-ticket{padding:12px}.assignment{grid-template-columns:28px 1fr auto}.signal-lifecycle{padding-inline:9px}
  .stat{padding:18px 12px}.stat .n{font-size:20px}.foundry-section{padding-block:76px}
  .logos{grid-template-columns:1fr}.protocol-core{min-height:190px}.protocol-core>span{width:62px;height:62px}
  .seclist li{padding:18px 14px}.plan{padding-inline:22px}.price{font-size:37px}
  .cta-band{padding-bottom:80px}.site-footer{padding-block:36px}.site-footer .wrap{padding-inline:18px}
  .kx-header-sub{font-size:11px}.kx-back{min-width:56px}.kx-send{min-width:76px;padding-inline:14px}
}
@media(max-height:620px) and (orientation:landscape){
  .hero-section{min-height:auto}.hero{padding-block:48px}.hero-copy h1{font-size:3.5rem}
}
@media(prefers-reduced-motion:reduce){
  html{scroll-behavior:auto}
  *,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;scroll-behavior:auto!important;transition-duration:.01ms!important}
  .js [data-reveal]{opacity:1!important;transform:none!important}
  [data-tilt],[data-magnetic]{transform:none!important}
  .scan-beam{display:none}.route-flow{stroke-dashoffset:0}.scroll-progress{display:none}
}
`;
// eof
