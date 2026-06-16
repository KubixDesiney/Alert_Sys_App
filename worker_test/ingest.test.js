import {
  timingSafeEqual,
  rateLimit,
  mapSeverity,
  typeFromMetric,
  parseTimestamp,
  normalizeTelemetry,
  dedupeKey,
  isDuplicate,
  CANONICAL_TYPES,
} from '../cloudflare_ingest_worker.js';

describe('mapSeverity', () => {
  test('high direction: critical / warning / normal', () => {
    expect(mapSeverity(95, { warn: 70, critical: 90 }).severity).toBe('critical');
    expect(mapSeverity(95, { warn: 70, critical: 90 }).isCritical).toBe(true);
    expect(mapSeverity(75, { warn: 70, critical: 90 }).severity).toBe('warning');
    expect(mapSeverity(50, { warn: 70, critical: 90 }).severity).toBe('normal');
  });
  test('low direction: smaller is worse', () => {
    expect(mapSeverity(2, { warn: 5, critical: 3, direction: 'low' }).severity).toBe('critical');
    expect(mapSeverity(4, { warn: 5, critical: 3, direction: 'low' }).severity).toBe('warning');
    expect(mapSeverity(9, { warn: 5, critical: 3, direction: 'low' }).severity).toBe('normal');
  });
  test('non-numeric / missing thresholds', () => {
    expect(mapSeverity('NaN', { warn: 1 }).severity).toBe('unknown');
    expect(mapSeverity(100, {}).severity).toBe('normal');
  });
});

describe('typeFromMetric', () => {
  test('keeps an explicit canonical type', () => {
    expect(typeFromMetric('whatever', 'Quality')).toBe('Quality');
  });
  test('ignores a non-canonical explicit type and falls back to heuristic', () => {
    expect(typeFromMetric('bearing_temp', 'Bogus')).toBe('Mechanical');
  });
  test('maps signal names to canonical types', () => {
    expect(typeFromMetric('phase_current')).toBe('Electrical');
    expect(typeFromMetric('vision_defect_rate')).toBe('Quality');
    expect(typeFromMetric('smoke_detector')).toBe('Safety');
    expect(typeFromMetric('unknown_signal')).toBe('Mechanical'); // safe default
  });
  test('canonical list is exactly the four SIA types', () => {
    expect(CANONICAL_TYPES).toEqual(['Mechanical', 'Electrical', 'Quality', 'Safety']);
  });
});

describe('parseTimestamp', () => {
  test('epoch seconds -> ms', () => {
    expect(parseTimestamp(1700000000)).toBe(1700000000000);
  });
  test('epoch millis pass through', () => {
    expect(parseTimestamp(1700000000000)).toBe(1700000000000);
  });
  test('ISO string parses', () => {
    expect(parseTimestamp('2026-06-16T00:00:00.000Z')).toBe(Date.parse('2026-06-16T00:00:00.000Z'));
  });
  test('empty falls back to ~now', () => {
    const before = Date.now();
    const t = parseTimestamp('');
    expect(t).toBeGreaterThanOrEqual(before);
  });
});

describe('normalizeTelemetry', () => {
  test('suppresses a normal reading (returns null)', () => {
    expect(
      normalizeTelemetry({ factory: 'Plant 1', line: 'L2', metric: 'temp', value: 40, thresholds: { warn: 70, critical: 90 } }),
    ).toBeNull();
  });

  test('builds a critical alert and preserves spaces in location', () => {
    const a = normalizeTelemetry({
      source: 'opcua',
      factory: 'Plant 1',
      line: 'Line 2',
      station: 'Station 3',
      metric: 'bearing_temp',
      value: 95,
      unit: 'C',
      thresholds: { warn: 70, critical: 90 },
    });
    expect(a).not.toBeNull();
    expect(a.type).toBe('Mechanical');
    expect(a.usine).toBe('Plant 1');
    expect(a.convoyeur).toBe('Line 2');
    expect(a.poste).toBe('Station 3');
    expect(a.isCritical).toBe(true);
    expect(a.source).toBe('scada:opcua');
    expect(a.push_sent).toBe(false);
    expect(a.notificationSent).toBe(false);
  });

  test('forced alert without a numeric value (explicit type)', () => {
    const f = normalizeTelemetry({ factory: 'P', machine: 'M1', type: 'Safety', message: 'E-stop pressed' });
    expect(f).not.toBeNull();
    expect(f.type).toBe('Safety');
    expect(f.isCritical).toBe(false); // no value => not critical
  });

  test('rejects payloads without enough location context', () => {
    expect(normalizeTelemetry({ metric: 'temp', value: 99, thresholds: { critical: 90 } })).toBeNull();
    expect(normalizeTelemetry(null)).toBeNull();
    expect(normalizeTelemetry('nope')).toBeNull();
  });

  test('strips control / zero-width characters from fields', () => {
    const zwsp = String.fromCharCode(0x200b); // zero-width space
    const bel = String.fromCharCode(0x07); // BEL control char
    const dirty = 'Pl' + zwsp + 'ant' + bel;
    const a = normalizeTelemetry({ factory: dirty, machine: 'M1', type: 'Quality' });
    expect(a.usine).toBe('Plant');
  });
});

describe('dedupeKey / isDuplicate', () => {
  const alert = { source: 'scada:mqtt', usine: 'P', convoyeur: 'L', poste: 'S', type: 'Mechanical' };

  test('key is stable within a window and changes across windows', () => {
    expect(dedupeKey(alert, 60000, 1000)).toBe(dedupeKey(alert, 60000, 1500));
    expect(dedupeKey(alert, 60000, 1000)).not.toBe(dedupeKey(alert, 60000, 120000));
  });

  test('isDuplicate collapses a storm inside the window', () => {
    const now = 10_000_000;
    expect(isDuplicate(alert, 60000, now)).toBe(false); // first
    expect(isDuplicate(alert, 60000, now + 1000)).toBe(true); // within window
    expect(isDuplicate(alert, 60000, now + 120000)).toBe(false); // new window
  });
});

describe('timingSafeEqual', () => {
  test('true only for identical strings', () => {
    expect(timingSafeEqual('abc123', 'abc123')).toBe(true);
    expect(timingSafeEqual('abc123', 'abc124')).toBe(false);
    expect(timingSafeEqual('abc', 'abcd')).toBe(false);
    expect(timingSafeEqual(undefined, '')).toBe(true);
  });
});

describe('rateLimit', () => {
  test('allows up to the limit, then blocks within the window', () => {
    const b = new Map();
    for (let i = 0; i < 3; i++) expect(rateLimit(b, 'opcua', 3, 60000, 1000 + i).allowed).toBe(true);
    expect(rateLimit(b, 'opcua', 3, 60000, 1003).allowed).toBe(false);
  });
  test('window slides so old hits expire', () => {
    const b = new Map();
    rateLimit(b, 'mqtt', 1, 1000, 0);
    expect(rateLimit(b, 'mqtt', 1, 1000, 500).allowed).toBe(false);
    expect(rateLimit(b, 'mqtt', 1, 1000, 2000).allowed).toBe(true);
  });
});
