#!/usr/bin/env bash
# Lock down `main`: require PR review + passing CI/security/quality checks.
# Prereqs: GitHub CLI installed and authenticated (`gh auth login`) with admin on the repo.
# Run the CI/security/quality workflows at least once so the check names exist.
#
#   ./tool/setup_branch_protection.sh [owner/repo]
#
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
POLICY_FILE="${BRANCH_PROTECTION_POLICY_FILE:-.github/branch-protection-main.json}"
echo "Applying branch protection to main on: $REPO"
echo "Policy file: $POLICY_FILE"

gh api -X PUT "repos/$REPO/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  --input "$POLICY_FILE"

echo "Done. Verify under repo Settings -> Branches and docs/BRANCH_PROTECTION.md."
