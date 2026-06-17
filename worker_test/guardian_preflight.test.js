import { checkSecrets } from '../tool/guardian_preflight.mjs';

const cap = (r, name) => r.capabilities.find((c) => c.name === name);

describe('checkSecrets', () => {
  test('empty env: nothing is runnable', () => {
    const r = checkSecrets({});
    expect(r.canRunLive).toBe(false);
    expect(r.canDeployWeb).toBe(false);
    expect(r.canDeployWorkers).toBe(false);
    expect(r.capabilities.every((c) => c.present === false)).toBe(true);
  });

  test('AI key alone is not enough to run live (needs a git token too)', () => {
    expect(checkSecrets({ ANTHROPIC_API_KEY: 'x' }).canRunLive).toBe(false);
  });

  test('AI key + GitHub token => live joint fix', () => {
    const r = checkSecrets({ GUARDIAN_FIX_API_KEY: 'x', AUTOFIX_GITHUB_TOKEN: 'y' });
    expect(r.canRunLive).toBe(true);
    expect(cap(r, 'Joint Fix+Review AI').present).toBe(true);
    expect(cap(r, 'Commit & push fixes').present).toBe(true);
  });

  test('default Actions GITHUB_TOKEN also satisfies push', () => {
    expect(checkSecrets({ OPENAI_API_KEY: 'x', GITHUB_TOKEN: 'y' }).canRunLive).toBe(true);
  });

  test('FIREBASE_TOKEN enables web deploy', () => {
    expect(checkSecrets({ FIREBASE_TOKEN: 't' }).canDeployWeb).toBe(true);
  });

  test('both Cloudflare creds required for worker deploy', () => {
    expect(checkSecrets({ CLOUDFLARE_API_TOKEN: 'a' }).canDeployWorkers).toBe(false);
    expect(checkSecrets({ CLOUDFLARE_API_TOKEN: 'a', CLOUDFLARE_ACCOUNT_ID: 'b' }).canDeployWorkers).toBe(true);
  });

  test('any one of several provider keys counts as an AI key', () => {
    for (const k of ['DEEPSEEK_API_KEY', 'QWEN_API_KEY', 'GROQ_API_KEY', 'MISTRAL_API_KEY', 'XAI_API_KEY', 'GEMINI_API_KEY']) {
      expect(cap(checkSecrets({ [k]: 'x' }), 'Joint Fix+Review AI').present).toBe(true);
    }
  });

  test('blank-string secrets are treated as absent', () => {
    expect(cap(checkSecrets({ ANTHROPIC_API_KEY: '   ' }), 'Joint Fix+Review AI').present).toBe(false);
  });
});
