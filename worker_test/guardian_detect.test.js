import { describe, test, expect } from '@jest/globals';
import { classifyFailure, modelForSeverity, DEFAULT_ROUTING } from '../tool/guardian_detect.mjs';

describe('classifyFailure', () => {
  test('the real Node/wrangler CI error -> high -> Opus', () => {
    const r = classifyFailure('Wrangler requires at least Node.js v22.0.0. You are using v20.20.2.');
    expect(r.category).toBe('ci_node_version');
    expect(r.severity).toBe('high');
    expect(r.model).toBe('claude-opus-4-8');
    expect(r.area).toContain('.github/workflows');
  });
  test('notifications not reaching supervisors -> high -> Opus', () => {
    const r = classifyFailure('Push notifications are not reaching supervisors');
    expect(r.category).toBe('notifications');
    expect(r.model).toBe('claude-opus-4-8');
  });
  test('collab not received -> medium -> Sonnet', () => {
    const r = classifyFailure('collaboration requests not received by supervisors');
    expect(r.category).toBe('collaboration');
    expect(r.severity).toBe('medium');
    expect(r.model).toBe('claude-sonnet-4-6');
  });
  test('forecaster not adapting -> low -> Haiku', () => {
    const r = classifyFailure('the forecaster is not adapting to new data');
    expect(r.category).toBe('forecaster');
    expect(r.model).toBe('claude-haiku-4-5');
  });
  test('unknown text -> medium default', () => {
    expect(classifyFailure('something weird happened').category).toBe('unknown');
  });
  test('manual routing override is honored', () => {
    const r = classifyFailure('Wrangler requires at least Node.js v22', { high: 'gpt-5', medium: 'x', low: 'y' });
    expect(r.model).toBe('gpt-5');
  });
});

describe('modelForSeverity', () => {
  test('maps severities, falls back to medium', () => {
    expect(modelForSeverity('high')).toBe(DEFAULT_ROUTING.high);
    expect(modelForSeverity('bogus')).toBe(DEFAULT_ROUTING.medium);
  });
});
