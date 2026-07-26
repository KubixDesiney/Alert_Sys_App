// Exercises worker/escalation.js's checkEscalations directly: threshold
// resolution (per-type/default), unclaimed vs. claimed-too-long timing,
// the RTDB patch + aiHistory write, and the FCM fan-out (incl. notifying a
// busy claimant who wasn't in the broadcast list). No live network.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

jest.unstable_mockModule('../worker/fcm.js', () => ({
  getFcmRecipientsForFactory: jest.fn(),
  sendFcmDetailed: jest.fn(),
}));

const { getFcmRecipientsForFactory, sendFcmDetailed } = await import('../worker/fcm.js');
const { checkEscalations } = await import('../worker/escalation.js');

const realFetch = globalThis.fetch;
function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

afterEach(() => {
  globalThis.fetch = realFetch;
  getFcmRecipientsForFactory.mockReset();
  sendFcmDetailed.mockReset();
});

const env = { FB_DB_URL: 'https://db.example/' };

describe('checkEscalations', () => {
  test('does nothing when escalation_settings cannot be read', async () => {
    globalThis.fetch = jest.fn(async (url) => {
      if (String(url).includes('escalation_settings')) return new Response('no', { status: 500 });
      throw new Error('should not reach here');
    });
    await checkEscalations(env, { token: 't', alertsMap: { a: { status: 'disponible', timestamp: Date.now() } }, usersMap: {} });
    expect(getFcmRecipientsForFactory).not.toHaveBeenCalled();
  });

  test('does nothing when settings are empty/invalid', async () => {
    globalThis.fetch = jest.fn(async () => response(null));
    await checkEscalations(env, { token: 't', alertsMap: { a: { status: 'disponible', timestamp: Date.now() } }, usersMap: {} });
    expect(getFcmRecipientsForFactory).not.toHaveBeenCalled();
  });

  test('escalates an unclaimed alert past its type threshold, patches, logs, and notifies', async () => {
    const oldTs = Date.now() - 20 * 60 * 1000; // 20 minutes ago
    const alertsMap = {
      a1: { status: 'disponible', timestamp: oldTs, type: 'maintenance', usine: 'Plant A', description: 'Hot bearing', isEscalated: false },
    };
    const usersMap = { sup: { fcmToken: 'tok-1', role: 'supervisor' } };
    const patches = [];
    const posts = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      if (u.includes('escalation_settings')) return response({ maintenance: { unclaimedMinutes: 15 } });
      if (init.method === 'PATCH') { patches.push({ url: u, body: JSON.parse(init.body) }); return response({}); }
      if (init.method === 'POST') { posts.push({ url: u, body: JSON.parse(init.body) }); return response({}); }
      throw new Error(`unexpected ${u}`);
    });
    getFcmRecipientsForFactory.mockReturnValue([{ uid: 'sup', token: 'tok-1' }]);
    sendFcmDetailed.mockResolvedValue({ ok: true });

    await checkEscalations(env, { token: 't', alertsMap, usersMap });

    expect(patches[0].url).toContain('alerts/a1.json');
    expect(patches[0].body).toMatchObject({ isEscalated: true });
    expect(posts[0].url).toContain('alerts/a1/aiHistory.json');
    expect(posts[0].body.reason).toMatch(/Unclaimed for \d+ minutes/);
    expect(sendFcmDetailed).toHaveBeenCalledWith(
      'tok-1',
      expect.stringContaining('Alert Escalated'),
      expect.stringContaining('Hot bearing'),
      expect.objectContaining({ alertId: 'a1', escalated: 'true' }),
      env,
      expect.objectContaining({ uid: 'sup' }),
    );
  });

  test('falls back to the default threshold when no per-type entry exists', async () => {
    const alertsMap = { a1: { status: 'disponible', timestamp: Date.now() - 100 * 60000, type: 'unknown_type' } };
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (String(url).includes('escalation_settings')) return response({ default: { unclaimedMinutes: 5 } });
      return response({});
    });
    getFcmRecipientsForFactory.mockReturnValue([]);
    await checkEscalations(env, { token: 't', alertsMap, usersMap: {} });
    // No throw, and the patch endpoint was reached (escalation fired on default threshold).
    expect(globalThis.fetch).toHaveBeenCalledWith(expect.stringContaining('alerts/a1.json'), expect.objectContaining({ method: 'PATCH' }));
  });

  test('escalates a claimed-too-long alert and additionally notifies the claimant if not in the broadcast list', async () => {
    const takenAt = Date.now() - 60 * 60000; // claimed an hour ago
    const alertsMap = {
      a1: { status: 'en_cours', timestamp: takenAt, takenAtTimestamp: takenAt, type: 'quality', usine: 'Plant B', superviseurId: 'claimant', description: 'Defect' },
    };
    const usersMap = {
      claimant: { fcmToken: 'claimant-tok', role: 'supervisor' },
      other: { fcmToken: 'other-tok', role: 'supervisor' },
    };
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      if (u.includes('escalation_settings')) return response({ quality: { claimedMinutes: 30 } });
      return response({});
    });
    getFcmRecipientsForFactory.mockReturnValue([{ uid: 'other', token: 'other-tok' }]); // claimant not broadcast
    sendFcmDetailed.mockResolvedValue({ ok: true });

    await checkEscalations(env, { token: 't', alertsMap, usersMap });

    expect(sendFcmDetailed).toHaveBeenCalledTimes(2);
    const claimantCall = sendFcmDetailed.mock.calls.find((c) => c[0] === 'claimant-tok');
    expect(claimantCall).toBeTruthy();
  });

  test('skips alerts with no matching threshold, unparsable timestamps, or already escalated/terminal status', async () => {
    const alertsMap = {
      noThreshold: { status: 'disponible', timestamp: Date.now(), type: 'nope' },
      badTs: { status: 'disponible', timestamp: 'not-a-date', type: 'maintenance' },
      done: { status: 'validee', timestamp: Date.now(), type: 'maintenance', isEscalated: false },
      already: { status: 'disponible', timestamp: Date.now(), type: 'maintenance', isEscalated: true },
    };
    globalThis.fetch = jest.fn(async (url) => {
      if (String(url).includes('escalation_settings')) return response({ maintenance: { unclaimedMinutes: 999999 } });
      throw new Error('should not patch anything');
    });
    await checkEscalations(env, { token: 't', alertsMap, usersMap: {} });
    expect(getFcmRecipientsForFactory).not.toHaveBeenCalled();
  });

  test('a failed PATCH is logged and does not throw; loop continues to remaining alerts', async () => {
    const alertsMap = {
      willFail: { status: 'disponible', timestamp: Date.now() - 60 * 60000, type: 'maintenance', usine: 'X' },
      willWork: { status: 'disponible', timestamp: Date.now() - 60 * 60000, type: 'maintenance', usine: 'Y', description: 'd' },
    };
    let patchCount = 0;
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      if (u.includes('escalation_settings')) return response({ maintenance: { unclaimedMinutes: 1 } });
      if (init.method === 'PATCH') {
        patchCount++;
        return patchCount === 1 ? new Response('fail', { status: 500 }) : response({});
      }
      return response({});
    });
    getFcmRecipientsForFactory.mockReturnValue([]);
    await expect(checkEscalations(env, { token: 't', alertsMap, usersMap: {} })).resolves.toBeUndefined();
    expect(patchCount).toBe(2);
  });

  test('respects MAX_ESCALATION_CHECKS budget (stops after the cap)', async () => {
    const alertsMap = {};
    for (let i = 0; i < 10; i++) {
      alertsMap[`a${i}`] = { status: 'disponible', timestamp: Date.now() - 60 * 60000, type: 'maintenance', usine: 'Z' };
    }
    let patchCount = 0;
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (String(url).includes('escalation_settings')) return response({ maintenance: { unclaimedMinutes: 1 } });
      if (init.method === 'PATCH') patchCount++;
      return response({});
    });
    getFcmRecipientsForFactory.mockReturnValue([]);
    await checkEscalations(env, { token: 't', alertsMap, usersMap: {} });
    expect(patchCount).toBe(5); // MAX_ESCALATION_CHECKS
  });
});
