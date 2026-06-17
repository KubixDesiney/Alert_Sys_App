# Mutation Testing & E2E Coverage — SIA

Line coverage tells you which code *ran* during tests; it does not tell you whether
the tests would *catch a bug*. SIA closes that gap two ways: end-to-end tests that
exercise the worker request lifecycle, and a zero-dependency mutation tester that
proves the suite actually fails when logic changes.

## End-to-end worker tests
Beyond the pure-function unit tests, these drive the real `fetch` handlers with a
mock `env` and a stubbed global `fetch` (no network):

- `worker_test/ingest_e2e.test.js` — SCADA ingestion lifecycle: auth gate, normal
  reading suppressed, critical reading → RTDB alert create + notify trigger,
  storm dedup, batch payloads, invalid-JSON handling. (Verified: 9/9.)
- `worker_test/github_e2e.test.js` — GitHub proxy: CORS preflight, bearer auth,
  `/config`, `/dispatch` forwarding a `repository_dispatch` with the server-side
  token, `/runs` mapping, 404s.

These assert the actual HTTP contract the app and gateways depend on, not just
internal helpers.

## Mutation testing (`tool/mutation_test.mjs`)
Zero external deps. It applies a curated operator set to one target file at a time,
runs a test command per mutant, and reports the **mutation score** (% of mutants the
tests killed). The original file is always restored, even on crash.

Operators: `>=`↔`>`, `<=`↔`<`, `===`↔`!==`, `&&`↔`||`, `true`↔`false`.

Run it:
```bash
node tool/mutation_test.mjs \
  --target tool/guardian_preflight.mjs \
  --cmd "npm test -- worker_test/guardian_preflight.test.js" \
  --floor 55
```
`--floor N` makes it a gate (non-zero exit if the score is below N). `--max N` caps
mutant count for a quick pass; `--bail` stops at the first survivor.

Output example:
```
[mutation] tool/guardian_preflight.mjs: 18 mutants, running "..." for each
..............S...
[mutation] killed 17/18  score 94.4%
[mutation] survivors (test gaps):
  line 42: ||->&&
```
A **survivor** is a real test gap: the code changed and no test noticed — add an
assertion that pins that behavior, then re-run.

`generateMutants()` is pure and unit-tested in `worker_test/mutation_test.test.js`.

## In CI
`.github/workflows/quality.yml` runs three coverage gates:
1. **worker-coverage** — Jest line/branch coverage with the `jest.config.js` threshold (60% floor).
2. **mutation** — `npm run test:mutation`, gated at a mutation-score floor.
3. **flutter-coverage** — `flutter test --coverage`.

## How to extend
Point the mutation tester at any pure module with a fast suite (scoring, parsers,
feature engineering). Keep targets pure and suites fast — mutation runs the suite
once per mutant, so a 1-second suite over 20 mutants is ~20s.

## Honest limits
The operator set is intentionally small and may mutate inside strings/comments
(those mutants usually survive and read as false gaps — ignore them or narrow the
target). It is not a replacement for Stryker on a large JS codebase, but it is
dependency-free, fast, and good enough to keep the Guardian core honest.
