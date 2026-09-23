//! SIAS - Smart Industrial Alert System — desktop shell.
//!
//! The shell deliberately renders **nothing** of its own except the native menu
//! and a first-run workspace picker. The product UI is the untouched Flutter web
//! build served by the `sias-app` Cloudflare Worker at
//! `https://<tenant>.kubixdesiney.com`, so the desktop app is always exactly the
//! same interface as the browser — and every web deploy ships to desktop with no
//! new installer.
//!
//! Two windows exist:
//!
//! * `launcher` — the local page (`../ui/index.html`); the only window with IPC.
//! * `main` — the remote tenant app, with **no** IPC capability at all. See
//!   `capabilities/default.json`.

mod menu;
mod tenant;

use tauri::menu::MenuEvent;
use tauri::{AppHandle, Manager, Runtime, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_store::StoreExt;

/// Persisted settings live next to the app's other data
/// (`%APPDATA%`, `~/Library/Application Support`, `~/.local/share`).
const STORE_FILE: &str = "sias-desktop.json";
const KEY_TENANT: &str = "tenant";
const KEY_ZOOM: &str = "zoom";

const LAUNCHER_LABEL: &str = "launcher";
const APP_LABEL: &str = "main";

const ZOOM_MIN: f64 = 0.5;
const ZOOM_MAX: f64 = 2.5;
const ZOOM_STEP: f64 = 0.1;

#[allow(dead_code)] // only referenced by builds without the `updater` feature
const RELEASES_URL: &str = "https://github.com/KubixDesiney/Alert_Sys_App/releases/latest";

// ---------------------------------------------------------------------------
// Persisted settings
// ---------------------------------------------------------------------------

fn store_get<R: Runtime>(app: &AppHandle<R>, key: &str) -> Option<serde_json::Value> {
    app.store(STORE_FILE).ok().and_then(|store| store.get(key))
}

fn store_put<R: Runtime>(app: &AppHandle<R>, key: &str, value: serde_json::Value) {
    match app.store(STORE_FILE) {
        Ok(store) => {
            store.set(key, value);
            if let Err(err) = store.save() {
                log::warn!("could not persist {key}: {err}");
            }
        }
        Err(err) => log::warn!("settings store unavailable: {err}"),
    }
}

/// Reads the remembered workspace. The value is re-validated on every read:
/// a hand-edited settings file must never be able to point the app window at
/// an arbitrary host.
fn read_tenant<R: Runtime>(app: &AppHandle<R>) -> Option<String> {
    let raw = store_get(app, KEY_TENANT)?;
    tenant::normalize_tenant_input(raw.as_str()?, tenant::APP_DOMAIN)
}

fn read_zoom<R: Runtime>(app: &AppHandle<R>) -> f64 {
    store_get(app, KEY_ZOOM)
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0)
        .clamp(ZOOM_MIN, ZOOM_MAX)
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

fn open_externally<R: Runtime>(app: &AppHandle<R>, url: &str) {
    if let Err(err) = app.opener().open_url(url, None::<&str>) {
        log::warn!("could not hand {url} to the system browser: {err}");
    }
}

/// Attaches the application menu to a window. On macOS the menu is owned by the
/// application itself, so there is nothing per-window to do.
#[allow(unused_variables, unused_mut)]
fn with_app_menu<'a, R: Runtime>(
    app: &'a AppHandle<R>,
    mut builder: WebviewWindowBuilder<'a, R, AppHandle<R>>,
) -> WebviewWindowBuilder<'a, R, AppHandle<R>> {
    #[cfg(not(target_os = "macos"))]
    if let Some(menu) = app.menu() {
        builder = builder.menu(menu);
    }
    builder
}

/// Opens (or focuses) the window that hosts the tenant's SIAS web app.
fn open_app_window<R: Runtime>(app: &AppHandle<R>, slug: &str) -> tauri::Result<WebviewWindow<R>> {
    if let Some(existing) = app.get_webview_window(APP_LABEL) {
        let _ = existing.set_focus();
        return Ok(existing);
    }

    let url: tauri::Url = tenant::tenant_url(slug, tenant::APP_DOMAIN)
        .parse()
        .expect("a validated tenant slug always yields a valid URL");

    let nav_tenant = slug.to_string();
    let nav_app = app.clone();

    let builder = WebviewWindowBuilder::new(app, APP_LABEL, WebviewUrl::External(url))
        .title(format!("SIAS - {slug}"))
        .inner_size(1440.0, 900.0)
        .min_inner_size(1024.0, 640.0)
        .resizable(true)
        .center()
        // The app window may only ever go to product or identity-provider
        // hosts. Anything else is handed to the user's real browser, so a
        // stray link can never repoint the application window.
        .on_navigation(move |url| {
            match tenant::classify_navigation(url.as_str(), &nav_tenant, tenant::APP_DOMAIN) {
                tenant::NavDecision::Allow => true,
                tenant::NavDecision::External => {
                    open_externally(&nav_app, url.as_str());
                    false
                }
            }
        });

    let window = with_app_menu(app, builder).build()?;
    let _ = window.set_zoom(read_zoom(app));
    Ok(window)
}

/// Opens (or focuses) the local first-run workspace picker.
fn open_launcher<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<WebviewWindow<R>> {
    if let Some(existing) = app.get_webview_window(LAUNCHER_LABEL) {
        let _ = existing.set_focus();
        return Ok(existing);
    }

    let builder =
        WebviewWindowBuilder::new(app, LAUNCHER_LABEL, WebviewUrl::App("index.html".into()))
            .title("SIAS - Connect workspace")
            .inner_size(520.0, 640.0)
            .min_inner_size(480.0, 600.0)
            .resizable(false)
            .center();

    with_app_menu(app, builder).build()
}

fn focus_existing<R: Runtime>(app: &AppHandle<R>) {
    for label in [APP_LABEL, LAUNCHER_LABEL] {
        if let Some(window) = app.get_webview_window(label) {
            let _ = window.unminimize();
            let _ = window.show();
            let _ = window.set_focus();
            return;
        }
    }
}

/// Forgets the saved workspace and returns to the picker.
/// The launcher is opened *before* the app window closes: on every platform,
/// closing the last window would otherwise terminate the process.
fn switch_workspace<R: Runtime>(app: &AppHandle<R>) {
    if let Ok(store) = app.store(STORE_FILE) {
        store.delete(KEY_TENANT);
        let _ = store.save();
    }
    if let Err(err) = open_launcher(app) {
        log::error!("failed to open the workspace picker: {err}");
        return;
    }
    if let Some(window) = app.get_webview_window(APP_LABEL) {
        let _ = window.close();
    }
}

// ---------------------------------------------------------------------------
// Zoom
// ---------------------------------------------------------------------------

fn set_zoom<R: Runtime>(app: &AppHandle<R>, zoom: f64) {
    let zoom = (zoom * 100.0).round() / 100.0;
    let zoom = zoom.clamp(ZOOM_MIN, ZOOM_MAX);
    store_put(app, KEY_ZOOM, serde_json::json!(zoom));
    if let Some(window) = app.get_webview_window(APP_LABEL) {
        if let Err(err) = window.set_zoom(zoom) {
            log::warn!("zoom not supported on this platform: {err}");
        }
    }
}

// ---------------------------------------------------------------------------
// Updates
// ---------------------------------------------------------------------------

#[cfg(feature = "updater")]
fn check_for_updates<R: Runtime>(app: &AppHandle<R>) {
    use tauri_plugin_updater::UpdaterExt;

    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        let updater = match handle.updater() {
            Ok(updater) => updater,
            Err(err) => return log::error!("updater unavailable: {err}"),
        };
        match updater.check().await {
            Ok(Some(update)) => {
                log::info!("update {} available - downloading", update.version);
                match update.download_and_install(|_, _| {}, || {}).await {
                    Ok(()) => handle.restart(),
                    Err(err) => log::error!("update install failed: {err}"),
                }
            }
            Ok(None) => log::info!("SIAS desktop is up to date"),
            Err(err) => log::error!("update check failed: {err}"),
        }
    });
}

/// Builds without the `updater` feature (unsigned / local builds) simply point
/// the user at the releases page rather than pretending to self-update.
#[cfg(not(feature = "updater"))]
fn check_for_updates<R: Runtime>(app: &AppHandle<R>) {
    open_externally(app, RELEASES_URL);
}

// ---------------------------------------------------------------------------
// Menu handling
// ---------------------------------------------------------------------------

fn handle_menu_event<R: Runtime>(app: &AppHandle<R>, event: &MenuEvent) {
    match event.id().0.as_str() {
        menu::SWITCH_TENANT => switch_workspace(app),
        menu::RELOAD => {
            if let Some(window) = app.get_webview_window(APP_LABEL) {
                let _ = window.reload();
            }
        }
        menu::ZOOM_IN => set_zoom(app, read_zoom(app) + ZOOM_STEP),
        menu::ZOOM_OUT => set_zoom(app, read_zoom(app) - ZOOM_STEP),
        menu::ZOOM_RESET => set_zoom(app, 1.0),
        menu::TOGGLE_FULLSCREEN => {
            if let Some(window) = app.get_webview_window(APP_LABEL) {
                let full = window.is_fullscreen().unwrap_or(false);
                let _ = window.set_fullscreen(!full);
            }
        }
        menu::TOGGLE_DEVTOOLS =>
        {
            #[cfg(any(debug_assertions, feature = "devtools"))]
            if let Some(window) = app.get_webview_window(APP_LABEL) {
                if window.is_devtools_open() {
                    window.close_devtools();
                } else {
                    window.open_devtools();
                }
            }
        }
        menu::CHECK_UPDATES => check_for_updates(app),
        menu::DOCS => open_externally(app, menu::DOCS_URL),
        menu::SUPPORT => open_externally(app, menu::SUPPORT_URL),
        _ => {}
    }
}

// ---------------------------------------------------------------------------
// Commands — available to the launcher window only (see capabilities)
// ---------------------------------------------------------------------------

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
fn app_domain() -> &'static str {
    tenant::APP_DOMAIN
}

#[tauri::command]
fn saved_tenant(app: AppHandle) -> Option<String> {
    read_tenant(&app)
}

#[tauri::command]
fn forget_tenant(app: AppHandle) {
    switch_workspace(&app);
}

/// Validates whatever the user typed, remembers it, and swaps the picker for
/// the real app window. Returns the resolved slug so the UI can confirm it.
#[tauri::command]
fn open_tenant(app: AppHandle, input: String) -> Result<String, String> {
    let slug = tenant::normalize_tenant_input(&input, tenant::APP_DOMAIN).ok_or_else(|| {
        format!(
            "That is not a valid SIAS workspace. Enter your workspace name or its \
             full address, for example: acme or acme.{}",
            tenant::APP_DOMAIN
        )
    })?;

    store_put(&app, KEY_TENANT, serde_json::json!(slug));
    open_app_window(&app, &slug).map_err(|err| format!("Could not open the workspace: {err}"))?;

    if let Some(launcher) = app.get_webview_window(LAUNCHER_LABEL) {
        let _ = launcher.close();
    }
    Ok(slug)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub fn run() {
    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default()
        // Must be registered first so a second launch focuses this instance
        // instead of opening a duplicate window.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            focus_existing(app);
        }))
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_window_state::Builder::default()
                // The picker is a fixed-size first-run dialog; restoring a
                // previous geometry for it would just look broken.
                .with_denylist(&[LAUNCHER_LABEL])
                .build(),
        )
        .plugin(
            tauri_plugin_log::Builder::default()
                .level(log::LevelFilter::Info)
                .build(),
        );

    #[cfg(feature = "updater")]
    {
        builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    }

    builder
        .invoke_handler(tauri::generate_handler![
            app_version,
            app_domain,
            saved_tenant,
            open_tenant,
            forget_tenant
        ])
        .setup(|app| {
            let handle = app.handle().clone();

            let menu = menu::build(&handle)?;
            app.set_menu(menu)?;
            app.on_menu_event(|app, event| handle_menu_event(app, &event));

            match read_tenant(&handle) {
                Some(slug) => {
                    open_app_window(&handle, &slug)?;
                }
                None => {
                    open_launcher(&handle)?;
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running the SIAS desktop shell");
}
