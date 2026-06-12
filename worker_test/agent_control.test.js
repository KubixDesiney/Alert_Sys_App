import {
  _agentEnabled,
  _agentSetting,
  _assistFillPrompt,
  _forecastDayKey,
} from '../cloudflare_ai_worker.js';

describe('AI agent fleet control plane', () => {
  test('agents default to enabled when the control node is missing or partial', () => {
    expect(_agentEnabled(null, 'shift')).toBe(true);
    expect(_agentEnabled({}, 'briefing')).toBe(true);
    expect(_agentEnabled({ assist: {} }, 'assist')).toBe(true);
    expect(_agentEnabled({ assist: { enabled: true } }, 'assist')).toBe(true);
  });

  test('an explicit enabled:false takes the agent offline', () => {
    const control = { shift: { enabled: false }, security: { enabled: true } };
    expect(_agentEnabled(control, 'shift')).toBe(false);
    expect(_agentEnabled(control, 'security')).toBe(true);
  });

  test('per-agent settings default open and only an explicit false disables', () => {
    expect(_agentSetting(null, 'security', 'promptInjection')).toBe(true);
    expect(_agentSetting({}, 'security', 'rateLimiting')).toBe(true);
    expect(
      _agentSetting({ security: { settings: { anomalyScan: false } } }, 'security', 'anomalyScan'),
    ).toBe(false);
    expect(
      _agentSetting({ security: { settings: { anomalyScan: false } } }, 'security', 'siemExport'),
    ).toBe(true);
  });
});

describe('AI assist prompt template', () => {
  test('fills every placeholder, including repeats', () => {
    const prompt = _assistFillPrompt('Fix {type} at {usine}. Again: {type}. {history}', {
      type: 'Quality',
      usine: 'Plant 7',
      history: 'No past fixes.',
    });
    expect(prompt).toBe('Fix Quality at Plant 7. Again: Quality. No past fixes.');
  });

  test('leaves unknown placeholders intact and stringifies null safely', () => {
    const prompt = _assistFillPrompt('{type} {unknown} {poste}', {
      type: 'Maintenance',
      poste: null,
    });
    expect(prompt).toBe('Maintenance {unknown} ');
  });
});

describe('forecast outcome learner helpers', () => {
  test('day keys match the Dart ledger scheme (yyyy-MM-dd, UTC)', () => {
    expect(_forecastDayKey(new Date('2026-06-12T15:30:00Z'))).toBe('2026-06-12');
    expect(_forecastDayKey(new Date('2026-01-01T00:00:00Z'))).toBe('2026-01-01');
  });
});
