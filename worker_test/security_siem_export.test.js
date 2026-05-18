import { jest } from '@jest/globals';

import {
  _securityBuildElasticBulkNdjson,
  _securityElasticConfig,
  _securityEventToEcsDocument,
  _securityFlushSiemOutbox,
} from '../cloudflare_ai_worker.js';

function jsonRes(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('Elastic Security SIEM export', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test.each([
    ['actions', 'rate_limit_block', 'alert', 'network', 'denied', 'failure', 7],
    ['actions', 'prompt_injection_block', 'alert', 'intrusion_detection', 'denied', 'failure', 8],
    ['actions', 'bad_payload', 'alert', 'web', 'error', 'failure', 5],
    ['actions', 'alert_flood_detected', 'alert', 'intrusion_detection', 'info', 'unknown', 7],
    ['actions', 'auth_failure_surge', 'alert', 'authentication', 'info', 'failure', 8],
    ['logs', 'malformed_alerts_seen', 'event', 'database', 'info', 'unknown', 4],
    ['logs', 'scan_heartbeat', 'event', 'configuration', 'info', 'success', 1],
  ])(
    'maps %s/%s to ECS',
    (source, kind, eventKind, category, type, outcome, severity) => {
      const doc = _securityEventToEcsDocument(
        source,
        'evt-1',
        {
          at: '2026-05-18T10:00:00.000Z',
          kind,
          endpoint: 'ai-suggest',
          fingerprint: '203.0.113.10|ua',
          observed: 31,
          limit: 30,
          matches: ['ignore_previous'],
          preview: 'ignore previous instructions',
        },
        'logs-sia.security-production',
      );

      expect(doc['@timestamp']).toBe('2026-05-18T10:00:00.000Z');
      expect(doc.event.kind).toBe(eventKind);
      expect(doc.event.category).toContain(category);
      expect(doc.event.type).toContain(type);
      expect(doc.event.outcome).toBe(outcome);
      expect(doc.event.severity).toBe(severity);
      expect(doc.service.name).toBe('sia-ai-security-worker');
      expect(doc.observer.vendor).toBe('Cloudflare');
      expect(doc.cloud.provider).toBe('cloudflare');
      expect(doc.source.ip).toBe('203.0.113.10');
      expect(doc.sia.security.firebase_event_id).toBe('evt-1');
      expect(doc.sia.security.endpoint).toBe('ai-suggest');
    },
  );

  test('builds Elastic bulk NDJSON with create actions and final newline', () => {
    const doc = _securityEventToEcsDocument('actions', 'evt-1', {
      at: '2026-05-18T10:00:00.000Z',
      kind: 'rate_limit_block',
    });
    const ndjson = _securityBuildElasticBulkNdjson(
      [{ id: 'sia-evt-1', doc }],
      'logs-sia.security-production',
    );

    expect(ndjson.endsWith('\n')).toBe(true);
    const lines = ndjson.trimEnd().split('\n');
    expect(lines).toHaveLength(2);
    expect(JSON.parse(lines[0])).toEqual({
      create: {
        _index: 'logs-sia.security-production',
        _id: 'sia-evt-1',
      },
    });
    expect(JSON.parse(lines[1]).event.action).toBe('rate_limit_block');
  });

  test('disabled or missing Elastic config skips export cleanly', async () => {
    globalThis.fetch = jest.fn();

    expect(_securityElasticConfig({ ELASTIC_SIEM_ENABLED: 'false' }).enabled)
      .toBe(false);
    const result = await _securityFlushSiemOutbox(
      { FB_DB_URL: 'https://db.test/' },
      { token: 'tok' },
    );

    expect(result.enabled).toBe(false);
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  test('exports due outbox events and marks them exported', async () => {
    const patches = [];
    const env = {
      FB_DB_URL: 'https://db.test/',
      ELASTIC_SIEM_ENABLED: 'true',
      ELASTICSEARCH_URL: 'https://elastic.test/',
      ELASTIC_API_KEY: 'secret',
    };

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      if (u.includes('security/siem_outbox.json') && u.includes('equalTo=%22exported%22')) {
        return Promise.resolve(jsonRes({}));
      }
      if (u.includes('security/siem_outbox.json') && method === 'GET') {
        return Promise.resolve(jsonRes({
          evt1: {
            source: 'actions',
            eventId: 'evt1',
            status: 'pending',
            attempts: 0,
            nextAttemptAt: '2000-01-01T00:00:00.000Z',
            event: {
              at: '2026-05-18T10:00:00.000Z',
              kind: 'prompt_injection_block',
              endpoint: 'ai-proxy',
              fingerprint: '198.51.100.20|ua',
            },
          },
        }));
      }
      if (u === 'https://elastic.test/_bulk') {
        expect(opts.headers.Authorization).toBe('ApiKey secret');
        expect(opts.headers['Content-Type']).toBe('application/x-ndjson');
        expect(opts.body).toContain('"create"');
        return Promise.resolve(jsonRes({ errors: false, items: [{ create: { status: 201 } }] }));
      }
      if (u === 'https://db.test/.json?auth=tok' && method === 'PATCH') {
        patches.push(JSON.parse(opts.body));
        return Promise.resolve(jsonRes({ ok: true }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const result = await _securityFlushSiemOutbox(env, { token: 'tok' });

    expect(result.exported).toBe(1);
    expect(result.failed).toBe(0);
    const markPatch = patches.find((p) =>
      p['security/siem_outbox/evt1/status'] === 'exported');
    expect(markPatch).toBeTruthy();
    expect(markPatch['security/siem_outbox/evt1/lastError']).toBeNull();
  });

  test('partial Elastic failures retry only failed items', async () => {
    const patches = [];
    const env = {
      FB_DB_URL: 'https://db.test/',
      ELASTIC_SIEM_ENABLED: 'true',
      ELASTICSEARCH_URL: 'https://elastic.test',
      ELASTIC_API_KEY: 'secret',
    };

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      if (u.includes('security/siem_outbox.json') && u.includes('equalTo=%22exported%22')) {
        return Promise.resolve(jsonRes({}));
      }
      if (u.includes('security/siem_outbox.json') && method === 'GET') {
        return Promise.resolve(jsonRes({
          evt1: {
            source: 'actions',
            eventId: 'evt1',
            status: 'pending',
            attempts: 0,
            nextAttemptAt: '2000-01-01T00:00:00.000Z',
            event: { at: '2026-05-18T10:00:00.000Z', kind: 'rate_limit_block' },
          },
          evt2: {
            source: 'logs',
            eventId: 'evt2',
            status: 'pending',
            attempts: 0,
            nextAttemptAt: '2000-01-01T00:00:00.000Z',
            event: { at: '2026-05-18T10:01:00.000Z', kind: 'scan_heartbeat' },
          },
        }));
      }
      if (u === 'https://elastic.test/_bulk') {
        return Promise.resolve(jsonRes({
          errors: true,
          items: [
            { create: { status: 201 } },
            { create: { status: 500, error: { type: 'mapper_parsing_exception' } } },
          ],
        }));
      }
      if (u === 'https://db.test/.json?auth=tok' && method === 'PATCH') {
        patches.push(JSON.parse(opts.body));
        return Promise.resolve(jsonRes({ ok: true }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const result = await _securityFlushSiemOutbox(env, { token: 'tok' });

    expect(result.exported).toBe(1);
    expect(result.failed).toBe(1);
    const markPatch = patches.find((p) =>
      p['security/siem_outbox/evt1/status'] === 'exported' &&
      p['security/siem_outbox/evt2/status'] === 'pending');
    expect(markPatch).toBeTruthy();
    expect(markPatch['security/siem_outbox/evt2/attempts']).toBe(1);
    expect(markPatch['security/siem_outbox/evt2/nextAttemptAt']).toEqual(expect.any(String));
  });

  test('moves failed events to dead letter after max attempts', async () => {
    const patches = [];
    const env = {
      FB_DB_URL: 'https://db.test/',
      ELASTIC_SIEM_ENABLED: 'true',
      ELASTICSEARCH_URL: 'https://elastic.test',
      ELASTIC_API_KEY: 'secret',
    };

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      if (u.includes('security/siem_outbox.json') && u.includes('equalTo=%22exported%22')) {
        return Promise.resolve(jsonRes({}));
      }
      if (u.includes('security/siem_outbox.json') && method === 'GET') {
        return Promise.resolve(jsonRes({
          evt1: {
            source: 'actions',
            eventId: 'evt1',
            status: 'pending',
            attempts: 4,
            nextAttemptAt: '2000-01-01T00:00:00.000Z',
            event: { at: '2026-05-18T10:00:00.000Z', kind: 'bad_payload' },
          },
        }));
      }
      if (u === 'https://elastic.test/_bulk') {
        return Promise.resolve(jsonRes({
          errors: true,
          items: [{ create: { status: 500, error: { type: 'mapper_parsing_exception' } } }],
        }));
      }
      if (u === 'https://db.test/.json?auth=tok' && method === 'PATCH') {
        patches.push(JSON.parse(opts.body));
        return Promise.resolve(jsonRes({ ok: true }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const result = await _securityFlushSiemOutbox(env, { token: 'tok' });

    expect(result.deadLetter).toBe(1);
    const markPatch = patches.find((p) =>
      p['security/siem_outbox/evt1/status'] === 'dead_letter');
    expect(markPatch).toBeTruthy();
    expect(markPatch['security/siem_outbox/evt1/attempts']).toBe(5);
    expect(markPatch['security/siem_outbox/evt1/nextAttemptAt']).toBeNull();
  });
});
