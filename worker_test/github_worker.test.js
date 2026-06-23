import { describe, test, expect } from '@jest/globals';
import {
  mapRun, mapPull, mapDeployment, mapJob, timingSafeEqual, rateLimit,
  tailText, stripLogTimestamps, normalizeRepo, chooseGithubCreds,
} from '../cloudflare_github_worker.js';

describe('mapRun', () => {
  test('trims a workflow run', () => {
    const r = mapRun({ id: 7, name: 'CI', status: 'completed', conclusion: 'success', head_branch: 'main', event: 'push', actor: { login: 'kubix' }, run_number: 42, html_url: 'u' });
    expect(r).toMatchObject({ id: 7, status: 'completed', conclusion: 'success', branch: 'main', actor: 'kubix', runNumber: 42 });
  });
});

describe('mapPull', () => {
  test('open PR', () => {
    expect(mapPull({ number: 148, title: 'fix', state: 'open', user: { login: 'guardian' }, head: { ref: 'g/fix' } }))
      .toMatchObject({ number: 148, state: 'open', user: 'guardian', branch: 'g/fix' });
  });
  test('merged PR derives state', () => {
    expect(mapPull({ number: 147, merged_at: '2026-06-15', state: 'closed' }).state).toBe('merged');
  });
});

describe('mapDeployment', () => {
  test('shortens sha and maps env', () => {
    const d = mapDeployment({ id: 1, environment: 'production', sha: 'abcdef1234', creator: { login: 'ci' } });
    expect(d).toMatchObject({ environment: 'production', sha: 'abcdef1', creator: 'ci' });
  });
});

describe('mapJob', () => {
  test('maps steps', () => {
    const j = mapJob({ id: 9, name: 'build', status: 'completed', conclusion: 'success', steps: [{ name: 'test', status: 'completed', conclusion: 'success', number: 1 }] });
    expect(j.steps).toEqual([{ name: 'test', status: 'completed', conclusion: 'success', number: 1 }]);
  });
});

describe('timingSafeEqual', () => {
  test('equal vs not', () => {
    expect(timingSafeEqual('abc', 'abc')).toBe(true);
    expect(timingSafeEqual('abc', 'abd')).toBe(false);
    expect(timingSafeEqual('abc', 'abcd')).toBe(false);
  });
});

describe('rateLimit', () => {
  test('allows to the limit then blocks', () => {
    const b = new Map();
    let ok;
    for (let i = 0; i < 3; i++) ok = rateLimit(b, 'ip', 3, 60000, 1000 + i);
    expect(ok).toBe(true);
    expect(rateLimit(b, 'ip', 3, 60000, 1003)).toBe(false);
  });
});

describe('tailText', () => {
  test('returns short text unchanged', () => {
    expect(tailText('hello', 16000)).toBe('hello');
  });
  test('tails long text to a clean line boundary', () => {
    const text = 'line1\nline2\nlonglonglongtail';
    const out = tailText(text, 18); // forces a cut inside the first lines
    expect(out.length).toBeLessThanOrEqual(18);
    expect(out.startsWith('line')).toBe(false); // partial first line dropped
    expect(text.endsWith(out)).toBe(true); // it is a true tail
  });
  test('handles null', () => {
    expect(tailText(null)).toBe('');
  });
});

describe('stripLogTimestamps', () => {
  test('removes GitHub ISO prefixes, keeps command output', () => {
    const raw = '2026-06-18T12:00:01.1234567Z $ npm test\n2026-06-18T12:00:02.0000000Z PASS';
    expect(stripLogTimestamps(raw)).toBe('$ npm test\nPASS');
  });
  test('leaves untimestamped lines alone', () => {
    expect(stripLogTimestamps('plain line')).toBe('plain line');
  });
});

describe('normalizeRepo', () => {
  test('accepts owner/name and common GitHub URLs', () => {
    expect(normalizeRepo('owner/repo')).toBe('owner/repo');
    expect(normalizeRepo('https://github.com/owner/repo')).toBe('owner/repo');
    expect(normalizeRepo('git@github.com:owner/repo.git')).toBe('owner/repo');
    expect(normalizeRepo('https://api.github.com/repos/owner/repo')).toBe('owner/repo');
  });
});

describe('chooseGithubCreds', () => {
  test('prefers the SuperAdmin vault over env bootstrap credentials', () => {
    expect(chooseGithubCreds({
      envRepo: 'env/repo',
      envToken: 'env-token',
      vaultRepo: 'https://github.com/vault/repo',
      vaultToken: 'vault-token',
    })).toEqual({ repo: 'vault/repo', token: 'vault-token' });
  });

  test('does not silently fall back to env after vault credentials are edited', () => {
    expect(chooseGithubCreds({
      envRepo: 'env/repo',
      envToken: 'env-token',
      vaultRepo: 'bad input',
      vaultToken: 'gibberish',
    })).toEqual({ repo: '', token: 'gibberish' });
  });

  test('uses env credentials only before the vault is populated', () => {
    expect(chooseGithubCreds({
      envRepo: 'env/repo',
      envToken: 'env-token',
    })).toEqual({ repo: 'env/repo', token: 'env-token' });
  });
});
