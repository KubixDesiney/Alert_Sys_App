# Main branch protection

`main` is a production branch. Changes to `main` must be reviewable and auditable.
The expected policy is versioned in `.github/branch-protection-main.json` and can
be applied with `tool/setup_branch_protection.sh`.

## Required policy

- Pull requests are required before changes land on `main`.
- At least one approving review is required.
- Stale approvals are dismissed after new pushes.
- The last pusher cannot self-approve their own update.
- Required status checks must pass and must be up to date with `main`.
- Admins are included in enforcement.
- Force pushes and branch deletion are disabled.
- Linear history and resolved conversations are required.

## Required checks

- `Flutter (analyze, test, build)`
- `Cloudflare Workers (Jest + deploy)`
- `Worker coverage (Jest, gated)`
- `Flutter coverage`
- `AI assignment performance guard`
- `Secret scan (gitleaks)`
- `Dependency audit (npm)`

If a workflow job is renamed, update `.github/branch-protection-main.json` in the
same PR that renames the job.

## Apply

```bash
gh auth status
./tool/setup_branch_protection.sh KubixDesiney/Alert_Sys_App
```

The GitHub token used by `gh` must have repository administration permission.

## Verify

```bash
REPO=KubixDesiney/Alert_Sys_App
gh api "repos/$REPO/branches/main/protection" --jq '{
  required_status_checks,
  enforce_admins: .enforce_admins.enabled,
  required_pull_request_reviews,
  required_linear_history: .required_linear_history.enabled,
  allow_force_pushes: .allow_force_pushes.enabled,
  allow_deletions: .allow_deletions.enabled,
  required_conversation_resolution: .required_conversation_resolution.enabled
}'
```

Owner checklist:

- `required_status_checks.strict` is `true`.
- Every required check listed above appears under `required_status_checks.checks`.
- `required_pull_request_reviews.required_approving_review_count` is at least `1`.
- `required_pull_request_reviews.dismiss_stale_reviews` is `true`.
- `required_pull_request_reviews.require_last_push_approval` is `true`.
- `enforce_admins`, `required_linear_history`, and `required_conversation_resolution` are enabled.
- `allow_force_pushes` and `allow_deletions` are disabled.

This repository cannot prove branch protection is enabled unless the owner runs
the verification command against GitHub. Store the redacted command output in the
release evidence package for enterprise pilots.
