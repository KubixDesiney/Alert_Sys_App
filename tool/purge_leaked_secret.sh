#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Purge a leaked secret string from the ENTIRE git history.
#
# The secret is intentionally NOT stored in this script. Pass it as $1 so this
# file is safe to commit.
#
#   ./tool/purge_leaked_secret.sh '<the-leaked-secret-string>'
#
# IMPORTANT ORDER OF OPERATIONS:
#   1) Rotate/REVOKE the secret at its provider FIRST. Scrubbing history does NOT
#      invalidate a secret that is already public — only revocation does.
#   2) Install git-filter-repo:  pip install git-filter-repo  (or brew install)
#   3) Commit/stash working changes (this rewrites history).
#   4) Run this script, then force-push and have collaborators re-clone.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SECRET="${1:-}"
if [ -z "$SECRET" ]; then
  echo "ERROR: pass the leaked secret as the first argument." >&2
  echo "Usage: $0 '<secret-string>'" >&2
  exit 1
fi

if ! command -v git-filter-repo >/dev/null 2>&1 && ! python3 -c "import git_filter_repo" >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo not found." >&2
  echo "Install:  pip install git-filter-repo" >&2
  echo "Or use BFG:  bfg --replace-text <(printf 'literal:%s==>REMOVED\\n' \"\$SECRET\")" >&2
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree not clean. Commit or stash changes first." >&2
  exit 1
fi

REPL="$(mktemp)"
trap 'rm -f "$REPL"' EXIT
printf 'literal:%s==>REMOVED_ROTATED_SECRET\n' "$SECRET" > "$REPL"

echo "Rewriting history across all commits/branches/tags..."
git filter-repo --force --replace-text "$REPL"

echo
echo "DONE — secret string replaced throughout history."
echo "Verify (should print nothing):  git log -S \"$SECRET\" --oneline --all"
echo "Then publish the rewrite:"
echo "  git push --force --all"
echo "  git push --force --tags"
echo "Finally: every collaborator must re-clone; purge CI caches; confirm the"
echo "secret is already REVOKED at its provider."
