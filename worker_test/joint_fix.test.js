import {
  parseFixResponse,
  parseReviewVerdict,
  buildFixPrompt,
  buildReviewPrompt,
  runJointFix,
} from '../tool/guardian_joint_fix.mjs';

describe('parseFixResponse', () => {
  test('extracts one file block', () => {
    const out = parseFixResponse('<<<FILE a/b.js>>>\nconst x = 1;\n<<<END>>>');
    expect(out).toEqual([{ path: 'a/b.js', content: 'const x = 1;' }]);
  });
  test('extracts multiple blocks and preserves inner content', () => {
    const txt = '<<<FILE one.js>>>\nline1\nline2\n<<<END>>>\n\n<<<FILE two.js>>>\n{ "a": 1 }\n<<<END>>>';
    const out = parseFixResponse(txt);
    expect(out.length).toBe(2);
    expect(out[0]).toEqual({ path: 'one.js', content: 'line1\nline2' });
    expect(out[1]).toEqual({ path: 'two.js', content: '{ "a": 1 }' });
  });
  test('returns [] when no block present', () => {
    expect(parseFixResponse('sorry, here is what I think...')).toEqual([]);
    expect(parseFixResponse(null)).toEqual([]);
  });
});

describe('parseReviewVerdict', () => {
  test('APPROVE on the verdict line', () => {
    const v = parseReviewVerdict('VERDICT: APPROVE\nlooks good');
    expect(v.approved).toBe(true);
    expect(v.verdict).toBe('APPROVE');
  });
  test('REVISE with a critique', () => {
    const v = parseReviewVerdict('VERDICT: REVISE\nyou removed an import');
    expect(v.approved).toBe(false);
    expect(v.critique).toContain('import');
  });
  test('defaults to REVISE when ambiguous', () => {
    expect(parseReviewVerdict('hmm not sure').approved).toBe(false);
  });
});

describe('buildFixPrompt / buildReviewPrompt', () => {
  test('fix prompt embeds files and prior critique', () => {
    const p = buildFixPrompt({ failure: 'boom', files: { 'x.js': 'CODE' }, priorCritique: 'fix the bracket', round: 2 });
    expect(p).toContain('Round 2');
    expect(p).toContain('boom');
    expect(p).toContain('CODE');
    expect(p).toContain('fix the bracket');
    expect(p).toContain('<<<FILE x.js>>>');
  });
  test('review prompt asks for a VERDICT first line', () => {
    const p = buildReviewPrompt({ failure: 'boom', proposal: [{ path: 'x.js', content: 'CODE' }], files: {} });
    expect(p).toContain('VERDICT: APPROVE');
    expect(p).toContain('VERDICT: REVISE');
    expect(p).toContain('CODE');
  });
});

// Helper: a scripted model caller that branches on provider id.
function scriptedCaller(script) {
  let fixCalls = 0;
  let reviewCalls = 0;
  return async ({ provider, user }) => {
    if (provider === 'fixco') return script.fix(++fixCalls, user);
    if (provider === 'revco') return script.review(++reviewCalls, user);
    throw new Error('unexpected provider ' + provider);
  };
}

const FIX = { provider: 'fixco', model: 'm', apiKey: 'k' };
const REVIEW = { provider: 'revco', model: 'm', apiKey: 'k' };
const FILES = { 'broken.js': 'function f() { return 1' };

describe('runJointFix', () => {
  test('approves and validates on round 1', async () => {
    const call = scriptedCaller({
      fix: () => '<<<FILE broken.js>>>\nfunction f() { return 1; }\n<<<END>>>',
      review: () => 'VERDICT: APPROVE',
    });
    const res = await runJointFix({ failure: 'syntax', files: FILES, fix: FIX, review: REVIEW, call, validate: async () => ({ ok: true }) });
    expect(res.ok).toBe(true);
    expect(res.rounds).toBe(1);
    expect(res.files['broken.js']).toContain('return 1;');
  });

  test('iterates when reviewer asks to revise, then approves', async () => {
    const call = scriptedCaller({
      fix: (n) => `<<<FILE broken.js>>>\n// attempt ${n}\nfunction f() { return 1; }\n<<<END>>>`,
      review: (n) => (n === 1 ? 'VERDICT: REVISE\nadd a semicolon' : 'VERDICT: APPROVE'),
    });
    const res = await runJointFix({ failure: 'syntax', files: FILES, fix: FIX, review: REVIEW, call, validate: async () => ({ ok: true }), maxRounds: 4 });
    expect(res.ok).toBe(true);
    expect(res.rounds).toBe(2);
  });

  test('validator failure re-enters the loop (validator is a participant)', async () => {
    let v = 0;
    const call = scriptedCaller({
      fix: () => '<<<FILE broken.js>>>\nfunction f() { return 1; }\n<<<END>>>',
      review: () => 'VERDICT: APPROVE',
    });
    const res = await runJointFix({
      failure: 'syntax', files: FILES, fix: FIX, review: REVIEW, call, maxRounds: 4,
      validate: async () => (++v === 1 ? { ok: false, detail: 'node --check failed' } : { ok: true }),
    });
    expect(res.ok).toBe(true);
    expect(res.rounds).toBe(2);
    expect(res.transcript.some((t) => t.role === 'validate' && /node --check/.test(t.text))).toBe(true);
  });

  test('exhausts maxRounds when never approved', async () => {
    const call = scriptedCaller({
      fix: () => '<<<FILE broken.js>>>\nfunction f() { return 1; }\n<<<END>>>',
      review: () => 'VERDICT: REVISE\nnope',
    });
    const res = await runJointFix({ failure: 'x', files: FILES, fix: FIX, review: REVIEW, call, maxRounds: 2 });
    expect(res.ok).toBe(false);
    expect(res.rounds).toBe(2);
    expect(res.reason).toBe('max_rounds_exhausted');
  });

  test('re-prompts when the fix engineer returns no parseable block', async () => {
    const call = scriptedCaller({
      fix: (n) => (n === 1 ? 'I think the bug is here' : '<<<FILE broken.js>>>\nfunction f() { return 1; }\n<<<END>>>'),
      review: () => 'VERDICT: APPROVE',
    });
    const res = await runJointFix({ failure: 'x', files: FILES, fix: FIX, review: REVIEW, call, validate: async () => ({ ok: true }), maxRounds: 3 });
    expect(res.ok).toBe(true);
    expect(res.rounds).toBe(2);
  });
});
