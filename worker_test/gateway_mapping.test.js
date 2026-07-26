// Reference edge gateway: mapping engine, Sparkplug transform, protocol pure
// helpers, the plant simulator, and the batcher. Pure logic only — every
// protocol library is out of the picture (their pure cores are imported
// directly; no sockets anywhere).
import { jest } from '@jest/globals';
import {
  wildcardMatch, findMapRule, scaleReading, ruleThresholds, toIngestReading, mapReadings,
} from '../gateway/src/mapping.mjs';
import {
  sparkplugMetricValue, sparkplugMetricsToReadings, isSparkplugDataTopic,
} from '../gateway/src/sparkplug.mjs';
import { mqttMessageToReadings } from '../gateway/src/sources/mqtt.mjs';
import { decodeRegister, modbusKey } from '../gateway/src/sources/modbus.mjs';
import { SimSource, simMapRules, makeRng } from '../gateway/src/sources/sim.mjs';
import { Batcher } from '../gateway/src/batcher.mjs';
import { parseDuration, validateConfig } from '../gateway/src/config.mjs';

const NOW = () => 1780000000000;

const RULE = {
  match: 'ns=2;s=Line2.BearingTemp',
  factory: 'Usine A',
  line: 'Conveyor 2',
  station: '3',
  machine: 'MACH-007',
  metric: 'bearing_temperature',
  unit: '°C',
  scale: 0.1,
  thresholds: { warn: 80, critical: 90, direction: 'high' },
  type: 'maintenance',
};

describe('wildcard matching and rule lookup', () => {
  test('+ matches one level, # matches the rest, exact wins over wildcard', () => {
    expect(wildcardMatch('plant/+/temp', 'plant/a/temp')).toBe(true);
    expect(wildcardMatch('plant/+/temp', 'plant/a/b/temp')).toBe(false);
    expect(wildcardMatch('plant/#', 'plant/a/b/temp')).toBe(true);
    expect(wildcardMatch('plant/a', 'plant/a/b')).toBe(false);
    const rules = [
      { match: 'plant/+/temp', factory: 'WILD' },
      { match: 'plant/a/temp', factory: 'EXACT' },
    ];
    expect(findMapRule(rules, 'plant/a/temp').factory).toBe('EXACT');
    expect(findMapRule(rules, 'plant/z/temp').factory).toBe('WILD');
    expect(findMapRule(rules, 'nothing')).toBeNull();
    expect(findMapRule(undefined, 'x')).toBeNull();
  });
});

describe('unit conversion and thresholds', () => {
  test('scale/offset convert raw units; junk stays null', () => {
    expect(scaleReading(905, { scale: 0.1 })).toBeCloseTo(90.5);
    expect(scaleReading(50, { scale: 2, offset: -30 })).toBe(70);
    expect(scaleReading(42, {})).toBe(42);
    expect(scaleReading('junk', {})).toBeNull();
  });

  test('ruleThresholds sanitizes and drops empty blocks', () => {
    expect(ruleThresholds({ thresholds: { warn: '80', critical: 90, direction: 'high' } }))
      .toEqual({ warn: 80, critical: 90, direction: 'high' });
    expect(ruleThresholds({ thresholds: { direction: 'sideways' } })).toBeUndefined();
    expect(ruleThresholds({})).toBeUndefined();
  });
});

describe('toIngestReading', () => {
  test('produces the full ingest payload with converted value', () => {
    const out = toIngestReading({ key: RULE.match, value: 905, ts: 1780000000123 }, RULE, { source: 'opcua', now: NOW });
    expect(out).toEqual({
      source: 'opcua',
      factory: 'Usine A',
      machine: 'MACH-007',
      line: 'Conveyor 2',
      station: '3',
      metric: 'bearing_temperature',
      unit: '°C',
      value: 90.5,
      thresholds: { warn: 80, critical: 90, direction: 'high' },
      type: 'maintenance',
      timestamp: 1780000000123,
    });
  });

  test('missing timestamp falls back to now; missing location returns null', () => {
    expect(toIngestReading({ key: 'k', value: 1 }, RULE, { now: NOW }).timestamp).toBe(NOW());
    expect(toIngestReading({ key: 'k', value: 1 }, { metric: 'x' })).toBeNull();
    expect(toIngestReading({ key: 'k', value: 1 }, { factory: 'A' })).toBeNull();
    expect(toIngestReading(null, RULE)).toBeNull();
  });

  test('event rules force alert:true and carry a message', () => {
    const rule = { factory: 'A', machine: 'M', metric: 'estop', alert: true, message: 'E-stop pressed' };
    const out = toIngestReading({ key: 'k', value: 1 }, rule);
    expect(out.alert).toBe(true);
    expect(out.message).toBe('E-stop pressed');
  });

  test('threshold rules attach their type only on breach (worker forces on type)', () => {
    const idle = toIngestReading({ key: RULE.match, value: 500 }, RULE, { now: NOW }); // 50.0 °C
    expect(idle.type).toBeUndefined();
    expect(idle.thresholds).toBeDefined();
    const hot = toIngestReading({ key: RULE.match, value: 905 }, RULE, { now: NOW }); // 90.5 °C
    expect(hot.type).toBe('maintenance');
    // threshold-less typed rules keep their type on every reading (event stream)
    const evt = toIngestReading({ key: 'k', value: 1 }, { factory: 'A', machine: 'M', metric: 'door', type: 'Safety' });
    expect(evt.type).toBe('Safety');
  });

  test('mapReadings counts unmapped readings instead of sending them', () => {
    const { mapped, unmapped } = mapReadings(
      [{ key: RULE.match, value: 900 }, { key: 'unknown', value: 1 }],
      [RULE],
      { now: NOW },
    );
    expect(mapped).toHaveLength(1);
    expect(unmapped).toBe(1);
  });
});

describe('Sparkplug B transform', () => {
  const topic = 'spBv1.0/PlantA/DDATA/edge1/press2';

  test('flattens metrics into topic/name readings', () => {
    const payload = {
      timestamp: 1780000000000,
      metrics: [
        { name: 'Bearing Temp', value: 92.5, timestamp: 1780000000500 },
        { name: 'Running', value: true },
        { name: '', value: 5 },
        { name: 'Nameless', value: null },
      ],
    };
    const readings = sparkplugMetricsToReadings(payload, topic);
    expect(readings).toEqual([
      { key: `${topic}/Bearing Temp`, value: 92.5, ts: 1780000000500 },
      { key: `${topic}/Running`, value: 1, ts: 1780000000000 },
    ]);
  });

  test('metric values decode from booleans, longs and strings', () => {
    expect(sparkplugMetricValue({ value: true })).toBe(1);
    expect(sparkplugMetricValue({ value: { toNumber: () => 7 } })).toBe(7);
    expect(sparkplugMetricValue({ value: { low: 9, high: 0 } })).toBe(9);
    expect(sparkplugMetricValue({ value: '42.5' })).toBe(42.5);
    expect(sparkplugMetricValue({ value: 'junk' })).toBeNull();
    expect(sparkplugMetricValue(null)).toBeNull();
  });

  test('only data/birth topics are treated as Sparkplug', () => {
    expect(isSparkplugDataTopic('spBv1.0/PlantA/DDATA/edge1/press2')).toBe(true);
    expect(isSparkplugDataTopic('spBv1.0/PlantA/NBIRTH/edge1')).toBe(true);
    expect(isSparkplugDataTopic('spBv1.0/PlantA/DCMD/edge1/press2')).toBe(false);
    expect(isSparkplugDataTopic('plant/a/temp')).toBe(false);
  });
});

describe('protocol pure helpers', () => {
  test('plain MQTT payloads: bare numbers and {value, ts} JSON', () => {
    expect(mqttMessageToReadings('t', Buffer.from('42.5'), { now: NOW }))
      .toEqual([{ key: 't', value: 42.5, ts: NOW() }]);
    expect(mqttMessageToReadings('t', Buffer.from('{"value": 7, "ts": 123}')))
      .toEqual([{ key: 't', value: 7, ts: 123 }]);
    expect(mqttMessageToReadings('t', Buffer.from('hello'))).toEqual([]);
    expect(mqttMessageToReadings('t', Buffer.from('{"other": 1}'))).toEqual([]);
  });

  test('modbus register decoding: uint16/int16/uint32/float32', () => {
    expect(decodeRegister([905], {})).toBe(905);
    expect(decodeRegister([0xFFFE], { kind: 'int16' })).toBe(-2);
    expect(decodeRegister([1, 2], { kind: 'uint32' })).toBe(65538);
    expect(decodeRegister([0x42B4, 0x0000], { kind: 'float32' })).toBeCloseTo(90, 0);
    expect(decodeRegister([], {})).toBeNull();
    expect(decodeRegister([1], { kind: 'float32' })).toBeNull();
    expect(modbusKey(1, 40001)).toBe('modbus/1/40001');
  });
});

describe('plant simulator', () => {
  test('a tick emits three metrics per machine with plausible values', () => {
    const sim = new SimSource({ machines: 2, seed: 7, faultEveryMs: 999999999, now: NOW });
    sim.lastFaultAt = NOW(); // no faults in this test
    const { readings, faulted } = sim.tick(NOW());
    expect(faulted).toBeNull();
    expect(readings).toHaveLength(6);
    const temp = readings.find((r) => r.key === 'sim/MACH-001/bearing_temperature');
    expect(temp.value).toBeGreaterThan(40);
    expect(temp.value).toBeLessThan(80);
  });

  test('fault injection pushes the victim metric past critical within a cycle', () => {
    const sim = new SimSource({ machines: 3, seed: 7, faultEveryMs: 1000, now: NOW });
    const { readings, faulted } = sim.tick(NOW());
    expect(faulted).toMatch(/^MACH-\d{3}$/);
    const rules = simMapRules(3);
    const victim = readings.filter((r) => r.key.includes(faulted));
    const breached = victim.some((r) => {
      const rule = rules.find((x) => x.match === r.key);
      const t = rule.thresholds;
      return t.direction === 'low' ? r.value <= t.critical : r.value >= t.critical;
    });
    expect(breached).toBe(true);
  });

  test('simulator is deterministic under a fixed seed', () => {
    const a = new SimSource({ machines: 2, seed: 42, faultEveryMs: 1000, now: NOW }).tick(NOW());
    const b = new SimSource({ machines: 2, seed: 42, faultEveryMs: 1000, now: NOW }).tick(NOW());
    expect(a).toEqual(b);
    expect(makeRng(1)()).toBe(makeRng(1)());
  });

  test('sim map rules give every machine a full location', () => {
    const rules = simMapRules(2, 'My Plant');
    expect(rules).toHaveLength(6);
    for (const r of rules) {
      expect(r.factory).toBe('My Plant');
      expect(r.machine).toMatch(/^MACH-\d{3}$/);
      expect(r.thresholds.critical).toBeGreaterThan(0);
    }
  });
});

describe('batcher', () => {
  test('flushes at 20 readings without waiting for the timer', () => {
    const flushed = [];
    const b = new Batcher({ onFlush: (batch) => flushed.push(batch), setTimer: () => 1, clearTimer: () => {} });
    for (let i = 0; i < 20; i++) b.push({ i });
    expect(flushed).toHaveLength(1);
    expect(flushed[0]).toHaveLength(20);
  });

  test('flushes on the delay timer for partial batches', () => {
    const flushed = [];
    let timerFn = null;
    const b = new Batcher({
      onFlush: (batch) => flushed.push(batch),
      setTimer: (fn) => { timerFn = fn; return 1; },
      clearTimer: () => {},
    });
    b.push({ a: 1 });
    b.push({ a: 2 });
    expect(flushed).toHaveLength(0);
    timerFn();
    expect(flushed).toEqual([[{ a: 1 }, { a: 2 }]]);
    timerFn = null;
    b.flush(); // empty flush is a no-op
    expect(flushed).toHaveLength(1);
  });

  test('a burst larger than the cap is chunked into contract-sized batches', () => {
    const flushed = [];
    const b = new Batcher({ onFlush: (batch) => flushed.push(batch), setTimer: () => 1, clearTimer: () => {} });
    b.pushMany(Array.from({ length: 45 }, (_, i) => ({ i })));
    b.flush();
    expect(flushed.map((f) => f.length)).toEqual([20, 20, 5]);
  });
});

describe('config helpers', () => {
  test('parseDuration understands ms/s/m/h and bare numbers', () => {
    expect(parseDuration('90s')).toBe(90000);
    expect(parseDuration('5m')).toBe(300000);
    expect(parseDuration('2000')).toBe(2000);
    expect(parseDuration(1500)).toBe(1500);
    expect(parseDuration('junk', 7)).toBe(7);
    expect(parseDuration(undefined, 7)).toBe(7);
  });

  test('validateConfig demands ingest target, key, and mapped sources', () => {
    const good = validateConfig({
      ingestUrl: 'https://x/ingest/abc',
      ingestKey: 'k'.repeat(16),
      sources: [{ type: 'sim' }],
    });
    expect(good.ok).toBe(true);
    const bad = validateConfig({ ingestUrl: 'ftp://x', ingestKey: 'short', sources: [{ type: 'opcua' }] });
    expect(bad.ok).toBe(false);
    expect(bad.errors.join(' ')).toMatch(/ingestUrl/);
    expect(bad.errors.join(' ')).toMatch(/ingestKey/);
    expect(bad.errors.join(' ')).toMatch(/map/);
    expect(validateConfig({ ingestUrl: 'https://x', ingestKey: 'k'.repeat(16), sources: [{ type: 'fax' }] }).ok).toBe(false);
  });
});
