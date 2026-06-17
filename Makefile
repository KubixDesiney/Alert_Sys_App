# Smart Industrial Alert (SIA) — one-command operations.
# Uses `>` as the recipe prefix (instead of TAB) to stay copy/paste robust.
#
#   make help          list targets
#   make bootstrap     install + full local gate (test + analyze)
#   make deploy-all    deploy every Cloudflare worker
#   make instance      print how to stand up a brand-new customer instance
.RECIPEPREFIX = >
.DEFAULT_GOAL := help

AI_URL ?= https://alert-notifier.aziz-nagati01.workers.dev
NOTIFY_URL ?= https://alertsys.aziz-nagati01.workers.dev
DEFINES = --dart-define=ALERTSYS_AI_WORKER_URL=$(AI_URL) --dart-define=ALERTSYS_NOTIFY_WORKER_URL=$(NOTIFY_URL)

.PHONY: help install test test-coverage analyze build-web build-apk \
        deploy-ai deploy-notify deploy-github deploy-ingest deploy-all \
        deploy-web deploy-rules smoke preflight drill bootstrap release instance

help:
> @grep -E '^[a-zA-Z_-]+:.*?# .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*?# "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: # install Flutter + worker deps
> flutter pub get
> npm ci

test: # run worker (Jest) + Flutter unit tests
> npm test
> flutter test

test-coverage: # worker coverage with the enforced threshold gate
> npm run test:coverage

analyze: # static analysis (CI-equivalent flags)
> flutter analyze --no-fatal-infos --no-fatal-warnings

build-web: # release web build with worker URLs baked in
> flutter build web --release --no-wasm-dry-run $(DEFINES)

build-apk: # release Android build
> flutter build apk --release $(DEFINES)

deploy-ai: # deploy the AI/security worker
> npx wrangler deploy --config wrangler.ai.toml

deploy-notify: # deploy the notifications worker
> npx wrangler deploy --config wrangler.notify.toml

deploy-github: # deploy the GitHub proxy worker (Guardian)
> npx wrangler deploy --config wrangler.github.toml

deploy-ingest: # deploy the SCADA telemetry ingestion worker
> npx wrangler deploy --config wrangler.ingest.toml

deploy-all: deploy-ai deploy-notify deploy-github deploy-ingest # deploy every worker

deploy-web: # deploy Flutter web to Firebase Hosting
> firebase deploy --only hosting

deploy-rules: # deploy Realtime Database security rules
> firebase deploy --only database

smoke: # synthetic health probe of the deployed instance
> node tool/smoke_test.mjs

preflight: # report which Guardian/deploy secrets are present
> node tool/guardian_preflight.mjs

drill: # local Guardian drill: inject a real fault, verify it broke, restore
> node tool/guardian_drill.mjs --inject --target tool/guardian_drill_target.mjs
> - node tool/guardian_drill.mjs --verify --target tool/guardian_drill_target.mjs
> node tool/guardian_drill.mjs --restore --target tool/guardian_drill_target.mjs

bootstrap: install test analyze # full local setup + gate (run before pushing)
> @echo "bootstrap complete: deps installed, tests + analysis green"

release: test-coverage analyze build-web # pre-release gate
> @echo "release gate passed: coverage + analysis + web build OK"

instance: # how to provision a brand-new customer instance
> @echo "1) gh workflow run deploy-instance.yml -f firebaseProjectId=<id> -f workersSubdomain=<sub>"
> @echo "   (or trigger from SuperAdmin -> Infrastructure). See PROVISIONING.md / docs/sales/PRICING.md"
> @echo "2) make deploy-all && make deploy-rules && make deploy-web"
> @echo "3) make smoke   # confirm the new instance is healthy"
