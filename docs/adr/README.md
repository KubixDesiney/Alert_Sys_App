# Architecture Decision Records (ADRs)

Short, immutable records of the significant architectural decisions behind SIAS —
the *why* behind the structure, so future engineers (and buyers' technical
reviewers) don't have to reverse-engineer intent. Format: Michael Nygard's ADR.

A decision, once Accepted, is not edited — it is superseded by a new ADR.

| # | Title | Status |
|---|---|---|
| [0001](0001-dual-worker-split.md) | Split Cloudflare Workers (AI/security vs notifications) | Accepted |
| [0002](0002-on-device-gbdt-forecaster.md) | On-device pure-Dart GBDT forecaster | Accepted |
| [0003](0003-dedicated-instance-model.md) | Dedicated per-customer instances | Accepted |
| [0004](0004-rtdb-rules-as-authorization.md) | Firebase RTDB + rules as the authorization boundary | Accepted |
| [0005](0005-guardian-self-healing-pipeline.md) | Provider-agnostic Guardian self-healing CI pipeline | Accepted |
| [0006](0006-data-layer-abstraction.md) | DataStore abstraction for backend portability | Accepted |

## Writing a new ADR
1. Copy the structure of any existing record; number it sequentially.
2. Fill Context → Decision → Consequences (positive **and** negative).
3. Open it in the same PR as the change it describes.
4. To reverse a past decision, add a new ADR and mark the old one `Superseded by ADR-NNNN`.
