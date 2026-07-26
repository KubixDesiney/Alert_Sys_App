// Kubix Copilot upgrades: the per-reply feedback validator + /api/kubix-feedback
// route, the French copilot chrome, the /welcome onboarding page, and the chat
// analytics report helpers.
import { jest } from '@jest/globals';
import worker, {
  validateFeedbackRequest,
  copilotLang,
  COPILOT_I18N,
} from '../cloudflare_store_worker.js';
import {
  parseCsv,
  normalizeRow,
  sessionsPerDay,
  escalationRate,
  topQuestionWords,
  medianReplyLength,
  buildReport,
} from '../tool/kubix_chat_report.mjs';

describe('validateFeedbackRequest', () => {
  const base = () => ({ sessionId: 'abc-123.xyz_9', messageIndex: 3, verdict: 'up' });

  test('accepts a well-formed verdict', () => {
    const r = validateFeedbackRequest(base());
    expect(r.ok).toBe(true);
    expect(r.value).toEqual({ sessionId: 'abc-123.xyz_9', messageIndex: 3, verdict: 'up' });
    expect(validateFeedbackRequest({ ...base(), verdict: 'down' }).ok).toBe(true);
    expect(validateFeedbackRequest({ ...base(), messageIndex: 0 }).ok).toBe(true);
  });

  test('rejects non-objects, bad session ids, and out-of-range indexes', () => {
    expect(validateFeedbackRequest(null).ok).toBe(false);
    expect(validateFeedbackRequest('x').ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), sessionId: 'has space' }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), sessionId: '' }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), sessionId: 'a'.repeat(81) }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), messageIndex: -1 }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), messageIndex: 1000 }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), messageIndex: 1.5 }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), messageIndex: 'x' }).ok).toBe(false);
  });

  test('rejects any verdict other than up/down', () => {
    expect(validateFeedbackRequest({ ...base(), verdict: 'sideways' }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), verdict: 1 }).ok).toBe(false);
    expect(validateFeedbackRequest({ ...base(), verdict: undefined }).ok).toBe(false);
  });
});

describe('/api/kubix-feedback route', () => {
  const post = (body, env = {}) =>
    worker.fetch(
      new Request('https://sias-store.example/api/kubix-feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': `fb-${Math.random()}` },
        body: typeof body === 'string' ? body : JSON.stringify(body),
      }),
      env,
    );

  test('returns 400 on junk and 503 when unconfigured', async () => {
    expect((await post('{nope')).status).toBe(400);
    expect((await post({ sessionId: 'x y', messageIndex: 0, verdict: 'up' })).status).toBe(400);
    expect((await post({ sessionId: 'abc', messageIndex: 0, verdict: 'up' })).status).toBe(503);
  });

  test('forwards the verdict to the feedback webhook with the bearer', async () => {
    const realFetch = global.fetch;
    const calls = [];
    global.fetch = jest.fn(async (url, init) => {
      calls.push({ url, headers: init.headers, body: JSON.parse(init.body) });
      return new Response('{}', { status: 200 });
    });
    try {
      const res = await post(
        { sessionId: 'abc', messageIndex: 2, verdict: 'down' },
        { N8N_FEEDBACK_WEBHOOK_URL: 'https://n8n.example/webhook/kubix-feedback', N8N_WEBHOOK_AUTH: 'tok' },
      );
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ ok: true });
      expect(calls).toHaveLength(1);
      expect(calls[0].url).toBe('https://n8n.example/webhook/kubix-feedback');
      expect(calls[0].headers.Authorization).toBe('Bearer tok');
      expect(calls[0].body).toMatchObject({ source: 'sias-store', sessionId: 'abc', messageIndex: 2, verdict: 'down' });
      expect(typeof calls[0].body.at).toBe('string');
    } finally {
      global.fetch = realFetch;
    }
  });

  test('returns 502 when the webhook rejects', async () => {
    const realFetch = global.fetch;
    global.fetch = jest.fn(async () => new Response('no', { status: 500 }));
    try {
      const res = await post(
        { sessionId: 'abc', messageIndex: 0, verdict: 'up' },
        { N8N_FEEDBACK_WEBHOOK_URL: 'https://n8n.example/webhook/x' },
      );
      expect(res.status).toBe(502);
    } finally {
      global.fetch = realFetch;
    }
  });
});

describe('copilot page chrome i18n', () => {
  test('copilotLang picks fr only for lang=fr', () => {
    expect(copilotLang(new URL('https://x.example/copilot'))).toBe('en');
    expect(copilotLang(new URL('https://x.example/copilot?lang=fr'))).toBe('fr');
    expect(copilotLang(new URL('https://x.example/copilot?lang=de'))).toBe('en');
    expect(copilotLang(null)).toBe('en');
  });

  test('both dictionaries carry the same keys', () => {
    expect(Object.keys(COPILOT_I18N.fr).sort()).toEqual(Object.keys(COPILOT_I18N.en).sort());
  });

  test('French page renders French chrome; English stays default', async () => {
    const fr = await worker.fetch(new Request('https://x.example/copilot?lang=fr'), {}).then((r) => r.text());
    expect(fr).toContain('Votre ingénieur SIAS dédié');
    expect(fr).toContain('Envoyer');
    expect(fr).toContain('Un ingénieur humain a été sollicité');
    const en = await worker.fetch(new Request('https://x.example/copilot'), {}).then((r) => r.text());
    expect(en).toContain('Your dedicated SIAS engineer');
    expect(en).toContain('>Send<');
  });

  test('copilot page ships the feedback UI', async () => {
    const htmlText = await worker.fetch(new Request('https://x.example/copilot'), {}).then((r) => r.text());
    expect(htmlText).toContain('kx-feedback');
    expect(htmlText).toContain('/api/kubix-feedback');
  });
});

describe('/welcome onboarding page', () => {
  test('renders the four milestones and links to Kubix', async () => {
    const htmlText = await worker.fetch(new Request('https://x.example/welcome'), {}).then((r) => r.text());
    expect(htmlText).toContain('What happens after you buy');
    expect(htmlText).toContain('MILESTONE 01');
    expect(htmlText).toContain('MILESTONE 04');
    expect(htmlText).toContain('one-time activation link');
    expect(htmlText).toContain('/copilot');
  });

  test('success page links to /welcome', async () => {
    const htmlText = await worker.fetch(new Request('https://x.example/success'), {}).then((r) => r.text());
    expect(htmlText).toContain('/welcome');
  });
});

describe('kubix chat report helpers', () => {
  const csv = [
    'sessionId,message,reply,escalated,createdAt',
    's1,"How do I wire OPC-UA, exactly?","Three steps: ...",false,2026-07-01T09:00:00Z',
    's1,"OPC-UA certificate error","Check the gateway trust list ""here""",false,2026-07-01T09:05:00Z',
    's2,Comment configurer Modbus ?,Voici les étapes...,true,2026-07-01T10:00:00Z',
    's3,forecast training fails,Escalating to an engineer.,true,2026-07-02T08:00:00Z',
  ].join('\r\n');

  test('parseCsv handles quotes, embedded commas, escaped quotes and CRLF', () => {
    const rows = parseCsv(csv);
    expect(rows).toHaveLength(4);
    expect(rows[0].message).toBe('How do I wire OPC-UA, exactly?');
    expect(rows[1].reply).toBe('Check the gateway trust list "here"');
    expect(parseCsv('')).toEqual([]);
  });

  test('normalizeRow maps aliased headers and coerces escalated', () => {
    const r = normalizeRow({ Session_ID: 's9', Question: 'hi', Answer: 'yo', Escalation: 'YES', created_at: '2026-07-01' });
    expect(r).toEqual({ sessionId: 's9', message: 'hi', reply: 'yo', escalated: true, createdAt: '2026-07-01' });
    expect(normalizeRow({}).escalated).toBe(false);
  });

  test('sessionsPerDay counts distinct sessions per UTC day in order', () => {
    const rows = parseCsv(csv).map(normalizeRow);
    expect(sessionsPerDay(rows)).toEqual([
      { day: '2026-07-01', sessions: 2 },
      { day: '2026-07-02', sessions: 1 },
    ]);
  });

  test('escalationRate is per-session, not per-message', () => {
    const rows = parseCsv(csv).map(normalizeRow);
    expect(escalationRate(rows)).toBeCloseTo(2 / 3);
    expect(escalationRate([])).toBe(0);
  });

  test('topQuestionWords filters stopwords in EN and FR', () => {
    const rows = parseCsv(csv).map(normalizeRow);
    const words = topQuestionWords(rows, 5).map((w) => w.word);
    expect(words).toContain('opc-ua');
    expect(words).not.toContain('how');
    expect(words).not.toContain('comment');
  });

  test('medianReplyLength ignores empty replies and takes the middle', () => {
    expect(medianReplyLength([{ reply: 'aaaa' }, { reply: 'bb' }, { reply: '' }, { reply: 'cccccc' }])).toBe(4);
    expect(medianReplyLength([{ reply: 'aa' }, { reply: 'bbbb' }])).toBe(3);
    expect(medianReplyLength([])).toBe(0);
  });

  test('buildReport assembles the full summary', () => {
    const rows = parseCsv(csv).map(normalizeRow);
    const report = buildReport(rows, { top: 3 });
    expect(report.totalMessages).toBe(4);
    expect(report.totalSessions).toBe(3);
    expect(report.topQuestionWords).toHaveLength(3);
    expect(report.medianReplyLength).toBeGreaterThan(0);
  });
});
