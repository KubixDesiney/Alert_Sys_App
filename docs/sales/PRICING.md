# SIA Pricing Model

A pricing *framework* for the dedicated-instance model (each customer runs their
own backend). Numbers are illustrative starting points — set finals per region,
deal size, and competition. The structure is what matters: predictable platform
fee + per-seat, with infra pass-through, so margins are clean and buyers can model cost.

## Editions

| Edition | Best for | Platform fee | Per supervisor seat / mo | Includes |
|---|---|---|---|---|
| **Pilot** | 1 line, 2-4 weeks | waived / nominal | n/a (flat pilot fee) | full features on one line, success metrics report |
| **Line** | single production line | low base | standard | alerts, AI assignment, voice, shifts, prediction |
| **Plant** | whole factory | mid base | standard (volume tiers) | + multi-factory hierarchy, presence, shift reporting, SCADA ingestion |
| **Enterprise** | multi-plant / regulated | custom | discounted at volume | + SSO/SCIM, on-prem option, SOC 2 report access, priority Guardian SLAs |

## What drives the price
- **Seats** = active supervisors/managers (the people who claim and coordinate alerts).
- **Plants/instances** = each dedicated backend is a unit (isolation has a cost and a value).
- **Add-ons**: SCADA/historian integration, on-prem/air-gapped deployment, custom AI providers, white-label branding.

## Infra pass-through (transparent)
Because each customer brings their own Firebase + Cloudflare, the cloud bill is
**theirs** — SIA's fee is software + support, not a cloud markup. This is a
procurement advantage: no opaque "compute" line item, data stays in their account.

## Commercial levers
- Annual prepay discount (e.g. 2 months free).
- Volume seat tiers (price/seat drops past 25 / 100 / 500 seats).
- Multi-plant discount.
- Pilot-to-Line conversion credit (pilot fee applied to first quarter).

## What's explicitly NOT metered
No per-alert or per-notification fees — supervisors must never hesitate to use it.
Pricing scales with people and plants, not with how hard they lean on it.

## Positioning vs alternatives
- vs bundled SCADA alarms: SIA is the *human-response* layer; price it as downtime insurance, not another SCADA module.
- vs generic CMMS: SIA wins the live incident loop; often sold alongside, not instead.
See `docs/integrations/COMPETITIVE_POSITIONING.md`.
