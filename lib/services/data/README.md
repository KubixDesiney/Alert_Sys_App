# Data layer (wired)

A backend-agnostic abstraction over SIAS's core alert lifecycle so the app can run
on the cloud (Firebase) or fully on-prem (PocketBase, see `deploy/onprem/`).

- `data_store.dart` — the `DataStore` interface (v2: watch all/usine/supervisor,
  pagination, create, claim, resolve, suspend/return, critical+note, comments,
  role lookup, audit).
- `firebase_data_store.dart` — pure delegation to the existing `AlertService` /
  `AuditService` (cloud parity; the delegation contract is pinned by
  `test/services/data/firebase_data_store_test.dart`).
- `pocketbase_data_store.dart` — on-prem path (REST writes + polled reads; the
  worker-runner pushes LAN SSE wake-ups). Imports zero Firebase packages.
- `data_store_factory.dart` — picks the backend from `--dart-define=SIAS_BACKEND`
  and exposes `isPocketBaseBackend` for gating Firebase-only side paths.
- `onprem_session.dart` — who-am-I for on-prem builds (set by
  `PocketBaseAuthService`); Firebase builds keep using FirebaseAuth.

## How it is wired

`ServiceLocator.init()` builds one `DataStore` (`createDataStore()`) and injects it
into `AlertActionsService` and `AlertStreamService`; `AlertProvider` therefore
routes claim / resolve / suspend / critical / comment through it, and the admin
"Simulate alert" dialog creates alerts through it. Firebase-only side effects
(admin suspend notification, Cloudflare AI-retry trigger, FCM new-alert fan-out,
`notifyAllUsers` on critical) are gated on `backendName == 'firebase'` — on-prem
those jobs belong to the worker-runner (`deploy/onprem/worker-runner/`).

## Honest coverage table

| Flow | firebase | pocketbase |
|---|---|---|
| Watch alerts (PM / usine / supervisor+assistant) | yes (RTDB streams) | yes (polling, 5s) |
| Create / claim / resolve / suspend / critical / comments | yes | yes |
| Pagination (older alerts) | yes | yes |
| Audit trail | `audit_log` RTDB node | `audit_logs` collection |
| Collaborator-shared alert visibility | yes | **not yet** (v3) |
| Help / collaboration / shift flows | yes (Firebase services) | **not yet** (v3) |
| Voice, FCM push, AI worker triggers | yes | n/a — LAN SSE via worker-runner |

Claim concurrency: Firebase uses RTDB transactions; PocketBase v1 relies on the
worker-runner being the only auto-assigner plus last-write-wins on manual claims —
a server-side claim guard hook is listed in `ONPREM.md` as follow-up work.

Tests: `test/services/data/` — PocketBase REST contract, Firebase delegation
contract, `AlertActionsService` lifecycle against both backends, and a widget
test driving `AlertProvider` end-to-end on both backends
(`fake_data_store.dart` is the reusable in-memory backend double).
