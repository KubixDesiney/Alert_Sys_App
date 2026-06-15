# Data layer (additive — not yet wired)

A backend-agnostic abstraction over SIA's core alert lifecycle so the app can run
on the cloud (Firebase) or fully on-prem (PocketBase, see `deploy/onprem/`).

- `data_store.dart` — the `DataStore` interface (v1: watch/claim/resolve/return/critical/role).
- `firebase_data_store.dart` — delegates to the existing `AlertService` (cloud parity, zero behaviour change).
- `pocketbase_data_store.dart` — air-gapped path (REST writes + polled reads; SSE later).
- `data_store_factory.dart` — picks the backend from `--dart-define=SIA_BACKEND`.

Nothing imports this yet. Adoption plan: switch `AlertProvider`/services to depend on
`DataStore` (via the factory) instead of calling Firebase directly. Tests:
`test/services/data/pocketbase_data_store_test.dart`.
