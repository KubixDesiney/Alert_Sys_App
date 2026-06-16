# ADR-0005: Provider-agnostic Guardian self-healing CI pipeline

Status: Accepted — 2026-06

## Context
Customer IT teams operate their own instances and want failures (CI breakage,
worker/UI/log/RTDB health regressions) triaged and fixed quickly without a
dedicated SIA engineer on call. Tying that automation to a single AI vendor would
be a lock-in and procurement problem, and auto-committing AI-generated code to
`main` is risky without guardrails.

## Decision
The Guardian agent (`tool/autonomous_bugfix_agent.mjs` + `tool/guardian_*.mjs`,
surfaced in the SuperAdmin AI Agents console) runs a gated pipeline:
**detect → gather context (source + logs + DB state) → fix (configurable provider)
→ independent review (a different configurable provider) → validate (`flutter
analyze`/tests + Jest) → deploy or open PR**. Fix and review providers, models, and
tokens are configurable per role (Claude/OpenAI/Qwen/DeepSeek/Mistral/… via
`tool/guardian_providers.mjs`). GitHub access goes through a server-side worker
vault, never the client. Deploy mode is selectable: "automatic" (push to `main`)
or "human review required" (PR only).

## Consequences
**Positive:** no AI-vendor lock-in; a second, independent model must approve any
change; the test gate runs before any merge/deploy; customers choose their risk
posture per instance; every run is logged to `bugs/agent`.

**Negative:** quality depends on the configured providers; an over-eager pipeline
could churn (mitigated by the review+test gate and RB-6); "automatic" mode should
be reserved for low-risk instances — customer instances default to PR-only.
