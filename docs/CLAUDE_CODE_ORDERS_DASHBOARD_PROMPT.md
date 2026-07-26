# Claude Code prompt — Founder Orders dashboard + manual-approval sales

Run from `alertsysapp/` repo root. Self-contained.

## The decided model (do not add card payments)

SIAS sells with **no online card payment**. Payment is cash or bank transfer, settled
offline. **The SuperAdmin's approval in the Orders dashboard IS the payment event.**

Flow:
1. Buyer submits the `/buy` form → store worker generates the tenant code, inserts an
   `awaiting_payment` order into Supabase `sias_orders`, and fires `order_placed` to
   n8n WF5 → buyer gets the branded "order received + how to pay" email.
2. Founder collects the money offline, opens the storefront **Orders dashboard**
   (`/admin`), and clicks **Approve** on that order.
3. Approve → store worker sets the order `provisioning` + `approved_at`, and fires
   `payment_approved` to n8n WF5 → buyer gets the "payment confirmed / welcome" email;
   the customer record is upserted to `provisioning`.
4. Founder runs `npm run provision:instance … --execute` → activation email (WF3).

The n8n side (WF5 `AnP16vyft2AwqegB`, both emails) is **already built, published and
tested live**. This prompt is the store-worker side only.

## Already provisioned (use these exact values)

- Supabase project ref: `dwbxavupuxvwzfywjadv`. Table `public.sias_orders` EXISTS:
  columns `id, tenant_code (unique), company, contact_name, email, phone, country,
  factories, plan, billing, currency, amount_display, notes, status (default
  'awaiting_payment'), approval_token, created_at, approved_at`. RLS is ON with no
  public policies — the store worker MUST use the Supabase **service_role** key
  (bypasses RLS) via the REST API (`https://dwbxavupuxvwzfywjadv.supabase.co/rest/v1/`).
- n8n webhooks live: `https://kubixdesiney.app.n8n.cloud/webhook/sias-order-placed`
  and `.../webhook/sias-payment-approved`.

## TASK

```
Read CLAUDE.md first (the "Store Worker" and "Manual-approval sales model" sections)
and cloudflare_store_worker.js. You are in the SIAS repo. Do NOT touch or revive the
parked Stripe/ClicToPay code paths; this is a separate, no-card motion.

Build the manual-approval order flow + a founder Orders dashboard on the sias-store
worker (cloudflare_store_worker.js, single-file, config wrangler.store.toml, tests
worker_test/store_worker.test.js — match the existing style exactly).

1. Order intake (replace the quote path as the default motion):
   - The /buy form submits to a new POST /api/order. Validate the intake (reuse the
     existing validateIntake-style helper; keep name/email/company/plan/billing +
     optional country/factories/phone/notes). Generate the tenant code with the
     existing makeTenantCode.
   - Insert the order into Supabase sias_orders (status defaults to awaiting_payment)
     via the REST API with the service key (env SUPABASE_URL, SUPABASE_SERVICE_KEY).
     Use Prefer: return=representation and handle the unique-tenant_code case.
   - Fire order_placed to env N8N_ORDER_WEBHOOK_URL with the payload shape WF5 expects:
     { tenantCode, company, name, email, planName, billing, amountDisplay,
       paymentInstructions, country, factories, notes, occurredAt }.
     planName from PLAN_CATALOG; amountDisplay from the shared pricing module
     (pricing.mjs); paymentInstructions from a store-worker var PAYMENT_INSTRUCTIONS
     (bank/IBAN/cash text — put a clearly-marked placeholder default).
     Include the optional Authorization: Bearer N8N_WEBHOOK_AUTH like the other forwards.
   - Success state: "Order received — your instance is reserved; it goes live the moment
     we confirm payment" + a Kubix chat link. Server-render the /buy CTA copy as
     "Place your order" (no "quote"/"checkout" wording) — no client flicker.

2. Founder Orders dashboard (NEW, must be auth-gated):
   - GET /admin → if not authed, a minimal login form (single FOUNDER_PASSWORD env
     secret; on submit set a signed, HttpOnly, Secure, SameSite=Strict session cookie —
     sign it with an HMAC of the password + a rotating day salt, or a random
     SESSION_SECRET env; do NOT store the raw password in the cookie). Rate-limit login
     attempts hard (e.g. 5/min/IP) with the existing rateLimited helper.
   - Authed GET /admin → the Orders dashboard: pull sias_orders from Supabase ordered by
     created_at desc, grouped/filtered by status (awaiting_payment first). Each order
     row shows company, contact, plan, amount, country, factories, notes, created time,
     status pill, and the tenant code. Match the dark storefront theme (reuse BASE_CSS
     tokens). Awaiting-payment rows get **Approve** and **Reject** buttons.
   - POST /admin/approve { tenantCode } (authed, same-origin check) → set that order's
     status=provisioning + approved_at=now in Supabase, then fire payment_approved to
     env N8N_APPROVED_WEBHOOK_URL with { tenantCode, company, name, email, plan,
     planName, billing, amountDisplay, country, factories, notes, occurredAt }. Redirect
     back to /admin with a success flash. Idempotent: approving an already-approved
     order is a no-op (do not re-fire the email).
   - POST /admin/reject { tenantCode } (authed) → status=rejected, no email.
   - GET /admin/logout clears the cookie.

3. Security: the /admin routes MUST require the session cookie; /api/order is public but
   rate-limited. Add the strict CSP/security headers the store already emits to the admin
   pages too (nonce for any inline script). Never expose SUPABASE_SERVICE_KEY,
   FOUNDER_PASSWORD, or the n8n URLs to the client or in /config (booleans only).

4. Config: document SUPABASE_URL, SUPABASE_SERVICE_KEY, FOUNDER_PASSWORD, SESSION_SECRET,
   N8N_ORDER_WEBHOOK_URL, N8N_APPROVED_WEBHOOK_URL in wrangler.store.toml comments; add
   PAYMENT_INSTRUCTIONS to [vars]; extend the /config probe with booleans
   (hasSupabase, hasFounderAuth, hasOrderWebhook, hasApprovedWebhook).

5. Tests (worker_test/store_worker.test.js or a new store_orders.test.js): pure helpers —
   order intake validation + the Supabase insert body builder, the order_placed and
   payment_approved payload builders, the session-cookie sign/verify roundtrip (valid,
   tampered, wrong password), and the auth gate decision (no cookie → login, valid cookie
   → dashboard). Mock fetch for Supabase/n8n; no live network.

6. Update CLAUDE.md's Store Worker section with the new routes and the Orders dashboard.

ACCEPTANCE
- npm test green. node --check clean. No card code touched.
- Smoke in Node: POST /api/order with valid body returns ok + a tenantCode and (with a
  mocked Supabase + webhook) inserts + forwards; GET /admin with no cookie shows the
  login; with a valid signed cookie shows the dashboard; POST /admin/approve without a
  cookie is 401/redirect; with a cookie fires payment_approved once (idempotent on
  repeat). /config exposes only booleans.
```

## Your steps after Claude Code merges (one-time)

1. Supabase → Project settings → API → copy the **service_role** key. Then:
   `wrangler secret put SUPABASE_SERVICE_KEY --config wrangler.store.toml`
   `wrangler secret put SUPABASE_URL --config wrangler.store.toml`  (https://dwbxavupuxvwzfywjadv.supabase.co)
2. `wrangler secret put FOUNDER_PASSWORD --config wrangler.store.toml` (your dashboard password)
3. `wrangler secret put SESSION_SECRET --config wrangler.store.toml` (any long random string)
4. `wrangler secret put N8N_ORDER_WEBHOOK_URL --config wrangler.store.toml`
   → https://kubixdesiney.app.n8n.cloud/webhook/sias-order-placed
5. `wrangler secret put N8N_APPROVED_WEBHOOK_URL --config wrangler.store.toml`
   → https://kubixdesiney.app.n8n.cloud/webhook/sias-payment-approved
6. Edit PAYMENT_INSTRUCTIONS in wrangler.store.toml with your real bank/IBAN/cash details.
7. Deploy: `npm run deploy:store` (or push to main).

Then place a test order on your own storefront, approve it in /admin, and watch both
emails arrive. That is the full loop with zero card processors.

## Still open (unchanged)

- Gemini paid billing before Kubix goes in front of a prospect (20 req/day free tier).
- Header Auth on the n8n webhooks (set N8N_WEBHOOK_AUTH on the store worker AND as
  Header Auth on each n8n webhook) before real customers — the order/approval webhooks
  especially, since an open approval webhook could fake a "paid" email.
