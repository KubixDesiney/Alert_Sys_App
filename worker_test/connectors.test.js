import {
  isPullKind,
  isPushKind,
  isMqttKind,
  getByPath,
  extractValue,
  connectorAuthHeaders,
  buildRestUrl,
  mergeConnectorDefaults,
  pollDue,
  verifyPushStatus,
  buildMqttConnect,
  parseConnack,
  mqttRemainingLength,
  normalizeTelemetry,
} from '../cloudflare_ingest_connectors.js';

describe('connector kind classification', () => {
  test('pull kinds', () => {
    expect(isPullKind('rest')).toBe(true);
    expect(isPullKind('historian_pi')).toBe(true);
    expect(isPullKind('historian_ignition')).toBe(true);
    expect(isPullKind('OPCUA')).toBe(false);
  });
  test('push kinds', () => {
    expect(isPushKind('opcua')).toBe(true);
    expect(isPushKind('modbus')).toBe(true);
    expect(isPushKind('microcontroller')).toBe(true);
    expect(isPushKind('rest')).toBe(false);
  });
  test('mqtt is its own family', () => {
    expect(isMqttKind('mqtt')).toBe(true);
    expect(isMqttKind('MQTT')).toBe(true);
    expect(isPullKind('mqtt')).toBe(false);
    expect(isPushKind('mqtt')).toBe(false);
  });
});

describe('getByPath / extractValue', () => {
  test('dotted + bracketed path', () => {
    expect(getByPath({ a: { b: [10, 20] } }, 'a.b[1]')).toBe(20);
    expect(getByPath({ a: 1 }, 'missing')).toBeUndefined();
    expect(getByPath(null, 'a')).toBeUndefined();
  });
  test('PI Web API shape: {Timestamp, Value, Good}', () => {
    expect(extractValue({ Timestamp: 't', Value: 95.4, Good: true }, 'Value')).toBe(95.4);
  });
  test('unwraps a nested {value} object', () => {
    expect(extractValue({ data: { value: 7 } }, 'data')).toBe(7);
  });
  test('plain nested number', () => {
    expect(extractValue({ data: { temp: 50 } }, 'data.temp')).toBe(50);
  });
});

describe('connectorAuthHeaders', () => {
  test('bearer', () => {
    expect(connectorAuthHeaders({ auth: { scheme: 'bearer' } }, { token: 'abc' }))
      .toEqual({ Authorization: 'Bearer abc' });
  });
  test('basic (user from secret, password from secret)', () => {
    const h = connectorAuthHeaders({ auth: { scheme: 'basic' } }, { username: 'u', password: 'p' });
    expect(h.Authorization).toBe('Basic ' + btoa('u:p'));
  });
  test('custom header name', () => {
    expect(connectorAuthHeaders({ auth: { scheme: 'header', headerName: 'X-Token' } }, { token: 't' }))
      .toEqual({ 'X-Token': 't' });
  });
  test('none -> no auth header', () => {
    expect(connectorAuthHeaders({ auth: { scheme: 'none' } }, {})).toEqual({});
  });
});

describe('buildRestUrl', () => {
  test('PI Web API stream value URL from webId', () => {
    const u = buildRestUrl({ kind: 'historian_pi', endpoint: 'https://pi/piwebapi' }, { webId: 'F1abc' });
    expect(u).toBe('https://pi/piwebapi/streams/F1abc/value');
  });
  test('path template substitution', () => {
    const u = buildRestUrl({ kind: 'rest', endpoint: 'https://h/api' }, { path: '/tags/{tag}/value', tag: 'bearing temp' });
    expect(u).toBe('https://h/api/tags/bearing%20temp/value');
  });
  test('tag query param fallback', () => {
    const u = buildRestUrl({ kind: 'rest', endpoint: 'https://h/api' }, { tag: 'T1' });
    expect(u).toBe('https://h/api?tag=T1');
  });
  test('query-string api key auth appends param', () => {
    const u = buildRestUrl({ kind: 'rest', endpoint: 'https://h/api', auth: { scheme: 'query', queryParam: 'key' } }, { tag: 'T1' }, { token: 'SEKRIT' });
    expect(u).toBe('https://h/api?tag=T1&key=SEKRIT');
  });
});

describe('mergeConnectorDefaults', () => {
  test('fills factory/line/station/metric from connector + tag', () => {
    const out = mergeConnectorDefaults(
      { value: 95 },
      { kind: 'rest', factory: 'Plant 1', line: 'Line 2', station: 'S3' },
      { metric: 'bearing_temp', unit: 'C', thresholds: { warn: 70, critical: 90 } },
    );
    expect(out.factory).toBe('Plant 1');
    expect(out.line).toBe('Line 2');
    expect(out.station).toBe('S3');
    expect(out.metric).toBe('bearing_temp');
    expect(out.unit).toBe('C');
    expect(out.thresholds).toEqual({ warn: 70, critical: 90 });
  });
  test('reading values win over connector defaults', () => {
    const out = mergeConnectorDefaults({ factory: 'Override', value: 1 }, { factory: 'Default' }, {});
    expect(out.factory).toBe('Override');
  });
  test('a merged reading drives a real alert through normalizeTelemetry', () => {
    const reading = mergeConnectorDefaults(
      { value: 95 },
      { kind: 'historian_pi', factory: 'Plant 1', line: 'Line 2', station: 'S3' },
      { metric: 'bearing_temp', unit: 'C', thresholds: { warn: 70, critical: 90 } },
    );
    const alert = normalizeTelemetry(reading, { source: 'historian_pi' });
    expect(alert).not.toBeNull();
    expect(alert.type).toBe('Mechanical');
    expect(alert.isCritical).toBe(true);
    expect(alert.usine).toBe('Plant 1');
  });
});

describe('pollDue', () => {
  const base = { kind: 'rest', pollIntervalSec: 60 };
  test('due when never polled', () => {
    expect(pollDue(base, 1_000_000)).toBe(true);
  });
  test('not due within interval', () => {
    expect(pollDue({ ...base, runtime: { lastPollAt: 1_000_000 } }, 1_000_000 + 30_000)).toBe(false);
  });
  test('due after interval elapses', () => {
    expect(pollDue({ ...base, runtime: { lastPollAt: 1_000_000 } }, 1_000_000 + 61_000)).toBe(true);
  });
  test('disabled connectors never poll', () => {
    expect(pollDue({ ...base, enabled: false }, 1_000_000)).toBe(false);
  });
  test('push kinds never cloud-poll', () => {
    expect(pollDue({ kind: 'opcua' }, 1_000_000)).toBe(false);
  });
});

describe('verifyPushStatus', () => {
  test('linked when a packet arrived inside the fresh window', () => {
    const r = verifyPushStatus({ runtime: { lastIngestAt: 1_000_000 } }, 1_000_000 + 60_000);
    expect(r.ok).toBe(true);
    expect(r.status).toBe('linked');
  });
  test('waiting when no recent packet', () => {
    const r = verifyPushStatus({ runtime: { lastIngestAt: 0 } }, 1_000_000);
    expect(r.ok).toBe(false);
    expect(r.status).toBe('waiting');
  });
});

describe('MQTT CONNECT/CONNACK', () => {
  test('remaining-length varint encoding', () => {
    expect(mqttRemainingLength(0)).toEqual([0]);
    expect(mqttRemainingLength(13)).toEqual([13]);
    expect(mqttRemainingLength(128)).toEqual([0x80, 0x01]);
  });
  test('CONNECT packet layout (clientId only)', () => {
    const p = buildMqttConnect('c', '', '', 30);
    // [0x10, len, 0,4,'M','Q','T','T', level, flags, kaHi, kaLo, 0,1,'c']
    expect(p[0]).toBe(0x10);
    expect(p[1]).toBe(13);
    expect(Array.from(p.slice(2, 8))).toEqual([0, 4, 77, 81, 84, 84]);
    expect(p[8]).toBe(0x04); // protocol level 3.1.1
    expect(p[9]).toBe(0x02); // clean session, no user/pass
    expect(p[10]).toBe(0); expect(p[11]).toBe(30); // keepAlive
    expect(Array.from(p.slice(12))).toEqual([0, 1, 99]); // clientId 'c'
  });
  test('CONNECT sets username + password flags', () => {
    const p = buildMqttConnect('id', 'user', 'pass');
    expect(p[9] & 0x80).toBe(0x80); // username flag
    expect(p[9] & 0x40).toBe(0x40); // password flag
  });
  test('CONNACK accepted / refused / malformed', () => {
    expect(parseConnack(new Uint8Array([0x20, 0x02, 0x00, 0x00])).ok).toBe(true);
    const refused = parseConnack(new Uint8Array([0x20, 0x02, 0x00, 0x05]));
    expect(refused.ok).toBe(false);
    expect(refused.reason).toMatch(/not authorized/);
    expect(parseConnack(new Uint8Array([0x30, 0x02, 0x00, 0x00])).reason).toBe('not_connack');
    expect(parseConnack(new Uint8Array([0x20, 0x02])).reason).toBe('short');
  });
});
