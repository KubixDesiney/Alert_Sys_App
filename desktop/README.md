# SIAS Desktop

Native desktop client for **SIAS - Smart Industrial Alert System**, shipped as
real installers for Windows, macOS and Linux:

| Platform | Artifacts |
| --- | --- |
| Windows 10/11 | `SIAS_<version>_x64-setup.exe` (NSIS), `SIAS_<version>_x64_en-US.msi` (WiX) |
| macOS 10.15+ | `SIAS_<version>_universal.dmg`, `SIAS.app` (Apple silicon + Intel) |
| Linux | `SIAS_<version>_amd64.AppImage`, `.deb`, `.rpm` |

Built with [Tauri v2](https://tauri.app): a small Rust binary that hosts the
operating system's own webview. Installers are ~10 MB, not ~150 MB, and startup
is native-fast.

---

## Why a shell, and not `flutter build windows`

The SIAS app is built end to end on Firebase Realtime Database — **55 files under
`lib/` import `package:firebase_database`** — and that plugin ships
`android, ios, macos, web` only. There is no Windows or Linux implementation.
`firebase_messaging`, `mobile_scanner`, `google_maps_flutter` and `geocoding`
have the same or worse desktop gaps.

A native Flutter desktop build would therefore mean replacing the entire data
layer with a hand-written RTDB REST/SSE client plus stubs for push, scanning,
maps and geocoding — a rewrite of the app's foundation, with the regression risk
that implies, for zero visible benefit.

This shell instead renders **the exact Flutter web build already in production**,
which means:

- **The design is untouched.** It is the same UI, the same code, the same pixels.
- **Per-tenant config keeps working.** The `sias-app` Worker injects
  `window.__SIAS_CONFIG__` based on the `Host` header, so each customer's
  Firebase project and worker URLs resolve exactly as they do in the browser.
- **Web deploys ship to desktop instantly.** No re-signing, no new installer, no
  version skew between browser and desktop users. You only cut a desktop release
  when the *shell* changes.

The shell itself adds only a native menu and a first-run workspace picker.

---

## Architecture

Two windows, with deliberately different privileges:

| Window | Label | Content | IPC |
| --- | --- | --- | --- |
| Workspace picker | `launcher` | Local `ui/index.html` | Yes — the five commands in `capabilities/default.json` |
| Application | `main` | `https://<tenant>.kubixdesiney.com` | **None** |

`capabilities/default.json` lists `"windows": ["launcher"]` and nothing else, so
the remote SIAS web app cannot invoke a single shell command. That is enforced by
Tauri's ACL, not by convention.

Top-level navigation in the app window is filtered by
[`src-tauri/src/tenant.rs`](src-tauri/src/tenant.rs): product hosts
(`*.kubixdesiney.com`) and known identity providers load in-app; **everything
else is handed to the user's real browser**. A stray or hostile link cannot
repoint the application window.

`tenant.rs` is a deliberate Rust mirror of `tenantFromHost` in
`cloudflare_app_worker.js` and is covered by unit tests — including the
suffix-confusion case (`kubixdesiney.com.evil.com`). **If you change the tenant
host rules in the worker, change them here and update the tests.**

### Where things are stored

| Data | Location |
| --- | --- |
| Chosen workspace, zoom level | `sias-desktop.json` in the app data dir |
| Window size and position | `.window-state.json` in the app data dir |

App data dir: `%APPDATA%\com.kubixdesiney.sias` (Windows),
`~/Library/Application Support/com.kubixdesiney.sias` (macOS),
`~/.local/share/com.kubixdesiney.sias` (Linux).

The saved workspace is **re-validated on every read**, so a hand-edited settings
file cannot point the window at an arbitrary host.

---

## Prerequisites

Rust stable is required everywhere: <https://rustup.rs>

| OS | Also needed |
| --- | --- |
| Windows | Visual Studio Build Tools (MSVC + Windows SDK); WebView2 runtime (preinstalled on Win11 and current Win10) |
| macOS | Xcode Command Line Tools (`xcode-select --install`) |
| Linux | `libwebkit2gtk-4.1-dev libgtk-3-dev librsvg2-dev libappindicator3-dev libssl-dev patchelf` (add `rpm` to build `.rpm`) |

---

## Commands

Run from `desktop/`:

```bash
npm install
```

```bash
npm run dev
```

```bash
npm run build
```

```bash
npm test
```

```bash
npm run lint
```

`npm run build` writes installers to
`src-tauri/target/release/bundle/`. `npm run icons` regenerates the icon set from
`media/sia_logo.png`.

---

## Releasing

Tag and push — [`desktop-release.yml`](../.github/workflows/desktop-release.yml)
builds all three platforms in parallel and attaches the installers to a GitHub
Release:

```bash
git tag desktop-v1.2.1 && git push origin desktop-v1.2.1
```

Keep the tag version and `src-tauri/tauri.conf.json` → `version` in step. The
release is created as a draft and published once every platform succeeds, so a
half-built release is never visible to customers.

### Optional secrets

Everything below is optional — with none of it set, the workflow still produces
working (unsigned) installers.

| Secret | Effect when set |
| --- | --- |
| `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PUBLIC_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Compiles in the auto-updater and publishes a signed `latest.json` feed |
| `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` | Signs and notarizes the macOS build (removes the "unidentified developer" warning) |

Generate an updater key pair with:

```bash
npx tauri signer generate -w sias-updater.key
```

Put the private key in `TAURI_SIGNING_PRIVATE_KEY` and the `.pub` contents in
`TAURI_SIGNING_PUBLIC_KEY`. **Never commit either file** — `*.key` is
git-ignored, and CI generates `tauri.updater.conf.json` from the secrets at build
time so no key material or stale placeholder lives in the repo.

Without those secrets the app is still a normal installer-updated desktop app;
**Check for Updates** simply opens the Releases page.

### Windows code signing

Unsigned Windows installers show a SmartScreen warning on first run. To remove
it you need an OV or EV code-signing certificate, then set
`bundle.windows.certificateThumbprint` (plus `digestAlgorithm` and
`timestampUrl`) in `tauri.conf.json` and import the certificate on the runner.
See <https://tauri.app/distribute/sign/windows/>.

---

## Notes and known constraints

- **Linux rendering.** The Linux webview is WebKitGTK, not Chromium. Flutter web
  renders with CanvasKit (WebGL), which is well supported but worth smoke-testing
  on each target distro. Windows uses WebView2 (Chromium) and macOS uses
  WKWebView, both of which match the browser experience closely.
- **Web push does not apply.** Desktop alerting is the live in-app stream; FCM
  web push is a browser/mobile delivery path. The one-minute notify-worker cron
  remains the durable fallback for every client.
- **Single instance.** Launching the app twice focuses the existing window
  instead of opening a second one.
- **Copy/paste on macOS** depends on the Edit menu existing — WKWebView only
  honours Cmd+C/Cmd+V when the standard edit items are present. Do not remove
  them from `src-tauri/src/menu.rs`.
