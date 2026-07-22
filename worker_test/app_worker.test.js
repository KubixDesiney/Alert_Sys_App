// Tests for the shared sias-app worker: host->tenant parsing, runtime-config
// injection, the APK path helpers (Prompt 2), and real default.fetch cycles
// against a stubbed KV + ASSETS binding (config injection, /__config,
// /__swconfig, unknown-host 404, security headers). No live network.
import { describe, test, expect } from '@jest/globals';
import worker, {
  tenantFromHost,
  isValidTenantSlug,
  escapeConfigJson,
  injectedConfig,
  injectRuntimeConfig,
  contentSecurityPolicy,
  swConfigObject,
  apkFileName,
  apkObjectKey,
  resolveApkKey,
  RESERVED_SUBDOMAINS,
} from '../cloudflare_app_worker.js';

const INDEX_HTML =
  '<!doctype html><html><head><base href="/"><title>SIAS</title></head>' +
  '<body><script src="flutter_bootstrap.js" defer></script></body></html>';

const TENANT_CONFIG = {
  tenantCode: 'NSW#7K2F',
  company: 'Nagati Steel Works',
  firebase: {
    apiKey: 'k', authDomain: 'sias-nagati.firebaseapp.com', projectId: 'sias-nagati',
    storageBucket: 'sias-nagati.appspot.com', messagingSenderId: '42', appId: '1:42:web:abc',
    databaseURL: 'https://sias-nagati-default-rtdb.firebaseio.com',
  },
  workers: { ai: 'https://ai', notify: 'https://notify', ingest: 'https://ingest', copilotUrl: 'https://copilot' },
};

function makeEnv({ tenants = { nagati: TENANT_CONFIG }, apk = null } = {}) {
  return {
    APP_DOMAIN: 'kubixdesiney.com',
    TENANTS: { get: async (key) => tenants[key] ?? null },
    ASSETS: { fetch: async () => new Response(INDEX_HTML, { headers: { 'content-type': 'text/html; charset=utf-8' } }) },
    APKS: apk ? { get: async (key) => (key === apk.key ? apk.object : null) } : undefined,
  };
}

const req = (url, init) => worker.fetch(new Request(url, init), makeEnv());

describe('tenantFromHost', () => {
  test('resolves a valid tenant subdomain (case + port insensitive)', () => {
    expect(tenantFromHost('nagati.kubixdesiney.com')).toBe('nagati');
    expect(tenantFromHost('NAGATI.kubixdesiney.com')).toBe('nagati');
    expect(tenantFromHost('nagati.kubixdesiney.com:8787')).toBe('nagati');
    expect(tenantFromHost('nsw-7k2f.kubixdesiney.com')).toBe('nsw-7k2f');
  });
  test('rejects apex, www, the storefront, foreign hosts, and >1 level deep', () => {
    expect(tenantFromHost('kubixdesiney.com')).toBeNull();
    expect(tenantFromHost('www.kubixdesiney.com')).toBeNull();
    expect(tenantFromHost('sias.kubixdesiney.com')).toBeNull();
    expect(tenantFromHost('unknown.example.com')).toBeNull();
    expect(tenantFromHost('a.b.kubixdesiney.com')).toBeNull();
    expect(tenantFromHost('')).toBeNull();
    expect(tenantFromHost(null)).toBeNull();
  });
  test('every reserved subdomain resolves to null', () => {
    for (const label of RESERVED_SUBDOMAINS) {
      expect(tenantFromHost(`${label}.kubixdesiney.com`)).toBeNull();
    }
  });
  test('honors a custom app domain', () => {
    expect(tenantFromHost('acme.sias.example', { appDomain: 'sias.example' })).toBe('acme');
    expect(tenantFromHost('ACME.SIAS.EXAMPLE.', { appDomain: 'SIAS.EXAMPLE' })).toBe('acme');
  });
});

describe('isValidTenantSlug', () => {
  test('matches the provisioning slug shape', () => {
    expect(isValidTenantSlug('nagati')).toBe(true);
    expect(isValidTenantSlug('nsw-7k2f')).toBe(true);
    expect(isValidTenantSlug('-x')).toBe(false);
    expect(isValidTenantSlug('X')).toBe(false);
    expect(isValidTenantSlug('a b')).toBe(false);
  });
});

describe('escapeConfigJson', () => {
  test('neutralizes a </script> breakout attempt', () => {
    const out = escapeConfigJson({ x: '</script><img src=x onerror=alert(1)>' });
    expect(out).not.toContain('</script>');
    expect(out).toContain('\\u003c/script>');
  });
  test('escapes U+2028/U+2029 line separators', () => {
    const out = escapeConfigJson({ x: 'a b c' });
    expect(out).toContain('\\u2028');
    expect(out).toContain('\\u2029');
    expect(out).not.toContain(' ');
  });
});

describe('injectRuntimeConfig', () => {
  const config = injectedConfig('nagati', TENANT_CONFIG);

  test('injects the config script immediately before flutter_bootstrap', () => {
    const out = injectRuntimeConfig(INDEX_HTML, config, 'NONCE');
    expect(out.indexOf('__SIAS_CONFIG__')).toBeLessThan(out.indexOf('flutter_bootstrap.js'));
    expect(out).toContain('window.__SIAS_CONFIG__=');
    expect(out).toContain('nonce="NONCE"');
    expect(out).toContain('sias-nagati'); // projectId present
  });

  test('carries tenant + workers into the blob', () => {
    const out = injectRuntimeConfig(INDEX_HTML, config, 'N');
    expect(out).toContain('"tenant":"nagati"');
    expect(out).toContain('"ai":"https://ai"');
  });

  test('falls back to before </body> when there is no bootstrap tag', () => {
    const html = '<html><head></head><body><p>x</p></body></html>';
    const out = injectRuntimeConfig(html, config, 'N');
    expect(out.indexOf('__SIAS_CONFIG__')).toBeLessThan(out.indexOf('</body>'));
  });

  test('adds a <base href="/"> when missing', () => {
    const html = '<html><head><title>x</title></head><body></body></html>';
    expect(injectRuntimeConfig(html, config, 'N')).toContain('<base href="/">');
  });
});

describe('contentSecurityPolicy (app-flavored)', () => {
  test('nonce-pins scripts, allows wasm eval, never uses unsafe-inline script', () => {
    const csp = contentSecurityPolicy('abc123');
    expect(csp).toContain("script-src 'self' 'nonce-abc123'");
    expect(csp).toContain("'wasm-unsafe-eval'");
    expect(csp).not.toContain("script-src 'self' 'unsafe-inline'");
    expect(csp).toContain("frame-ancestors 'none'");
  });
});

describe('APK helpers', () => {
  test('canonical filename + object key', () => {
    expect(apkFileName('nagati')).toBe('sias-nagati.apk');
    expect(apkObjectKey('nagati')).toBe('nagati/sias-nagati.apk');
  });
  test('resolveApkKey only accepts the tenant canonical filename (blocks traversal)', () => {
    expect(resolveApkKey('nagati', '/app/sias-nagati.apk')).toBe('nagati/sias-nagati.apk');
    expect(resolveApkKey('nagati', '/app/sias-other.apk')).toBeNull();
    expect(resolveApkKey('nagati', '/app/../secret')).toBeNull();
    expect(resolveApkKey('nagati', '/app/%2e%2e%2fsecret')).toBeNull();
    expect(resolveApkKey('nagati', '/app/%E0%A4%A')).toBeNull();
  });
});

describe('swConfigObject', () => {
  test('returns only the messaging fields, never worker URLs or databaseURL secrets', () => {
    const sw = swConfigObject(TENANT_CONFIG);
    expect(sw).toEqual({
      apiKey: 'k', authDomain: 'sias-nagati.firebaseapp.com', projectId: 'sias-nagati',
      storageBucket: 'sias-nagati.appspot.com', messagingSenderId: '42', appId: '1:42:web:abc',
    });
    expect(sw).not.toHaveProperty('databaseURL');
  });
});

describe('default.fetch — full request cycle', () => {
  test('serves index.html with the tenant config injected + no-store + app CSP', async () => {
    const res = await req('https://nagati.kubixdesiney.com/');
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('window.__SIAS_CONFIG__=');
    expect(body).toContain('sias-nagati');
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(res.headers.get('Strict-Transport-Security')).toContain('max-age=31536000');
    const csp = res.headers.get('Content-Security-Policy');
    expect(csp).toMatch(/script-src 'self' 'nonce-[0-9a-f]{32}'/);
    // The nonce in the header matches the injected script tag.
    const nonce = csp.match(/'nonce-([0-9a-f]{32})'/)[1];
    expect(body).toContain(`nonce="${nonce}"`);
    // The app needs these — unlike the locked-down storefront.
    expect(res.headers.get('Permissions-Policy')).toContain('geolocation=(self)');
  });

  test('/__config reports tenant + hasConfig', async () => {
    const res = await req('https://nagati.kubixdesiney.com/__config');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, tenant: 'nagati', hasConfig: true });
  });

  test('/__config on an unknown host is a probe, not a 404', async () => {
    const res = await req('https://kubixdesiney.com/__config');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, tenant: null, hasConfig: false });
  });

  test('/__swconfig serves only the messaging config', async () => {
    const res = await req('https://nagati.kubixdesiney.com/__swconfig');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.projectId).toBe('sias-nagati');
    expect(body).not.toHaveProperty('workers');
  });

  test('unknown host + apex render the branded 404', async () => {
    for (const url of ['https://unknown.kubixdesiney.com/', 'https://kubixdesiney.com/']) {
      const res = await req(url);
      expect(res.status).toBe(404);
      expect(await res.text()).toContain("isn't set up");
    }
  });

  test('an unprovisioned (KV-miss) tenant gets the branded 404', async () => {
    const res = await worker.fetch(
      new Request('https://ghost.kubixdesiney.com/'),
      makeEnv({ tenants: {} }),
    );
    expect(res.status).toBe(404);
  });

  test('/app renders the download page with a QR + the APK link', async () => {
    const res = await req('https://nagati.kubixdesiney.com/app');
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('<svg');
    expect(body).toContain('sias-nagati.apk');
    expect(body).toContain('Nagati Steel Works');
  });

  test('/app/<file> streams the APK from R2', async () => {
    const env = makeEnv({
      apk: {
        key: 'nagati/sias-nagati.apk',
        object: { body: 'APKBYTES', writeHttpMetadata: () => {} },
      },
    });
    const res = await worker.fetch(new Request('https://nagati.kubixdesiney.com/app/sias-nagati.apk'), env);
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('application/vnd.android.package-archive');
    expect(res.headers.get('Content-Disposition')).toContain('sias-nagati.apk');
  });

  test('/app/<file> for a missing APK (bucket present, object absent) shows the pending page', async () => {
    const env = {
      ...makeEnv(),
      APKS: { get: async () => null }, // bucket configured, object not uploaded yet
    };
    const res = await worker.fetch(new Request('https://nagati.kubixdesiney.com/app/sias-nagati.apk'), env);
    expect(res.status).toBe(404);
    expect(await res.text()).toContain('Build pending');
  });

  test('non-HTML assets pass through with nosniff added', async () => {
    const env = {
      APP_DOMAIN: 'kubixdesiney.com',
      TENANTS: { get: async () => TENANT_CONFIG },
      ASSETS: { fetch: async () => new Response('console.log(1)', { headers: { 'content-type': 'text/javascript' } }) },
    };
    const res = await worker.fetch(new Request('https://nagati.kubixdesiney.com/main.dart.js'), env);
    expect(res.status).toBe(200);
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(await res.text()).toBe('console.log(1)');
  });
});
