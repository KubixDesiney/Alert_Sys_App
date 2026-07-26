# Automatic SIAS order provisioning

This is the production contract behind the B2B superadmin **Accept** and
**Paid** buttons.

## Buyer-visible contract

| Superadmin action | Durable transition | Buyer result |
|---|---|---|
| New order | `under_review` | Tenant code is reserved; request is under review. |
| **Accept** | `under_review → confirmed` | `order_confirmed` email: the order is accepted and KubixDesiney will contact the buyer shortly to discuss payment details. |
| **Paid** | `under_review` or `confirmed → provisioning_queued → provisioning` | Automatic dedicated-instance job starts. This direct transition is the virement/bank-transfer path. |
| Provisioning succeeds | `provisioning → active` | Dedicated SIAS URL plus separate single-use activation emails for one Production Manager (`admin`) and one supervisor (`supervisor`). |
| Provisioning fails | `provisioning → provisioning_failed` | No false “ready” status. The dashboard exposes **Retry provisioning**, and the operations failure webhook receives the order/run identifiers. |

Activation emails are sent only after the new tenant passes all Worker, app,
RTDB-reachability, and anonymous-rule-denial probes.

## One-time control-plane setup

1. Run [`sias_orders_schema.sql`](sias_orders_schema.sql) in the private
   Supabase control-plane project. It migrates legacy `awaiting_payment`
   orders to `under_review`, adds the delivery/provisioning fields, enables
   RLS, and revokes browser roles.
2. Configure these `sias-store` secrets:

   - `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`
   - `FOUNDER_PASSWORD`, `SESSION_SECRET`
   - `N8N_ORDER_WEBHOOK_URL`, `N8N_CONFIRMED_WEBHOOK_URL`,
     `N8N_PAID_WEBHOOK_URL`, `N8N_WEBHOOK_AUTH`
   - `PROVISIONING_GITHUB_TOKEN` — fine-grained token allowed to dispatch
     workflows in this repository only
   - `PROVISIONING_GITHUB_REPOSITORY` — `owner/repository`

   **Live n8n webhook URLs (published 2026-07-26):**

   - `N8N_ORDER_WEBHOOK_URL` →
     `https://n8n.kubixdesiney.com/webhook/54a55bfe-8211-492f-a886-95edc228a78d/sias-order-placed`
   - `N8N_CONFIRMED_WEBHOOK_URL` →
     `https://n8n.kubixdesiney.com/webhook/1705a44a-7dac-42a5-88b7-909565574e1b/sias-order-confirmed`
   - `N8N_PAID_WEBHOOK_URL` →
     `https://n8n.kubixdesiney.com/webhook/d2ef2f0b-e3b9-4714-a521-a3b68da1b8fe/sias-payment-paid`

   The activation workflow URL belongs in the repository secret
   `N8N_ACTIVATION_WEBHOOK_URL`:

   - `https://n8n.kubixdesiney.com/webhook/f37fe0d7-21f0-4e29-aa45-7deaecc1e62d/sias-activation`

   Both workflows are active and published. Provisioning deliberately fails
   before seat delivery when activation delivery is absent or returns a
   non-2xx response.

3. Configure repository secrets for
   [provision-paid-order.yml](../../.github/workflows/provision-paid-order.yml):

   - `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`
   - `FIREBASE_PROVISIONER_SERVICE_ACCOUNT`
   - `GOOGLE_BILLING_ACCOUNT`
   - optional `GOOGLE_RESOURCE_PARENT` (`organizations/...` or `folders/...`)
   - `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
   - `SIAS_GITHUB_TOKEN` (persistent token used by the tenant GitHub Worker)
   - `ALERT_WEBHOOK_URL`
   - `N8N_ACTIVATION_WEBHOOK_URL`, `N8N_ACTIVATION_WEBHOOK_AUTH`
   - optional failure-alert secrets `N8N_PROVISIONING_ALERT_WEBHOOK_URL` and
     `N8N_PROVISIONING_ALERT_WEBHOOK_AUTH`

4. Configure repository variables:

   - `CLOUDFLARE_WORKERS_SUBDOMAIN`
   - `FIREBASE_DATABASE_REGION` (defaults to `europe-west1`)

5. The Firebase provisioner identity needs organization/folder project-create,
   project billing-link, Service Usage, Firebase, Resource Manager IAM, and
   service-account administration permissions. An organization policy that
   prohibits service-account keys will intentionally stop provisioning because
   Cloudflare Workers need a tenant runtime credential; use a dedicated
   broker/workload-identity design before enabling that policy.

6. Deploy `database.rules.json`, `sias-app`, and `sias-store` after the tests in
   this document pass. The `TENANTS` KV ID in `wrangler.app.toml` and the
   wildcard `*.kubixdesiney.com/*` app route must already be live.

## Provisioning job

The Store Worker dispatch contains only `orderId` and `tenantCode`; buyer names
and emails never enter GitHub event metadata. The job then:

1. Fetches the private order directly from Supabase and validates both required,
   distinct delivery seats.
2. Creates/reuses a stable GCP project, links billing, enables required APIs,
   adds Firebase, creates RTDB, enables Email/Password Auth, and creates a Web
   app config.
3. Creates a tenant-only `sias-runtime` service account, grants it Firebase
   administration inside that tenant project, rotates one user-managed key, and
   never logs the private key.
4. Generates the seven data-plane Worker configs. `sias-store` and `sias-app`
   stay shared and are never duplicated per buyer.
5. Pushes Worker secrets with checked exit codes and fails on the first deploy
   error.
6. Seeds missing RTDB leaves only:

   - counters;
   - `Usine A → Conveyor 1 → Station 1`;
   - matching `MACH-001` asset index;
   - the four standard alert types;
   - escalation thresholds plus a default;
   - tenant identity and plan entitlements;
   - predictive-AI onboarding status.

7. Writes the tenant's public Firebase config and Worker URLs to `TENANTS` KV.
8. Verifies all seven Workers, `<tenant>.kubixdesiney.com/__config`, RTDB
   reachability, and that anonymous `/users.json` reads are denied.
9. Creates/reuses the PM and supervisor Auth users, writes PII only to
   `users_private/{uid}`, generates fresh password-reset activation links, and
   sends one authenticated/retried activation webhook per seat.
10. Marks the order `active`, records its URL/project, and deletes temporary
    local copies of the runtime key and `.env.tenant`.

Every create/seed/account operation is retry-safe. A retry preserves buyer
hierarchy/settings, reuses Auth users, issues fresh links, and rotates the
tenant runtime key.

## Full-package adaptive AI

`growth` is the full-package entitlement. Its tenant seed enables
`aiTraining` and `adaptiveAlertSchema`; Starter explicitly disables both.

An entitled Production Manager sees the **AI Training** tab. On upload:

- configured codes and synonyms normalize known alert types;
- new safe snake-case categories are ranked by observed frequency and capped
  at 24 additions per upload;
- inferred definitions are added without rewriting existing operator choices;
- the training feature schema expands before samples are engineered;
- model metadata persists the expanded type list and feature count;
- normal daily-count features and continuous adaptation learn future frequency
  changes.

Database rules require the corresponding entitlement for PM writes to
`ai_forecast` and `app_config/alertTypes`; a Starter PM cannot reveal or bypass
the feature by calling RTDB directly.

## n8n payload contract

- `order_placed`: initial under-review receipt.
- `order_confirmed`: send “accepted; we will contact you shortly to discuss
  payment details.”
- `payment_paid`: optional acknowledgement that automatic provisioning started.
- Activation webhook (one call per seat): `seat`, `role`, `seatLabel`, `uid`,
  `email`, `tenantCode`, `company`, `activationLink`, `consoleUrl`,
  `expiresNote`.

The activation URL exists only in that authenticated request. Console output,
GitHub artifacts, and `provision-summary.json` contain a redacted delivery
record.

## Verification

```bash
npm test -- --runInBand \
  worker_test/store_worker.test.js \
  worker_test/provision_seats.test.js \
  worker_test/seed_tenant.test.js \
  worker_test/bootstrap_firebase_project.test.js \
  worker_test/build_tenant_env.test.js \
  worker_test/provision_paid_order.test.js \
  worker_test/provision_instance.test.js \
  worker_test/database_rules_security.test.js

flutter test test/services/alert_type_registry_test.dart
npx wrangler deploy --dry-run --config wrangler.store.toml
```

For a controlled dry run of the data/account shape:

```bash
npm run provision:seed -- \
  --tenant "NSW#7K2F" --company "Nagati Steel Works" --plan growth

npm run provision:seats -- \
  --tenant "NSW#7K2F" --company "Nagati Steel Works" \
  --pm-email pm@example.com --pm-name "Sonia Trabelsi" \
  --supervisor-email supervisor@example.com --supervisor-name "Karim Aloui" \
  --require-delivery-pair
```
