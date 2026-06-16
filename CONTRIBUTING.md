# Contributing to SIA

This guide keeps the codebase production-grade. It applies to humans and to the
Guardian agent (ADR-0005) alike — the automated pipeline enforces the same gates.

## Ground rules (the ones that bite if ignored)
1. **Every new alert/user/worker field must land in `database.rules.json`** (type
   validator + index if queried) **in the same change**. Skipping this causes
   production permission-denial spikes (see `docs/ops/RUNBOOK.md` RB-3).
   - `push_sent` / `notificationSent` / `isCritical` are **booleans** — never write strings.
   - Push timestamp/error/skip fields are **strings** when present.
2. **Keep `cloudflare_notify_worker.js` and `worker/alerts.js` in sync** when you
   change notification fan-out.
3. **State transitions that must be exclusive** (claims) use RTDB **transactions**,
   not blind writes.
4. **Provider methods stay thin** — business rules live in services, not widgets/providers.
5. **Respect platform abstraction** — keep the `_io` / `_stub` split for platform code.
6. **Use the worker trigger queue** for side effects where offline matters; no
   fire-and-forget network calls on the hot path.
7. **Keep AI/predictive outputs explainable** — include reason + confidence fields.
8. **Update docs in the same PR** — `CLAUDE.md`, `.claude/CLAUDE.md`, relevant ADR,
   and `TESTING.md` when behavior changes.

## Local workflow
```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings   # must be clean of errors
flutter test --reporter expanded
npm ci && npm test                                      # worker (Jest) suite
node tool/smoke_test.mjs                                 # optional: synthetic health
```
Generated files (`lib/l10n/generated/**`, `lib/firebase_options.dart`, `*.g.dart`)
are excluded from analysis — edit sources/ARB and regenerate, don't hand-edit.

## Tests are required
- New pure logic (parsers, scoring, feature engineering) → unit tests under `test/`.
- New worker pure functions → Jest tests under `worker_test/`.
- New DB nodes/rules → extend `worker_test/database_rules_security.test.js`.
- Non-trivial changes include a verification step (the CI runs analyze + tests + Jest).

## Commits & PRs
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`,
  `security:`. Scope when useful: `fix(guardian): …`.
- One logical change per PR; describe risk + rollback. PRs to `main` require green
  CI and review (`docs/BRANCH_PROTECTION.md`). Code ownership: `.github/CODEOWNERS`.
- Security-relevant changes: pair with the ASVS checklist
  (`docs/security/ASVS_CHECKLIST.md`) and re-check the threat model.

## Linting
`analysis_options.yaml` enables a curated premium lint set (correctness, async/resource
hygiene, performance, consistency). Lints surface in review/IDE; CI does not fail on
infos/warnings, but **new code should land lint-clean**. Don't blanket-disable a rule —
use a scoped `// ignore:` with a reason if truly necessary.

## Releasing
See `RELEASE.md` (versioning, build, deploy) and `docs/ops/SLO.md` (error-budget
gate on release pace).
