# ADR-0004: Firebase RTDB + rules as the authorization boundary

Status: Accepted — 2026-06

## Context
SIA is real-time first: alerts, claims, presence, and AI decisions must stream to
many clients with low latency and survive flaky factory networks. The team needed
a store that offers live sync, offline persistence, and a declarative authorization
model without standing up a bespoke backend per customer.

## Decision
Use Firebase Realtime Database as the primary operational store, with
`database.rules.json` as the **single authorization boundary**: deny-by-default,
role read server-side from `users/{uid}/role`, field-level validators (types,
ranges), and indexed query paths. Clients read/write directly where rules allow;
Workers use a service-account JWT and ETag transactions for privileged/locked
operations. Claim exclusivity uses RTDB transactions, not blind writes.

## Consequences
**Positive:** real-time sync + offline cache for free; authorization is declarative,
auditable, and unit-tested (`worker_test/database_rules_security.test.js`); no
custom auth server to operate per instance.

**Negative:** business rules split between rules-file validators and app/worker code
— every new field must be added to validators in the same change (enforced via
`CONTRIBUTING.md` and RB-3). RTDB query expressiveness is limited, so some access
patterns require denormalized index nodes (e.g. `collaboration_alerts/{supervisorId}`).
A portability path is provided by ADR-0006 for customers who cannot use Firebase.
