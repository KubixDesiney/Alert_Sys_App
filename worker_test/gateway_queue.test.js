// Reference edge gateway: the on-disk retry queue and the retrying forwarder.
// No sockets — fetch is injected; the queue runs against a temp directory.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { jest } from '@jest/globals';
import { DiskQueue } from '../gateway/src/queue.mjs';
import { Forwarder } from '../gateway/src/forwarder.mjs';

const silentLog = { info: () => {}, warn: () => {}, error: () => {} };
const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'sias-gw-q-'));
const readings = (n, tag = 'r') => Array.from({ length: n }, (_, i) => ({ metric: `${tag}${i}` }));

describe('DiskQueue', () => {
  test('persists batches across restarts (JSONL round-trip)', () => {
    const dir = tmpDir();
    try {
      const q1 = new DiskQueue(dir, { log: silentLog });
      q1.enqueue(readings(3), 111);
      q1.enqueue(readings(2), 222);
      expect(q1.size).toBe(5);

      const q2 = new DiskQueue(dir, { log: silentLog });
      expect(q2.size).toBe(5);
      expect(q2.peek().at).toBe(111);
      expect(q2.shift().readings).toHaveLength(3);
      const q3 = new DiskQueue(dir, { log: silentLog });
      expect(q3.size).toBe(2);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('caps total readings and drops the OLDEST batch with a warning', () => {
    const dir = tmpDir();
    try {
      const warns = [];
      const q = new DiskQueue(dir, { capReadings: 10, log: { warn: (m) => warns.push(m) } });
      q.enqueue(readings(6, 'old'));
      q.enqueue(readings(6, 'new'));
      expect(q.size).toBe(6); // old batch dropped
      expect(q.peek().readings[0].metric).toBe('new0');
      expect(q.dropped).toBe(6);
      expect(warns[0]).toMatch(/queue full/);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('skips a corrupt (torn) line on load instead of dying', () => {
    const dir = tmpDir();
    try {
      const q = new DiskQueue(dir, { log: silentLog });
      q.enqueue(readings(2));
      fs.appendFileSync(path.join(dir, 'queue.jsonl'), '{"at": 1, "readi'); // simulated crash mid-write
      const q2 = new DiskQueue(dir, { log: silentLog });
      expect(q2.size).toBe(2);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('empty/invalid enqueues are ignored', () => {
    const dir = tmpDir();
    try {
      const q = new DiskQueue(dir, { log: silentLog });
      q.enqueue([]);
      q.enqueue(null);
      expect(q.size).toBe(0);
      expect(q.shift()).toBeNull();
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('Forwarder', () => {
  const okFetch = () => jest.fn(async () => new Response(JSON.stringify({ ok: true, created: 1 }), { status: 200 }));

  function make({ fetchImpl, nowRef = { t: 1000 } }) {
    const dir = tmpDir();
    const queue = new DiskQueue(dir, { log: silentLog });
    const fwd = new Forwarder({
      ingestUrl: 'https://ingest.example/ingest/abc',
      ingestKey: 'k'.repeat(16),
      queue,
      fetchImpl,
      log: silentLog,
      backoffBaseMs: 1000,
      backoffMaxMs: 8000,
      now: () => nowRef.t,
    });
    return { fwd, queue, dir, nowRef };
  }

  test('successful send posts the batch with the ingest key header', async () => {
    const fetchImpl = okFetch();
    const { fwd, dir } = make({ fetchImpl });
    try {
      const res = await fwd.send(readings(3));
      expect(res).toEqual({ ok: true, sent: 3 });
      expect(fetchImpl).toHaveBeenCalledTimes(1);
      const [url, init] = fetchImpl.mock.calls[0];
      expect(url).toBe('https://ingest.example/ingest/abc');
      expect(init.headers['x-alertsys-ingest']).toBe('k'.repeat(16));
      expect(JSON.parse(init.body).readings).toHaveLength(3);
      expect(fwd.stats.created).toBe(1);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('network failure queues the batch and backs off exponentially', async () => {
    const fetchImpl = jest.fn(async () => { throw new Error('ECONNREFUSED'); });
    const { fwd, queue, dir, nowRef } = make({ fetchImpl });
    try {
      await fwd.send(readings(2));
      await fwd.send(readings(2));
      expect(queue.size).toBe(4);
      expect(fwd.consecutiveFailures).toBe(2);
      expect(fwd.nextDelay(1)).toBe(1000);
      expect(fwd.nextDelay(2)).toBe(2000);
      expect(fwd.nextDelay(10)).toBe(8000); // capped
      // drain refuses to hammer the endpoint before the backoff expires
      expect(await fwd.drain()).toMatchObject({ drained: 0, waiting: true });
      nowRef.t += 100000;
      fetchImpl.mockImplementation(async () => new Response('{}', { status: 200 }));
      const drained = await fwd.drain();
      expect(drained.drained).toBe(4);
      expect(queue.size).toBe(0);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('5xx and 429 are retryable; other 4xx drops permanently', async () => {
    const codes = [];
    const fetchImpl = jest.fn(async () => new Response('no', { status: codes.shift() }));
    const { fwd, queue, dir } = make({ fetchImpl });
    try {
      codes.push(503);
      await fwd.send(readings(1, 'a'));
      expect(queue.size).toBe(1);
      codes.push(429);
      await fwd.send(readings(1, 'b'));
      expect(queue.size).toBe(2);
      codes.push(400);
      const res = await fwd.send(readings(1, 'c'));
      expect(res.retryable).toBe(false);
      expect(queue.size).toBe(2); // 400 batch not queued
      expect(fwd.stats.droppedPermanent).toBe(1);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('401 (key rotation window) stays queued rather than lost', async () => {
    const fetchImpl = jest.fn(async () => new Response('no', { status: 401 }));
    const { fwd, queue, dir } = make({ fetchImpl });
    try {
      await fwd.send(readings(2));
      expect(queue.size).toBe(2);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('drain puts a still-failing batch back at the FRONT (ordering preserved)', async () => {
    let fail = true;
    const fetchImpl = jest.fn(async () => {
      if (fail) throw new Error('down');
      return new Response('{}', { status: 200 });
    });
    const { fwd, queue, dir, nowRef } = make({ fetchImpl });
    try {
      queue.enqueue(readings(1, 'first'));
      queue.enqueue(readings(1, 'second'));
      await fwd.drain();
      expect(queue.peek().readings[0].metric).toBe('first0');
      fail = false;
      nowRef.t += 100000;
      const res = await fwd.drain();
      expect(res.drained).toBe(2);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test('empty sends are free; missing ingestUrl is a construction error', async () => {
    const { fwd, dir } = make({ fetchImpl: okFetch() });
    try {
      expect(await fwd.send([])).toEqual({ ok: true, sent: 0 });
      expect(() => new Forwarder({})).toThrow(/ingestUrl/);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
