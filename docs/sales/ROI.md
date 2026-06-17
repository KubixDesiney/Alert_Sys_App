# SIA ROI Model

A transparent way to size value for a prospect. Plug in their numbers; every input
is something a plant manager can estimate. All figures below are **illustrative**.

## The value levers
1. **Faster response** — SIA cuts the time from alert to a technician acting (mobile
   dispatch + AI routing + voice claim) vs radios/on-call lists.
2. **Fewer/shorter unplanned stoppages** — prediction + faster response shrink
   downtime minutes.
3. **Labor efficiency** — less time spent finding who's free / coordinating.

## Core formula (annual downtime savings)
```
annual_savings =
    incidents_per_year
  * minutes_saved_per_incident
  * downtime_cost_per_minute
```
Optionally add prevented incidents from prediction:
```
prevention_savings = prevented_incidents_per_year * avg_downtime_minutes * downtime_cost_per_minute
```

## Worked example (mid-size plant)
| Input | Value |
|---|---|
| Unplanned incidents / year | 1,200 |
| Response time saved / incident | 8 min |
| Downtime cost / min | $150 |
| Prevented incidents / year (prediction) | 60 |
| Avg downtime / prevented incident | 45 min |

- Response savings = 1,200 × 8 × $150 = **$1,440,000 / yr**
- Prevention savings = 60 × 45 × $150 = **$405,000 / yr**
- **Total modeled value ≈ $1.85M / yr**

Against a platform + seats cost typically in the low-to-mid five/six figures per
year (see `PRICING.md`), payback is usually **weeks**, and even a conservative
50% haircut on the inputs leaves a strong multiple.

## How to run it with a prospect
1. Get their incident count and a credible downtime cost/min (finance usually has it).
2. Be conservative on "minutes saved" — anchor on the pilot's measured delta, not a guess.
3. Use the pilot to replace estimates with **their** real before/after numbers, then
   extrapolate to all lines/plants.

## Soft value (mention, don't model)
Safety (faster response to Safety-type alerts), supervisor morale (less chaos),
audit-readiness (compliance pack), and resilience (self-healing platform).

## Honesty note
Don't oversell prevention — the forecaster improves with data and grades itself, so
present prediction value as upside that grows, with response-time savings as the
floor you can defend from pilot data.
