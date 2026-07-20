# Claude Code prompts — max-out pack (targeting 99 everywhere)

Run each prompt in a fresh Claude Code session from `alertsysapp/` repo root.
Every prompt is self-contained. Run them in any order; Prompt 2 (gateway) and
Prompt 4 (Kubix upgrades) are the highest-value ones.

## Honest ceilings first (read before running anything)

Code can take every dimension a long way, but 99 is not purchasable with code
alone. What the prompts below buy, and what only you / the world can buy:

| Dimension | Now | Code-max (these prompts) | The last points require |
|---|---|---|---|
| Product & engineering | 89 | ~97 | Production mileage with real customers |
| SCADA integrations | 82 | ~95 | Field-proven deployments at real plants |
| Security & trust | 78 | ~90 | SOC 2 Type II audit (~12 months) + external pentest report |
| Onboarding & Kubix | 72 | ~93 | Gemini paid billing (10 min, you) + real-customer iteration |
| Docs & sales enablement | 72 | ~95 | Customer case studies (needs customers) |
| Deployment automation | 62 | ~92 | One rehearsed end-to-end provisioning run (you) |
| Legal pack | 55 | ~65 | Qualified counsel review + signature-ready versions |
| Billing & checkout | 40 | ~75 sales-led | Business decision: revive card rails (→90+) or stay invoice-led |

Anyone who promises you 99/99 across the board without an auditor, a lawyer,
and live customers is lying to you. This pack gets everything to its
engineering maximum; the remaining gap is time, money, and mileage.

---

## Prompt 1 — Product & engineering: 89 → ~97

```
Read CLAUDE.md first. You are in the SIAS repo (Flutter app + 8 Cloudflare
workers + Firebase RTDB). Current state: 49 Jest worker suites (pure-helper
level), ~330 Flutter tests, jest coverageThreshold floor at 60/54/62/60.

TASK — raise engineering rigor to its ceiling, in four moves:

1. Worker integration test harness. Add worker_test/integration/ using
   wrangler's unstable_dev (already a devDependency via wrangler) to boot
   cloudflare_store_worker.js and cloudflare_ingest_worker.js in-process and
   test REAL request/response flows: store landing/buy/copilot render, checkout
   validation errors, /api/kubix 400/503 paths, ingest payload normalization ->
   alert-shape assertions with a mocked RTDB (intercept fetch to
   firebaseio.com with a tiny in-memory fake). No live network. If unstable_dev
   fights the ESM setup, fall back to importing each worker's default.fetch
   directly with stubbed env + global fetch mock — the goal is route-level
   coverage, not the runtime.
2. Coverage ratchet. Get worker/ line coverage to >=75%, then raise
   jest.config.js coverageThreshold to statements 72 / branches 64 / functions
   72 / lines 72 (or the highest floor that passes with >=5% headroom). Add
   the biggest uncovered pure functions to reach it — do not lower any floor.
3. Flutter golden + logic gaps. Add widget tests for the three highest-traffic
   untested screens (check test/ for gaps vs lib/screens: supervisor dashboard
   header, admin overview cards, alert detail actions) using the existing test
   style; add unit tests for lib/utils files with zero coverage.
4. Docs truth pass. README.md and TESTING.md: verify every command against
   package.json/ci.yml, fix stale references (worker names, main files —
   wrangler.github.toml's main is cloudflare_github_worker_rpc.js, CLAUDE.md
   says otherwise: fix CLAUDE.md), add a repo map refresh, and record new test
   counts in CLAUDE.md "Testing Inventory".

ACCEPTANCE
- npm test green with the RAISED thresholds committed.
- flutter analyze --no-fatal-infos --no-fatal-warnings clean; flutter test green.
- No production code behavior changes except bug fixes discovered by new tests
  (document any in CLAUDE.md).
```

---

## Prompt 2 — SCADA integrations: 82 → ~95 (reference gateway + simulator)

```
Read CLAUDE.md ("Hybrid Industrial Connectors") and
docs/integrations/SCADA_INTEGRATION.md first. You are in the SIAS repo.

CONTEXT
SIAS ingests via edge-push (gateway POSTs to the ingest worker) or cloud-pull.
Today customers get inline gateway snippets. Gap: no packaged, supported
gateway they can run in one command, and no plant simulator for demos.

TASK — create gateway/ (a self-contained Node 20 ESM package, its own
package.json, no coupling to the worker code):

1. sias-gateway core (gateway/src/): config-driven poller/bridge that reads
   gateway/gateway.config.json ({ ingestUrl, ingestKey, sources: [...] }) and
   supports source types:
   - opcua: subscribe to nodeIds via node-opcua (optional peer dep, lazy import)
   - modbus: poll registers via modbus-serial (optional peer dep, lazy import)
   - s7: poll Siemens S7 DB addresses via nodes7 (optional peer dep, lazy import)
   - mqtt: subscribe to topics incl. Sparkplug B payload decode (mqtt +
     sparkplug-payload optional peer deps)
   - sim: built-in, zero deps — see simulator below
   Each source maps readings to the SIAS ingest contract (factory/line/station/
   machine/metric/value/unit/thresholds) with per-source mapping rules,
   batches POSTs (max 20 readings/2s), retries with backoff + on-disk queue
   (gateway/queue/) so plant network blips lose nothing, and logs one clean
   status line per cycle. Constant-memory: cap queue at 10k readings, drop-
   oldest with a warning.
2. Plant simulator (gateway/src/sources/sim.mjs): generates realistic machine
   telemetry (bearing temps with slow drift + fault spikes, vibration, line
   speed) for N machines with configurable fault injection — this is the demo
   engine: `node gateway/bin/sias-gateway.mjs --sim 6 --fault-every 90s`
   against a real instance produces a live, believable plant.
3. Packaging: gateway/bin/sias-gateway.mjs CLI (--config, --sim, --dry-run
   prints mapped payloads without POSTing), gateway/Dockerfile (node:20-slim,
   non-root user), gateway/README.md (60-second quickstart per protocol,
   air-gapped deployment notes, exactly which optional dep each protocol needs).
4. Tests (in the ROOT worker_test/ so CI runs them): gateway_mapping.test.js
   + gateway_queue.test.js covering the mapping rules, Sparkplug decode,
   batching, backoff, queue overflow — pure logic only, no sockets. Mock every
   protocol lib.
5. Conformance: worker_test/gateway_contract.test.js asserts the gateway's
   payloads satisfy the ingest worker's normalizer (import the normalization
   helpers from cloudflare_ingest_connectors.js and run gateway output through
   them).
6. Docs: extend docs/integrations/SCADA_INTEGRATION.md with the gateway
   quickstart and update CLAUDE.md (new "Reference Edge Gateway" section).

ACCEPTANCE
- npm test green including the new suites. gateway has zero REQUIRED deps
  beyond Node builtins (protocol libs are optional peers, lazy-imported with a
  helpful install message when missing).
- `node gateway/bin/sias-gateway.mjs --sim 3 --dry-run` prints valid mapped
  payloads and exits cleanly.
```

---

## Prompt 3 — Security & trust: 78 → ~90

```
Read CLAUDE.md (security sections + SECURITY_REMEDIATION_2026-07-09.md) and
SECURITY.md first. You are in the SIAS repo.

TASK — close every code-addressable trust gap:

1. Supply-chain CI. New .github/workflows/security.yml (push + PR + weekly
   cron): gitleaks (secret scanning, fail on findings), osv-scanner or npm
   audit --omit=dev with a documented allowlist file, and CycloneDX SBOM
   generation (npm sbom) uploaded as an artifact. Keep it fast (<3 min) and
   non-flaky: pin action versions.
2. Store worker headers. Add a strict Content-Security-Policy to the store
   worker's html() responses (self + fonts.googleapis.com/gstatic, no inline
   event handlers — refactor the few onclick= attributes to addEventListener
   so 'unsafe-inline' script is NOT needed; style stays inline-allowed),
   plus HSTS, X-Frame-Options already present — verify complete set. Add
   /.well-known/security.txt (contact from SALES_EMAIL var, expires +1y).
3. RTDB rules regression fuzz. Extend worker_test/database_rules_security.test.js
   (follow its existing harness style) with adversarial cases: supervisor
   attempting role self-escalation, cross-factory alert writes, users_private
   reads by another supervisor, hardware_lab writes by admin (must fail),
   connector_secrets reads by non-superadmin (must fail).
4. Threat model + whitepaper. docs/SECURITY_WHITEPAPER.md — buyer-facing,
   honest (SOC 2/ISO roadmap only, never claimed): architecture + isolation
   model, authn/authz matrix per role and per worker, data flows incl. Kubix
   chat (what leaves the instance: nothing except the chat text to the
   AI provider), encryption, backup/retention, vulnerability handling +
   security.txt, subprocessors. docs/THREAT_MODEL.md — STRIDE table over the
   real attack surfaces (store, ingest, workers, app, n8n webhooks) with
   existing mitigations and accepted risks.
5. CLAUDE.md: document the new CI workflow and docs.

ACCEPTANCE
- npm test green; security.yml passes on a clean run (verify gitleaks has no
  hits — if it finds anything real, STOP and report it, do not allowlist it).
- Store pages render identically with CSP enforced (no console violations —
  check every inline handler was converted).
```

---

## Prompt 4 — Onboarding & Kubix Copilot: 72 → ~93 (code side)

```
Read CLAUDE.md ("Store Worker" + "Kubix Copilot chat" + "Per-Customer
Provisioning") first. You are in the SIAS repo. The Kubix chat API contract:
POST /api/kubix -> {ok, reply, escalated, agent}. n8n owns the agent runtime —
do NOT try to edit n8n from here; everything below is repo-side.

TASK
1. Feedback loop. Add thumbs up/down per bot reply on /copilot (kx-feedback
   buttons). POST /api/kubix-feedback {sessionId, messageIndex, verdict:
   'up'|'down'} -> validated (reuse the chat validator style, rate-limited)
   -> forwarded to secret N8N_FEEDBACK_WEBHOOK_URL (same optional-bearer
   pattern) -> {ok:true}. Buttons show a subtle "thanks" state; verdicts are
   persisted into the localStorage transcript so they survive reload.
2. Owner-console entry point. In the Flutter app, add a "Kubix Copilot" card
   to the SuperAdmin console (follow the existing Sa.* theme + context.tr
   localization pattern; EN + FR strings) that deep-links to the copilot page
   with the instance's tenant context. Config: AppConfig gains
   ALERTSYS_COPILOT_URL dart-define (default https://sias-store URL + /copilot).
3. French copilot page. /copilot?lang=fr renders the page chrome in French
   (labels, placeholder, escalation banner, error bubbles) — a tiny inline
   dictionary, not a framework. Kubix already answers in the user's language.
4. Onboarding checklist page. New GET /welcome route on the store worker: the
   buyer-facing "what happens after you buy" page — activation steps, first
   30 minutes in the console, first integration, meet Kubix — matching the
   landing design, linked from /success and the welcome email copy in
   CLAUDE.md's WF1 description.
5. Chat analytics helper. tool/kubix_chat_report.mjs: reads a CSV export of
   the sias_chats data table (path arg), prints sessions/day, escalation rate,
   top question words, median reply length — pure Node, tested pure helpers
   in worker_test/kubix_chat_report.test.js.
6. Update wrangler.store.toml secret docs (+N8N_FEEDBACK_WEBHOOK_URL),
   /config probe, tests for the new validator + routes, CLAUDE.md.

ACCEPTANCE
- npm test green; flutter analyze + flutter test green.
- Smoke: /copilot renders feedback buttons; /api/kubix-feedback returns 400 on
  junk, 503 unconfigured; /welcome renders; French page shows French chrome.
```

---

## Prompt 5 — Docs & sales enablement: 72 → ~95

```
Read CLAUDE.md fully first — it is the source of truth. You are in the SIAS repo.

TASK — build the buyer-facing doc pack under docs/sales/ (all Markdown,
professional, honest — SOC 2/ISO are roadmap only; the ONLY citable customer
metric is AMEC Export ~30min -> ~1-2min, 100% logged):

1. docs/sales/SECURITY_OVERVIEW_ONEPAGER.md — condensed from the whitepaper
   (if docs/SECURITY_WHITEPAPER.md exists; else from CLAUDE.md): isolation
   model, auth, encryption, backups, retention, subprocessors, roadmap items.
2. docs/sales/RFP_ANSWER_BANK.md — 40+ real RFP/security-questionnaire
   questions with honest canned answers (hosting, data residency, SSO/SCIM,
   uptime, DR/RTO/RPO from the backup design, AI boundaries, offline behavior,
   integration protocols, support tiers) — mark anything uncertain
   "confirm with engineering", never invent.
3. docs/sales/DEMO_SCRIPT.md — the 25-minute demo: setup checklist (use the
   gateway simulator if gateway/ exists: --sim 6 --fault-every 90s), the
   live-alert wow moment (SCADA fault -> phone buzz -> voice claim -> AI
   assignment -> resolution -> forecast), per-persona branches (plant IT /
   maintenance / ops leadership), objection pivots.
4. docs/sales/AFTER_YOU_BUY.md — the buyer journey doc mirroring the
   provisioning flow (purchase -> 1 business day provisioning -> activation
   link -> first 30 min -> first integration -> Kubix).
5. CHANGELOG.md at repo root — reconstruct honest coarse-grained history from
   CLAUDE.md's dated sections (2026-05 through today), Keep-a-Changelog format,
   then a note that it is maintained forward.
6. README.md: rewrite the top half as the product front door (what SIAS is,
   architecture diagram in Mermaid, quickstart per audience: developer /
   IT buyer / sales), keep build commands accurate per package.json/ci.yml.
7. Add a docs index: docs/README.md linking every doc with one-line purposes.
   Update CLAUDE.md pointing to the pack.

ACCEPTANCE
- Zero contradictions with CLAUDE.md (spot-check every number you cite).
- No invented customers, metrics, or certifications anywhere.
```

---

## Prompt 6 — Deployment automation: 62 → ~92

```
Read CLAUDE.md ("Per-Customer Provisioning") and docs/PROVISIONING.md, then
tool/provision_instance.mjs and tool/provision_owner.mjs. You are in the SIAS
repo.

TASK — make provisioning verifiable, reversible, and CI-capable:

1. Post-provision verification. tool/verify_instance.mjs --tenant <slug>
   [--db-url <url>]: probes every tenant worker's /config endpoint (reads the
   URLs from deploy/tenants/<tenant>/provision-summary.json), checks the RTDB
   REST /.json?shallow=true responds, confirms rules deployed (a read that
   MUST be denied without auth actually 401s), prints a green/red table, exit
   code reflects health. Wire it as the final step of provision_instance
   (non-dry-run) and as npm run verify:instance.
2. Teardown. tool/teardown_instance.mjs --tenant <slug>: DRY-RUN BY DEFAULT;
   with --execute deletes the tenant workers (wrangler delete --config each
   tenant config), prints the manual steps it will NOT do (Firebase project
   deletion is manual and irreversible — say so loudly), archives
   deploy/tenants/<tenant>/ to deploy/tenants/_archived/<tenant>-<date>/.
3. Tenant registry. deploy/tenants/registry.json (git-ignored) maintained by
   provision/teardown: tenant, projectId, createdAt, status, workerUrls.
   tool/list_tenants.mjs prints it as a table.
4. Backup drill. tool/backup_drill.mjs --tenant <slug>: fetches the latest R2
   snapshot listing via the tenant backup worker's status endpoint (add a
   GET /config backup-info if the backup worker lacks one — check
   cloudflare_backup_worker.js), verifies the newest snapshot is <36h old,
   exit code accordingly. This is the "are backups actually happening" check.
5. CI option. .github/workflows/provision-tenant.yml: workflow_dispatch with
   tenant + project-id inputs that runs provision_instance --execute using
   repo secrets, then verify_instance. Gate it behind an environment named
   "provisioning" (manual approval) so a stray click cannot create infra.
6. Tests for every new pure helper (summary parsing, registry ops, probe
   result classification) in worker_test/, no live network in tests.
   Update docs/PROVISIONING.md + CLAUDE.md.

ACCEPTANCE
- npm test green. All new CLIs support --dry-run (or are read-only) and print
  exact plans. Nothing touches root wrangler.*.toml files.
- verify_instance against a FAKE summary file with unreachable URLs exits
  non-zero with a readable red table (test this path).
```

---

## Prompt 7 — Legal pack: 55 → ~65 (the ceiling until counsel signs)

```
Read docs/legal/*.md and CLAUDE.md ("Legal Documents" + "Store Worker") first.
You are in the SIAS repo. These are UNREVIEWED drafts — nothing you do here
publishes them.

TASK
1. Consistency linter. tool/legal_lint.mjs: parses docs/legal/*.md and fails
   on: unresolved [[PLACEHOLDER:...]] (lists them), company/product name
   variants (only "KubixDesiney" and "SIAS — Smart Industrial Alert System"
   allowed), forbidden claims (regex for "SOC 2 certified", "ISO 27001
   certified", "guarantee" outside the SLA/money-back contexts), cross-
   reference integrity (MSA must reference DPA + SLA where stated). npm run
   legal:lint + a step in ci.yml that runs it (non-blocking warning job).
2. Store /legal routes, gated OFF. Add GET /legal, /legal/privacy, /legal/terms
   to the store worker rendering the markdown (tiny renderer, reuse the
   copilot one server-side) ONLY when env LEGAL_PUBLISH = "true"; otherwise
   404. Footer links appear only when enabled. This makes counsel-approved
   publishing a one-var flip instead of a code change.
3. Counsel handoff package. docs/legal/COUNSEL_BRIEF.md: one page for the
   lawyer — what the product does, deployment/data model, jurisdictions in
   play (Tunisia seller, international B2B buyers), the exact list of
   [[PLACEHOLDER]] decisions needed from them, and the questions you want
   answered (governing law recommendation, arbitration venue, GDPR rep
   requirement, TN export/invoice specifics).
4. Tests for the lint helpers; CLAUDE.md update.

ACCEPTANCE
- npm test green; legal:lint currently passes except placeholders, which it
  reports as a counted warning list (that is its job until counsel resolves
  them). /legal 404s without the env flag.
```

---

## Prompt 8 — Billing & checkout: 40 → ~75 (invoice-led, no card rails)

```
Read CLAUDE.md ("Store Worker") and cloudflare_store_worker.js first. You are
in the SIAS repo. Business context: card rails (Stripe/ClicToPay) exist in
code but are PARKED — do not revive, remove, or modify them. The active sales
motion is invoice-led pilots. Money must never be collected by anything you
build here.

TASK — make the invoice-led motion self-serve up to the signature:

1. Quote request flow. Repurpose the buy CTA path: /buy keeps the intake form
   but the submit action becomes "Request a quote" when env SALES_MODE =
   "quote" (default "quote"; "card" restores current behavior). In quote mode
   POST /api/quote validates the same intake shape (+ optional phone,
   preferred currency USD/TND/EUR), generates the tenant code, forwards to
   N8N_INTAKE_WEBHOOK_URL with type "quote_requested" (n8n dedupes on eventId
   "qr_" + crypto.randomUUID()), and shows a success state: "Your tailored
   quote lands in your inbox within 1 business day" + Kubix chat link.
2. Quote PDF generator. tool/generate_quote.mjs --company --contact --email
   --plan --billing --currency [--discount-pct] [--valid-days 30]: renders a
   branded quote PDF (pdfkit or the repo's existing PDF approach — check what
   lib/services/*pdf* uses server-side; if nothing fits Node, use pdfkit as a
   devDependency) with plan pricing from a shared pricing module — EXTRACT
   PLAN_CATALOG into pricing.mjs imported by both the store worker and this
   tool so prices live in exactly one place. Output
   quotes/SIAS-Quote-<tenant>-<date>.pdf (git-ignored dir) + a JSON sidecar.
3. Pipeline tracking fields. The quote_requested payload includes everything
   WF1 needs to later convert to a customer record (same customer shape as
   purchase_completed) so the n8n side stays one workflow.
4. Landing copy: pricing cards' buttons read "Get a quote" in quote mode
   (server-rendered from env, no client flicker); FAQ entry about invoicing
   (bank transfer, USD/TND/EUR, net-15) replacing card-specific wording when
   in quote mode.
5. Tests: quote validator, payload builder, pricing module round-trip
   (worker and tool import identical figures), PDF tool smoke (file exists,
   >10KB, sidecar fields correct). Update wrangler.store.toml ([vars]
   SALES_MODE = "quote"), /config probe, CLAUDE.md.

ACCEPTANCE
- npm test green. With SALES_MODE=quote: /buy renders quote flow, /api/quote
  validates + forwards; with SALES_MODE=card everything behaves exactly as
  today (regression-check the existing store tests still pass untouched).
- No Stripe/ClicToPay code paths altered.
```

---

## Not runnable by Claude Code (the same four, still yours)

1. Gemini paid billing + model bump to `models/gemini-3.1-pro-preview` in WF2.
2. Counsel review of docs/legal/ (send them COUNSEL_BRIEF.md from Prompt 7).
3. One rehearsed `provision:instance --execute` run on a scratch GCP project.
4. The SALES_MODE decision: stay "quote" (invoice-led) or flip rails back on.

n8n-side work (Kubix runtime, WF1b activation email automation, feedback
workflow receiving N8N_FEEDBACK_WEBHOOK_URL) belongs to the Cowork session,
not Claude Code — ask for it there.
