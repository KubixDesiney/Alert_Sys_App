// SIAS desktop — workspace picker.
//
// The only job of this page is to turn whatever the operator types into a
// validated tenant slug and hand it to the Rust side, which owns the real
// window. Validation here is a *fast, friendly mirror* of src-tauri/src/tenant.rs;
// Rust re-validates everything it is given, so this file is never the security
// boundary — it only exists so the user gets an instant, specific error.

(() => {
  "use strict";

  const RESERVED = new Set([
    "www", "sias", "store", "api", "app", "mail", "smtp", "ns1", "ns2", "cdn",
    "assets", "static", "admin", "dashboard", "status",
  ]);

  const form = document.getElementById("form");
  const input = document.getElementById("tenant");
  const field = input.closest(".field");
  const suffix = document.getElementById("suffix");
  const button = document.getElementById("submit");
  const status = document.getElementById("status");
  const version = document.getElementById("version");

  let appDomain = "kubixdesiney.com";
  let busy = false;

  const invoke = (cmd, args) => {
    const api = window.__TAURI__;
    if (!api || !api.core || typeof api.core.invoke !== "function") {
      return Promise.reject(new Error("This page must run inside the SIAS desktop app."));
    }
    return api.core.invoke(cmd, args);
  };

  // --- Validation (mirror of tenant.rs) -------------------------------------

  const isValidSlug = (slug) =>
    slug.length > 0 && slug.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(slug);

  /** Returns the tenant slug for anything a human might paste, or null. */
  function normalizeTenant(raw, domain) {
    let host = String(raw || "").trim().toLowerCase();
    if (!host) return null;

    host = host.replace(/^https?:\/\//, "");
    host = host.split(/[/?#]/)[0];
    host = host.replace(/^[^@]*@/, "");
    host = host.split(":")[0];
    host = host.replace(/\.$/, "");
    if (!host) return null;

    if (host === domain) return null; // the apex is never a tenant

    let label;
    if (host.endsWith("." + domain)) {
      label = host.slice(0, -(domain.length + 1));
    } else if (host.includes(".")) {
      return null; // a foreign domain, not a workspace name
    } else {
      label = host;
    }

    if (!label || label.includes(".")) return null;
    if (RESERVED.has(label) || !isValidSlug(label)) return null;
    return label;
  }

  // --- UI helpers -----------------------------------------------------------

  // `blameField` is deliberate: a startup failure is not the operator typing
  // something wrong, so it must not paint the input red.
  function setStatus(message, kind, blameField = kind === "error") {
    status.textContent = message || "";
    status.className = "status" + (kind ? " " + kind : "");
    field.classList.toggle("invalid", Boolean(blameField));
  }

  function setBusy(next) {
    busy = next;
    button.disabled = next;
    input.readOnly = next;
    button.classList.toggle("busy", next);
    button.querySelector(".label").textContent = next ? "Connecting..." : "Continue";
  }

  function syncSuffix() {
    // Once the user types a dot, slash or colon they are giving a full address,
    // so the decorative ".kubixdesiney.com" would be actively misleading. While
    // they are typing a bare name -- including before they start -- it is the
    // clearest possible hint about what the field expects.
    suffix.classList.toggle("hidden", /[.:/]/.test(input.value));
  }

  // --- Reachability probe ---------------------------------------------------

  /**
   * Asks the sias-app worker whether this workspace exists and is provisioned.
   * `/__config` answers for ANY host and never exposes secrets:
   *   { ok: true, tenant: "acme" | null, hasConfig: true|false }
   * Returns "ready" | "unprovisioned" | "unknown" | "offline".
   */
  async function probeTenant(slug) {
    const url = `https://${slug}.${appDomain}/__config`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
      const res = await fetch(url, { signal: controller.signal, cache: "no-store" });
      if (!res.ok) return "unknown";
      const body = await res.json();
      if (!body || body.tenant !== slug) return "unknown";
      return body.hasConfig ? "ready" : "unprovisioned";
    } catch (_) {
      return "offline";
    } finally {
      clearTimeout(timer);
    }
  }

  // --- Submit ---------------------------------------------------------------

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (busy) return;

    const raw = input.value.trim();
    if (!raw) {
      setStatus("Enter your workspace name to continue.", "error");
      input.focus();
      return;
    }

    const slug = normalizeTenant(raw, appDomain);
    if (!slug) {
      setStatus(
        `That is not a valid SIAS workspace. Try your workspace name (for example "acme") ` +
          `or its full address (acme.${appDomain}).`,
        "error",
      );
      input.focus();
      input.select();
      return;
    }

    setBusy(true);
    setStatus(`Checking ${slug}.${appDomain}...`);

    const result = await probeTenant(slug);
    if (result === "unknown") {
      setBusy(false);
      setStatus(
        `No SIAS workspace called "${slug}" exists. Check the spelling with your administrator.`,
        "error",
      );
      input.focus();
      input.select();
      return;
    }
    if (result === "unprovisioned") {
      setBusy(false);
      setStatus(
        `"${slug}" is not finished provisioning yet. Your activation email arrives when it is ready.`,
        "error",
      );
      return;
    }
    // "offline" still proceeds: the slug is well-formed and the app itself
    // handles reconnecting far better than this picker can.
    if (result === "offline") {
      setStatus("No connection - opening anyway...");
    } else {
      setStatus(`Workspace found. Opening ${slug}...`, "ok");
    }

    try {
      await invoke("open_tenant", { input: slug });
      // On success the Rust side closes this window; nothing else to do.
    } catch (err) {
      setBusy(false);
      setStatus(String(err && err.message ? err.message : err), "error");
    }
  });

  input.addEventListener("input", () => {
    syncSuffix();
    if (status.classList.contains("error")) setStatus("");
  });

  // --- Boot -----------------------------------------------------------------

  (async () => {
    try {
      const [domain, appVersion, saved] = await Promise.all([
        invoke("app_domain"),
        invoke("app_version"),
        invoke("saved_tenant"),
      ]);
      if (domain) {
        appDomain = domain;
        suffix.textContent = "." + domain;
      }
      version.textContent = appVersion ? `Version ${appVersion}` : "";
      if (saved) input.value = saved;
    } catch (err) {
      setStatus(String(err && err.message ? err.message : err), "error", false);
    }
    syncSuffix();
    input.focus();
  })();
})();
