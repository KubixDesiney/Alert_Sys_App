import { configProbeUrl, crashFreeBreach } from '../cloudflare_monitor_worker.js';

describe('tenant worker probe URL', () => {
  test('replaces delivery paths instead of appending /config to them', () => {
    expect(configProbeUrl('https://alertsys-tenant.example.workers.dev/notify'))
      .toBe('https://alertsys-tenant.example.workers.dev/config');
    expect(configProbeUrl('https://alert-notifier-tenant.example.workers.dev'))
      .toBe('https://alert-notifier-tenant.example.workers.dev/config');
  });
});

describe('crashFreeBreach (app error-budget SLO)', () => {
  test('no breach below the minimum session count', () => {
    expect(crashFreeBreach({ sessions: 5, errorSessions: 5 }, 99, 20)).toBeNull();
  });

  test('no breach when crash-free meets the SLO', () => {
    expect(crashFreeBreach({ sessions: 100, errorSessions: 1 }, 99, 20)).toBeNull();
  });

  test('breaches when crash-free falls below the SLO', () => {
    const r = crashFreeBreach({ sessions: 100, errorSessions: 5 }, 99, 20);
    expect(r).toContain('Crash-free 95.0%');
    expect(r).toContain('SLO 99%');
    expect(r).toContain('5/100');
  });

  test('handles missing/empty telemetry', () => {
    expect(crashFreeBreach(null)).toBeNull();
    expect(crashFreeBreach({})).toBeNull();
  });

  test('defaults to 99% SLO and 20 sessions', () => {
    expect(crashFreeBreach({ sessions: 50, errorSessions: 0 })).toBeNull();
    expect(crashFreeBreach({ sessions: 50, errorSessions: 2 })).toContain('< SLO 99%');
  });

  test('respects a custom SLO', () => {
    // 96% crash-free passes a 95% SLO but fails a 99% SLO.
    expect(crashFreeBreach({ sessions: 100, errorSessions: 4 }, 95, 20)).toBeNull();
    expect(crashFreeBreach({ sessions: 100, errorSessions: 4 }, 99, 20)).not.toBeNull();
  });
});
