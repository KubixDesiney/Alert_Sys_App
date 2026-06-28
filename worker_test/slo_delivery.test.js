import {
  deliveryLatencyMs,
  percentile,
  bucketLabel,
  summarize,
  harvestSamples,
  deliveryBreaches,
  canaryStatus,
  DEFAULT_TARGETS,
} from '../slo_delivery.js';

describe('slo_delivery latency math', () => {
  test('deliveryLatencyMs computes a non-negative delta', () => {
    expect(deliveryLatencyMs('2026-06-27T10:00:00.000Z', '2026-06-27T10:00:03.500Z')).toBe(3500);
  });
  test('deliveryLatencyMs rejects clock-skew negatives and junk', () => {
    expect(deliveryLatencyMs('2026-06-27T10:00:05Z', '2026-06-27T10:00:00Z')).toBeNull();
    expect(deliveryLatencyMs('nope', '2026-06-27T10:00:00Z')).toBeNull();
  });
  test('percentile uses nearest-rank', () => {
    const v = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    expect(percentile(v, 50)).toBe(5);
    expect(percentile(v, 95)).toBe(10);
    expect(percentile([], 95)).toBeNull();
  });
  test('bucketLabel maps to edges', () => {
    expect(bucketLabel(900)).toBe('<=1000');
    expect(bucketLabel(1000)).toBe('<=1000');
    expect(bucketLabel(45000)).toBe('<=60000');
    expect(bucketLabel(120000)).toBe('>60000');
    expect(bucketLabel(-1)).toBe('invalid');
  });
});

describe('slo_delivery breach detection', () => {
  test('no breach when within targets', () => {
    const s = summarize(Array(50).fill(3000));
    expect(deliveryBreaches(s, 1.0)).toEqual([]);
  });
  test('p95 breach is flagged (received profile)', () => {
    const s = summarize(Array(45).fill(2000).concat(Array(5).fill(45000)));
    const b = deliveryBreaches(s, 1.0, DEFAULT_TARGETS, 'received');
    expect(b.join(' ')).toMatch(/p9/);
  });
  test('success-rate breach is flagged', () => {
    const s = summarize(Array(50).fill(2000));
    expect(deliveryBreaches(s, 0.97).join(' ')).toMatch(/success/);
  });
  test('insufficient samples means not enough signal (no breach)', () => {
    const s = summarize(Array(5).fill(99000));
    expect(deliveryBreaches(s, 0.5)).toEqual([]);
  });
});

describe('slo_delivery canary', () => {
  const now = Date.parse('2026-06-27T10:05:00.000Z');
  test('delivered within target is ok', () => {
    const r = canaryStatus(
      { createdAt: '2026-06-27T10:00:00.000Z', receivedAt: '2026-06-27T10:00:08.000Z' },
      DEFAULT_TARGETS, now);
    expect(r.ok).toBe(true);
    expect(r.latencyMs).toBe(8000);
  });
  test('too slow is a breach', () => {
    const r = canaryStatus(
      { createdAt: '2026-06-27T10:00:00.000Z', sentAt: '2026-06-27T10:00:25.000Z' },
      DEFAULT_TARGETS, now);
    expect(r.ok).toBe(false);
    expect(r.reason).toMatch(/>/);
  });
  test('missing and stale is a breach', () => {
    const r = canaryStatus({ createdAt: '2026-06-27T09:50:00.000Z' }, DEFAULT_TARGETS, now);
    expect(r.ok).toBe(false);
    expect(r.reason).toMatch(/not delivered/);
  });
  test('missing but fresh is in flight (ok)', () => {
    const r = canaryStatus({ createdAt: '2026-06-27T10:04:30.000Z' }, DEFAULT_TARGETS, now);
    expect(r.ok).toBe(true);
    expect(r.reason).toMatch(/flight/);
  });
  test('no canary recorded is a breach', () => {
    expect(canaryStatus(null, DEFAULT_TARGETS, now).ok).toBe(false);
  });
});

describe('slo_delivery harvestSamples', () => {
  const sinceMs = Date.parse('2026-06-27T10:00:00.000Z');
  const alerts = {
    a1: { timestamp: '2026-06-27T10:01:00.000Z', push_sent_at: '2026-06-27T10:01:03.000Z' },
    a2: { timestamp: '2026-06-27T10:02:00.000Z', push_sent_at: '2026-06-27T10:02:02.000Z' },
    a3: { timestamp: '2026-06-27T10:03:00.000Z' },
    old: { timestamp: '2026-06-27T09:00:00.000Z', push_sent_at: '2026-06-27T09:00:01.000Z' },
    junk: null,
  };
  test('only in-window alerts are counted; samples come from push_sent_at', () => {
    const h = harvestSamples(alerts, sinceMs, 'push_sent_at');
    expect(h.total).toBe(3);
    expect(h.samples.sort((x, y) => x - y)).toEqual([2000, 3000]);
  });
  test('an unsent alert lowers the success rate', () => {
    const h = harvestSamples(alerts, sinceMs, 'push_sent_at');
    expect(h.delivered).toBe(2);
    expect(h.successRate).toBeCloseTo(2 / 3, 5);
  });
  test('a slow alert outside the success window does not count as delivered', () => {
    const slow = { s1: { timestamp: '2026-06-27T10:01:00.000Z', push_sent_at: '2026-06-27T10:03:30.000Z' } };
    const h = harvestSamples(slow, sinceMs, 'push_sent_at', 60000);
    expect(h.total).toBe(1);
    expect(h.delivered).toBe(0);
  });
  test('empty map yields null success rate', () => {
    expect(harvestSamples({}, sinceMs).successRate).toBeNull();
  });
});
