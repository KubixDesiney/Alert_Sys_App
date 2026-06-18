import {
  scoreAssistOutput,
  scoreBriefingOutput,
  scoreShiftOutput,
  evalVerdict,
  modelDriftBreach,
} from '../cloudflare_ai_worker.js';

const assistCtx = {
  typeLabel: 'quality',
  machine: 'Line 3',
  historyKeywords: ['sensor', 'gate', 'rail', 'debris', 'bracket'],
  fallback: 'Check equipment. Verify sensors. Restart.',
};

describe('scoreAssistOutput', () => {
  test('a grounded, multi-step, on-topic answer scores high', () => {
    const good =
      '1. Realign the sensor bracket on Line 3.\n2. Clear debris from the gate.\n3. Inspect the guide rail for wear and replace if needed.';
    const r = scoreAssistOutput(good, assistCtx);
    expect(r.overall).toBeGreaterThan(0.85);
    expect(r.dims.grounded).toBe(1);
    expect(r.dims.actionable).toBe(1);
  });

  test('the static fallback scores low', () => {
    const r = scoreAssistOutput(assistCtx.fallback, assistCtx);
    expect(r.dims.notFallback).toBe(0);
    expect(r.overall).toBeLessThan(0.6);
  });

  test('an empty answer scores near zero', () => {
    const r = scoreAssistOutput('', assistCtx);
    expect(r.overall).toBeLessThan(0.3);
  });
});

describe('scoreBriefingOutput', () => {
  const ctx = { numbers: ['42', '38', '90', '11'], onTopicWords: ['alert', 'resolution'] };

  test('greeting + all numbers + on-topic scores high', () => {
    const good =
      'Good morning. The team handled 42 alerts last week, resolving 38 for a 90% resolution rate with an average response of 11 minutes. Stay sharp on critical signals today.';
    const r = scoreBriefingOutput(good, ctx);
    expect(r.overall).toBeGreaterThan(0.9);
    expect(r.dims.greeting).toBe(1);
    expect(r.dims.numbersPresent).toBe(1);
  });

  test('leaked {placeholder} is penalised', () => {
    const bad = 'Good morning. We saw {total} alerts and {resolved} resolved.';
    const r = scoreBriefingOutput(bad, ctx);
    expect(r.dims.noPlaceholderLeak).toBe(0);
  });

  test('missing greeting and numbers scores low', () => {
    const r = scoreBriefingOutput('Things were fine this week overall.', ctx);
    expect(r.dims.greeting).toBe(0);
    expect(r.overall).toBeLessThan(0.5);
  });
});

describe('scoreShiftOutput', () => {
  const ctx = { counts: ['12', '3', '1'] };

  test('counts present, concise, actionable scores high', () => {
    const good =
      'Resolved 12 alerts, 3 still pending, 1 critical open. Next shift should monitor the critical line and follow up on the pending items.';
    const r = scoreShiftOutput(good, ctx);
    expect(r.overall).toBeGreaterThan(0.85);
    expect(r.dims.countsPresent).toBe(1);
    expect(r.dims.actionable).toBe(1);
  });

  test('vague output without counts scores lower', () => {
    const r = scoreShiftOutput('The shift went well, nothing major.', ctx);
    expect(r.dims.countsPresent).toBe(0);
    expect(r.overall).toBeLessThan(scoreShiftOutput(
      'Resolved 12, pending 3, critical 1 — monitor the critical line next.', ctx).overall);
  });
});

describe('evalVerdict', () => {
  test('candidate clearly above champion → better', () => {
    expect(evalVerdict(0.9, 0.6).verdict).toBe('better');
  });
  test('candidate clearly below → worse', () => {
    expect(evalVerdict(0.6, 0.9).verdict).toBe('worse');
  });
  test('within the margin → similar', () => {
    expect(evalVerdict(0.82, 0.80).verdict).toBe('similar');
  });
  test('reports a rounded delta', () => {
    expect(evalVerdict(0.9, 0.6).delta).toBeCloseTo(0.3, 5);
  });
});

describe('modelDriftBreach', () => {
  test('no breach when quality holds near baseline', () => {
    expect(
      modelDriftBreach({ score: 0.83, baseline: 0.85, modelId: 'gpt-4o', baselineModelId: 'gpt-4o' }),
    ).toBeNull();
  });

  test('breaches when quality drops past the baseline margin', () => {
    const r = modelDriftBreach({ score: 0.70, baseline: 0.85, modelId: 'gpt-4o', baselineModelId: 'gpt-4o' });
    expect(r).toContain('dropped');
    expect(r).toContain('baseline');
  });

  test('breaches when quality falls below the absolute floor', () => {
    expect(modelDriftBreach({ score: 0.40, baseline: 0.42, modelId: 'm', baselineModelId: 'm' }))
      .toContain('floor');
  });

  test('no breach right after a model swap (baseline belongs to old model)', () => {
    expect(
      modelDriftBreach({ score: 0.6, baseline: 0.9, modelId: 'claude-opus', baselineModelId: 'gpt-4o' }),
    ).toBeNull();
  });

  test('no breach with no baseline yet', () => {
    expect(modelDriftBreach({ score: 0.8, baseline: null, modelId: 'm' })).toBeNull();
  });
});
