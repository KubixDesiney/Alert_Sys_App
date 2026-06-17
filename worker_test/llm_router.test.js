import { LLM_MODELS, resolveLlm, llmRequest, llmParse } from '../cloudflare_ai_worker.js';

describe('resolveLlm', () => {
  test('defaults to built-in Llama when no config', () => {
    const r = resolveLlm(null);
    expect(r.provider).toBe('cloudflare');
    expect(r.model).toBe('@cf/meta/llama-3.2-3b-instruct');
    expect(r.fellBack).toBe(false);
  });

  test('falls back to Llama when an external model has no key', () => {
    const r = resolveLlm({ modelId: 'gpt-4o', apiKey: '' });
    expect(r.provider).toBe('cloudflare');
    expect(r.fellBack).toBe(true);
  });

  test('resolves an external model with a key', () => {
    const r = resolveLlm({ modelId: 'claude-sonnet', apiKey: 'sk-x' });
    expect(r.provider).toBe('anthropic');
    expect(r.model).toBe('claude-sonnet-4-6');
    expect(r.apiKey).toBe('sk-x');
    expect(r.fellBack).toBe(false);
  });

  test('unknown model id falls back to Llama spec', () => {
    const r = resolveLlm({ modelId: 'does-not-exist', apiKey: 'k' });
    expect(r.provider).toBe('cloudflare');
  });

  test('every catalog id maps to a provider+model', () => {
    for (const [id, spec] of Object.entries(LLM_MODELS)) {
      expect(spec.provider).toBeTruthy();
      expect(spec.model).toBeTruthy();
      expect(id).toBeTruthy();
    }
  });
});

describe('llmRequest', () => {
  test('OpenAI-style chat completions (openai/xai/deepseek/mistral)', () => {
    for (const [provider, host] of [
      ['openai', 'api.openai.com'],
      ['xai', 'api.x.ai'],
      ['deepseek', 'api.deepseek.com'],
      ['mistral', 'api.mistral.ai'],
    ]) {
      const req = llmRequest(provider, 'm', 'KEY', 'hello');
      expect(req.url).toContain(host);
      expect(req.url).toContain('/chat/completions');
      expect(req.init.headers.Authorization).toBe('Bearer KEY');
      const body = JSON.parse(req.init.body);
      expect(body.model).toBe('m');
      expect(body.messages[0].content).toBe('hello');
    }
  });

  test('Anthropic uses x-api-key + version header', () => {
    const req = llmRequest('anthropic', 'claude-x', 'KEY', 'hi');
    expect(req.url).toBe('https://api.anthropic.com/v1/messages');
    expect(req.init.headers['x-api-key']).toBe('KEY');
    expect(req.init.headers['anthropic-version']).toBeTruthy();
    expect(JSON.parse(req.init.body).max_tokens).toBeGreaterThan(0);
  });

  test('Google puts the key in the query string', () => {
    const req = llmRequest('google', 'gemini-1.5-flash', 'KEY', 'hi');
    expect(req.url).toContain('gemini-1.5-flash:generateContent');
    expect(req.url).toContain('key=KEY');
    expect(JSON.parse(req.init.body).contents[0].parts[0].text).toBe('hi');
  });

  test('Cohere v2 chat', () => {
    const req = llmRequest('cohere', 'command-r-plus', 'KEY', 'hi');
    expect(req.url).toBe('https://api.cohere.com/v2/chat');
    expect(req.init.headers.Authorization).toBe('Bearer KEY');
  });

  test('cloudflare/unknown returns null (handled by env.AI)', () => {
    expect(llmRequest('cloudflare', 'm', '', 'x')).toBeNull();
    expect(llmRequest('nope', 'm', 'k', 'x')).toBeNull();
  });
});

describe('llmParse', () => {
  test('OpenAI-style content', () => {
    const json = { choices: [{ message: { content: '  answer  ' } }] };
    expect(llmParse('openai', json)).toBe('answer');
    expect(llmParse('mistral', json)).toBe('answer');
  });

  test('Anthropic content blocks', () => {
    const json = { content: [{ type: 'text', text: 'a' }, { type: 'text', text: 'b' }] };
    expect(llmParse('anthropic', json)).toBe('ab');
  });

  test('Gemini candidates parts', () => {
    const json = { candidates: [{ content: { parts: [{ text: 'g1' }, { text: 'g2' }] } }] };
    expect(llmParse('google', json)).toBe('g1g2');
  });

  test('Cohere v2 message content', () => {
    const json = { message: { content: [{ text: 'co' }] } };
    expect(llmParse('cohere', json)).toBe('co');
  });

  test('empty / malformed returns null', () => {
    expect(llmParse('openai', null)).toBeNull();
    expect(llmParse('openai', {})).toBeNull();
    expect(llmParse('anthropic', { content: [] })).toBeNull();
    expect(llmParse('google', { candidates: [] })).toBeNull();
  });
});
