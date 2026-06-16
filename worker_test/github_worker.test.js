import { describe, test, expect } from '@jest/globals';
import {
  mapRun, mapPull, mapDeployment, mapJob, timingSafeEqual, rateLimit,
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
