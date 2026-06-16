# Change management policy

Version 1.0 - 2026-06-15 - Owner: engineering lead - Review: annual

## 1. Purpose
Every production change is reviewed, tested, and reversible. No direct, unreviewed
changes to production.

## 2. Branching & review
- `main` is protected: changes land via pull request.
- At least one review approval required before merge.
- Required status checks must pass (see section 3) before merge.
- The expected `main` protection policy is versioned in
  `.github/branch-protection-main.json` and verified with `docs/BRANCH_PROTECTION.md`.
- The autonomous bug-fix agent opens draft PRs; its changes are subject to the
  same CI gates + review.

## 3. Required CI gates (all green to merge/release)
- `flutter analyze` clean + `flutter test --coverage`.
- `npm test` + worker coverage gate (`jest.config.js` threshold).
- Performance guard: `npm run bench:ci` (assignment p99 within budget).
- Security workflow: `gitleaks` + `npm audit`.
- Firebase RTDB rules/configuration behavior: `npm run test:rules`.

## 4. Release & deploy
Follow `RELEASE.md`: staging first, then production; tag releases; deploy order rules,
database/worker/hosting, post-deploy verification.

## 5. Rollback
Every change must be reversible: Firebase Hosting rollback, `wrangler rollback` for
workers, redeploy previous `database.rules.json`, Shorebird code push for mobile hotfix.
Tag the last-known-good commit before each production deploy.

## 6. Emergency changes
SEV1 hotfixes may bypass the staging step but still require: a PR, one review (can be
post-merge for true emergencies), all CI gates, and a same-day post-incident note.
