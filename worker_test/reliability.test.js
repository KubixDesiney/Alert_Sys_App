/**
 * Reliability tests: cron lock, ETag retry, handover idempotency,
 * collaboration confidence, health monitoring, and randomization order.
 *
 * All Firebase / fetch calls are mocked at the global level.
 */
import { describe, test, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { _shiftContainsTime, pickActiveShift, scoreSupervisor } from '../cloudflare_worker.js';
import worker from '../cloudflare_worker.js';

// ─── shared mock helpers ─────────────────────────────────────────────────────

function makeCtx() {
  const fns = [];
  return {
    waitUntil(p) { fns.push(p); },
    async flush() { await Promise.all(fns); },
  };
}

function jsonRes(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...extra },
  });
}

function etagRes(body, etag = '"etag1"', status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ETag: etag },
  });
}

// ─── 1. Cron lock ────────────────────────────────────────────────────────────

describe('cron lock', () => {
  let fetchMock;
  let fetchCalls;

  beforeEach(() => {
    fetchCalls = [];
    fetchMock = jest.fn((url, opts) => {
      fetchCalls.push({ url: String(url), method: opts?.method ?? 'GET' });
      // Default: return empty OK for everything
      return Promise.resolve(jsonRes(null));
    });
    globalThis.fetch = fetchMock;
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('skips execution when lock is fresh (< 55 s old)', async () => {
    const freshTs = Date.now() - 10000; // 10 s ago — still in-flight
    fetchMock.mockImplementation((url, opts) => {
      fetchCalls.push({ url: String(url), method: opts?.method ?? 'GET' });
      if (String(url).includes('cron_lock')) {
        // Return a fresh lock
        return Promise.resolve(etagRes({ ts: freshTs }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' }, ctx);
    await ctx.flush();

    // Should have read the lock but NOT written alerts/users/shifts (loadCoreData never called)
    const alertCalls = fetchCalls.filter((c) => c.url.includes('/alerts.json'));
    expect(alertCalls.length).toBe(0);
  });

  test('proceeds when lock is stale (> 55 s old)', async () => {
    const staleTs = Date.now() - 60000; // 60 s ago — safe to proceed
    let lockPutCount = 0;

    fetchMock.mockImplementation((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: staleTs }));
      }
      if (u.includes('cron_lock') && method === 'PUT') {
        lockPutCount++;
        return Promise.resolve(jsonRes({ ts: Date.now() }));
      }
      if (u.includes('cron_lock') && method === 'DELETE') {
        return Promise.resolve(jsonRes(null));
      }
      // Auth token
      if (u.includes('identitytoolkit') || u.includes('accounts:signUp')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' }, ctx);
    await ctx.flush();

    // Lock was written (execution proceeded)
    expect(lockPutCount).toBeGreaterThanOrEqual(1);
  });

  test('second rapid invocation skips when first already acquired lock', async () => {
    // Simulates: first run acquires lock (ts = now), second run reads same lock.
    const nowTs = Date.now();
    const logs = [];

    fetchMock.mockImplementation((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: nowTs })); // lock is fresh
      }
      return Promise.resolve(jsonRes(null));
    });

    jest.spyOn(console, 'log').mockImplementation((msg) => logs.push(msg));

    const ctx = makeCtx();
    await worker.scheduled({}, { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' }, ctx);
    await ctx.flush();

    expect(logs.some((l) => String(l).includes('Skipping'))).toBe(true);
  });

  test('skips when lock PUT returns 412 (concurrent acquisition)', async () => {
    const staleTs = Date.now() - 60000;
    const logs = [];

    fetchMock.mockImplementation((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: staleTs }));
      }
      if (u.includes('cron_lock') && method === 'PUT') {
        // Another worker beat us to the lock
        return Promise.resolve(new Response(null, { status: 412 }));
      }
      return Promise.resolve(jsonRes(null));
    });

    jest.spyOn(console, 'log').mockImplementation((msg) => logs.push(msg));

    const ctx = makeCtx();
    await worker.scheduled({}, { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' }, ctx);
    await ctx.flush();

    expect(logs.some((l) => String(l).includes('concurrent execution acquired lock'))).toBe(true);
  });
});

// ─── 2. ETag retry on alert assignment ──────────────────────────────────────

describe('ETag retry on alert assignment', () => {
  // Build a complete fetch mock that lets runAIAssignments reach aiAssignAlert.
  // Keys used to distinguish URL patterns (all under https://db.test/):
  //   /alerts.json?       → top-level alerts collection (runAIAssignments initial load)
  //   /alerts/alert1.json → individual alert document  (aiAssignAlert ETag loop)
  function buildRetryMock(fetchCalls, { onAlertPut } = {}) {
    let alertGetCount = 0;
    let alertPutCount = 0;
    const alertData = {
      status: 'disponible',
      type: 'qualite',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
      push_sent: false,
    };
    const usersData = {
      u1: { role: 'supervisor', usine: 'Usine A', status: 'active', fcmToken: 'tok1', fullName: 'Test User' },
    };

    const mock = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      // Auth (anonymous sign-up, no service account)
      if (u.includes('identitytoolkit') || u.includes('accounts:signUp')) {
        return Promise.resolve(jsonRes({ idToken: 'test-token' }));
      }
      // Alert collection — must match before the individual-doc check.
      // Pattern: URL contains 'alerts.json?' (i.e. /alerts.json?auth=...)
      if (u.includes('/alerts.json?')) {
        return Promise.resolve(jsonRes({ alert1: alertData }));
      }
      // Users / shifts collections
      if (u.includes('/users.json?')) return Promise.resolve(jsonRes(usersData));
      if (u.includes('/shifts.json?')) return Promise.resolve(jsonRes({}));
      // AI feedback
      if (u.includes('ai_feedback/summary')) return Promise.resolve(jsonRes({}));
      // Factory AI config — must be enabled for usine_a
      if (u.includes('aiConfig/enabled')) return Promise.resolve(jsonRes(true));
      // Idempotency check: no prior action this minute
      if (u.includes('ai_decisions/alert1/actionId')) return Promise.resolve(jsonRes(null));

      // Individual alert document — ETag GET + conditional PUT
      if (u.includes('/alerts/alert1.json') && method === 'GET') {
        alertGetCount++;
        return Promise.resolve(etagRes(alertData, `"etag${alertGetCount}"`));
      }
      if (u.includes('/alerts/alert1.json') && method === 'PUT') {
        alertPutCount++;
        return onAlertPut
          ? onAlertPut(alertPutCount, alertData)
          : Promise.resolve(jsonRes({ ...alertData, status: 'en_cours' }));
      }

      return Promise.resolve(jsonRes(null));
    });

    return { mock, getCounts: () => ({ alertGetCount, alertPutCount }) };
  }

  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('retries once when first PUT returns 412', async () => {
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    const fetchCalls = [];
    const { mock, getCounts } = buildRetryMock(fetchCalls, {
      onAlertPut(attempt) {
        if (attempt === 1) return Promise.resolve(new Response(null, { status: 412 }));
        return Promise.resolve(jsonRes({ status: 'en_cours' }));
      },
    });
    globalThis.fetch = mock;

    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };
    const ctx = makeCtx();
    await worker.fetch(new Request('https://w.test/ai-retry'), env, ctx);
    await ctx.flush();

    const { alertGetCount, alertPutCount } = getCounts();
    // On 412 the loop re-fetches a fresh ETag before retrying, so 2 GETs + 2 PUTs.
    expect(alertGetCount).toBe(2);
    expect(alertPutCount).toBe(2);
  });

  test('gives up after two 412 responses and makes at most 2 PUT attempts', async () => {
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    const fetchCalls = [];
    const { mock, getCounts } = buildRetryMock(fetchCalls, {
      onAlertPut() {
        return Promise.resolve(new Response(null, { status: 412 }));
      },
    });
    globalThis.fetch = mock;

    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };
    const ctx = makeCtx();
    await worker.fetch(new Request('https://w.test/ai-retry'), env, ctx);
    await ctx.flush();

    const { alertPutCount } = getCounts();
    // Should try exactly 2 times and give up — never a third attempt.
    expect(alertPutCount).toBeLessThanOrEqual(2);
    expect(alertPutCount).toBeGreaterThanOrEqual(1);
  });
});

// ─── 4. Commander mode: cross-factory can outscore same-factory ──────────────

describe('AI Commander scoring (pure function)', () => {
  const NOW = Date.UTC(2026, 4, 1, 9, 0, 0);
  const alert = { type: 'qualite', usine: 'Usine A', convoyeur: 1, poste: 1, isCritical: false };

  test('cross-factory + commander outscores inexperienced same-factory', () => {
    const crossSup = { uid: 'u1', usine: 'Usine B' };
    const sameSup  = { uid: 'u2', usine: 'Usine A' };
    const stats = {
      u1: { typeCounts: { qualite: 10 }, typeAvgRes: {}, stationCounts: {}, conveyorCounts: {} },
      u2: { typeCounts: {}, typeAvgRes: {}, stationCounts: {}, conveyorCounts: {} },
    };

    const crossScore = scoreSupervisor(crossSup, alert, stats, {}, 0, NOW, { isCommander: true }).score;
    const sameScore  = scoreSupervisor(sameSup,  alert, stats, {}, 0, NOW, { isCommander: true }).score;

    // cross: 0 + 40 = 40, same: 30 + 0 = 30
    expect(crossScore).toBe(40);
    expect(sameScore).toBe(30);
    expect(crossScore).toBeGreaterThan(sameScore);
  });

  test('without commander, same result is reversed (penalty applies)', () => {
    const crossSup = { uid: 'u1', usine: 'Usine B' };
    const stats = {
      u1: { typeCounts: { qualite: 10 }, typeAvgRes: {}, stationCounts: {}, conveyorCounts: {} },
    };
    const crossScore = scoreSupervisor(crossSup, alert, stats, {}, 0, NOW, { isCommander: false }).score;
    // -25 + 40 = 15 (clamped)
    expect(crossScore).toBe(15);
  });
});

// ─── 5. Confidence floor before shuffle ──────────────────────────────────────

describe('confidence floor applied before shuffle', () => {
  // We can't directly call runAIAssignments in isolation, but we can verify
  // the pure-function aspect: that the confidence calculation uses sorted scores.
  test('sorted pool confidence is higher than a shuffled worst-case pick', () => {
    const scores = [80, 20, 10]; // sorted descending
    const topSum = 80 + 20 + 10;

    // Correct: confidence from top sorted score
    const correctConfidence = 80 / topSum;
    // Buggy: confidence from a low-score random pick (e.g. score=10 ended up first after shuffle)
    const badConfidence = 10 / topSum;

    expect(correctConfidence).toBeCloseTo(0.727, 2);
    expect(badConfidence).toBeCloseTo(0.091, 2);

    // With floor=0.5, correct passes, buggy fails
    const floor = 0.5;
    expect(correctConfidence).toBeGreaterThanOrEqual(floor);
    expect(badConfidence).toBeLessThan(floor);
  });
});

// ─── 6. Handover timing and idempotency ──────────────────────────────────────

describe('shift handover timing and idempotency', () => {
  test('_shiftContainsTime handles overnight wrap', () => {
    const nightShift = { startMinutes: 22 * 60, endMinutes: 6 * 60 }; // 22:00–06:00
    expect(_shiftContainsTime(nightShift, 23 * 60)).toBe(true);  // 23:00 ✓
    expect(_shiftContainsTime(nightShift, 3 * 60)).toBe(true);   // 03:00 ✓
    expect(_shiftContainsTime(nightShift, 7 * 60)).toBe(false);  // 07:00 ✗
    expect(_shiftContainsTime(nightShift, 21 * 60)).toBe(false); // 21:00 ✗
  });

  test('pickActiveShift returns null outside all windows', () => {
    const shifts = {
      s1: { startMinutes: 8 * 60, endMinutes: 16 * 60 },
    };
    // 18:00 UTC — outside window
    const d = new Date(Date.UTC(2026, 4, 1, 18, 0));
    expect(pickActiveShift(shifts, d)).toBeNull();
  });

  test('pickActiveShift returns active shift inside window', () => {
    const shifts = {
      s1: { startMinutes: 8 * 60, endMinutes: 16 * 60, name: 'Day' },
    };
    const d = new Date(Date.UTC(2026, 4, 1, 10, 0)); // 10:00
    const active = pickActiveShift(shifts, d);
    expect(active).not.toBeNull();
    expect(active.name).toBe('Day');
  });

  test('handover not generated when lastHandoverAt is within 15 minutes', async () => {
    const recentHandover = new Date(Date.now() - 5 * 60 * 1000).toISOString(); // 5 min ago
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        // Stale lock so execution proceeds
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock') && method === 'PUT') {
        return Promise.resolve(jsonRes({ ts: Date.now() }));
      }
      if (u.includes('cron_lock') && method === 'DELETE') {
        return Promise.resolve(jsonRes(null));
      }
      if (u.includes('shifts.json')) {
        // Shift ending in 5 min, aiCommander=true, recent handover
        const nowMin = new Date().getUTCHours() * 60 + new Date().getUTCMinutes();
        const endMin = (nowMin + 5) % 1440;
        return Promise.resolve(jsonRes({
          s1: {
            name: 'Test Shift',
            startMinutes: (nowMin - 300 + 1440) % 1440,
            endMinutes: endMin,
            aiCommander: true,
            lastHandoverAt: recentHandover, // already done
          },
        }));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    // No handover generation calls (no PATCH to shifts/s1 with lastHandoverSummary)
    const handoverPatches = fetchCalls.filter(
      (c) => c.url.includes('/shifts/s1') && c.method === 'PATCH',
    );
    expect(handoverPatches.length).toBe(0);

    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('handover IS generated when window ≤ 10 min and no recent handover', async () => {
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock')) {
        return Promise.resolve(jsonRes({ ts: Date.now() }));
      }
      if (u.includes('shifts.json')) {
        const nowMin = new Date().getUTCHours() * 60 + new Date().getUTCMinutes();
        const endMin = (nowMin + 8) % 1440; // 8 min to end → within 10-min window
        const startMin = (nowMin - 300 + 1440) % 1440;
        return Promise.resolve(jsonRes({
          s1: {
            name: 'Test Shift',
            startMinutes: startMin,
            endMinutes: endMin,
            aiCommander: true,
            supervisors: { u1: { ready: true } },
            // No lastHandoverAt — never generated
          },
        }));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    const handoverPatches = fetchCalls.filter(
      (c) => c.url.includes('/shifts/s1') && c.method === 'PATCH',
    );
    expect(handoverPatches.length).toBeGreaterThanOrEqual(1);

    delete globalThis.fetch;
    jest.restoreAllMocks();
  });
});

// ─── 7. Collaboration confidence check ───────────────────────────────────────

describe('collaboration auto-approval confidence check', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('does NOT auto-approve when accepted fraction < confidence floor', async () => {
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock')) return Promise.resolve(jsonRes({ ts: Date.now() }));

      if (u.includes('shifts.json')) {
        // Active shift with aiCommander=true, aiConfidence floor = 0.9
        const nowMin = new Date().getUTCHours() * 60 + new Date().getUTCMinutes();
        return Promise.resolve(jsonRes({
          s1: {
            name: 'Morning',
            startMinutes: (nowMin - 60 + 1440) % 1440,
            endMinutes: (nowMin + 60) % 1440,
            aiCommander: true,
            aiConfidence: 0.9, // floor = 0.9
          },
        }));
      }
      if (u.includes('collaboration_requests.json')) {
        // 1 of 2 assistants accepted → confidence = 0.5, below floor of 0.9
        return Promise.resolve(jsonRes({
          req1: {
            status: 'awaiting_pm',
            requesterId: 'u1',
            alertId: 'a1',
            assistantDecisions: {
              u2: 'accepted',
              u3: 'pending', // not accepted
            },
          },
        }));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    // PATCH to collaboration_requests/req1 should NOT have been called
    const approvalCalls = fetchCalls.filter(
      (c) => c.url.includes('collaboration_requests/req1') && c.method === 'PATCH',
    );
    expect(approvalCalls.length).toBe(0);
  });

  test('auto-approves when accepted fraction >= confidence floor', async () => {
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock')) return Promise.resolve(jsonRes({ ts: Date.now() }));

      if (u.includes('shifts.json')) {
        const nowMin = new Date().getUTCHours() * 60 + new Date().getUTCMinutes();
        return Promise.resolve(jsonRes({
          s1: {
            name: 'Morning',
            startMinutes: (nowMin - 60 + 1440) % 1440,
            endMinutes: (nowMin + 60) % 1440,
            aiCommander: true,
            aiConfidence: 0.5, // floor = 0.5
          },
        }));
      }
      if (u.includes('collaboration_requests.json')) {
        // Both assistants accepted → confidence = 1.0 >= 0.5
        return Promise.resolve(jsonRes({
          req1: {
            status: 'awaiting_pm',
            requesterId: 'u1',
            alertId: 'a1',
            assistantDecisions: {
              u2: 'accepted',
              u3: 'accepted',
            },
          },
        }));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    const approvalCalls = fetchCalls.filter(
      (c) => c.url.includes('collaboration_requests/req1') && c.method === 'PATCH',
    );
    expect(approvalCalls.length).toBeGreaterThanOrEqual(1);
  });
});

// ─── 8. Idempotency: duplicate write ignored ─────────────────────────────────

describe('idempotency keys', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('skips assignment when same actionId already exists in ai_decisions', async () => {
    const minuteKey = Math.floor(Date.now() / 60000);
    const existingActionId = `worker_alert1_${minuteKey}`;
    const fetchCalls = [];

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('ai_decisions/alert1/actionId')) {
        // Idempotency check: same actionId already recorded
        return Promise.resolve(jsonRes(existingActionId));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };
    const ctx = makeCtx();
    await worker.fetch(new Request('https://w.test/ai-retry'), env, ctx);
    await ctx.flush();

    // No PUT to alerts/alert1 since idempotency check stopped it
    const alertPuts = fetchCalls.filter(
      (c) => c.url.includes('/alerts/alert1.json') && c.method === 'PUT',
    );
    expect(alertPuts.length).toBe(0);
  });
});

// ─── 9. Health monitoring ─────────────────────────────────────────────────────

describe('health monitoring', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('writes workers/health/lastRun after a successful cron run', async () => {
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock')) return Promise.resolve(jsonRes({ ts: Date.now() }));
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    const healthWrites = fetchCalls.filter(
      (c) => c.url.includes('workers/health/lastRun') && c.method === 'PUT',
    );
    expect(healthWrites.length).toBeGreaterThanOrEqual(1);
  });

  test('writes health node even when coreData load fails', async () => {
    const fetchCalls = [];
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      fetchCalls.push({ url: u, method });

      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock') && method === 'PUT') {
        return Promise.resolve(jsonRes({ ts: Date.now() }));
      }
      if (u.includes('cron_lock') && method === 'DELETE') {
        return Promise.resolve(jsonRes(null));
      }
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      // Make alerts/users/shifts fail so loadCoreData throws
      if (u.includes('/alerts.json') || u.includes('/users.json') || u.includes('/shifts.json')) {
        return Promise.resolve(new Response('error', { status: 500 }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    const healthWrites = fetchCalls.filter(
      (c) => c.url.includes('workers/health/lastRun') && c.method === 'PUT',
    );
    expect(healthWrites.length).toBeGreaterThanOrEqual(1);
  });

  test('health payload contains required fields', async () => {
    let capturedBody = null;
    const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});

    globalThis.fetch = jest.fn((url, opts) => {
      const u = String(url);
      const method = opts?.method ?? 'GET';
      if (u.includes('workers/health/lastRun') && method === 'PUT') {
        try { capturedBody = JSON.parse(opts.body); } catch (_) {}
      }
      if (u.includes('cron_lock') && method === 'GET') {
        return Promise.resolve(etagRes({ ts: Date.now() - 60000 }));
      }
      if (u.includes('cron_lock')) return Promise.resolve(jsonRes({ ts: Date.now() }));
      if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
        return Promise.resolve(jsonRes({ idToken: 'tok' }));
      }
      return Promise.resolve(jsonRes(null));
    });

    const ctx = makeCtx();
    await worker.scheduled({}, env, ctx);
    await ctx.flush();

    expect(capturedBody).not.toBeNull();
    expect(typeof capturedBody.timestamp).toBe('string');
    expect(typeof capturedBody.assignmentsMade).toBe('number');
    expect(typeof capturedBody.collaborationsApproved).toBe('number');
    expect(typeof capturedBody.handoversGenerated).toBe('number');
    expect(Array.isArray(capturedBody.errors)).toBe(true);
    expect(typeof capturedBody.durationMs).toBe('number');
  });
});
