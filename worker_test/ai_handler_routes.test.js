// Exercises the modular AI route handlers with local AI/fetch doubles.  These
// tests cover response contracts, fallback behavior, and prompt inputs without
// ever sending alert context to an external provider.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

const getFirebaseToken = jest.fn();
jest.unstable_mockModule('../worker/auth.js', () => ({ getFirebaseToken }));

const { _runLlama, handleAiProxy, handleAiSuggest } = await import('../worker/ai_suggest.js');
const { handleAutoFix, handleAutoFixFull } = await import('../worker/auto_fix.js');
const realFetch = globalThis.fetch;

function jsonRequest(path, body) {
  return new Request(`https://worker.example${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

function response(value = {}, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

afterEach(() => {
  globalThis.fetch = realFetch;
  getFirebaseToken.mockReset();
});

describe('_runLlama and /ai-proxy', () => {
  test('does not call a model when no binding exists, and handles model failures', async () => {
    await expect(_runLlama('hello', {})).resolves.toBeNull();
    await expect(_runLlama('hello', { AI: { run: async () => { throw new Error('unavailable'); } } })).resolves.toBeNull();
  });

  test('returns a trimmed model response and a stable fallback for malformed input', async () => {
    const ai = { run: jest.fn(async () => ({ response: '  Suggested action  ' })) };
    const ok = await handleAiProxy(jsonRequest('/ai-proxy', { prompt: 'Review this alert' }), { AI: ai });
    expect(ok.status).toBe(200);
    await expect(ok.json()).resolves.toEqual({ suggestion: 'Suggested action' });
    expect(ai.run).toHaveBeenCalledWith('@cf/meta/llama-3.2-3b-instruct', expect.objectContaining({
      messages: [{ role: 'user', content: 'Review this alert' }],
    }));

    const malformed = await handleAiProxy(jsonRequest('/ai-proxy', '{not json'), {});
    expect(malformed.status).toBe(200);
    expect((await malformed.json()).suggestion).toBeTruthy();
  });
});

describe('/ai-suggest', () => {
  test('validates the minimum plant context', async () => {
    const res = await handleAiSuggest(jsonRequest('/ai-suggest', { type: 'maintenance' }), {});
    expect(res.status).toBe(400);
    expect((await res.json()).suggestion).toBeTruthy();
  });

  test('feeds matching resolved history to the model and returns its answer', async () => {
    getFirebaseToken.mockResolvedValue('firebase-token');
    globalThis.fetch = jest.fn(async (url) => {
      expect(String(url)).toContain('alerts.json?auth=firebase-token');
      return response({
        matching: {
          status: 'validee', type: 'maintenance', convoyeur: 2, poste: 4,
          resolutionReason: 'Inspect the belt tension.', resolvedAt: '2026-07-19T12:00:00Z',
        },
        wrongStatus: { status: 'en_cours', type: 'maintenance', convoyeur: 2, poste: 4, resolutionReason: 'ignore' },
      });
    });
    const ai = { run: jest.fn(async (_, request) => {
      expect(request.messages[0].content).toContain('Inspect the belt tension.');
      expect(request.messages[0].content).toContain('Factory: Plant A');
      return { response: '- Isolate the belt\n- Inspect tension' };
    }) };

    const res = await handleAiSuggest(jsonRequest('/ai-suggest', {
      type: 'maintenance', usine: 'Plant A', convoyeur: 2, poste: 4, description: 'High vibration',
    }), { FB_DB_URL: 'https://db.example/', AI: ai });
    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ suggestion: '- Isolate the belt\n- Inspect tension' });
  });

  test('keeps the response contract when history lookup fails or model has no answer', async () => {
    getFirebaseToken.mockRejectedValue(new Error('auth unavailable'));
    const res = await handleAiSuggest(jsonRequest('/ai-suggest', {
      type: 'quality', usine: 'Plant A', convoyeur: 1, poste: 1, description: 'Defect',
    }), { FB_DB_URL: 'https://db.example/', AI: { run: async () => ({ response: '' }) } });
    expect(res.status).toBe(200);
    expect((await res.json()).suggestion).toBeTruthy();
  });
});

describe('auto-fix route contracts', () => {
  test('returns a model-proposed source patch', async () => {
    const res = await handleAutoFix(jsonRequest('/auto-fix', {
      code: 'Widget build() => ;', errors: 'Expected an expression.',
    }), { AI: { run: async () => ({ response: 'Widget build() => const SizedBox();' }) } });
    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ fixedCode: 'Widget build() => const SizedBox();' });
  });

  test('parses only a JSON array from full-project fixes and rejects non-array model output', async () => {
    const good = await handleAutoFixFull(jsonRequest('/auto-fix-full', {
      files: [{ path: 'lib/a.dart', content: 'broken' }], errors: 'error',
    }), { AI: { run: async () => ({ response: '[{"path":"lib/a.dart","content":"fixed"}]' }) } });
    await expect(good.json()).resolves.toEqual({ fixedFiles: [{ path: 'lib/a.dart', content: 'fixed' }] });

    const invalid = await handleAutoFixFull(jsonRequest('/auto-fix-full', { files: 'not an array' }), {
      AI: { run: async () => ({ response: '{"path":"not-an-array"}' }) },
    });
    await expect(invalid.json()).resolves.toEqual({ fixedFiles: [] });
  });

  test('returns explicit error fields for malformed JSON bodies', async () => {
    const fix = await handleAutoFix(jsonRequest('/auto-fix', '{bad'), {});
    expect(fix.status).toBe(500);
    expect((await fix.json()).fixedCode).toBe('');

    const full = await handleAutoFixFull(jsonRequest('/auto-fix-full', '{bad'), {});
    expect(full.status).toBe(500);
    expect((await full.json()).fixedFiles).toEqual([]);
  });
});
