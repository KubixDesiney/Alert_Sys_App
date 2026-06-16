import { describe, test, expect } from '@jest/globals';
import { ciSignalsFromRuns, collectCiSignals } from '../tool/guardian_ci_watch.mjs';

describe('ciSignalsFromRuns', () => {
  test('keeps only failed runs and triages them', () => {
    const sigs = ciSignalsFromRuns([
      { id: 1, name: 'deploy failed', conclusion: 'failure', head_branch: 'main', html_url: 'u' },
      { id: 2, name: 'CI', conclusion: 'success', head_branch: 'main' },
    ]);
    expect(sigs).toHaveLength(1);
    expect(sigs[0]).toMatchObject({ area: 'ci', runId: 1 });
    expect(sigs[0].severity).toBeDefined();
    expect(sigs[0].model).toBeDefined();
  });
});

describe('collectCiSignals', () => {
  test('pushes failed-run signals via a mocked fetch', async () => {
    const fakeFetch = async () => ({
      ok: true,
      json: async () => ({ workflow_runs: [{ id: 9, name: 'deploy failed', conclusion: 'failure', head_branch: 'main' }] }),
    });
    const signals = { issues: [], skipped: [] };
    await collectCiSignals(signals, { token: 't', repo: 'o/r', fetch: fakeFetch });
    expect(signals.issues).toHaveLength(1);
    expect(signals.ci).toHaveLength(1);
    expect(signals.issues[0].area).toBe('ci');
  });
  test('no-ops without token or repo', async () => {
    const signals = { issues: [], skipped: [] };
    await collectCiSignals(signals, { token: '', repo: '' });
    expect(signals.issues).toHaveLength(0);
  });
});
