# Vendor Technical Due-Diligence Memo — SIAS (Smart Industrial Alert System)

**Prepared by:** Principal/Chief Engineering reviewer (gatekeeper sign-off for purchase)
**Subject:** SIAS — Smart Industrial Alert System, v1.2.1 (vendor: KubixDesiney)
**Date:** 2026-06-27
**Verdict:** **5.5 / 10 — Conditional. Real product, not yet a trustable purchase.**
**Recommendation:** Do **not** approve for tier-1 procurement today. **Approve a paid pilot** with a design-partner customer once the four P0 items below are closed and the product is contractually positioned as *advisory*.

---

## 1. Executive summary

SIAS is a genuinely substantial piece of engineering — ~100,000 lines of Flutter across 202 files, 74 test files, a real on-device machine-learning forecaster, a hardened multi-worker Cloudflare edge backend, and a hybrid SCADA/PLC/MQTT/historian ingestion layer. The documentation is unusually honest about what is and isn't shipped. For what appears to be a solo or very small team, this is impressive and well above prototype quality.

It is **not**, however, something a serious industrial company can buy and trust today. The blockers are not about code volume — they are about **trust, change-control, and operations**:

1. An **autonomous AI agent that pushes to `main` and auto-deploys to production** with no human approval (only AI-reviews-AI).
2. **Database rules that permit unauthenticated writes** to the primary `alerts` table.
3. **Bus factor of one** — everything defaults to a single personal Cloudflare account.
4. **No certifications, no SLA, manual onboarding, undefined unit economics**, and an undecided answer to the most important question of all: *is this alert path advisory, or is the plant relying on it for safety?*

None of these are fatal to the *product*. They are fatal to the *purchase decision* until fixed. All are fixable.

---

## 2. Scope and method

This review is based on direct inspection of the repository, not the vendor's self-reported handoff notes. Reviewed: `database.rules.json` (527 lines), all 7 `wrangler.*.toml` worker configs, `cloudflare_ingest_connectors.js`, `tool/autonomous_bugfix_agent.mjs`, `.github/workflows/*` (11 workflows), `lib/config/` (app + company config), `PROVISIONING.md`, `ONPREM.md`, `COMPLIANCE.md`, `SECURITY.md`, `TERMS.md`, `.gitignore`/`.gitleaks.toml`, the forecast ML module, and the test inventory. Claims in the vendor docs were cross-checked against code wherever practical.

---

## 3. Scorecard

| Category | Score | Read |
|---|---|---|
| Engineering depth & breadth | 8 / 10 | Large, real, multi-platform, multi-service |
| AI / ML substance (on-device GBDT) | 7 / 10 | Genuine gradient-boosted forecaster with tests |
| Documentation & honesty | 7 / 10 | Extensive; flags unshipped work; some contradictions |
| Data-isolation model (per-tenant) | 7 / 10 | Strongest model on paper; manual in practice |
| Code quality & maintainability | 6 / 10 | Low TODO density; but sprawl + single maintainer |
| App & database-rules security | 5 / 10 | Good instincts; anonymous-write hole; secrets in RTDB |
| Commercial / trust readiness | 4 / 10 | No SLA, no references, solo vendor |
| Compliance & certifications | 3 / 10 | Honest, but uncertified; biometric-data gap |
| Production reliability & SLA | 3 / 10 | Personal account, cron-based, single points of failure |
| Ops & scale (provisioning, unit econ) | 3 / 10 | Manual onboarding; cost model undefined |
| **Weighted overall** | **5.5 / 10** | **Conditional** |

---

## 4. Findings by domain

Severity key: **P0** = blocks any sale · **P1** = blocks tier-1 / formal procurement · **P2** = credibility polish.

### A. Multi-tenancy & data isolation — *strong model, manual execution*
- **Found:** `PROVISIONING.md` defines a **dedicated-instance-per-company** model: each customer gets its own Firebase project and its own Cloudflare workers (`company_config.dart`, `companies/example.input.json`). This is the strongest possible isolation — physically separate deployments, no shared data path.
- **Risk:** The model is **documented but not yet operated**. The live deployment is a *single shared instance* on a personal account (`.firebaserc` → `alertappsys`; worker URLs → `aziz-nagati01.workers.dev`). Onboarding each tenant is a **manual ritual** (`flutterfire configure`, copy toml files, `wrangler secret put` by hand). One mistake ships the wrong customer's Firebase config. **(P1)**
- **Recommend:** Build a provisioning control plane that automates project creation, secret injection, worker deploy, and per-build config. Until then, every new tenant is an artisanal, error-prone deploy.

### B. Security — *mature hygiene, two real holes*
- **Found (good):** `gitleaks` config that correctly understands Firebase client keys are public-by-design; CodeQL + `security.yml` + `npm audit` in CI; `backups/` is gitignored and labeled "may contain PII"; deny-by-default root rules (`.read:false/.write:false`); role-gated `connector_secrets`, `scim`, `provisioning`, `ai_model_config` (most worker-write-only).
- **Found (hole 1 — P0):** `alerts/$alertId` permits **unauthenticated create** when the payload matches a shape (`auth == null && !data.exists() && newData.hasChildren([...])`). Anyone who learns the RTDB URL can inject or spoof alerts and flood the primary operational table. The worker ingest path *is* properly key-authenticated (timing-safe compare, per-connector keys), but the raw rule bypasses it.
- **Found (hole 2 — P1):** Third-party LLM API keys are stored at `ai_model_config/$agent/apiKey`, readable by the `superadmin` client role — a client-reachable secret. `connector_secrets` (PLC/historian tokens) live in RTDB too; acceptable if strictly worker-read, but verify no client path reads them.
- **Found (legal/biometric — P1):** The app stores **voiceprints** (`users/{uid}/voiceprint`) for speaker verification. That is **biometric data** (GDPR Art. 9 special category; US BIPA). Requires a DPIA, explicit consent, and a retention/erasure policy. Not addressed in `PRIVACY.md`/`COMPLIANCE.md`.
- **Recommend:** (1) Replace the anonymous-create rule with a token-gated ingest boundary only. (2) Move LLM/connector secrets to a worker-only store the client never reads. (3) Add a biometric-data policy or make voice auth opt-in and off by default.

### C. Change management / autonomous AI deploy — *the disqualifier (P0)*
- **Found:** `tool/autonomous_bugfix_agent.mjs` has a **direct-to-`main`** mode (`AGENT_DIRECT_MAIN_PUSH_ALLOWED=1`) that, after an *OpenAI review gate*, pushes to `main` and **auto-deploys** Firebase Hosting + Cloudflare workers. CI (`ci.yml`) auto-deploys all workers on every `main` push and has an AI `/auto-fix-full` path for failing tests. A human is only involved on *rejection* (a GitHub issue is opened).
- **Risk:** For a system whose only job is raising alerts in a plant, "AI wrote the code, AI reviewed the code, AI shipped the code to production, no human approved it" is **categorically unacceptable** to any competent industrial buyer's security/change-management review. This single item fails the deal regardless of everything else.
- **Recommend:** Disable autonomous production deploy. Require a human approval gate (protected branch + mandatory human PR review) for anything touching `main` or production infra. Keep the AI agent as a *PR-proposing* assistant only.

### D. Reliability & alert delivery — *undefined contract (P0/P1)*
- **Found:** New-alert delivery relies on FCM push plus a **1-minute cron fallback** across multiple workers (`alert-notifier`, `alertsys` notify, `alertsys-ingest` all on `* * * * *`). No redundancy if the single Cloudflare account, a worker, or the (gated) HuggingFace LSTM space degrades. No documented delivery-latency SLO or end-to-end alert-delivery guarantee.
- **Risk:** An "industrial alert system" where a missed or delayed notification is possible — with no SLA — is fine for *advisory* use and unacceptable for *safety-relied-upon* use. The product hasn't declared which it is. **(see §5)**
- **Recommend:** Define and measure an alert-delivery SLO (e.g., p99 < N seconds), add a redundant delivery path, and state the guarantee in the contract.

### E. Operations & vendor risk — *bus factor 1 (P0)*
- **Found:** All default infrastructure runs on one personal Cloudflare tenant (`aziz-nagati01.workers.dev`) and one Firebase project. No org account, no on-call rotation, no status page beyond `uptime.yml`, no evidence of a second maintainer.
- **Risk:** Industrial buyers veto single-person vendors for anything touching operations. If one person is unavailable, the customer's alerting is unsupported. This is a **procurement veto**, independent of code quality.
- **Recommend:** Move infra to a KubixDesiney **organization** cloud account with role-separated access; document a support model, on-call, and escalation; ideally show a second engineer.

### F. Cost model / unit economics — *the "we just pay Cloudflare" myth (P1)*
- **Found:** The stated mental model ("we pay for Cloudflare workers and that's it") is incorrect. Per customer you also incur **Firebase Blaze** (Realtime Database at SCADA alert volume is metered and can be significant), **Workers AI / Llama inference** on every relevant cron, and **3 every-minute crons + 1 five-minute + 1 daily backup per tenant** (7 workers total). If each tenant has its own Firebase project, **who owns and pays that billing account** — you or the customer?
- **Risk:** Margins are undefined. A few high-volume plants could make a flat monthly price unprofitable.
- **Recommend:** Build a per-tenant cost model (RTDB ops, Workers AI calls, FCM, egress) and set pricing tiers by alert volume / machine count. Decide explicitly who holds Firebase billing.

### G. Compliance & legal — *honest but uncertified (P1)*
- **Found (good):** `COMPLIANCE.md` maps to SOC 2 criteria but truthfully marks everything "Partial/Planned/Open items" — **no false certification claims.** `TERMS.md` is a real B2B agreement with an "AS IS" warranty disclaimer and a liability cap; a pen-test scope is drafted.
- **Risk:** No SOC 2 Type II, no ISO 27001, no IEC 62443 alignment. That blocks most tier-1 procurement checklists today. Separately, an "AS IS / no warranty" disclaimer will be heavily contested if the product is positioned anywhere near safety.
- **Recommend:** Start SOC 2 Type I (Vanta/Drata), commission the drafted pen test, and align the warranty/liability language with the declared criticality tier (§5).

### H. Code quality, tests, docs — *good signal, fixable noise (P2)*
- **Found (good):** Only ~11 TODO/FIXME markers across 100K lines; 38 Dart + 36 worker test files; 11 CI workflows incl. CodeQL/quality/uptime; stale product-name cleanup is complete.
- **Found (noise):** Two `CLAUDE.md` files contradict each other on whether the monolithic worker is deployed or deleted; commit history is sloppy ("new", "new new", "not interested"); a junk file (`__synctest.js`) sits in the repo root.
- **Recommend:** Reconcile the docs, clean the history before any buyer sees the repo, remove junk. Cheap, high-impact for due-diligence optics.

### I. Feature substance vs theater — *mixed (P2)*
- **Found:** The ML forecaster (`lib/services/forecast/`, with tests) and the connector engine are **real**. But there is heavy surface area — SuperAdmin console, "AI Agent Fleet," a 3D Guardian pipeline, holographic war-room monitors, a Hardware Lab — and the vendor's own notes admit at least one agent feature was "pure UI… zero behavior behind it." For a solo maintainer this is a security and maintenance liability.
- **Recommend:** Harden a small, real core (intake → assign → notify → resolve → forecast). Mark or remove cosmetic features; every screen is attack surface someone has to keep secure.

---

## 5. The decision you haven't made: advisory vs safety-relied-upon

You answered "I don't know" to whether the plant relies on SIAS for safety. **This is the most important commercial and engineering decision in the entire product**, and it must be made before you sell.

| | **Advisory** (recommended) | **Safety-relied-upon** |
|---|---|---|
| What it means | A faster pager. The plant keeps its existing certified SCADA alarms; SIAS speeds human response. | The plant depends on SIAS to catch real faults. |
| Engineering bar | Current architecture is broadly appropriate. | Functional-safety rigor: IEC 61508 / 62443, redundancy, fail-safe, certified delivery, formal verification. |
| Liability | Manageable; "AS IS" defensible if clearly advisory. | Severe. A missed alert that causes harm is your exposure. An "AS IS" clause will not hold. |
| Who can deliver it | A small vendor can. | A solo/small vendor realistically **cannot** today. |

**Recommendation:** Position SIAS **explicitly and contractually as advisory** — "a faster, smarter notification layer on top of your existing alarms, not a replacement for your safety systems." Put that sentence in the sales deck, the docs, and the contract. Going safety-relied-upon is a multi-year, capital-intensive, liability-heavy undertaking that does not fit the current team or architecture. Advisory is honest, sellable, and keeps you out of a courtroom.

---

## 6. Remediation roadmap

**P0 — before you sell anything (deal-blockers):**
1. Put a human in the loop — disable AI auto-merge and auto-deploy to production.
2. Close the unauthenticated `alerts` write rule; require a signed gateway token at the ingest boundary.
3. Move infrastructure to a KubixDesiney org cloud account, off the personal one.
4. Define an alert-delivery SLO + a redundant delivery path; remove single points of failure.
5. Contractually declare SIAS as advisory (see §5).

**P1 — before any tier-1 / formal procurement:**
1. Automate per-tenant provisioning into a control plane.
2. Start SOC 2 Type I and commission the already-scoped penetration test.
3. Add a biometric-data policy (DPIA, consent, retention) for voiceprints; default voice auth off.
4. Move LLM/connector secrets out of client-readable RTDB.
5. Build the per-tenant cost model; decide who owns Firebase billing.
6. Stand up incident response, on-call, a real status page, and tested disaster recovery.

**P2 — credibility polish:**
1. Reconcile the two `CLAUDE.md` files and contradictory worker docs.
2. Clean commit history and remove junk files before sharing the repo.
3. Trim or clearly label cosmetic features as roadmap, not shipped.
4. Ship the on-prem / air-gapped path many plants will mandate (currently a scaffold + plan).

---

## 7. Buy / no-buy recommendation

- **Tier-1 industrial company, formal procurement:** **No-buy today.** Fails on certifications, single-person operations, autonomous production deploy, and anonymous alert writes. Revisit after P0 + P1.
- **SMB manufacturer or friendly design partner, paid pilot:** **Conditional buy.** Acceptable *if* P0 items are closed and the product is sold as advisory, ideally with a pilot SOW, a named support contact, and a data-processing addendum covering the biometric voiceprints.
- **As an acquisition / acqui-hire of the engineering:** the underlying build quality and ML work are a genuine asset; the gaps are organizational, not talent.

---

## 8. Open questions for the vendor

1. Is each customer truly on a separate Firebase project today, or is everyone on the shared `alertappsys` instance? Show me one isolated tenant end-to-end.
2. Who owns and pays each customer's Firebase billing account?
3. What is the measured end-to-end alert-delivery latency, and what happens if the Cloudflare account or a worker is down?
4. Is the autonomous deploy agent ever enabled against production, or only in dry-run? Prove `main` is branch-protected.
5. Where are voiceprints stored, for how long, and under what consent? Can a customer disable voice auth entirely?
6. What is the support model — hours, on-call, escalation — and how many engineers can ship a production fix?

---

*This memo reflects the state of the repository at review time. The strengths are real; the blockers are organizational and fixable. Close the P0 list and re-submit for a pilot sign-off.*
