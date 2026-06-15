# Secret rotation & history purge runbook

Version 1.0 - 2026-06-15 - Owner: SuperAdmin / security lead

A Firebase **service-account private key** (`service-account.json`) was committed in commit
`22fede5` and a **OneSignal** key existed in history. Your current tree is clean, but both
are still in git history. **Rotation neutralizes the leaked values; purging removes them
from history. Do them in this order — rotation first.**

> Scrubbing history does NOT un-leak a secret that was already public. Only rotating/revoking
> it at the provider does. Purge is cleanup after the value is already dead.

---

## 1. Rotate the Firebase service-account key  (CRITICAL — do this first)

Find the service account from `client_email` inside the old `service-account.json`.

**Console:** console.cloud.google.com -> IAM & Admin -> Service Accounts -> select that SA
-> **Keys** -> delete the existing (leaked) key -> **Add key -> Create new key -> JSON** -> download.

**Or gcloud:**
```bash
SA=your-sa@your-project.iam.gserviceaccount.com
gcloud iam service-accounts keys list --iam-account="$SA"
gcloud iam service-accounts keys delete LEAKED_KEY_ID --iam-account="$SA"
gcloud iam service-accounts keys create new-sa.json --iam-account="$SA"
```

**Push the new key into every worker secret** (paste the new JSON when prompted):
```bash
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.ai.toml
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.notify.toml
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.scim.toml
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.backup.toml
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.monitor.toml
```
Update the same secret in GitHub Actions if CI uses it (Settings -> Secrets -> Actions).
Then delete `new-sa.json` locally — never commit it (it is git-ignored).

The moment the old key is deleted, the leaked copy in history is dead.

## 2. Decommission OneSignal (you no longer use it)

In the OneSignal dashboard, **delete the app** (or at minimum revoke/regenerate the REST API
key) so the historical key is worthless. No code references remain after the recent cleanup.

## 3. Restrict the Firebase client API keys

`google-services.json` / `firebase_options.dart` keys are public *client* keys — restrict,
don't rotate. Console -> APIs & Services -> Credentials -> each key:
- **Application restrictions**: Android (package + SHA-256), iOS (bundle id), web (HTTP referrers).
- **API restrictions**: limit to the Firebase APIs you actually use.

## 4. Purge the secrets from git history

Only after rotating. This rewrites history — coordinate, then everyone re-clones.

```bash
# 0. Install the tool + take a full backup mirror first
pip install git-filter-repo
git clone --mirror . ../alertsysapp-backup.git

# 1. Remove the service-account key file from ALL history
git filter-repo --invert-paths --path service-account.json

# 2. Remove the RTDB backup dumps (PII) from ALL history
git filter-repo --invert-paths --path-glob 'backups/*'

# 3. Redact the leaked OneSignal key string everywhere
printf 'literal:PASTE_OLD_ONESIGNAL_KEY==>REDACTED\n' > ../replacements.txt
git filter-repo --replace-text ../replacements.txt
#   (equivalently: ./tool/purge_leaked_secret.sh 'PASTE_OLD_ONESIGNAL_KEY')

# 4. filter-repo drops the remote — re-add and force-push every ref
git remote add origin https://github.com/<you>/<repo>.git
git push --force --all
git push --force --tags
```

Everyone with an existing clone must re-clone (old clones still hold the secret).

## 5. Verify

```bash
gitleaks detect --config .gitleaks.toml --redact --no-banner   # expect 0 findings
```
- Hit each worker's health/status endpoint to confirm the new key authenticates.
- Sign in to the app and confirm reads/writes still work.

## Notes
- If the GitHub repo is or ever was **public**, assume the key was scraped — rotation
  (steps 1-2) is the real protection; also ask GitHub Support to purge cached commit views.
- After the force-push, old commit/PR links will break — expected.
- Re-enable blocking full-history gitleaks in `.github/workflows/security.yml` once the
  purge verifies clean (flip the informational scan back to `--exit-code 1`).
