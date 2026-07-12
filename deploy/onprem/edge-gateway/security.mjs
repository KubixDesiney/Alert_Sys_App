// Gateway-side security: per-adapter API keys, token-bucket rate limiting and
// payload size caps. Dedup runs downstream in the worker-runner (single
// authority), but the gateway also carries a short-window local guard so a
// chattering device is absorbed before it even crosses the LAN.

import { timingSafeEqual } from 'node:crypto';

export function keyMatches(provided, expected) {
  const a = Buffer.from(String(provided || ''));
  const b = Buffer.from(String(expected || ''));
  if (!b.length || a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** apiKeys: { "<adapterName>": "<key>" }; returns adapter name or null. */
export function authenticate(headers = {}, apiKeys = {}) {
  const auth = String(headers.authorization || '');
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const provided = String(headers['x-api-key'] || bearer || '');
  if (!provided) return null;
  for (const [name, key] of Object.entries(apiKeys)) {
    if (keyMatches(provided, key)) return name;
  }
  return null;
}

/** Classic token bucket, per caller key. */
export class RateLimiter {
  constructor({ capacity = 60, refillPerSec = 1 } = {}) {
    this.capacity = capacity;
    this.refillPerSec = refillPerSec;
    this.buckets = new Map();
  }

  allow(key, now = Date.now()) {
    let b = this.buckets.get(key);
    if (!b) {
      b = { tokens: this.capacity, at: now };
      this.buckets.set(key, b);
    }
    b.tokens = Math.min(this.capacity, b.tokens + ((now - b.at) / 1000) * this.refillPerSec);
    b.at = now;
    if (b.tokens >= 1) {
      b.tokens -= 1;
      return true;
    }
    return false;
  }
}

export const MAX_PAYLOAD_BYTES = 32 * 1024; // sensor payloads are tiny

export function payloadTooLarge(raw, limit = MAX_PAYLOAD_BYTES) {
  return Buffer.byteLength(String(raw || ''), 'utf8') > limit;
}
