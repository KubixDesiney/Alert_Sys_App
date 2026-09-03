fn main() {
    // App-defined commands are ACL-gated in Tauri v2 exactly like plugin
    // commands. Listing them here autogenerates `allow-<kebab-command>`
    // permissions, which capabilities/default.json grants to the launcher
    // window only — the remote tenant window never gets IPC.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "saved_tenant",
            "open_tenant",
            "forget_tenant",
            "app_version",
            "app_domain",
        ]),
    ))
    .expect("failed to run tauri-build");
}
