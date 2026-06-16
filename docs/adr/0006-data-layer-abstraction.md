# ADR-0006: DataStore abstraction for backend portability

Status: Accepted — 2026-06

## Context
ADR-0004 commits the hosted product to Firebase RTDB. Some prospects (air-gapped
plants, strict on-prem mandates) cannot use Firebase at all. We needed a way to
target an alternative backend without forking the app or rewriting every service.

## Decision
Introduce an additive data-layer abstraction (`lib/services/data/`): a `DataStore`
interface with a Firebase adapter (default, unchanged behavior) and a PocketBase
adapter for on-prem. The abstraction is *additive* — existing services keep working
against Firebase; the adapter is selected at the edge. The on-prem deployment
scaffold (`deploy/onprem/`: Caddy + PocketBase + worker-runner, plus a rules port
and an RTDB→PocketBase migration tool) implements the alternative target.

## Consequences
**Positive:** opens air-gapped/on-prem deals without abandoning the Firebase-first
hosted product; the migration tool + rules port give a concrete path; no regression
risk to existing Firebase instances (additive).

**Negative:** two backend adapters to test and keep at feature parity; PocketBase
lacks some RTDB semantics (the rules port re-implements authorization), so the
on-prem path trails the hosted path and must be validated per release. Documented
in `ONPREM.md` and `deploy/onprem/RULES_PORT.md`.
