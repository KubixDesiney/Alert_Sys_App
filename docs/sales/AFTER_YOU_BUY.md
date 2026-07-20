# After You Buy — The SIAS Onboarding Journey

Buyer-facing. Mirrors the provisioning flow exactly (`docs/PROVISIONING.md`
is the internal counterpart; the public web version is the storefront's
`/welcome` page). Send this as the "what happens next" attachment with every
quote and order confirmation.

## Day 0 — you order

Whether you paid by card or confirmed an invoice-led order: the moment the
order is confirmed, provisioning of your **dedicated instance** starts — your
own isolated database, authentication realm, and edge services, plus your
named **Kubix Copilot** agent (you'll recognize it by your tenant code, e.g.
`NSW#7K2F`, printed on your receipt/quote).

## Within 1 business day — activation

Your designated Owner receives the **activation email**:

- It contains a **one-time activation link** (expires in about an hour — we
  resend on request). We never send passwords by email.
- Click it, set your password, enable MFA. You land on your SuperAdmin
  console. The instance is yours.

*Prepare in advance:* decide who the Owner is; allow-list our sender domain
so the email never lands in spam.

## Your first 30 minutes — console setup

From the SuperAdmin console, in order:

1. **Factory hierarchy** — plants → conveyor lines → stations.
2. **Alert types** — keep the standard set or define your own vocabulary
   (colors, icons, severities); everything downstream adapts, including the
   forecaster.
3. **Production Manager accounts** — provision your PMs; they get the same
   activation-link flow.
4. **Supervisor phones** — supervisors install the app, sign in, and enroll
   voice (under two minutes each). From here, a raised alert buzzes the right
   phones and can be claimed by voice from a locked screen.

Kubix walks your team through each step in English or French — it already
knows your plan, your tenant code, and your configuration.

## Same week — first integration

Open **Infrastructure → Connectors**, pick your protocol (OPC-UA, Modbus,
Siemens S7, MQTT/Sparkplug, REST, PI, Ignition):

- The console generates a ready-to-run gateway config with your ingest key
  baked in; the packaged gateway runs it in one command (or one Docker
  container).
- The **Verify link test** proves the handshake live.
- Milestone to celebrate: the first SCADA-raised alert claimed on a phone.

No hardware yet? Alerts can be raised manually or from the mobile app on
day one — the integration can follow.

## Week 2–4 — the platform starts learning

- Once alert history accumulates, train the **failure forecaster** on your
  own data from the console (seconds, on-device). The Production Manager
  dashboard's predictive cards go live and the model grades its own accuracy
  daily.
- Turn on the AI agents you want (dispatch, shift commander, briefings) —
  every one has an off switch and logs its reasons.
- Invite us to your first review: we measure response-time deltas together.

## Always — who to call

| Need | Channel |
|---|---|
| Product questions, 2am included | Kubix Copilot chat (EN/FR) — escalates to a human engineer when it should |
| Anything human | The sales/support address on your quote — a human answers |
| Security reports | `/.well-known/security.txt` on our site |

One honest number while you wait for your own: a customer's export/reporting
workflow went from ~30 minutes of manual collation to ~1–2 minutes, fully
logged. Your pilot will produce your numbers — that's the point.
