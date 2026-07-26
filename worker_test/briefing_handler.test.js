// Route-handler coverage for the daily briefing path.  Dependencies are
// mocked at the module boundary so this tests request/response behavior and
// persistence without authenticating to Firebase or calling Workers AI.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

const loadCoreData = jest.fn();
jest.unstable_mockModule('../worker/load_core.js', () => ({ loadCoreData }));

const { handleBriefing } = await import('../worker/briefing.js');
const realFetch = globalThis.fetch;

function response(value = {}, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

const core = {
  token: 'firebase-token',
  alertsMap: {
    solved: {
      type: 'maintenance', usine: 'Plant A', status: 'validee', isCritical: true,
      elapsedTime: 12, timestamp: new Date().toISOString(), aiAssigned: true,
    },
    pending: { type: 'quality', usine: 'Plant A', status: 'disponible', timestamp: new Date().toISOString() },
  },
  usersMap: { sup: { fullName: 'Amina Operator', role: 'supervisor' } },
};

afterEach(() => {
  globalThis.fetch = realFetch;
  loadCoreData.mockReset();
});

describe('handleBriefing', () => {
  test('returns today\'s cached global briefing without generating a duplicate', async () => {
    loadCoreData.mockResolvedValue(core);
    const today = new Date().toISOString().slice(0, 10);
    globalThis.fetch = jest.fn(async (url) => {
      expect(String(url)).toContain('ai_briefing/latest.json?auth=firebase-token');
      return response({ date: today, summary: 'Already prepared.' });
    });

    const res = await handleBriefing(new Request('https://worker.example/briefing'), { FB_DB_URL: 'https://db.example/' });
    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ date: today, summary: 'Already prepared.' });
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
  });

  test('builds a factory-scoped briefing, consumes predictive context, and persists latest plus history', async () => {
    loadCoreData.mockResolvedValue(core);
    const writes = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      if (u.includes('ai_predictions/performance/latest')) {
        return response({ averageAccuracy: 0.88, totalSnapshots: 7 });
      }
      if (u.includes('ai_predictions/latest')) {
        return response({ predictions: [
          { usine: 'Plant A', type: 'maintenance', convoyeur: 'L-2', confidence: 91 },
        ] });
      }
      if (init.method === 'PUT') {
        writes.push({ url: u, body: JSON.parse(init.body) });
        return response({});
      }
      throw new Error(`Unexpected fetch ${u}`);
    });
    const ai = { run: jest.fn(async (_, request) => {
      expect(request.messages[0].content).toContain('Plant scope: Plant A');
      expect(request.messages[0].content).toContain('88%');
      return { response: 'Good morning. Plant A is ready.' };
    }) };

    const res = await handleBriefing(
      new Request('https://worker.example/briefing?force=1&factory=Plant%20A'),
      { FB_DB_URL: 'https://db.example/', AI: ai },
    );
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({
      summary: 'Good morning. Plant A is ready.',
      factoryScope: 'Plant A',
      accuracyPct: 88,
      predictiveInsight: { type: 'maintenance', convoyeur: 'L-2', confidence: 91 },
    });
    expect(writes).toHaveLength(2);
    expect(writes[0].url).toContain('ai_briefing/factory/plant_a/latest.json');
    expect(writes[1].url).toContain('ai_briefing/factory/plant_a/history/');
    expect(writes.every((write) => write.body.summary === body.summary)).toBe(true);
  });

  test('falls back cleanly when predictive data and Workers AI are unavailable', async () => {
    loadCoreData.mockResolvedValue(core);
    globalThis.fetch = jest.fn(async (_, init = {}) => {
      if (init.method === 'PUT') return response({});
      throw new Error('temporary database read failure');
    });

    const res = await handleBriefing(new Request('https://worker.example/briefing?force=1'), {
      FB_DB_URL: 'https://db.example/',
      AI: { run: jest.fn(async () => { throw new Error('model unavailable'); }) },
    });
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.model).toBe('fallback');
    expect(body.summary).toContain('Good morning');
    expect(body.accuracyPct).toBeNull();
  });

  test('renders an empty global briefing when no operational data is available', async () => {
    loadCoreData.mockResolvedValue({ token: 't', alertsMap: null, usersMap: null });
    const writes = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (init.method === 'PUT') {
        writes.push({ url: String(url), body: JSON.parse(init.body) });
        return response({});
      }
      // A non-OK predictive read is intentionally non-fatal.
      return response({}, 503);
    });

    const res = await handleBriefing(new Request('https://worker.example/briefing?force=1'), {
      FB_DB_URL: 'https://db.example/',
    });
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({
      model: 'fallback', topType: null, topFactory: null, topSupervisor: null,
      factoryScope: null, accuracyPct: null, predictiveInsight: null, resolutionRate: 0,
    });
    expect(writes).toHaveLength(2);
  });

  test('preserves sparse prediction fields and permits an empty model response', async () => {
    const now = new Date().toISOString();
    loadCoreData.mockResolvedValue({
      token: 't',
      alertsMap: {
        solved: {
          type: 'quality', usine: 'Plant B', status: 'validee', elapsedTime: 4,
          timestamp: now, superviseurId: 'sup',
        },
      },
      usersMap: { sup: { firstName: 'Meriem', lastName: 'Lead' } },
    });
    const prompts = [];
    globalThis.fetch = jest.fn(async (_, init = {}) => {
      if (init.method === 'PUT') return response({});
      // Accuracy is structurally present but not usable; the prediction itself
      // has no type/line/confidence and must not be invented into the prompt.
      if (prompts.length++ === 0) return response({ averageAccuracy: 0.9, totalSnapshots: 0 });
      return response({ predictions: [{ usine: 'Plant B' }] });
    });
    const res = await handleBriefing(new Request('https://worker.example/briefing?force=1'), {
      FB_DB_URL: 'https://db.example/',
      AI: { run: jest.fn(async (_, request) => {
        expect(request.messages[0].content).toContain('Top supervisor this week: Meriem Lead');
        expect(request.messages[0].content).toContain('Do not mention any AI prediction');
        return { response: '' };
      }) },
    });
    const body = await res.json();
    expect(body).toMatchObject({
      model: 'fallback',
      predictiveInsight: { type: null, convoyeur: null, confidence: null },
      topSupervisor: { name: 'Meriem Lead', count: 1, topType: 'quality' },
    });
  });

  test('returns a safe error response when core loading fails', async () => {
    loadCoreData.mockRejectedValue(new Error('credentials unavailable'));
    const res = await handleBriefing(new Request('https://worker.example/briefing'), { FB_DB_URL: 'https://db.example/' });
    expect(res.status).toBe(500);
    await expect(res.json()).resolves.toEqual({ error: 'credentials unavailable' });
  });
});
