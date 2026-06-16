import { describe, test, expect } from '@jest/globals';
import { resolveProvider, buildChatRequest, extractText, PROVIDERS } from '../tool/guardian_providers.mjs';

describe('resolveProvider', () => {
  test('known providers + custom base for other', () => {
    expect(resolveProvider('deepseek').base).toContain('deepseek.com');
    expect(resolveProvider('other', 'https://my.llm/v1/chat/completions').base).toBe('https://my.llm/v1/chat/completions');
    expect(resolveProvider('unknown').id).toBe('other');
  });
});

describe('buildChatRequest', () => {
  test('anthropic uses x-api-key + messages/system', () => {
    const r = buildChatRequest({ provider: 'anthropic', apiKey: 'k', system: 's', user: 'u' });
    expect(r.headers['x-api-key']).toBe('k');
    expect(r.body.system).toBe('s');
    expect(r.body.messages[0]).toEqual({ role: 'user', content: 'u' });
  });
  test('openai-compatible uses bearer + system+user messages', () => {
    const r = buildChatRequest({ provider: 'deepseek', apiKey: 'k', system: 's', user: 'u' });
    expect(r.headers.authorization).toBe('Bearer k');
    expect(r.body.messages.map((x) => x.role)).toEqual(['system', 'user']);
    expect(r.url).toContain('deepseek.com');
  });
  test('falls back to provider default model', () => {
    expect(buildChatRequest({ provider: 'qwen', apiKey: 'k', user: 'u' }).body.model).toBe(PROVIDERS.qwen.defaultModel);
  });
});

describe('extractText', () => {
  test('reads both response shapes', () => {
    expect(extractText('anthropic', { content: [{ text: 'hi' }] })).toBe('hi');
    expect(extractText('openai', { choices: [{ message: { content: 'yo' } }] })).toBe('yo');
    expect(extractText('openai', {})).toBe('');
  });
});
