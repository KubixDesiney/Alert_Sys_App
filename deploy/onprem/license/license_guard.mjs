// Licence validation inside the local SIAS server (worker-runner).
//
// Resolution order:
//   1. LICENSE_FILE (offline annual licence for air-gapped plants) — a signed
//      token on disk; no network ever attempted when it is valid.
//   2. Licence server (LICENSE_SERVER_URL) — sends ONLY installationId +
//      current software version; caches the returned token locally.
//   3. Cached last-known-good token when the server is unreachable, honoured
//      for a configurable grace window (7 or 14 days).
//
// Degradation policy (deliberate, documented): an invalid/expired-beyond-grace
// licence NEVER kills core alert intake/claim/resolve — bricking a safety
// system over billing is unacceptable. Instead, plan-gated features
// (Industrial protocol adapters, forecaster, AI commander) switch off and the
// status is surfaced on /health and in the console.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { verifyLicense, featuresForPlan } from './license.mjs';

const DAY_MS = 24 * 60 * 60 * 1000;

/** Features that stay on no matter what (safety floor). */
export const SAFETY_FLOOR = Object.freeze(['alerts.core', 'notifications.lan', 'backups.local']);

export class LicenseGuard {
  constructor({
    publicKeyPem,
    licenseFile = null,
    serverUrl = null,
    installationId = '',
    softwareVersion = '',
    graceDays = 7,
    cachePath = null,
    now = () => Date.now(),
    fetchImpl = globalThis.fetch,
    log = null,
  }) {
    this.publicKeyPem = publicKeyPem;
    this.licenseFile = licenseFile;
    this.serverUrl = serverUrl ? String(serverUrl).replace(/\/+$/, '') : null;
    this.installationId = installationId;
    this.softwareVersion = softwareVersion;
    this.graceDays = graceDays;
    this.cachePath = cachePath;
    this.now = now;
    this.fetch = fetchImpl;
    this.log = log;
    this.state = { status: 'unknown', plan: null, features: [...SAFETY_FLOOR], source: null };
  }

  isEnabled(flag) {
    return this.state.features.includes(flag);
  }

  _finish(status, payload, source, extra = {}) {
    const licensed = status === 'active' || status === 'grace';
    this.state = {
      status,
      source,
      plan: payload ? payload.plan : null,
      companyId: payload ? payload.companyId : null,
      expiresAt: payload ? payload.expiresAt : null,
      features: licensed
        ? [...new Set([...(payload.features?.length ? payload.features : featuresForPlan(payload.plan)), ...SAFETY_FLOOR])]
        : [...SAFETY_FLOOR],
      checkedAt: new Date(this.now()).toISOString(),
      ...extra,
    };
    if (this.log) this.log.info('license state', { status, source, plan: this.state.plan });
    return this.state;
  }

  _readCache() {
    try {
      if (this.cachePath && existsSync(this.cachePath)) {
        return JSON.parse(readFileSync(this.cachePath, 'utf8'));
      }
    } catch (_) { /* corrupted cache = no cache */ }
    return null;
  }

  _writeCache(token) {
    if (!this.cachePath) return;
    try {
      mkdirSync(dirname(this.cachePath), { recursive: true });
      writeFileSync(this.cachePath, JSON.stringify({
        token,
        validatedAt: new Date(this.now()).toISOString(),
      }));
    } catch (_) { /* best effort */ }
  }

  async check() {
    const now = this.now();

    // 1. Offline annual licence file (air-gapped path).
    if (this.licenseFile && existsSync(this.licenseFile)) {
      let token = '';
      try { token = readFileSync(this.licenseFile, 'utf8').trim(); } catch (_) { /* fall through */ }
      const res = verifyLicense(token, this.publicKeyPem, { now });
      if (res.valid) return this._finish('active', res.payload, 'file');
      return this._finish(res.expired ? 'expired' : 'invalid', res.payload || null, 'file', { reason: res.reason });
    }

    // 2. Licence server. Sends nothing but identity + version — see server
    //    whitelist test for the enforcement on the receiving side.
    if (this.serverUrl) {
      try {
        const r = await this.fetch(`${this.serverUrl}/license/validate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            installationId: this.installationId,
            version: this.softwareVersion,
          }),
        });
        if (r.ok) {
          const { token } = await r.json();
          const res = verifyLicense(token, this.publicKeyPem, { now });
          if (res.valid) {
            this._writeCache(token);
            return this._finish('active', res.payload, 'server');
          }
          return this._finish(res.expired ? 'expired' : 'invalid', res.payload || null, 'server', { reason: res.reason });
        }
        if (r.status === 403 || r.status === 404) {
          return this._finish('invalid', null, 'server', { reason: `server said ${r.status}` });
        }
        // 5xx falls through to the grace path
      } catch (_) {
        // network unreachable -> grace path
      }

      // 3. Grace window on the cached last-known-good token.
      const cache = this._readCache();
      if (cache && cache.token) {
        const res = verifyLicense(cache.token, this.publicKeyPem, { now, allowExpired: true });
        const validatedAt = Date.parse(cache.validatedAt || 0);
        const graceUntil = validatedAt + this.graceDays * DAY_MS;
        if (res.valid !== false && res.payload && now <= graceUntil && !res.expired) {
          return this._finish('grace', res.payload, 'cache', {
            graceUntil: new Date(graceUntil).toISOString(),
            reason: 'licence server unreachable — running on cached licence',
          });
        }
        if (res.payload && res.expired) {
          return this._finish('expired', res.payload, 'cache', { reason: 'cached licence expired' });
        }
        if (now > graceUntil) {
          return this._finish('expired', res.payload || null, 'cache', { reason: 'grace period over' });
        }
      }
      return this._finish('missing', null, 'server', { reason: 'licence server unreachable and no cached licence' });
    }

    return this._finish('missing', null, null, { reason: 'no LICENSE_FILE or LICENSE_SERVER_URL configured' });
  }
}
