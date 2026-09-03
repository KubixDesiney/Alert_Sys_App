//! Pure tenant-host logic for the SIAS desktop shell.
//!
//! This is a deliberate Rust mirror of `tenantFromHost` / `isValidTenantSlug`
//! in `cloudflare_app_worker.js`. The desktop app must resolve a tenant slug to
//! exactly the host the `sias-app` worker will serve, otherwise the worker's
//! per-tenant `window.__SIAS_CONFIG__` injection never happens and the app
//! boots against the wrong Firebase project (or a branded 404).
//!
//! Everything here is dependency-free and unit-tested — no Tauri types, no I/O.

/// Root domain every tenant lives under: `https://<tenant>.kubixdesiney.com`.
pub const APP_DOMAIN: &str = "kubixdesiney.com";

/// Labels the worker never treats as a tenant (storefront + infra).
/// Keep in sync with `RESERVED_SUBDOMAINS` in `cloudflare_app_worker.js`.
pub const RESERVED_SUBDOMAINS: &[&str] = &[
    "www",
    "sias",
    "store",
    "api",
    "app",
    "mail",
    "smtp",
    "ns1",
    "ns2",
    "cdn",
    "assets",
    "static",
    "admin",
    "dashboard",
    "status",
];

/// Hosts allowed to take over the app window as a top-level navigation.
/// These are the identity providers a tenant may redirect to during SSO/SAML
/// sign-in; anything not listed here is opened in the user's real browser
/// instead, so the app window can never be navigated somewhere unexpected.
/// An entry starting with `.` matches that domain and any subdomain of it.
const AUTH_HOST_SUFFIXES: &[&str] = &[
    "accounts.google.com",
    "login.microsoftonline.com",
    ".firebaseapp.com",
    ".web.app",
    ".googleapis.com",
    ".gstatic.com",
    ".okta.com",
    ".auth0.com",
    ".onelogin.com",
    ".pingidentity.com",
];

/// What to do with a top-level navigation request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NavDecision {
    /// Load it in the app window.
    Allow,
    /// Hand it to the OS default browser and keep the app window put.
    External,
}

/// Same slug shape `tool/provision_instance.mjs` enforces:
/// `^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$`, capped at one DNS label.
pub fn is_valid_slug(slug: &str) -> bool {
    let b = slug.as_bytes();
    if b.is_empty() || b.len() > 63 {
        return false;
    }
    let alnum = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit();
    if !alnum(b[0]) || !alnum(b[b.len() - 1]) {
        return false;
    }
    b.iter().all(|&c| alnum(c) || c == b'-')
}

/// Extracts the lowercase hostname from an absolute http(s) URL.
/// Returns `None` for any other scheme (`mailto:`, `tel:`, `file:`, ...), which
/// is what makes those navigations fall through to the external browser.
pub fn host_of(url: &str) -> Option<String> {
    // Lowercase up front: the scheme match, the host we return, and every
    // comparison downstream are all case-insensitive anyway.
    let lower = url.trim().to_ascii_lowercase();
    let rest = lower
        .strip_prefix("https://")
        .or_else(|| lower.strip_prefix("http://"))?;

    // authority = everything before the path / query / fragment
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    // drop any `user:pass@` userinfo prefix
    let authority = authority.rsplit('@').next().unwrap_or(authority);

    let host = if let Some(after) = authority.strip_prefix('[') {
        // IPv6 literal: `[::1]:8080`
        after.split(']').next().unwrap_or("")
    } else {
        authority.split(':').next().unwrap_or("")
    };

    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

/// Accepts anything a human might paste — `acme`, `ACME`,
/// `acme.kubixdesiney.com`, `https://acme.kubixdesiney.com/dashboard?x=1` —
/// and returns the bare tenant slug, or `None` when it is not a servable tenant.
pub fn normalize_tenant_input(raw: &str, app_domain: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    // Either a full URL, or a bare host / slug that may still carry a path.
    let host = match host_of(trimmed) {
        Some(h) => h,
        None => {
            let no_path = trimmed.split(['/', '?', '#']).next().unwrap_or("");
            let no_port = no_path.split(':').next().unwrap_or("");
            no_port.trim().trim_end_matches('.').to_ascii_lowercase()
        }
    };
    if host.is_empty() {
        return None;
    }

    let domain = app_domain.trim().trim_end_matches('.').to_ascii_lowercase();
    if host == domain {
        return None; // the apex is never a tenant
    }

    let label = match host.strip_suffix(&format!(".{domain}")) {
        Some(l) => l,
        // A bare slug was given. Reject any other domain outright rather than
        // silently treating `evil.com` as the tenant slug `evil.com`.
        None if host.contains('.') => return None,
        None => host.as_str(),
    };

    if label.is_empty() || label.contains('.') {
        return None; // exactly one level deep, matching Universal SSL coverage
    }
    if RESERVED_SUBDOMAINS.contains(&label) || !is_valid_slug(label) {
        return None;
    }
    Some(label.to_string())
}

/// `acme` -> `acme.kubixdesiney.com`
pub fn tenant_host(slug: &str, app_domain: &str) -> String {
    format!("{slug}.{app_domain}")
}

/// The URL the app window loads.
pub fn tenant_url(slug: &str, app_domain: &str) -> String {
    format!("https://{}/", tenant_host(slug, app_domain))
}

fn matches_auth_host(host: &str) -> bool {
    AUTH_HOST_SUFFIXES.iter().any(|entry| {
        match entry.strip_prefix('.') {
            // ".okta.com" matches "okta.com" and "acme.okta.com"
            Some(bare) => host == bare || host.ends_with(entry),
            None => host == *entry,
        }
    })
}

/// Decides whether a top-level navigation stays in the app window.
pub fn classify_navigation(url: &str, tenant: &str, app_domain: &str) -> NavDecision {
    let s = url.trim();

    // Internal webview URLs (the launcher page, blank targets) always load.
    if s.is_empty()
        || s.starts_with("about:")
        || s.starts_with("tauri://")
        || s.starts_with("http://tauri.localhost")
        || s.starts_with("https://tauri.localhost")
    {
        return NavDecision::Allow;
    }

    let Some(host) = host_of(s) else {
        // mailto:, tel:, file:, custom schemes -> the OS knows what to do.
        return NavDecision::External;
    };

    let domain = app_domain.trim().trim_end_matches('.').to_ascii_lowercase();
    if host == tenant_host(tenant, &domain)
        || host == domain
        || host.ends_with(&format!(".{domain}"))
        || matches_auth_host(&host)
    {
        NavDecision::Allow
    } else {
        NavDecision::External
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const D: &str = APP_DOMAIN;

    #[test]
    fn slug_shape_matches_the_worker() {
        for good in ["acme", "a", "a1", "north-star", "x9-y8-z7", "0abc"] {
            assert!(is_valid_slug(good), "{good} should be valid");
        }
        let too_long = "a".repeat(64);
        let bad: [&str; 8] = [
            "", "-acme", "acme-", "ACME", "ac_me", "ac me", "acme.co", &too_long,
        ];
        for b in bad {
            assert!(!is_valid_slug(b), "{b} should be invalid");
        }
    }

    #[test]
    fn host_of_extracts_hostnames_and_rejects_other_schemes() {
        assert_eq!(
            host_of("https://acme.kubixdesiney.com/x?y=1#z").as_deref(),
            Some("acme.kubixdesiney.com")
        );
        assert_eq!(
            host_of("http://Acme.Kubixdesiney.com:8080").as_deref(),
            Some("acme.kubixdesiney.com")
        );
        assert_eq!(
            host_of("https://user:pw@acme.kubixdesiney.com/").as_deref(),
            Some("acme.kubixdesiney.com")
        );
        assert_eq!(
            host_of("https://acme.kubixdesiney.com./").as_deref(),
            Some("acme.kubixdesiney.com")
        );
        assert_eq!(host_of("https://[::1]:8080/x").as_deref(), Some("::1"));
        assert_eq!(host_of("mailto:ops@example.com"), None);
        assert_eq!(host_of("file:///etc/passwd"), None);
        assert_eq!(host_of("https://"), None);
    }

    #[test]
    fn normalize_accepts_every_shape_a_human_pastes() {
        for input in [
            "acme",
            "  ACME ",
            "acme.kubixdesiney.com",
            "https://acme.kubixdesiney.com",
            "https://acme.kubixdesiney.com/",
            "https://ACME.kubixdesiney.com/dashboard?tab=alerts#top",
            "acme.kubixdesiney.com/dashboard",
        ] {
            assert_eq!(
                normalize_tenant_input(input, D).as_deref(),
                Some("acme"),
                "input: {input}"
            );
        }
    }

    #[test]
    fn normalize_rejects_non_tenants() {
        for input in [
            "",
            "   ",
            "sias",                          // storefront
            "www",                           // reserved
            "status",                        // reserved
            "https://sias.kubixdesiney.com", // storefront by URL
            "kubixdesiney.com",              // apex
            "https://kubixdesiney.com",      // apex by URL
            "a.b.kubixdesiney.com",          // two levels deep
            "evil.com",                      // foreign domain
            "https://acme.evil.com",         // lookalike
            "-acme",
            "ACME_CORP",
        ] {
            assert_eq!(normalize_tenant_input(input, D), None, "input: {input}");
        }
    }

    #[test]
    fn urls_point_at_the_worker() {
        assert_eq!(tenant_host("acme", D), "acme.kubixdesiney.com");
        assert_eq!(tenant_url("acme", D), "https://acme.kubixdesiney.com/");
    }

    #[test]
    fn navigation_keeps_product_hosts_in_app() {
        for url in [
            "https://acme.kubixdesiney.com/dashboard",
            "https://kubixdesiney.com/",
            "https://sias.kubixdesiney.com/copilot",
            "https://other-tenant.kubixdesiney.com/",
            "https://accounts.google.com/o/oauth2/auth",
            "https://acme-corp.okta.com/login",
            "https://okta.com/",
            "https://alertappsys.firebaseapp.com/__/auth/handler",
            "about:blank",
        ] {
            assert_eq!(
                classify_navigation(url, "acme", D),
                NavDecision::Allow,
                "url: {url}"
            );
        }
    }

    #[test]
    fn navigation_pushes_everything_else_to_the_browser() {
        for url in [
            "https://evil.com/phish",
            "https://kubixdesiney.com.evil.com/", // suffix-confusion attempt
            "https://notokta.com/",
            "http://192.168.1.1/",
            "mailto:sales@kubixdesiney.com",
            "tel:+21600000000",
            "file:///C:/Windows/System32",
        ] {
            assert_eq!(
                classify_navigation(url, "acme", D),
                NavDecision::External,
                "url: {url}"
            );
        }
    }
}
