import { describe, test, expect } from '@jest/globals';
import { haversineKm } from '../cloudflare_worker.js';

describe('haversineKm', () => {
  test('returns 0 for identical coordinates', () => {
    const d = haversineKm({ lat: 36.8, lng: 10.18 }, { lat: 36.8, lng: 10.18 });
    expect(d).toBeCloseTo(0, 5);
  });

  test('computes Tunis → Sfax distance (~270 km)', () => {
    const tunis = { lat: 36.8065, lng: 10.1815 };
    const sfax = { lat: 34.7406, lng: 10.7603 };
    const d = haversineKm(tunis, sfax);
    expect(d).toBeGreaterThan(230);
    expect(d).toBeLessThan(280);
  });

  test('is symmetric', () => {
    const a = { lat: 48.8566, lng: 2.3522 };
    const b = { lat: 51.5074, lng: -0.1278 };
    expect(haversineKm(a, b)).toBeCloseTo(haversineKm(b, a), 6);
  });

  test('returns null when either coordinate is missing', () => {
    expect(haversineKm(null, { lat: 1, lng: 2 })).toBeNull();
    expect(haversineKm({ lat: 1, lng: 2 }, null)).toBeNull();
    expect(haversineKm({}, { lat: 1, lng: 2 })).toBeNull();
    expect(haversineKm({ lat: 'x', lng: 'y' }, { lat: 1, lng: 2 })).toBeNull();
  });
});
