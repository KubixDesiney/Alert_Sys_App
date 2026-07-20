// End-to-end request coverage for the modular suggested-assignee handler.
// Scoring itself remains real; only the Firebase loader is substituted.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

const loadCoreData = jest.fn();
jest.unstable_mockModule('../worker/load_core.js', () => ({ loadCoreData }));

const { handleSuggestAssignee } = await import('../worker/suggest_assignee.js');
const realFetch = globalThis.fetch;

function response(value = {}, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

afterEach(() => {
  globalThis.fetch = realFetch;
  loadCoreData.mockReset();
});

describe('handleSuggestAssignee', () => {
  test('rejects an absent alert id before accessing the database', async () => {
    const res = await handleSuggestAssignee(new Request('https://worker.example/suggest-assignee'), {});
    expect(res.status).toBe(400);
    await expect(res.json()).resolves.toEqual({ error: 'alertId required' });
    expect(loadCoreData).not.toHaveBeenCalled();
  });

  test('returns 404 for an alert that is not in the loaded core data', async () => {
    loadCoreData.mockResolvedValue({ token: 't', alertsMap: {}, usersMap: {} });
    const res = await handleSuggestAssignee(new Request('https://worker.example/suggest-assignee?alertId=missing'), {});
    expect(res.status).toBe(404);
    await expect(res.json()).resolves.toEqual({ error: 'alert not found' });
  });

  test('ranks eligible same-factory supervisors and reports confidence plus runners-up', async () => {
    const now = new Date().toISOString();
    loadCoreData.mockResolvedValue({
      token: 'firebase-token',
      alertsMap: {
        target: { usine: 'Plant A', type: 'maintenance', status: 'disponible', timestamp: now },
        done: { usine: 'Plant A', type: 'maintenance', status: 'validee', superviseurId: 'best', elapsedTime: 5, timestamp: now },
        busyAlert: { usine: 'Plant A', type: 'maintenance', status: 'en_cours', superviseurId: 'busy', timestamp: now },
      },
      usersMap: {
        best: { role: 'supervisor', usine: 'Plant A', fullName: 'Best Match', status: 'available', fcmToken: 'best-token' },
        busy: { role: 'supervisor', usine: 'Plant A', fullName: 'Busy Match', status: 'available', fcmToken: 'busy-token' },
        optout: { role: 'supervisor', usine: 'Plant A', fullName: 'Opt Out', aiOptOut: true },
        other: { role: 'supervisor', usine: 'Plant B', fullName: 'Other Plant' },
        admin: { role: 'admin', usine: 'Plant A', fullName: 'Admin' },
      },
    });
    globalThis.fetch = jest.fn(async (url) => {
      expect(String(url)).toContain('ai_feedback/summary.json?auth=firebase-token');
      return response({ best: { acceptanceRate: 1, averageResolutionMinutes: 5 } });
    });

    const res = await handleSuggestAssignee(new Request('https://worker.example/suggest-assignee?alertId=target'), {
      FB_DB_URL: 'https://db.example/',
    });
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({
      alertId: 'target',
      best: { uid: 'best', name: 'Best Match', busy: false },
      candidateCount: 2,
    });
    expect(body.confidence).toBeGreaterThan(0);
    expect(body.confidencePct).toBeGreaterThan(0);
    expect(body.runners).toHaveLength(1);
    expect(body.runners[0]).toMatchObject({ uid: 'busy', busy: true });
  });

  test('continues with an empty feedback summary when that optional read fails', async () => {
    loadCoreData.mockResolvedValue({
      token: 't',
      alertsMap: { a1: { usine: 'Plant A', type: 'maintenance', status: 'disponible' } },
      usersMap: {},
    });
    globalThis.fetch = jest.fn(async () => { throw new Error('feedback unavailable'); });

    const res = await handleSuggestAssignee(new Request('https://worker.example/suggest-assignee?alertId=a1'), {
      FB_DB_URL: 'https://db.example/',
    });
    await expect(res.json()).resolves.toMatchObject({ best: null, confidence: 0, candidateCount: 0 });
  });

  test('returns a safe 500 payload when core loading throws', async () => {
    loadCoreData.mockRejectedValue(new Error('Firebase down'));
    const res = await handleSuggestAssignee(new Request('https://worker.example/suggest-assignee?alertId=a1'), {});
    expect(res.status).toBe(500);
    await expect(res.json()).resolves.toEqual({ error: 'Firebase down' });
  });
});
