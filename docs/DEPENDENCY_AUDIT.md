# Dependency audit gate

CI blocks high or critical advisories in deployable production dependencies:

```bash
npm audit --omit=dev --audit-level=high
cd functions && npm audit --audit-level=high
cd codebasedelta && npm audit --audit-level=high
```

The root package keeps Wrangler as a dev/deploy tool. As of the current lockfile,
`npm audit --audit-level=high` still reports high advisories through the
Wrangler/Miniflare/esbuild/ws development toolchain, while
`npm audit --omit=dev --audit-level=high` passes for production dependencies.

Operational handling:

- Do not run `wrangler dev` against untrusted networks.
- Use Wrangler only in trusted CI/developer environments for deployment.
- Keep Wrangler pinned on the newest tested major in `package.json`.
- Re-run full root `npm audit --audit-level=high` during release review and
  remove the root `--omit=dev` scope once Cloudflare's toolchain has a clean
  high-severity audit result.
