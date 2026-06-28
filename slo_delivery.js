/**
 * Alert-delivery SLO math — pure, dependency-free, unit-tested.
 *
 * Shared by two workers:
 *   - the notify worker writes a per-alert latency sample when it finalizes a push;
 *   - the monitor worker aggregates daily, decides breach, and drives the canary.
 *
 * "Delivered" has two measurable checkpoints, both already present in your data:
 *   - accepted:  alert.timestamp -> alert.push_sent_at                  (worker handed it to FCM)
 *   - received:  alert.timestamp -> notifications/{uid}/{id}/deliveredAt (device ack — added in phase 2)
 *
 * Mirrors the contract of crashFreeBreach() in cloudflare_monitor_worker.js:
 * the breach functions return human-readable problem strings (empty = healthy).
 */

export const LAT_BUCKETS_MS = [1000, 2000, 5000, 10000, 30000, 60000];

export const DEFAULT_TARGETS = {
  acceptedP95Ms: 5000,
  acceptedP99Ms: 15000,
  receivedP95Ms: 10000,
  receivedP99Ms: 30000,
  successRate: 0.995,
  canaryMs: 15000,
  canaryStaleMin: 12,
  minSamples: 20,
};

export function deliveryLatencyMs(createdIso, doneIso) {
  const a = Date.parse(createdIso);
  const b = Date.parse(doneIso);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  const d = b - a;
  return d >= 0 ? d : null;
}

export function percentile(values, p) {
  const a = (values || [])
    .filter((v) => typeof v === 'number' && Number.isFinite(v))
    .sort((x, y) => x - y);
  if (!a.length) return null;
  if (p <= 0) return a[0];
  if (p >= 100) return a[a.length - 1];
  const rank = Math.ceil((p / 100) * a.length);
  return a[Math.min(a.length - 1, Math.max(0, rank - 1))];
}

export function bucketLabel(ms) {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms < 0) return 'invalid';
  for (const edge of LAT_BUCKETS_MS) {
    if (ms <= edge) return `<=${edge}`;
  }
  return `>${LAT_BUCKETS_MS[LAT_BUCKETS_MS.length - 1]}`;
}

export function summarize(samplesMs) {
  const a = (samplesMs || []).filter(
    (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0,
  );
  if (!a.length) return { count: 0, p50: null, p95: null, p99: null, maxMs: null };
  return {
    count: a.length,
    p50: percentile(a, 50),
    p95: percentile(a, 95),
    p99: percentile(a, 99),
    maxMs: Math.max(...a),
  };
}

/**
 * Harvest latency samples from an alerts map over the window [sinceMs, now].
 * field = 'push_sent_at' (accepted profile) or 'deliveredAt' (received, phase 2).
 * delivered = reached the checkpoint within successWindowMs. Pure — no I/O.
 */
export function harvestSamples(alertsMap, sinceMs, field = 'push_sent_at', successWindowMs = 60000) {
  const samples = [];
  let total = 0;
  let delivered = 0;
  for (const a of Object.values(alertsMap || {})) {
    if (!a || typeof a !== 'object') continue;
    const created = Date.parse(a.timestamp);
    if (Number.isNaN(created) || created < sinceMs) continue;
    total += 1;
    const lat = deliveryLatencyMs(a.timestamp, a[field]);
    if (lat != null) {
      samples.push(lat);
      if (lat <= successWindowMs) delivered += 1;
    }
  }
  return { samples, total, delivered, successRate: total ? delivered / total : null };
}

/**
 * successRate = delivered / total over the period (caller computes it).
 * profile = 'accepted' | 'received'. Returns problem strings (empty = healthy).
 */
export function deliveryBreaches(summary, successRate, targets = DEFAULT_TARGETS, profile = 'received') {
  const out = [];
  if (!summary || !summary.count || summary.count < (targets.minSamples || 0)) return out;
  const p95Target = profile === 'accepted' ? targets.acceptedP95Ms : targets.receivedP95Ms;
  const p99Target = profile === 'accepted' ? targets.acceptedP99Ms : targets.receivedP99Ms;
  if (summary.p95 != null && summary.p95 > p95Target) {
    out.push(`Delivery p95 ${(summary.p95 / 1000).toFixed(1)}s > SLO ${(p95Target / 1000).toFixed(0)}s (${profile})`);
  }
  if (summary.p99 != null && summary.p99 > p99Target) {
    out.push(`Delivery p99 ${(summary.p99 / 1000).toFixed(1)}s > SLO ${(p99Target / 1000).toFixed(0)}s (${profile})`);
  }
  if (typeof successRate === 'number' && successRate < targets.successRate) {
    out.push(`Delivery success ${(successRate * 100).toFixed(2)}% < SLO ${(targets.successRate * 100).toFixed(1)}%`);
  }
  return out;
}

/**
 * Canary verdict. canary = { createdAt, sentAt, receivedAt }; now = Date.now().
 * Returns { ok, latencyMs, reason }.
 */
export function canaryStatus(canary, targets = DEFAULT_TARGETS, now = Date.now()) {
  if (!canary || !canary.createdAt) return { ok: false, latencyMs: null, reason: 'no canary recorded' };
  const created = Date.parse(canary.createdAt);
  if (Number.isNaN(created)) return { ok: false, latencyMs: null, reason: 'invalid canary timestamp' };
  const ageMin = (now - created) / 60000;
  const done = canary.receivedAt || canary.sentAt;
  if (!done) {
    if (ageMin > (targets.canaryStaleMin || 12)) {
      return { ok: false, latencyMs: null, reason: `canary not delivered after ${Math.round(ageMin)} min` };
    }
    return { ok: true, latencyMs: null, reason: 'in flight' };
  }
  const latencyMs = deliveryLatencyMs(canary.createdAt, done);
  if (latencyMs == null) return { ok: false, latencyMs: null, reason: 'invalid canary latency' };
  if (latencyMs > (targets.canaryMs || 15000)) {
    return { ok: false, latencyMs, reason: `canary ${(latencyMs / 1000).toFixed(1)}s > ${(targets.canaryMs / 1000).toFixed(0)}s target` };
  }
  return { ok: true, latencyMs, reason: 'ok' };
}
