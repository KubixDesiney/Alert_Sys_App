# ADR-0002: On-device pure-Dart GBDT forecaster

Status: Accepted — 2026-06 (supersedes an earlier external LSTM approach)

## Context
SIA needs next-24h machine-risk forecasting per factory. An earlier design called
a hosted LSTM (HuggingFace Space) from the worker cron. That added an external
runtime dependency, network latency, a scaler/window-fragility surface, cold-start
failures, and a per-instance hosting cost — awkward for a dedicated-instance
product that customers self-host. Alert history is tabular and modest in size,
which is the regime where gradient-boosted trees outperform deep nets.

## Decision
Replace the LSTM with a pure-Dart, second-order (Newton) gradient-boosted decision
tree engine (`lib/services/forecast/`) trained **on-device** from uploaded company
history (CSV/Excel/JSON/SQL/PDF). It trains in seconds, needs no scaler, serializes
to RTDB (`ai_forecast/model`), serves live inference on PM dashboards, grades its
own forecasts against realized alerts, and adapts daily behind a cross-dashboard
lock. The hosted LSTM path remains in code but is cron-disabled.

## Consequences
**Positive:** no external inference dependency or per-instance ML hosting; trains
fast; scale-invariant (trees); explainable; self-evaluating (precision/recall/Brier
in the console); fully owned by the customer's instance.

**Negative:** model lives in the client/RTDB rather than a managed service, so very
large histories must be sampled; training runs on the SuperAdmin's device (mitigated
by checkpoint/resume + an app-global training controller). Deep temporal patterns an
LSTM might capture are approximated via engineered lag/rolling features.
