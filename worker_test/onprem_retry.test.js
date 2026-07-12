// Retry/backoff behaviour used for every PocketBase call the runner makes.
import { describe, test, expect } from '@jest/globals';
import { withRetry, retryableHttp } from '../deploy/onprem/worker-runner/retry.mjs';

const noSleep = { sleep: async () => {}, rand: () => 0.5 };

describe('withRetry', () => {
  test('returns on first success without retrying', async () => {
    let calls = 0;
    const out = await withRetry(async () => { calls++; return 'ok'; }, noSleep);
    expect(out).toBe('ok');
    expect(calls).toBe(1);
  });

  test('retries transient failures then succeeds', async () => {
    let calls = 0;
    const out = await withRetry(async () => {
      calls++;
      if (calls < 3) throw new Error('flaky');
      return 'recovered';
    }, { attempts: 4, ...noSleep });
    expect(out).toBe('recovered');
    expect(calls).toBe(3);
  });

  test('gives up after the attempt budget and rethrows the last error', async () => {
    let calls = 0;
    await expect(withRetry(async () => { calls++; throw new Error(`fail ${calls}`); }, { attempts: 3, ...noSleep }))
      .rejects.toThrow('fail 3');
    expect(calls).toBe(3);
  });

  test('non-retryable errors abort immediately', async () => {
    let calls = 0;
    const err = Object.assign(new Error('forbidden'), { status: 403 });
    await expect(withRetry(async () => { calls++; throw err; }, {
      attempts: 5, shouldRetry: retryableHttp, ...noSleep,
    })).rejects.toThrow('forbidden');
    expect(calls).toBe(1);
  });

  test('backoff grows exponentially (capped) with jitter', async () => {
    const delays = [];
    await expect(withRetry(async () => { throw new Error('x'); }, {
      attempts: 4, baseMs: 100, maxMs: 350,
      sleep: async (ms) => delays.push(ms),
      rand: () => 1, // deterministic upper bound
    })).rejects.toThrow();
    expect(delays).toEqual([100, 200, 350]); // 100, 200, min(400,350)
  });
});

describe('retryableHttp policy', () => {
  test('network errors and 5xx/429 retry; other 4xx do not', () => {
    expect(retryableHttp(new Error('ECONNREFUSED'))).toBe(true);
    expect(retryableHttp(Object.assign(new Error(), { status: 500 }))).toBe(true);
    expect(retryableHttp(Object.assign(new Error(), { status: 429 }))).toBe(true);
    expect(retryableHttp(Object.assign(new Error(), { status: 404 }))).toBe(false);
    expect(retryableHttp(Object.assign(new Error(), { status: 401 }))).toBe(false);
  });
});
