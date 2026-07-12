// Edge Gateway: protocol adapters against SIMULATED data (no real PLC/broker
// has been touched), the mapping/threshold engine, security controls and the
// retrying forwarder. Every adapter's pure core is exercised here.
import { describe, test, expect } from '@jest/globals';
import {
  applyThresholds, scaleValue, readingToAlert, findRule, wildcardMatch,
} from '../deploy/onprem/edge-gateway/mapping.mjs';
import { parseEsp32 } from '../deploy/onprem/edge-gateway/adapters/esp32.mjs';
import { parseWebhook, pick } from '../deploy/onprem/edge-gateway/adapters/webhook.mjs';
import { decodePayload, mqttMessageToAlert } from '../deploy/onprem/edge-gateway/adapters/mqtt.mjs';
import {
  buildReadRequest, parseReadResponse, decodeRegisters, registerToAlert,
  FC_READ_HOLDING, FC_READ_INPUT,
} from '../deploy/onprem/edge-gateway/adapters/modbus.mjs';
import { dataValueToNumber, opcuaChangeToAlert } from '../deploy/onprem/edge-gateway/adapters/opcua.mjs';
import { authenticate, RateLimiter, payloadTooLarge, keyMatches } from '../deploy/onprem/edge-gateway/security.mjs';
import { Forwarder } from '../deploy/onprem/edge-gateway/forward.mjs';
import { allowedAdapters } from '../deploy/onprem/edge-gateway/index.mjs';
import { validateCanonicalAlert } from '../deploy/onprem/worker-runner/ingest.mjs';

const NOW = () => new Date('2026-07-11T09:00:00.000Z');

describe('mapping & thresholds', () => {
  test('threshold comparisons fire on any breach and report why', () => {
    expect(applyThresholds(95, { gte: 90 })).toEqual({ breached: true, reason: '95 >= 90' });
    expect(applyThresholds(85, { gte: 90 })).toEqual({ breached: false, reason: null });
    expect(applyThresholds(3, { lt: 5 }).breached).toBe(true);
    expect(applyThresholds(1, { eq: 1 }).breached).toBe(true);
    expect(applyThresholds(0, { notEq: 1 }).breached).toBe(true);
    // event-style rules (no thresholds) always fire
    expect(applyThresholds(null, {}).breached).toBe(true);
    // non-numeric values never breach numeric thresholds
    expect(applyThresholds('n/a', { gt: 1 }).breached).toBe(false);
  });

  test('scale/offset convert raw units before thresholds', () => {
    expect(scaleValue(905, { scale: 0.1 })).toBeCloseTo(90.5);
    expect(scaleValue(50, { scale: 2, offset: -30 })).toBe(70);
    expect(scaleValue('junk', {})).toBeNull();
  });

  test('readingToAlert produces a canonical payload the runner accepts', () => {
    const rule = {
      key: 'k', factory: 'Usine A', line: 2, station: 3, machine: 'MACH-007',
      metric: 'temperature', type: 'maintenance', severity: 'critical',
      thresholds: { gte: 90 },
    };
    const alert = readingToAlert({ key: 'k', value: 92.5 }, rule, { source: 'test', now: NOW });
    expect(alert).toMatchObject({
      factory: 'Usine A', line: 2, station: 3, machine: 'MACH-007',
      severity: 'critical', type: 'maintenance', source: 'test',
    });
    expect(validateCanonicalAlert(alert).ok).toBe(true); // gateway->runner contract
    expect(readingToAlert({ key: 'k', value: 20 }, rule)).toBeNull();
  });

  test('wildcard rule lookup: exact wins, + matches one level, # matches rest', () => {
    const rules = [
      { key: 'plant/a/temp', factory: 'A' },
      { key: 'plant/+/temp', factory: 'WILD' },
      { key: 'plant/b/#', factory: 'HASH' },
    ];
    expect(findRule(rules, 'plant/a/temp').factory).toBe('A');
    expect(findRule(rules, 'plant/z/temp').factory).toBe('WILD');
    expect(findRule(rules, 'nothing')).toBeNull();
    expect(wildcardMatch('plant/b/#', 'plant/b/x/y')).toBe(true);
    expect(wildcardMatch('plant/+/temp', 'plant/a/pressure')).toBe(false);
  });
});

describe('ESP32 adapter (simulated boards)', () => {
  const devices = {
    'esp32-oven-3': {
      factory: 'Usine A', line: 2, station: 3, machine: 'MACH-007',
      metric: 'temperature', type: 'maintenance', severity: 'critical',
      thresholds: { gte: 90 },
    },
  };

  test('a hot reading becomes a critical canonical alert', () => {
    const r = parseEsp32({ deviceId: 'esp32-oven-3', value: 92.5 }, devices, { now: NOW });
    expect(r.ok).toBe(true);
    expect(r.alert).toMatchObject({ factory: 'Usine A', severity: 'critical', source: 'esp32:esp32-oven-3' });
    expect(validateCanonicalAlert(r.alert).ok).toBe(true);
  });

  test('a healthy reading is accepted but produces no alert', () => {
    const r = parseEsp32({ deviceId: 'esp32-oven-3', value: 40 }, devices);
    expect(r.ok).toBe(true);
    expect(r.alert).toBeNull();
  });

  test('unknown devices and missing ids are rejected', () => {
    expect(parseEsp32({ deviceId: 'ghost', value: 1 }, devices).ok).toBe(false);
    expect(parseEsp32({ value: 1 }, devices).ok).toBe(false);
    expect(parseEsp32(null, devices).ok).toBe(false);
  });
});

describe('REST webhook adapter (simulated MES payload)', () => {
  const wc = {
    type: 'qualite',
    fields: {
      factory: 'plant.name', line: 'location.lineNumber', station: 'location.stationNumber',
      machine: 'asset.code', value: 'measurement.value', metric: 'measurement.name',
      timestamp: 'occurredAt',
    },
    thresholds: { lt: 0.95 },
  };
  const mesBody = {
    plant: { name: 'Usine A' },
    location: { lineNumber: 1, stationNumber: 4 },
    asset: { code: 'MACH-002' },
    measurement: { name: 'first_pass_yield', value: 0.91 },
    occurredAt: '2026-07-11T08:59:00Z',
  };

  test('dotted-path extraction produces a valid canonical alert', () => {
    const r = parseWebhook(mesBody, wc, { source: 'webhook:mes-quality' });
    expect(r.ok).toBe(true);
    expect(r.alert).toMatchObject({
      factory: 'Usine A', line: 1, station: 4, machine: 'MACH-002',
      type: 'qualite', source: 'webhook:mes-quality',
    });
    expect(validateCanonicalAlert(r.alert).ok).toBe(true);
  });

  test('yield above threshold -> no alert; missing factory -> error', () => {
    const healthy = { ...mesBody, measurement: { name: 'fpy', value: 0.99 } };
    expect(parseWebhook(healthy, wc).alert).toBeNull();
    expect(parseWebhook({ nope: 1 }, wc).ok).toBe(false);
  });

  test('constants override extraction and pick() walks arrays', () => {
    expect(pick({ a: [{ b: 7 }] }, 'a.0.b')).toBe(7);
    const r = parseWebhook({ workorder: { title: 'Pump seal', assetId: 'MACH-9' } }, {
      type: 'maintenance',
      constants: { factory: 'Usine B', line: 0, station: 0 },
      fields: { description: 'workorder.title', machine: 'workorder.assetId' },
    });
    expect(r.alert.factory).toBe('Usine B');
    expect(r.alert.description).toBe('Pump seal');
  });
});

describe('MQTT adapter (simulated broker messages)', () => {
  const rules = [{
    key: 'plant/usine-a/line/2/station/3/temperature',
    factory: 'Usine A', line: 2, station: 3, metric: 'temperature',
    type: 'maintenance', thresholds: { gte: 90 },
  }];

  test('decodes JSON, bare-number and text payloads', () => {
    expect(decodePayload(Buffer.from('{"value": 92.5, "ts": "2026-07-11T08:00:00Z"}')))
      .toMatchObject({ value: 92.5, timestamp: '2026-07-11T08:00:00Z' });
    expect(decodePayload(Buffer.from('42.5')).value).toBe(42.5);
    expect(decodePayload(Buffer.from('ONLINE')).value).toBeNull();
  });

  test('a hot topic message becomes a canonical alert; cool one does not', () => {
    const hot = mqttMessageToAlert(
      'plant/usine-a/line/2/station/3/temperature', Buffer.from('95'), rules, { now: NOW },
    );
    expect(hot).toMatchObject({ factory: 'Usine A', type: 'maintenance' });
    expect(validateCanonicalAlert(hot).ok).toBe(true);
    expect(mqttMessageToAlert('plant/usine-a/line/2/station/3/temperature', Buffer.from('50'), rules)).toBeNull();
    expect(mqttMessageToAlert('unmapped/topic', Buffer.from('95'), rules)).toBeNull();
  });
});

describe('Modbus TCP adapter (simulated frames — no real PLC tested)', () => {
  test('read request frame is byte-exact', () => {
    const frame = buildReadRequest({ txnId: 7, unitId: 1, fc: FC_READ_HOLDING, address: 100, count: 2 });
    expect([...frame]).toEqual([0, 7, 0, 0, 0, 6, 1, 3, 0, 100, 0, 2]);
  });

  test('the builder refuses write function codes — read-only by construction', () => {
    for (const writeFc of [0x05, 0x06, 0x0f, 0x10]) {
      expect(() => buildReadRequest({ fc: writeFc, address: 0, count: 1 })).toThrow(/read-only/);
    }
    expect(() => buildReadRequest({ fc: FC_READ_INPUT, address: 0, count: 200 })).toThrow(/1\.\.125/);
  });

  test('parses a simulated response and modbus exceptions', () => {
    // response: txn 7, unit 1, fc 3, 4 bytes, registers [0x4212, 0x8000]
    const res = Buffer.from([0, 7, 0, 0, 0, 7, 1, 3, 4, 0x42, 0x12, 0x80, 0x00]);
    const parsed = parseReadResponse(res);
    expect(parsed.ok).toBe(true);
    expect(parsed.registers).toEqual([0x4212, 0x8000]);

    const exception = Buffer.from([0, 7, 0, 0, 0, 3, 1, 0x83, 0x02]);
    const bad = parseReadResponse(exception);
    expect(bad.ok).toBe(false);
    expect(bad.error).toContain('exception');
    expect(parseReadResponse(Buffer.from([0, 1]))).toMatchObject({ ok: false });
  });

  test('register decoding: float32/int32/int16 with word order', () => {
    // 36.5f big-endian = 0x4212 0x0000
    expect(decodeRegisters([0x4212, 0x0000], { dataType: 'float32' })).toBeCloseTo(36.5);
    expect(decodeRegisters([0x0000, 0x4212], { dataType: 'float32', wordOrder: 'LH' })).toBeCloseTo(36.5);
    expect(decodeRegisters([0xffff], { dataType: 'int16' })).toBe(-1);
    expect(decodeRegisters([0xffff], { dataType: 'uint16' })).toBe(0xffff);
    expect(decodeRegisters([0x0001, 0x0000], { dataType: 'uint32' })).toBe(65536);
    expect(decodeRegisters([1], { dataType: 'bool' })).toBe(true);
    expect(decodeRegisters([], { dataType: 'float32' })).toBeNull();
  });

  test('a register map entry turns simulated registers into a canonical alert', () => {
    const entry = {
      name: 'oven_temp', address: 40001, dataType: 'float32',
      factory: 'Usine A', line: 2, station: 3, machine: 'MACH-007',
      metric: 'temperature', type: 'maintenance', severity: 'critical',
      thresholds: { gte: 90 },
    };
    // 92.5f = 0x42B9 0x0000
    const alert = registerToAlert(entry, [0x42b9, 0x0000], { now: NOW });
    expect(alert).toMatchObject({ factory: 'Usine A', severity: 'critical', value: 92.5 });
    expect(validateCanonicalAlert(alert).ok).toBe(true);
    expect(registerToAlert(entry, [0x41a0, 0x0000])).toBeNull(); // 20.0 -> healthy
  });
});

describe('OPC UA adapter (simulated DataValues — no real server tested)', () => {
  const rules = [{
    key: 'ns=2;s=Line2.Station3.Motor.Temperature',
    factory: 'Usine A', line: 2, station: 3, metric: 'motor_temperature',
    type: 'maintenance', thresholds: { gte: 90 },
  }];

  test('extracts numbers from DataValue shapes (incl. booleans)', () => {
    expect(dataValueToNumber({ value: { value: 92.5 } })).toBe(92.5);
    expect(dataValueToNumber({ value: { value: true } })).toBe(1);
    expect(dataValueToNumber({ value: { value: 'text' } })).toBeNull();
  });

  test('a monitored-item change maps to a canonical alert', () => {
    const alert = opcuaChangeToAlert(
      'ns=2;s=Line2.Station3.Motor.Temperature',
      { value: { value: 95 }, sourceTimestamp: '2026-07-11T08:30:00Z' },
      rules, { now: NOW },
    );
    expect(alert).toMatchObject({ factory: 'Usine A', metric: 'motor_temperature' });
    expect(alert.timestamp).toBe('2026-07-11T08:30:00.000Z');
    expect(validateCanonicalAlert(alert).ok).toBe(true);
    expect(opcuaChangeToAlert('ns=9;s=Unmapped', { value: { value: 95 } }, rules)).toBeNull();
  });
});

describe('gateway security', () => {
  test('API key auth via header or bearer, timing-safe compare', () => {
    const keys = { 'oven-fleet': 'k-123456' };
    expect(authenticate({ 'x-api-key': 'k-123456' }, keys)).toBe('oven-fleet');
    expect(authenticate({ authorization: 'Bearer k-123456' }, keys)).toBe('oven-fleet');
    expect(authenticate({ 'x-api-key': 'wrong' }, keys)).toBeNull();
    expect(authenticate({}, keys)).toBeNull();
    expect(keyMatches('abc', '')).toBe(false); // empty expected never matches
  });

  test('token-bucket rate limiter refills over time', () => {
    const rl = new RateLimiter({ capacity: 2, refillPerSec: 1 });
    const t0 = 1_000_000;
    expect(rl.allow('dev', t0)).toBe(true);
    expect(rl.allow('dev', t0)).toBe(true);
    expect(rl.allow('dev', t0)).toBe(false); // bucket empty
    expect(rl.allow('other', t0)).toBe(true); // independent callers
    expect(rl.allow('dev', t0 + 1500)).toBe(true); // refilled
  });

  test('payload size cap', () => {
    expect(payloadTooLarge('x'.repeat(10))).toBe(false);
    expect(payloadTooLarge('x'.repeat(33 * 1024))).toBe(true);
  });
});

describe('forwarder retry/queue', () => {
  const alert = { factory: 'Usine A', type: 'maintenance', line: 1, station: 1, source: 'test' };

  test('delivers with Bearer auth and counts runner verdicts', async () => {
    const calls = [];
    const f = new Forwarder({
      ingestUrl: 'http://runner/ingest',
      sharedSecret: 'S',
      fetchImpl: async (url, opts) => {
        calls.push({ url, auth: opts.headers.Authorization });
        return { ok: true, status: 200, json: async () => ({ status: 'created' }) };
      },
    });
    await f.send(alert);
    expect(calls[0].auth).toBe('Bearer S');
    expect(f.stats.sent).toBe(1);
    expect(f.queue.length).toBe(0);
  });

  test('5xx retries then succeeds; alert is never lost', async () => {
    let n = 0;
    const f = new Forwarder({
      ingestUrl: 'u', sharedSecret: 's',
      retry: { attempts: 3, sleep: async () => {}, rand: () => 0 },
      fetchImpl: async () => {
        n++;
        if (n < 3) return { ok: false, status: 503, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => ({ status: 'created' }) };
      },
    });
    await f.send(alert);
    expect(n).toBe(3);
    expect(f.stats.sent).toBe(1);
  });

  test('total outage keeps the alert queued for the next drain', async () => {
    const f = new Forwarder({
      ingestUrl: 'u', sharedSecret: 's',
      retry: { attempts: 2, sleep: async () => {}, rand: () => 0 },
      fetchImpl: async () => { throw new Error('down'); },
    });
    await f.send(alert);
    expect(f.queue.length).toBe(1);
    expect(f.stats.failed).toBe(1);

    // runner comes back -> drain flushes the backlog
    f.fetch = async () => ({ ok: true, status: 200, json: async () => ({ status: 'created' }) });
    await f.drain();
    expect(f.queue.length).toBe(0);
    expect(f.stats.sent).toBe(1);
  });

  test('bounded queue drops the oldest on overflow', async () => {
    const f = new Forwarder({
      ingestUrl: 'u', sharedSecret: 's', maxQueue: 2,
      retry: { attempts: 1, sleep: async () => {} },
      fetchImpl: async () => { throw new Error('down'); },
    });
    await f.send({ ...alert, station: 1 });
    await f.send({ ...alert, station: 2 });
    await f.send({ ...alert, station: 3 });
    expect(f.queue.length).toBe(2);
    expect(f.stats.dropped).toBe(1);
    expect(f.queue[0].station).toBe(2); // oldest gone
  });
});

describe('licence gating of protocol adapters', () => {
  const config = {
    adapters: {
      mqtt: { enabled: true },
      opcua: { enabled: true },
      modbus: { enabled: false },
    },
  };

  test('standard plan keeps HTTP but skips industrial adapters', () => {
    const std = ['alerts.core', 'gateway.http'];
    expect(allowedAdapters(config, std)).toEqual([]);
  });

  test('industrial plan starts everything enabled', () => {
    const ind = ['gateway.mqtt', 'gateway.opcua', 'gateway.modbus'];
    expect(allowedAdapters(config, ind)).toEqual(['mqtt', 'opcua']);
  });

  test('no licence info -> fail open (never brick ingestion on a probe error)', () => {
    expect(allowedAdapters(config, null)).toEqual(['mqtt', 'opcua']);
  });
});
