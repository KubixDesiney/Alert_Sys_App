#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Purge the leaked OneSignal REST key from the ENTIRE git history.
#
# The key string is intentionally NOT stored in this script. Pass it as $1 so
# this file is safe to commit.
#
#   ./tool/purge_onesignal_secret.sh 'os_v2_app_...the_leaked_key...'
#
# IMPORTANT ORDER OF OPERATIONS:
#   1) Rotate/REVOKE the key in the OneSignal dashboard FIRST. Scrubbing history
#      does NOT invalidate a key that is already public — only revocation does.
#   2) Install git-filter-repo:  pip install git-filter-repo  (or brew install)
#   3) Commit/stash working changes (this rewrites history).
#   4) Run this script, then force-push and have collaborators re-clone.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

KEY="${1:-}"
if [ -z "$KEY" ]; then
  echo "ERROR: pass the leaked key as the first argument." >&2
  echo "Usage: $0 'os_v2_app_...'" >&2
  exit 1
fi

if ! command -v git-filter-repo >/dev/null 2>&1 && ! python3 -c "import git_filter_repo" >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo not found." >&2
  echo "Install:  pip install git-filter-repo" >&2
  echo "Or use BFG:  bfg --replace-text <(printf 'literal:%s==>REMOVED\\n' \"\$KEY\")" >&2
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree not clean. Commit or stash changes first." >&2
  exit 1
fi

REPL="$(mktemp)"
trap 'rm -f "$REPL"' EXIT
printf 'literal:%s==>REMOVED_ROTATED_ONESIGNAL_KEY\n' "$KEY" > "$REPL"

echo "Rewriting history across all commits/branches/tags..."
git filter-repo --force --replace-text "$REPL"

echo
echo "DONE — key string replaced throughout history."
echo "Verify (should print nothing):  git log -S \"$KEY\" --oneline --all"
echo "Then publish the rewrite:"
echo "  git push --force --all"
echo "  git push --force --tags"
echo "Finally: every collaborator must re-clone; purge CI caches; confirm the"
echo "key is already REVOKED in the OneSignal dashboard."
