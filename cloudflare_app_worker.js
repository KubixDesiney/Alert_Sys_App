// =============================================================================
// SIAS App Worker (`sias-app`) — one shared worker serves the Flutter web app
// to every tenant at <tenant>.kubixdesiney.com.
// =============================================================================
// Design (see CLAUDE.md "Per-Tenant App Delivery"):
//   - ONE worker serves the same Flutter web build (build/web, via the ASSETS
//     binding) to all tenants. App updates ship once, not once per customer.
//   - The tenant is resolved from the Host header. That tenant's PUBLIC Firebase
//     config + worker URLs live in the TENANTS KV namespace and are injected
//     into index.html as `window.__SIAS_CONFIG__` before flutter_bootstrap runs.
//   - Isolation is unchanged: Firebase client config is public by design;
//     isolation comes from each tenant's own Auth realm + RTDB rules. This
//     worker only serves static assets + a config blob — it never touches data.
//
// Routes (per tenant host):
//   GET /__config     { ok, tenant, hasConfig } probe (NEVER dumps secrets)
//   GET /__swconfig   that tenant's Firebase messaging config as JSON (the web
//                     push service worker fetches this instead of hardcoding it)
//   GET /app          branded Android APK download page (QR + direct link)
//   GET /app/<file>   streams the tenant's release APK from the APKS R2 bucket
//   * (everything else) static asset, or index.html (with config injected) for
//     SPA routes via not_found_handling = "single-page-application"
//
// Unknown/unprovisioned hosts (apex, www, the storefront host, a tenant with no
// KV entry) get a branded 404 page.
//
// Bindings (wrangler.app.toml):
//   ASSETS   static-assets binding for ./build/web
//   TENANTS  KV namespace: key = tenant slug, value = JSON
//            { tenantCode, company, firebase:{...}, workers:{ai,notify,ingest,copilotUrl} }
//   APKS     R2 bucket holding per-tenant release APKs (key: <tenant>/sias-<tenant>.apk)
// Vars: APP_DOMAIN (default "kubixdesiney.com"), STOREFRONT_URL
// =============================================================================

import { qrSvg } from './qr_svg.js';

export const APP_DOMAIN = 'kubixdesiney.com';

// Subdomains that are never a tenant: the storefront + common infra labels.
export const RESERVED_SUBDOMAINS = new Set([
  'www', 'sias', 'store', 'api', 'app', 'mail', 'smtp', 'ns1', 'ns2', 'cdn',
  'assets', 'static', 'admin', 'dashboard', 'status',
]);

// Same slug shape provisioning enforces (tool/provision_instance.mjs).
export function isValidTenantSlug(slug) {
  return typeof slug === 'string' && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(slug);
}

/**
 * Resolves a request Host header to a tenant slug, or null when the host is not
 * a servable tenant subdomain. Handles case, a trailing port, the apex, `www`,
 * the storefront/infra labels, and rejects anything more than one label deep
 * (Universal SSL only covers `*.kubixdesiney.com` one level).
 */
export function tenantFromHost(hostname, { appDomain = APP_DOMAIN } = {}) {
  if (!hostname || typeof hostname !== 'string') return null;
  const domain = String(appDomain || APP_DOMAIN).toLowerCase().trim().replace(/\.$/, '');
  const host = hostname.toLowerCase().trim().replace(/\.$/, '').split(':')[0];
  if (!host || host === domain) return null;
  const suffix = `.${domain}`;
  if (!host.endsWith(suffix)) return null;
  const label = host.slice(0, -suffix.length);
  if (!label || label.includes('.')) return null;   // exactly one level deep
  if (RESERVED_SUBDOMAINS.has(label)) return null;
  if (!isValidTenantSlug(label)) return null;
  return label;
}

// --- Runtime config injection ---------------------------------------------------

/** JSON.stringify that is safe to embed inside an inline <script>. */
export function escapeConfigJson(obj) {
  // JSON.stringify leaves '<' and the raw U+2028/U+2029 line separators
  // intact; all three are unsafe inside an inline <script>, so escape them.
  return JSON.stringify(obj ?? {}).replace(/[<\u2028\u2029]/g, (c) => (
    { '<': '\\u003c', '\u2028': '\\u2028', '\u2029': '\\u2029' }[c]
  ));
}

/** The exact blob written to window.__SIAS_CONFIG__ for a tenant. */
export function injectedConfig(tenant, config) {
  const c = config || {};
  return {
    tenant,
    tenantCode: c.tenantCode ?? null,
    company: c.company ?? null,
    firebase: c.firebase ?? {},
    workers: c.workers ?? {},
  };
}

/**
 * Injects `<script>window.__SIAS_CONFIG__ = {...}</script>` into the Flutter
 * index.html, immediately before the flutter_bootstrap loader so it is defined
 * before any Dart code runs. Also guarantees a `<base href="/">`. Pure string
 * transform — the caller supplies the CSP nonce.
 */
export function injectRuntimeConfig(markup, config, nonce) {
  let out = String(markup);
  const scriptTag =
    `<script nonce="${nonce}">window.__SIAS_CONFIG__=${escapeConfigJson(config)};</script>`;

  if (!/<base\s/i.test(out)) {
    out = out.replace(/<head(\s[^>]*)?>/i, (m) => `${m}\n  <base href="/">`);
  }

  const bootstrapRe = /<script\s+src="flutter_bootstrap\.js"[^>]*>\s*<\/script>/i;
  if (bootstrapRe.test(out)) {
    return out.replace(bootstrapRe, (m) => `${scriptTag}\n  ${m}`);
  }
  if (/<\/body>/i.test(out)) {
    return out.replace(/<\/body>/i, `${scriptTag}\n</body>`);
  }
  return out + scriptTag;
}

// --- Security headers ------------------------------------------------------------
// Deliberately broader than the storefront CSP: this HTML boots a live Flutter +
// Firebase SPA that needs wasm eval, CanvasKit from gstatic, Google Maps, and
// websocket/https connections to Firebase + the tenant workers. The one inline
// script we add (the config blob) is still nonce-pinned; there is no
// 'unsafe-inline' in script-src. connect-src/img-src stay broad on purpose and
// can be tightened per tenant once the exact host set is pinned.
export function contentSecurityPolicy(nonce) {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'wasm-unsafe-eval' https://www.gstatic.com https://maps.googleapis.com`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' https://fonts.gstatic.com data:",
    "img-src 'self' data: blob: https:",
    "connect-src 'self' https: wss:",
    "worker-src 'self' blob:",
    "frame-src 'self' https://*.firebaseapp.com https://accounts.google.com",
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
  ].join('; ');
}

// The app needs geolocation (supervisor tracking), microphone (voice) and camera
// (web QR scan) — so those are self-allowed, unlike the locked-down storefront.
function securityHeaders(nonce, extra = {}) {
  return {
    'Content-Security-Policy': contentSecurityPolicy(nonce),
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'geolocation=(self), microphone=(self), camera=(self), payment=()',
    ...extra,
  };
}

function htmlResponse(markup, { status = 200, cache = 'no-store' } = {}) {
  const nonce = crypto.randomUUID().replace(/-/g, '');
  // Stamp attribute-less <script> tags (page-authored inline scripts) with the
  // nonce; scripts we author with an explicit nonce already carry theirs.
  const body = markup.replaceAll('<script>', `<script nonce="${nonce}">`);
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': cache,
      ...securityHeaders(nonce),
    },
  });
}

/** Serves an already-nonced Flutter index.html (config injected by the caller). */
function appHtmlResponse(markup, nonce) {
  return new Response(markup, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      ...securityHeaders(nonce),
    },
  });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

// --- Service-worker messaging config --------------------------------------------
/** The minimal Firebase config the web push service worker needs. */
export function swConfigObject(config) {
  const f = (config && config.firebase) || {};
  return {
    apiKey: f.apiKey || '',
    authDomain: f.authDomain || '',
    projectId: f.projectId || '',
    storageBucket: f.storageBucket || '',
    messagingSenderId: f.messagingSenderId || '',
    appId: f.appId || '',
  };
}

// --- APK delivery (Prompt 2) ----------------------------------------------------
/** The download filename supervisors get: sias-<tenant>.apk. */
export function apkFileName(tenant) {
  return `sias-${tenant}.apk`;
}

/** R2 object key for a tenant's APK: <tenant>/sias-<tenant>.apk. */
export function apkObjectKey(tenant) {
  return `${tenant}/${apkFileName(tenant)}`;
}

/**
 * Resolves a `/app/<file>` request to the R2 object key, or null if the
 * filename isn't this tenant's canonical APK (blocks path traversal / probing).
 */
export function resolveApkKey(tenant, pathname) {
  try {
    const file = decodeURIComponent(String(pathname).replace(/^\/app\//, ''));
    if (file !== apkFileName(tenant)) return null;
    return apkObjectKey(tenant);
  } catch {
    // A malformed percent escape is a bad asset path, not a Worker failure.
    return null;
  }
}

// =============================================================================
// KV lookup (60s in-isolate cache — KV is eventually consistent; a short cache
// avoids a read per request without making credential rotation feel slow).
// =============================================================================
const _tenantCache = new Map();
const TENANT_CACHE_MS = 60000;

async function loadTenantConfig(env, tenant) {
  if (!tenant) return null;
  const now = Date.now();
  const hit = _tenantCache.get(tenant);
  if (hit && hit.exp > now) return hit.config;
  let config = null;
  try {
    config = env.TENANTS ? await env.TENANTS.get(tenant, 'json') : null;
  } catch {
    config = null;
  }
  _tenantCache.set(tenant, { config, exp: now + TENANT_CACHE_MS });
  return config;
}

// =============================================================================
// Worker entry
// =============================================================================
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const { pathname } = url;
    const appDomain = env.APP_DOMAIN || APP_DOMAIN;
    const tenant = tenantFromHost(url.hostname, { appDomain });
    const config = tenant ? await loadTenantConfig(env, tenant) : null;

    try {
      // Probe endpoint answers for any host (never exposes secrets).
      if (pathname === '/__config') {
        return json({ ok: true, tenant: tenant || null, hasConfig: !!config });
      }

      // Unknown or unprovisioned host → branded 404 for everything else.
      if (!tenant || !config) {
        if (pathname === '/__swconfig') return json({ ok: false, error: 'unknown tenant' }, 404);
        return htmlResponse(notFoundPage(url.hostname, env), { status: 404 });
      }

      if (pathname === '/__swconfig') {
        return json(swConfigObject(config));
      }
      if (pathname === '/app') {
        return htmlResponse(appDownloadPage(tenant, config, url, env));
      }
      if (pathname.startsWith('/app/')) {
        return serveApk(request, env, tenant, pathname);
      }

      // Static assets + SPA fallback (not_found_handling serves index.html).
      const assetResp = await env.ASSETS.fetch(request);
      const contentType = assetResp.headers.get('content-type') || '';
      if (contentType.includes('text/html')) {
        const nonce = crypto.randomUUID().replace(/-/g, '');
        const markup = await assetResp.text();
        const injected = injectRuntimeConfig(markup, injectedConfig(tenant, config), nonce);
        return appHtmlResponse(injected, nonce);
      }
      // Non-HTML asset: pass the (possibly streamed) body through, add nosniff.
      const headers = new Headers(assetResp.headers);
      headers.set('X-Content-Type-Options', 'nosniff');
      return new Response(assetResp.body, { status: assetResp.status, headers });
    } catch (e) {
      return json({ ok: false, error: String(e?.message || e) }, 500);
    }
  },
};

async function serveApk(request, env, tenant, pathname) {
  const key = resolveApkKey(tenant, pathname);
  if (!key || !env.APKS) {
    return htmlResponse(notFoundPage(request.headers.get('host') || tenant, env, 'APK not found'), { status: 404 });
  }
  const object = await env.APKS.get(key);
  if (!object) {
    return htmlResponse(
      appDownloadPage(tenant, await loadTenantConfig(env, tenant), new URL(request.url), env, {
        pending: true,
      }),
      { status: 404 },
    );
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Content-Type', 'application/vnd.android.package-archive');
  headers.set('Content-Disposition', `attachment; filename="${apkFileName(tenant)}"`);
  headers.set('Cache-Control', 'public, max-age=300');
  headers.set('X-Content-Type-Options', 'nosniff');
  return new Response(object.body, { headers });
}

// =============================================================================
// Pages
// =============================================================================
function storefrontUrl(env) {
  return env.STOREFRONT_URL || `https://sias.${env.APP_DOMAIN || APP_DOMAIN}`;
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

const PAGE_CSS = `
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;font-family:'Inter',system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;
  background:radial-gradient(1200px 600px at 50% -10%,#13233f 0%,#0a1120 55%,#070b16 100%);
  color:#e5edf9;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:32px}
.card{width:100%;max-width:520px;background:rgba(17,26,45,.72);border:1px solid rgba(120,160,220,.18);
  border-radius:22px;padding:38px 34px;box-shadow:0 30px 80px -30px rgba(0,0,0,.7);backdrop-filter:blur(10px)}
.mark{display:inline-flex;align-items:center;gap:10px;font-weight:700;letter-spacing:.5px;font-size:15px;color:#9fc0ff}
.mark .tri{color:#f5a524;font-size:18px}
h1{font-size:23px;margin:18px 0 6px;font-weight:700;letter-spacing:-.3px}
p{margin:8px 0;color:#a7b6cf;line-height:1.55;font-size:14.5px}
.company{color:#f5a524;font-weight:600}
.qr{background:#fff;border-radius:16px;padding:16px;display:flex;justify-content:center;margin:22px 0 14px}
.qr svg{width:100%;height:auto;max-width:230px;display:block}
.url{display:flex;gap:8px;align-items:center;margin-top:14px}
.url code{flex:1;background:rgba(9,14,26,.8);border:1px solid rgba(120,160,220,.2);border-radius:10px;
  padding:11px 13px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;color:#cfe0ff;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.btn{border:0;cursor:pointer;border-radius:10px;padding:11px 15px;font-weight:600;font-size:13px;
  background:#2f6df6;color:#fff;text-decoration:none;display:inline-flex;align-items:center;justify-content:center}
.btn.copy{background:rgba(120,160,220,.16);color:#cfe0ff;border:1px solid rgba(120,160,220,.24)}
.dl{display:block;text-align:center;margin-top:16px}
.note{margin-top:22px;padding:14px 16px;border-radius:12px;background:rgba(9,14,26,.55);
  border:1px solid rgba(120,160,220,.14);font-size:12.8px;color:#8ea3c4}
.note b{color:#cfe0ff}
.foot{margin-top:22px;font-size:12px;color:#6f819e;text-align:center}
.foot a{color:#9fc0ff;text-decoration:none}
.badge{display:inline-block;margin-top:4px;font-size:11px;letter-spacing:1px;text-transform:uppercase;
  color:#7f93b4;font-weight:600}
`;

function shell(title, bodyInner, { lang = 'en' } = {}) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${esc(title)}</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%23F59E0B' d='M12 2a7 7 0 0 0-7 7v3.3L3.3 16a1 1 0 0 0 .9 1.5h15.6a1 1 0 0 0 .9-1.5L19 12.3V9a7 7 0 0 0-7-7Z'/%3E%3C/svg%3E">
<style>${PAGE_CSS}</style>
</head>
<body><main class="card">${bodyInner}</main></body>
</html>`;
}

function notFoundPage(hostname, env, reason = '') {
  const store = storefrontUrl(env);
  return shell('Workspace not found — SIAS', `
  <div class="mark"><span class="tri">&#9650;</span>SIAS</div>
  <h1>This workspace isn't set up${reason ? '' : ''}</h1>
  <p><code style="color:#cfe0ff">${esc(hostname)}</code> isn't a recognized SIAS workspace${reason ? ` — ${esc(reason)}` : ''}.</p>
  <p>If your company has a SIAS instance, double-check the address your administrator
     shared with you. Each customer's app lives at
     <b style="color:#cfe0ff">yourcompany.${esc(env.APP_DOMAIN || APP_DOMAIN)}</b>.</p>
  <div class="note">Looking for SIAS? Visit the product site to see plans and request a
     dedicated instance.</div>
  <div class="foot"><a href="${esc(store)}">${esc(store.replace(/^https?:\/\//, ''))}</a></div>
  `);
}

function appDownloadPage(tenant, config, url, env, { pending = false } = {}) {
  const company = (config && config.company) || 'Your workspace';
  const apkUrl = `${url.origin}/app/${apkFileName(tenant)}`;
  const webUrl = url.origin;
  const svg = qrSvg(apkUrl, { moduleSize: 6, margin: 4 });
  const pendingNote = pending
    ? `<div class="note" style="border-color:rgba(245,165,36,.35)"><b>Build pending.</b> This
        tenant's Android app hasn't been published yet. Ask your administrator to run the
        APK build, or use the web app below — it works right now with no install.</div>`
    : '';
  return shell(`Install the ${esc(company)} app — SIAS`, `
  <div class="mark"><span class="tri">&#9650;</span>SIAS</div>
  <span class="badge">Android app</span>
  <h1>Install SIAS on your phone</h1>
  <p>The <span class="company">${esc(company)}</span> supervisor app. Scan the code with your
     phone camera, or download the APK directly.</p>
  <div class="qr">${svg}</div>
  <div class="url">
    <code id="apkurl">${esc(apkUrl)}</code>
    <button class="btn copy" id="copybtn" type="button" data-url="${esc(apkUrl)}">Copy</button>
  </div>
  <a class="btn dl" href="${esc(apkUrl)}">Download APK</a>
  ${pendingNote}
  <div class="note"><b>First install:</b> Android will ask you to allow installing from this
     source — tap <b>Settings &rarr; Allow</b>, then reopen the file. Managed devices can push
     it via MDM instead.</div>
  <div class="note" style="margin-top:12px">Prefer no install? The <b>web app</b> works
     immediately in your browser: <a class="foot" style="color:#9fc0ff" href="${esc(webUrl)}">${esc(webUrl.replace(/^https?:\/\//, ''))}</a></div>
  <div class="foot">Powered by SIAS &middot; ${esc(env.APP_DOMAIN || APP_DOMAIN)}</div>
  <script>
    (function(){
      var b=document.getElementById('copybtn');
      if(!b) return;
      b.addEventListener('click',function(){
        var u=b.getAttribute('data-url');
        var done=function(){var t=b.textContent;b.textContent='Copied';setTimeout(function(){b.textContent=t;},1600);};
        if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(u).then(done,done);}
        else{done();}
      });
    })();
  </script>
  `);
}
