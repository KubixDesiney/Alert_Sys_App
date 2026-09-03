//! Native application menu.
//!
//! The menu is the only chrome the desktop shell adds — the SIAS web UI itself
//! is rendered untouched inside the window. On macOS the Edit submenu is not
//! cosmetic: WKWebView only honours Cmd+C / Cmd+V when the standard edit items
//! exist in the menu bar, so removing it silently breaks copy/paste.

use tauri::menu::{AboutMetadataBuilder, Menu, MenuItemBuilder, SubmenuBuilder};
use tauri::{AppHandle, Runtime};

pub const SWITCH_TENANT: &str = "sias:switch-tenant";
pub const RELOAD: &str = "sias:reload";
pub const ZOOM_IN: &str = "sias:zoom-in";
pub const ZOOM_OUT: &str = "sias:zoom-out";
pub const ZOOM_RESET: &str = "sias:zoom-reset";
pub const TOGGLE_FULLSCREEN: &str = "sias:fullscreen";
pub const TOGGLE_DEVTOOLS: &str = "sias:devtools";
pub const CHECK_UPDATES: &str = "sias:check-updates";
pub const DOCS: &str = "sias:docs";
pub const SUPPORT: &str = "sias:support";

pub const DOCS_URL: &str = "https://sias.kubixdesiney.com";
pub const SUPPORT_URL: &str = "mailto:support@kubixdesiney.com";

/// Builds the full menu bar for the current platform.
pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let pkg = app.package_info();
    let about = AboutMetadataBuilder::new()
        .name(Some("SIAS"))
        .version(Some(pkg.version.to_string()))
        .authors(Some(vec!["KubixDesiney".into()]))
        .comments(Some("Smart Industrial Alert System"))
        .copyright(Some("Copyright (c) 2026 KubixDesiney"))
        .website(Some(DOCS_URL))
        .website_label(Some("kubixdesiney.com"))
        .build();

    let switch_tenant = MenuItemBuilder::with_id(SWITCH_TENANT, "Switch Workspace...")
        .accelerator("CmdOrCtrl+Shift+O")
        .build(app)?;
    let check_updates =
        MenuItemBuilder::with_id(CHECK_UPDATES, "Check for Updates...").build(app)?;

    // --- App / File -----------------------------------------------------------
    #[cfg(target_os = "macos")]
    let first = SubmenuBuilder::new(app, "SIAS")
        .about(Some(about))
        .separator()
        .item(&check_updates)
        .separator()
        .item(&switch_tenant)
        .separator()
        .services()
        .separator()
        .hide()
        .hide_others()
        .show_all()
        .separator()
        .quit()
        .build()?;

    #[cfg(not(target_os = "macos"))]
    let first = SubmenuBuilder::new(app, "&File")
        .item(&switch_tenant)
        .separator()
        .quit()
        .build()?;

    // --- Edit -----------------------------------------------------------------
    let edit = SubmenuBuilder::new(app, "&Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;

    // --- View -----------------------------------------------------------------
    let reload = MenuItemBuilder::with_id(RELOAD, "Reload")
        .accelerator("CmdOrCtrl+R")
        .build(app)?;
    let zoom_in = MenuItemBuilder::with_id(ZOOM_IN, "Zoom In")
        .accelerator("CmdOrCtrl+=")
        .build(app)?;
    let zoom_out = MenuItemBuilder::with_id(ZOOM_OUT, "Zoom Out")
        .accelerator("CmdOrCtrl+-")
        .build(app)?;
    let zoom_reset = MenuItemBuilder::with_id(ZOOM_RESET, "Actual Size")
        .accelerator("CmdOrCtrl+0")
        .build(app)?;

    #[allow(unused_mut)]
    let mut view = SubmenuBuilder::new(app, "&View")
        .item(&reload)
        .separator()
        .item(&zoom_in)
        .item(&zoom_out)
        .item(&zoom_reset)
        .separator();

    // `fullscreen()` is a macOS-only predefined item; elsewhere we toggle the
    // window ourselves from the menu event handler.
    #[cfg(target_os = "macos")]
    {
        view = view.fullscreen();
    }
    #[cfg(not(target_os = "macos"))]
    {
        let fullscreen = MenuItemBuilder::with_id(TOGGLE_FULLSCREEN, "Toggle Full Screen")
            .accelerator("F11")
            .build(app)?;
        view = view.item(&fullscreen);
    }

    #[cfg(any(debug_assertions, feature = "devtools"))]
    {
        let devtools = MenuItemBuilder::with_id(TOGGLE_DEVTOOLS, "Toggle Developer Tools")
            .accelerator("CmdOrCtrl+Shift+I")
            .build(app)?;
        view = view.separator().item(&devtools);
    }

    let view = view.build()?;

    // --- Help -----------------------------------------------------------------
    let docs = MenuItemBuilder::with_id(DOCS, "SIAS Documentation").build(app)?;
    let support = MenuItemBuilder::with_id(SUPPORT, "Contact Support").build(app)?;

    #[allow(unused_mut)]
    let mut help = SubmenuBuilder::new(app, "&Help").item(&docs).item(&support);
    #[cfg(not(target_os = "macos"))]
    {
        help = help
            .separator()
            .item(&check_updates)
            .separator()
            .about(Some(about));
    }
    let help = help.build()?;

    #[allow(unused_mut)]
    let mut menu = tauri::menu::MenuBuilder::new(app)
        .item(&first)
        .item(&edit)
        .item(&view);

    // macOS expects a Window menu between View and Help.
    #[cfg(target_os = "macos")]
    {
        let window = SubmenuBuilder::new(app, "Window")
            .minimize()
            .separator()
            .close_window()
            .build()?;
        menu = menu.item(&window);
    }

    menu.item(&help).build()
}
