# Claude Code prompts — remaining SIAS commercialization tasks

Run each prompt in a fresh Claude Code session from the repo root (`alertsysapp/`).
They are self-contained: paste the whole block, including the context section.
Order matters only loosely; Prompt 1 and Prompt 2 are independent.

Current state (2026-07-16), for your own reference:

- Storefront worker `sias-store` (`cloudflare_store_worker.js`) is built; Stripe/ClicToPay rails are parked (code present, not pursued commercially).
- n8n (kubixdesiney.app.n8n.cloud): WF1 purchase intake (`S7PiPrb3DWm2T7GN`, webhook `/webhook/sias-purchase-intake`), WF2b knowledge ingest (`fH7jUSm4rP0ga12H`, `/webhook/sias-knowledge-ingest`), WF2 Kubix Copilot chat (`dI4h0nH3bAsjuzGJ`, `/webhook/kubix-copilot-chat`) — all published and tested end-to-end.
- Kubix knowledge base: Supabase project `dwbxavupuxvwzfywjadv`, table `sias_knowledge` (pgvector 3072, `gemini-embedding-001`), RPC `match_sias_knowledge`. Chat log in n8n data table `sias_chats`.
- WF2 chat contract: `POST {message, sessionId, tenantCode, company, userName, plan}` → `{reply, escalated, agent, sessionId}`.
- Gemini key is free tier (20 req/day on `gemini-2.5-flash`) — enable billing before real customers, then bump the WF2 model to `models/gemini-3.1-pro-preview` in the "Gemini Chat Model" node.

---

## Prompt 1 — Owner activation flow (one-time link, never email passwords)

```
Read CLAUDE.md first. You are working in the SIAS repo (Flutter app + 8 Cloudflare
workers + Firebase RTDB, project alias alertappsys).

CONTEXT
SIAS is sold as one dedicated instance per customer. After we provision a customer's
instance, the buyer must claim the SuperAdmin ("Owner") seat via a ONE-TIME activation
link — we never send passwords by email. Today SuperAdmin accounts are created by hand
in the Firebase console (see "Role And Routing" in CLAUDE.md). Firebase Auth action
links give us single-use + expiry for free, so do NOT build custom token infrastructure.

TASK
Create tool/provision_owner.mjs, a Node ESM CLI (firebase-admin is already a
dependency) that automates seeding a customer's Owner account:

1. Args: --email (required), --name "First Last" (required), --company (required),
   --tenant "NSW#7K2F" (required), --db-url (RTDB URL, defaults to env FB_DB_URL),
   --dry-run (print the plan, write nothing).
2. Auth via GOOGLE_APPLICATION_CREDENTIALS or a FIREBASE_SERVICE_ACCOUNT env var
   containing the service-account JSON (same convention as the workers). Never print
   or log the credential.
3. Steps, each idempotent and clearly logged:
   a. Create the Firebase Auth user (random unguessable password via crypto,
      emailVerified false). If the user exists, reuse it and say so.
   b. Write users/{uid}: role "SuperAdmin", firstName/lastName parsed from --name,
      email, active true, plus tenantCode and company fields. The Admin SDK bypasses
      RTDB rules, so no rules changes are needed — do not touch database.rules.json.
   c. Generate the activation link with admin.auth().generatePasswordResetLink(email)
      — this IS the one-time activation link (single use, expires ~1h by default;
      note the expiry in the output).
   d. Print a JSON summary: { uid, email, tenantCode, activationLink, expiresNote }.
   e. If env N8N_ACTIVATION_WEBHOOK_URL is set, POST that JSON to it (this will later
      trigger the branded Brevo activation email from n8n). Non-fatal on failure.
4. Add an npm script "provision:owner": "node tool/provision_owner.mjs".
5. Pure helpers (name parsing, arg parsing, summary shaping) must be exported and
   covered by a new Jest suite worker_test/provision_owner.test.js following the
   existing suite style (ESM, node --experimental-vm-modules). Do not hit Firebase in
   tests — test pure helpers only.
6. Update CLAUDE.md: replace the "create the account record manually in Firebase"
   guidance with this tool, and document the flow (provision instance -> run
   provision:owner -> activation email -> buyer sets password + MFA on first login).

ACCEPTANCE
- npm test passes (all suites, including the new one).
- node tool/provision_owner.mjs --dry-run --email x@y.z --name "A B" --company "C"
  --tenant "C#AAAA" prints the full plan and exits 0 without network calls.
- No secret values ever printed. No changes to database.rules.json.
```

---

## Prompt 2 — Buyer-facing Kubix chat page (/copilot on the store worker)

```
Read CLAUDE.md first, especially the "Store Worker" section. You are working in the
SIAS repo. The storefront is a single-file Cloudflare worker: cloudflare_store_worker.js
(config wrangler.store.toml, tests worker_test/store_worker.test.js). It serves a dark
industrial-themed landing page from embedded template strings (see BASE_CSS and the
page()/landingBody() helpers — match that design language exactly).

CONTEXT
Every SIAS customer gets a personal AI engineer, "Kubix · <TENANT#CODE>", running as an
n8n agent. Its chat API (do NOT expose this URL to the browser):
  POST https://kubixdesiney.app.n8n.cloud/webhook/kubix-copilot-chat
  body: { message, sessionId, tenantCode, company, userName, plan }
  response: { reply, escalated, agent, sessionId }
reply is markdown-ish text (### headings, **bold**, numbered lists, ```code blocks```).
escalated=true means a human engineer will follow up.

TASK
1. New route GET /copilot — a premium chat page consistent with the landing theme:
   - Header: Kubix avatar badge, agent name ("Kubix · <tenant>" once known, else
     "Kubix Copilot"), online dot, subtitle "Your dedicated SIAS engineer".
   - Message list with user/bot bubbles; render the bot reply's lightweight markdown
     (headings, bold, ordered/unordered lists, inline code, fenced code blocks) with a
     small safe client-side renderer — escape ALL HTML first, never innerHTML raw text.
   - Typing indicator while waiting; graceful error bubble on failure.
   - When escalated=true, show an amber banner under that message: "A human engineer
     has been looped in and will follow up by email."
   - Input bar with Enter-to-send, disabled while pending.
   - Context: read tenant, company, name, plan from query params (e.g.
     /copilot?tenant=NSW%237K2F&company=Nagati+Steel+Works&name=Amine&plan=growth).
     sessionId = crypto.randomUUID(), persisted in localStorage together with the
     transcript so a page reload keeps the conversation.
2. New route POST /api/kubix — the server-side proxy:
   - Validate: message (1..2000 chars after trim), sessionId (<=80, [A-Za-z0-9._-]),
     tenantCode/company/userName/plan clipped like validateIntake does.
   - Rate limit with the existing rateLimited() helper: 20/min per IP under key "kx:".
   - Forward to env.N8N_CHAT_WEBHOOK_URL with optional Authorization bearer
     env.N8N_WEBHOOK_AUTH; 25s timeout; on non-OK return
     { ok:false, error:"Kubix is busy, try again in a moment." } with status 502.
   - Return { ok:true, reply, escalated, agent } to the browser. The n8n URL and auth
     header must never reach the client.
3. Wire-up: add "Kubix Copilot" to the landing nav and footer; on the /success page add
   a primary button "Chat with Kubix now" linking to /copilot with tenant/company/name
   from the fetched session/order data.
4. Config: document N8N_CHAT_WEBHOOK_URL (and reuse N8N_WEBHOOK_AUTH) in
   wrangler.store.toml comments; add both to the /config probe as booleans.
5. Tests: extend worker_test/store_worker.test.js with pure-helper coverage — the
   chat-request validator and the forward-payload builder (export them). Follow the
   existing test style.
6. Update the CLAUDE.md Store Worker section with the new routes and secrets.

ACCEPTANCE
- node --check cloudflare_store_worker.js passes; npm test passes.
- Smoke test in Node: default.fetch(new Request('https://x/copilot')) returns 200 HTML
  containing the chat UI; POST /api/kubix with a bad body returns 400; with no
  N8N_CHAT_WEBHOOK_URL returns 503 with a friendly error.
- No external JS/CSS dependencies; single-file worker preserved.
```

---

## Prompt 3 — Instance provisioning automation (v1: script the runbook)

```
Read CLAUDE.md first. You are working in the SIAS repo (8 Cloudflare workers deployed
via per-config wrangler files, Firebase RTDB project alias alertappsys).

CONTEXT
SIAS sells dedicated instances: each customer needs their own Firebase project (RTDB +
Auth) and their own set of workers. Today this is a manual runbook. Goal: one command
that automates everything scriptable and prints an explicit TODO list for what is not.
This is v1 — bias to safe, idempotent, resumable steps over completeness.

TASK
Create tool/provision_instance.mjs (Node ESM CLI) + docs/PROVISIONING.md.

1. Args: --tenant nsw-7k2f (slug, required), --project-id (Firebase/GCP project id,
   required), --region europe-west1 (default), --dry-run (DEFAULT TRUE — real run
   requires --execute), --skip <step,step> to resume.
2. Steps (numbered, idempotent, each prints DONE/SKIPPED/TODO):
   a. Preflight: firebase-tools and wrangler on PATH, firebase login status, wrangler
      whoami. Fail early with exact install commands.
   b. Firebase project: firebase projects:create <project-id> (or reuse if it exists),
      create the default RTDB instance, print the TODO for manual steps that need the
      console (enable Blaze billing, enable Email/Password auth provider, create the
      Android app + download google-services.json, FCM enabled).
   c. Rules: firebase deploy --only database --project <project-id>.
   d. Worker configs: generate wrangler.<name>.<tenant>.toml for each of the 8 configs
      by templating the existing ones — worker name suffixed "-<tenant>", and set the
      instance vars (FB_DB_URL -> the new RTDB URL, NOTIFY_WORKER_URL -> the tenant
      notify worker URL). Write them under deploy/tenants/<tenant>/ and NEVER modify
      the root configs.
   e. Secrets: read deploy/tenants/<tenant>/.env.tenant (git-ignored; generate a
      commented template on first run listing every secret each worker needs — mirror
      the secret lists documented in CLAUDE.md) and pipe each value into
      wrangler secret put --config <tenant config>. Refuse to run if the template
      still contains placeholder values.
   f. Deploy: wrangler deploy for the 8 tenant configs.
   g. Seed the Owner: shell out to tool/provision_owner.mjs (from Prompt 1) with the
      tenant's --db-url; include its JSON output in the final summary.
   h. Summary: write deploy/tenants/<tenant>/provision-summary.json (no secret values)
      + print the remaining manual TODOs.
3. Add npm script "provision:instance". Add deploy/tenants/ and *.env.tenant to
   .gitignore.
4. Pure helpers (config templating, env parsing, step planner) exported and tested in
   worker_test/provision_instance.test.js — no network in tests.
5. docs/PROVISIONING.md: the full runbook — what the script does, the manual console
   steps with screenshots-level precision, and the post-provision checklist (activation
   email, Kubix agent context, monitoring probe URLs).
6. Update CLAUDE.md with a short "Per-customer provisioning" section pointing to the
   doc and tool.

ACCEPTANCE
- npm test passes. --dry-run prints the complete numbered plan for a fake tenant with
  zero side effects and exit 0.
- Root wrangler.*.toml files are byte-identical to before (git diff clean on them).
- No secret values in any committed file or in stdout.
```

---

## Prompt 4 — Legal pack v1 (drafts for lawyer review)

```
Read CLAUDE.md first ("Store Worker" section + security remediation notes) so the
documents describe the real product. You are working in the SIAS repo.

CONTEXT
SIAS (Smart Industrial Alert System) by KubixDesiney is sold B2B as a dedicated,
KubixDesiney-operated instance per customer (Firebase RTDB/Auth + Cloudflare edge
services). Plans: Starter / Growth / Enterprise (Enterprise adds a 99.9% SLA). 30-day
money-back guarantee on the first payment. Sub-processors: Google (Firebase/Gemini),
Cloudflare, Supabase, Brevo, n8n. SOC 2 / ISO 27001 are roadmap, NOT certified — no
document may imply otherwise. Data: customer owns operational data, export on request,
365-day default alert retention, daily encrypted backups, PII separated and role-scoped.
Company is Tunisia-based selling internationally.

TASK
Create docs/legal/ with five Markdown drafts, each headed by a prominent banner:
"DRAFT v1 — requires review by qualified counsel before use."

1. EULA.md — end-user terms for the apps (license, acceptable use, no reverse
   engineering, AI-output disclaimer: SIAS never controls machinery and outputs are
   decision support, not safety instrumentation).
2. MSA.md — the B2B subscription agreement (services, term/renewal, fees, 30-day
   money-back, suspension, limitation of liability capped at 12 months of fees,
   indemnities, confidentiality, force majeure, governing law placeholder).
3. DPA.md — GDPR-aligned data processing addendum (roles: customer = controller,
   KubixDesiney = processor; the sub-processor list above with change-notice terms;
   TOMs annex describing the real security posture from CLAUDE.md; breach notice
   within 72h; SCCs placeholder for international transfer).
4. SLA.md — Enterprise only: 99.9% monthly uptime on the alert pipeline, measurement
   method (synthetic monitor), exclusions (customer OT network, force majeure,
   scheduled maintenance with notice), service-credit table, support response targets
   per plan (Starter email/48h, Growth priority/8h business, Enterprise 4h).
5. PRIVACY.md — storefront + product privacy policy (what is collected at purchase,
   what the product stores about supervisors incl. voiceprints for on-device
   verification and GPS presence — both role-scoped, chat logs with Kubix, retention,
   data subject rights contact).

RULES
- Mark every jurisdiction-dependent choice as [[PLACEHOLDER: ...]] (governing law,
  arbitration venue, DPO contact, company registration details).
- Consistent naming: "KubixDesiney" (provider), "SIAS — Smart Industrial Alert
  System" (service). No invented certifications, metrics, or customers; the only
  citable customer metric is AMEC Export (~30 min -> ~1-2 min alert response).
- Cross-reference consistently (MSA incorporates DPA and, for Enterprise, SLA).
- Finish by updating CLAUDE.md with a one-line pointer to docs/legal/ and a reminder
  that these are unreviewed drafts.

ACCEPTANCE
- Five files, professional tone, no lorem ipsum, no contradiction with the product
  reality documented in CLAUDE.md (especially: certifications roadmap-only, dedicated
  instances, provider-operated infrastructure).
```

---

## Not Claude Code tasks (do these yourself, 10 minutes)

1. **Gemini billing** — enable pay-as-you-go on the Google AI Studio key used by n8n,
   then in WF2 ("SIAS WF2 - Kubix Copilot Chat Agent") set the Gemini Chat Model node
   to `models/gemini-3.1-pro-preview` and republish.
2. **Webhook auth** — set an `N8N_WEBHOOK_AUTH` bearer value: add Header Auth to the
   two n8n webhooks (purchase intake + kubix chat) and put the same value as a secret
   on the store worker (`wrangler secret put N8N_WEBHOOK_AUTH --config wrangler.store.toml`).
3. **Cleanup test data** — delete the `TPI#T3ST` rows from the n8n data tables
   `sias_customers` and `sias_chats` before the first real customer.
