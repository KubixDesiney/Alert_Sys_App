# Secret rotation and history-purge evidence

Version 1.1 - Owner: SuperAdmin / security lead

Previously exposed material was identified in git history:

- Firebase service-account private key file: `service-account.json` in commit `22fede5`.
- Legacy OneSignal credential string in history.
- Historical RTDB backup dumps under `backups/*`.

No real replacement key, provider token, private key, customer export, or screenshot
may be committed to this repository. Store provider-side proof in the private
release evidence package or security ticket, with secrets redacted.

## Repository evidence available in this PR

- Current tree has no tracked `service-account.json`.
- `backups/` is git-ignored.
- `.gitleaks.toml` scans the tree while allowing only public Firebase client config files.
- `.github/workflows/security.yml` blocks current-tree gitleaks findings.
- `.github/workflows/security.yml` uploads a full-history gitleaks report as explicit
  legacy-risk evidence until the owner performs history purge.
- `tool/purge_leaked_secret.sh` and this runbook define the history-purge procedure.

Run locally:

```bash
gitleaks detect --no-git --config .gitleaks.toml --redact --no-banner --exit-code 1
gitleaks detect --config .gitleaks.toml --redact --no-banner --report-path gitleaks-history.json --exit-code 1
```

Expected before history purge:

- Current-tree scan exits `0`.
- Full-history scan may exit non-zero because old commits still contain legacy
  findings. Treat that as an open release risk until purge is complete.

Expected after history purge:

- Both commands exit `0`.
- The GitHub Actions `gitleaks-history-report` artifact is empty or reports no findings.

## Provider-side rotation evidence required

The repository cannot prove that an old cloud/provider secret is dead. The owner
must attach redacted provider evidence before a production pilot:

| Secret class | Required evidence | Do not include |
|---|---|---|
| Firebase service-account key | Old key ID absent from `gcloud iam service-accounts keys list`; deletion timestamp; new key creation timestamp; list of Cloudflare/GitHub secret stores updated | Private key JSON, full client email if sensitive, screenshots with key material |
| OneSignal REST key | App deleted, key revoked, or key regenerated; timestamp; provider audit/event ID if available | REST API key, app auth token |
| Firebase client API keys | Google Cloud API key restrictions enabled for Android/iOS/web and required Firebase APIs only | Full unrestricted API-key inventory screenshots |
| RTDB backups | Confirmation that historical backup dumps were removed from git history and retained only in approved backup storage | Customer data, backup content |

## Verification checklist

Firebase service account:

```bash
SA=your-sa@your-project.iam.gserviceaccount.com
gcloud iam service-accounts keys list --iam-account="$SA"
```

- The leaked key ID is not present.
- Only current, expected key IDs remain.
- Every worker secret was updated after the old key deletion:

```bash
npx wrangler secret list --config wrangler.ai.toml
npx wrangler secret list --config wrangler.notify.toml
npx wrangler secret list --config wrangler.scim.toml
npx wrangler secret list --config wrangler.backup.toml
npx wrangler secret list --config wrangler.monitor.toml
```

- If an archived copy of the old JSON exists in the private incident package, a
  test authentication attempt fails. Never commit or paste the JSON.

OneSignal:

- Provider dashboard shows the old REST key invalidated, regenerated, or the app deleted.
- Any production code path using OneSignal remains removed or disabled.

GitHub Actions and Cloudflare:

- `FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS` was updated after old-key deletion.
- `FIREBASE_TOKEN`, `WORKER_SHARED_SECRET`, and Cloudflare tokens were reviewed
  and rotated if exposed outside approved secret stores.

## History purge status

Status: not proven complete by repository state alone.

Risk while purge is pending:

- Anyone with an old clone, fork, PR cache, GitHub cached commit view, or full-history
  checkout may still see the dead secret values and historical backup content.
- Rotation/revocation makes the old provider values unusable, but history still
  contains sensitive evidence until rewritten and force-pushed.
- Existing clones must be re-cloned after purge or they retain the old objects.

Required owner action:

1. Complete provider rotation first.
2. Coordinate a maintenance window because history rewrite changes commit SHAs.
3. Run the purge procedure below from a clean clone.
4. Force-push all refs and tags.
5. Ask collaborators to re-clone.
6. Ask GitHub Support to purge cached commit views if the repository was ever public.
7. Re-run both gitleaks commands above and attach redacted output to the release evidence package.

## Purge procedure

```bash
pip install git-filter-repo
git clone --mirror https://github.com/KubixDesiney/Alert_Sys_App.git ../alertsysapp-backup.git

git filter-repo --invert-paths --path service-account.json
git filter-repo --invert-paths --path-glob 'backups/*'

printf 'literal:PASTE_OLD_ONESIGNAL_KEY==>REDACTED\n' > ../replacements.txt
git filter-repo --replace-text ../replacements.txt

git remote add origin https://github.com/KubixDesiney/Alert_Sys_App.git
git push --force --all
git push --force --tags
```

Alternatively, use the repository helper for a single literal secret:

```bash
./tool/purge_leaked_secret.sh 'PASTE_OLD_SECRET_VALUE'
```

## Release gate

Before enterprise pilot release, the owner must confirm:

- Provider-side rotation evidence is attached outside the repo.
- Current-tree gitleaks passes.
- Full-history gitleaks passes, or the risk above is accepted in writing by the owner.
- Branch protection is verified with `docs/BRANCH_PROTECTION.md`.
