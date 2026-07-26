#!/usr/bin/env node
// =============================================================================
// SIAS quote generator — renders a branded, signature-ready quote PDF.
// =============================================================================
// Usage:
//   node tool/generate_quote.mjs --company "Nagati Steel Works" \
//     --contact "Amine Ben Salah" --email a.bensalah@company.com \
//     --plan growth --billing annual --currency USD \
//     [--discount-pct 10] [--valid-days 30] [--amount 9800] [--out-dir quotes]
//
// Pricing comes from pricing.mjs — the same module the store worker serves, so
// a quote can never disagree with the storefront. EUR has no list price in the
// catalog, so EUR quotes require an explicit --amount (whole euros).
// Output: quotes/SIAS-Quote-<TENANT>-<yyyy-mm-dd>.pdf + a .json sidecar with
// the exact figures for the CRM/n8n side. The quotes/ dir is git-ignored.
// Money is never collected by this tool — it produces paperwork only.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PLAN_CATALOG, listPrice } from '../pricing.mjs';
import { makeTenantCode } from '../cloudflare_store_worker.js';

const CURRENCIES = ['USD', 'TND', 'EUR'];
const BILLINGS = ['monthly', 'annual'];

export function parseQuoteArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) { out[key] = true; continue; }
    out[key] = next;
    i++;
  }
  return out;
}

/** Builds the complete quote model (all figures + validity) or throws with a
 *  human-readable message. Pure: inject nowMs/rand for deterministic tests. */
export function buildQuoteModel(args, { nowMs = Date.now(), rand = Math.random } = {}) {
  const company = String(args.company || '').trim();
  const contact = String(args.contact || '').trim();
  const email = String(args.email || '').trim();
  const plan = String(args.plan || '').trim().toLowerCase();
  const billing = String(args.billing || 'annual').trim().toLowerCase();
  const currency = String(args.currency || 'USD').trim().toUpperCase();
  const discountPct = args['discount-pct'] !== undefined ? Number(args['discount-pct']) : 0;
  const validDays = args['valid-days'] !== undefined ? Number(args['valid-days']) : 30;

  if (!company) throw new Error('--company is required.');
  if (!contact) throw new Error('--contact is required.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new Error('--email must be a valid address.');
  if (!PLAN_CATALOG[plan]) throw new Error(`--plan must be one of: ${Object.keys(PLAN_CATALOG).join(', ')}.`);
  if (!BILLINGS.includes(billing)) throw new Error('--billing must be monthly or annual.');
  if (!CURRENCIES.includes(currency)) throw new Error(`--currency must be one of: ${CURRENCIES.join(', ')}.`);
  if (!Number.isFinite(discountPct) || discountPct < 0 || discountPct > 60) {
    throw new Error('--discount-pct must be between 0 and 60.');
  }
  if (!Number.isFinite(validDays) || validDays < 1 || validDays > 180) {
    throw new Error('--valid-days must be between 1 and 180.');
  }

  let list = listPrice(plan, billing, currency);
  if (list == null) {
    const explicit = Number(args.amount);
    if (!Number.isFinite(explicit) || explicit <= 0) {
      throw new Error(`No ${currency} list price for ${plan}/${billing} — pass --amount (whole ${currency}).`);
    }
    list = explicit;
  }
  const discount = Math.round(list * (discountPct / 100) * 100) / 100;
  const total = Math.round((list - discount) * 100) / 100;

  const def = PLAN_CATALOG[plan];
  const tenantCode = makeTenantCode(company, rand);
  const issued = new Date(nowMs);
  const validUntil = new Date(nowMs + validDays * 86400000);
  const dateSlug = issued.toISOString().slice(0, 10);

  return {
    quoteNumber: `SIAS-Q-${tenantCode.replace('#', '-')}-${dateSlug.replace(/-/g, '')}`,
    tenantCode,
    issuedAt: issued.toISOString(),
    validUntil: validUntil.toISOString(),
    validDays,
    company,
    contact,
    email,
    plan,
    planName: def.name,
    planScope: `${def.factories} · ${def.seats}`,
    features: [...def.features],
    billing,
    currency,
    listPrice: list,
    discountPct,
    discount,
    total,
    terms: 'Invoice on order confirmation · bank transfer · net-15 payment terms.',
    fileBase: `SIAS-Quote-${tenantCode.replace('#', '-')}-${dateSlug}`,
  };
}

export function formatAmount(amount, currency) {
  const n = Number(amount);
  const s = n.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  return currency === 'USD' ? `$${s}` : `${s} ${currency}`;
}

const INK = '#0F172A';
const MUT = '#64748B';
const AMBER = '#F59E0B';
const LINE = '#E2E8F0';

export async function generateQuotePdf(model, outDir) {
  const { default: PDFDocument } = await import('pdfkit');
  fs.mkdirSync(outDir, { recursive: true });
  const pdfPath = path.join(outDir, `${model.fileBase}.pdf`);
  const jsonPath = path.join(outDir, `${model.fileBase}.json`);

  // compress:false keeps the content streams inspectable (and diffable) —
  // quotes are audit paperwork, not bandwidth-sensitive assets.
  const doc = new PDFDocument({ size: 'A4', compress: false, margins: { top: 0, bottom: 54, left: 0, right: 0 } });
  const stream = fs.createWriteStream(pdfPath);
  doc.pipe(stream);
  const W = doc.page.width;
  const L = 56;
  const R = W - 56;

  // Header band with a fine diagonal-hatch texture
  doc.rect(0, 0, W, 118).fill('#0A0F1C');
  doc.save().rect(0, 0, W, 118).clip();
  doc.lineWidth(0.5).strokeOpacity(0.05);
  for (let x = -120; x < W + 120; x += 9) {
    doc.moveTo(x, 0).lineTo(x + 118, 118).stroke('#F8FAFC');
  }
  doc.restore().strokeOpacity(1);
  doc.fillColor(AMBER).font('Helvetica-Bold').fontSize(22).text('▲ SIAS', L, 34, { lineBreak: false });
  doc.fillColor('#94A3B8').font('Helvetica').fontSize(10)
    .text('Smart Industrial Alert System · by KubixDesiney', L, 64);
  doc.fillColor('#F8FAFC').font('Helvetica-Bold').fontSize(15).text('QUOTE', R - 180, 38, { width: 180, align: 'right' });
  doc.fillColor('#94A3B8').font('Helvetica').fontSize(9)
    .text(model.quoteNumber, R - 260, 60, { width: 260, align: 'right' })
    .text(`Issued ${model.issuedAt.slice(0, 10)} · valid until ${model.validUntil.slice(0, 10)}`, R - 260, 74, { width: 260, align: 'right' });

  // Bill-to
  let y = 150;
  doc.fillColor(MUT).font('Helvetica-Bold').fontSize(8.5).text('PREPARED FOR', L, y);
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(13).text(model.company, L, y + 14);
  doc.fillColor(MUT).font('Helvetica').fontSize(10)
    .text(`${model.contact} · ${model.email}`, L, y + 32);
  doc.fillColor(MUT).font('Helvetica-Bold').fontSize(8.5).text('YOUR DEDICATED INSTANCE', R - 220, y, { width: 220, align: 'right' });
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(13).text(model.tenantCode, R - 220, y + 14, { width: 220, align: 'right' });
  doc.fillColor(MUT).font('Helvetica').fontSize(9)
    .text('Isolated database · auth realm · edge services', R - 220, y + 32, { width: 220, align: 'right' });

  // Line-item table
  y = 226;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(1).stroke(LINE);
  y += 12;
  doc.fillColor(MUT).font('Helvetica-Bold').fontSize(8.5)
    .text('DESCRIPTION', L, y, { lineBreak: false })
    .text('BILLING', R - 250, y, { width: 110, align: 'right', lineBreak: false })
    .text('AMOUNT', R - 120, y, { width: 120, align: 'right' });
  y += 18;
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(11.5)
    .text(`SIAS ${model.planName} — dedicated instance`, L, y, { lineBreak: false });
  doc.font('Helvetica').fontSize(10)
    .text(model.billing === 'annual' ? '12 months' : 'per month', R - 250, y + 1, { width: 110, align: 'right', lineBreak: false })
    .text(formatAmount(model.listPrice, model.currency), R - 120, y + 1, { width: 120, align: 'right' });
  y += 18;
  doc.fillColor(MUT).fontSize(9.5).text(model.planScope, L, y);
  y += 16;
  for (const f of model.features) {
    doc.fillColor(MUT).font('Helvetica').fontSize(9).text(`•  ${f}`, L + 8, y);
    y += 13;
  }
  y += 8;
  if (model.discountPct > 0) {
    doc.fillColor(INK).font('Helvetica').fontSize(10)
      .text(`Discount (${model.discountPct}%)`, L, y, { lineBreak: false })
      .text(`-${formatAmount(model.discount, model.currency)}`, R - 120, y, { width: 120, align: 'right' });
    y += 18;
  }
  doc.moveTo(L, y).lineTo(R, y).lineWidth(1).stroke(LINE);
  y += 12;
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(13)
    .text(`Total (${model.currency}, excl. taxes)`, L, y, { lineBreak: false })
    .text(formatAmount(model.total, model.currency), R - 160, y, { width: 160, align: 'right' });
  y += 34;

  // Terms
  doc.rect(L, y, R - L, 74).fill('#F8FAFC');
  doc.fillColor(MUT).font('Helvetica-Bold').fontSize(8.5).text('TERMS', L + 14, y + 12);
  doc.fillColor(INK).font('Helvetica').fontSize(9.5)
    .text(model.terms, L + 14, y + 26, { width: R - L - 28 })
    .text(`This quote is valid for ${model.validDays} days. Your instance is provisioned within 1 business day of order confirmation; a one-time activation link (never a password) is emailed to the owner. 30-day money-back guarantee on your first payment.`, L + 14, y + 40, { width: R - L - 28 });
  y += 96;

  doc.fillColor(MUT).font('Helvetica').fontSize(9)
    .text('KubixDesiney · SIAS — Smart Industrial Alert System', L, y)
    .text('Questions? Reply to this email or chat with your Kubix Copilot — it already knows your tenant code.', L, y + 13);

  doc.end();
  await new Promise((resolve, reject) => {
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  fs.writeFileSync(jsonPath, JSON.stringify(model, null, 2));
  return { pdfPath, jsonPath };
}

async function main() {
  const args = parseQuoteArgs(process.argv.slice(2));
  if (args.help || Object.keys(args).length === 0) {
    console.log('Usage: node tool/generate_quote.mjs --company <name> --contact <name> --email <addr> --plan <starter|growth> --billing <monthly|annual> --currency <USD|TND|EUR> [--discount-pct N] [--valid-days 30] [--amount N] [--out-dir quotes]');
    process.exit(args.help ? 0 : 1);
  }
  let model;
  try {
    model = buildQuoteModel(args);
  } catch (e) {
    console.error(`✗ ${e.message}`);
    process.exit(1);
  }
  const outDir = String(args['out-dir'] || 'quotes');
  const { pdfPath, jsonPath } = await generateQuotePdf(model, outDir);
  console.log(`✓ Quote ${model.quoteNumber} for ${model.company}`);
  console.log(`  total ${formatAmount(model.total, model.currency)} (${model.billing}, ${model.discountPct}% discount)`);
  console.log(`  ${pdfPath}`);
  console.log(`  ${jsonPath}`);
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
