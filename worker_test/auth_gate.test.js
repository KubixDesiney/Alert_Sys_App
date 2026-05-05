import { describe, expect, jest, test } from '@jest/globals';
import worker from '../cloudflare_worker.js';

const ctx = { waitUntil: () => {} };

describe('worker auth gate', () => {
  test('allows notify endpoint without shared secret', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => {});
    const response = await worker.fetch(
      new Request('https://worker.test/notify', { method: 'POST' }),
      {},
      ctx,
    );

    expect(response.status).toBe(200);
  });

  test('works even when shared secret is not configured', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => {});
    const response = await worker.fetch(
      new Request('https://worker.test/notify', {
        method: 'POST',
      }),
      {},
      ctx,
    );

    expect(response.status).toBe(200);
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
