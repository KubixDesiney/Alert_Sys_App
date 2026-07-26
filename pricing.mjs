// =============================================================================
// SIAS pricing — the single source of truth for plan pricing.
// =============================================================================
// Imported by BOTH the store worker (cloudflare_store_worker.js — landing page,
// checkout, quote intake) and tool/generate_quote.mjs (branded quote PDFs), so
// a price change lands everywhere in one edit. USD amounts are cents; TND
// amounts are whole dinars (converted to millimes at the payment gateway).
// The store worker re-exports these symbols, so existing importers keep working.

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

// TND is ISO 4217 numeric 788; ClicToPay amounts travel in minor units
// (millimes, exponent 3 — configurable because gateway contracts vary).
export const TND_CURRENCY_CODE = '788';

export function tndMinorUnits(dinars, exponent = 3) {
  return Math.round(Number(dinars) * Math.pow(10, Number(exponent)));
}

/** List price of a plan+billing in a given display currency (whole units, or
 *  null when no list price exists — e.g. EUR, which is always custom-quoted). */
export function listPrice(plan, billing, currency = 'USD') {
  const def = PLAN_CATALOG[plan];
  if (!def) return null;
  const cur = String(currency || 'USD').toUpperCase();
  if (cur === 'USD') return billing === 'annual' ? def.annual / 100 : def.monthly / 100;
  if (cur === 'TND') return billing === 'annual' ? def.tndAnnual : def.tndMonthly;
  return null;
}
