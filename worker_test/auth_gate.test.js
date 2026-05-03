import { describe, expect, jest, test } from '@jest/globals';
import worker from '../cloudflare_worker.js';

const ctx = { waitUntil: () => {} };

describe('worker auth gate', () => {
  test('rejects sensitive endpoints without the shared secret', async () => {
    const response = await worker.fetch(
      new Request('https://worker.test/notify', { method: 'POST' }),
      { WORKER_SHARED_SECRET: 'ci-secret' },
      ctx,
    );

    expect(response.status).toBe(401);
  });

  test('fails closed when shared secret is not configured', async () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    const response = await worker.fetch(
      new Request('https://worker.test/notify', {
        method: 'POST',
        headers: { 'X-AlertSys-Worker-Secret': 'ci-secret' },
      }),
      {},
      ctx,
    );

    expect(response.status).toBe(503);
    spy.mockRestore();
  });

  test('leaves the deprecated config endpoint public', async () => {
    const response = await worker.fetch(
      new Request('https://worker.test/config'),
      {},
      ctx,
    );

    expect(response.status).toBe(200);
  });
});
