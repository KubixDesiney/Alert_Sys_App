#!/usr/bin/env bash
# Lock down `main`: require PR review + passing CI/security/quality checks.
# Prereqs: GitHub CLI installed and authenticated (`gh auth login`) with admin on the repo.
# Run the CI/security/quality workflows at least once so the check names exist.
#
#   ./tool/setup_branch_protection.sh [owner/repo]
#
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "Applying branch protection to main on: $REPO"

gh api -X PUT "repos/$REPO/branches/main/protection" \
  -H "Accept: application/vnd.github+json" --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "Flutter (analyze, test, build)" },
      { "context": "Cloudflare Workers (Jest + deploy)" },
      { "context": "Worker coverage (Jest, gated)" },
      { "context": "AI assignment performance guard" },
      { "context": "Secret scan (gitleaks)" },
      { "context": "Dependency audit (npm)" }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "Done. Verify under repo Settings -> Branches. Adjust check names if a workflow job is renamed."
