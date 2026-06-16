// Configurable-AI core for Guardian. Maps a provider id -> chat endpoint + auth
// so the Fix and Review AIs can be Claude, OpenAI, DeepSeek, Qwen, Mistral, xAI,
// Gemini, Groq, or ANY OpenAI-compatible endpoint (provider 'other' + baseUrl).
// Pure builders are unit-tested; callModel is the thin IO wrapper.

export const PROVIDERS = {
  anthropic: { base: 'https://api.anthropic.com/v1/messages',                        kind: 'anthropic', defaultModel: 'claude-opus-4-8' },
  openai:    { base: 'https://api.openai.com/v1/chat/completions',                   kind: 'openai',    defaultModel: 'gpt-4o' },
  deepseek:  { base: 'https://api.deepseek.com/v1/chat/completions',                 kind: 'openai',    defaultModel: 'deepseek-reasoner' },
  qwen:      { base: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions', kind: 'openai', defaultModel: 'qwen-max' },
  mistral:   { base: 'https://api.mistral.ai/v1/chat/completions',                   kind: 'openai',    defaultModel: 'mistral-large-latest' },
  xai:       { base: 'https://api.x.ai/v1/chat/completions',                         kind: 'openai',    defaultModel: 'grok-2-latest' },
  gemini:    { base: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions', kind: 'openai', defaultModel: 'gemini-2.0-flash' },
  groq:      { base: 'https://api.groq.com/openai/v1/chat/completions',              kind: 'openai',    defaultModel: 'llama-3.3-70b-versatile' },
  moonshot:  { base: 'https://api.moonshot.cn/v1/chat/completions',                kind: 'openai', defaultModel: 'moonshot-v1-128k' },
  together:  { base: 'https://api.together.xyz/v1/chat/completions',               kind: 'openai', defaultModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo' },
  fireworks: { base: 'https://api.fireworks.ai/inference/v1/chat/completions',     kind: 'openai', defaultModel: 'accounts/fireworks/models/llama-v3p3-70b-instruct' },
  openrouter:{ base: 'https://openrouter.ai/api/v1/chat/completions',              kind: 'openai', defaultModel: 'openai/gpt-4o' },
  perplexity:{ base: 'https://api.perplexity.ai/chat/completions',                 kind: 'openai', defaultModel: 'sonar-pro' },
  cohere:    { base: 'https://api.cohere.ai/compatibility/v1/chat/completions',    kind: 'openai', defaultModel: 'command-r-plus' },
  other:     { base: '',                                                            kind: 'openai',    defaultModel: '' },
};

export function resolveProvider(id, customBase) {
  const p = PROVIDERS[id] || PROVIDERS.other;
  const base = (id === 'other' || !p.base) ? (customBase || p.base) : (customBase || p.base);
  return { ...p, id: PROVIDERS[id] ? id : 'other', base };
}

/** Build a provider-correct chat request (Anthropic Messages vs OpenAI-compatible). */
export function buildChatRequest({ provider, model, apiKey, system, user, baseUrl, maxTokens = 4096 }) {
  const p = resolveProvider(provider, baseUrl);
  const m = model || p.defaultModel;
  if (p.kind === 'anthropic') {
    return {
      url: p.base,
      headers: { 'content-type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
      body: { model: m, max_tokens: maxTokens, system: system || '', messages: [{ role: 'user', content: user }] },
    };
  }
  return {
    url: p.base,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` },
    body: {
      model: m,
      messages: [
        ...(system ? [{ role: 'system', content: system }] : []),
        { role: 'user', content: user },
      ],
    },
  };
}

/** Pull the assistant text out of either response shape. */
export function extractText(provider, json, baseUrl) {
  const p = resolveProvider(provider, baseUrl);
  if (p.kind === 'anthropic') {
    return (json && Array.isArray(json.content) && json.content[0] && json.content[0].text) || '';
  }
  return (json && Array.isArray(json.choices) && json.choices[0] && json.choices[0].message && json.choices[0].message.content) || '';
}

export async function callModel({ provider, model, apiKey, system, user, baseUrl, maxTokens, fetchImpl = globalThis.fetch }) {
  if (!apiKey) throw new Error(`no API key for provider ${provider}`);
  const req = buildChatRequest({ provider, model, apiKey, system, user, baseUrl, maxTokens });
  if (!req.url) throw new Error(`no endpoint for provider ${provider} (set a base URL for 'other')`);
  const res = await fetchImpl(req.url, { method: 'POST', headers: req.headers, body: JSON.stringify(req.body) });
  if (!res.ok) throw new Error(`${provider} ${res.status}: ${String(await res.text()).slice(0, 300)}`);
  return extractText(provider, await res.json(), baseUrl);
}
