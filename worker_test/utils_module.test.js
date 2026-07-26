// Fills the remaining worker/utils.js gaps not already covered by
// briefing_helpers.test.js, factory_id.test.js and haversine.test.js:
// _topSupervisorWeek, _shiftContainsTime/pickActiveShift, and
// loadFactoryLocations (network-mocked, no live Firebase).
import { afterEach, describe, expect, jest, test } from '@jest/globals';
import {
  _topSupervisorWeek,
  _shiftContainsTime,
  pickActiveShift,
  loadFactoryLocations,
} from '../worker/utils.js';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

describe('_topSupervisorWeek', () => {
  const now = Date.now();
  const recent = (daysAgo) => new Date(now - daysAgo * 86400000).toISOString();

  test('returns null when nobody resolved anything in the window', () => {
    expect(_topSupervisorWeek({}, {})).toBeNull();
    expect(_topSupervisorWeek({ a: { status: 'en_cours', timestamp: recent(1), superviseurId: 'x' } }, {})).toBeNull();
  });

  test('ranks by resolved count, ignoring alerts outside the 7-day window or without a supervisor', () => {
    const alertsMap = {
      a1: { status: 'validee', timestamp: recent(1), superviseurId: 'sup1', type: 'maintenance', elapsedTime: 10 },
      a2: { status: 'validee', timestamp: recent(2), superviseurId: 'sup1', type: 'maintenance', elapsedTime: 20 },
      a3: { status: 'validee', timestamp: recent(1), superviseurId: 'sup2', type: 'quality', elapsedTime: 5 },
      old: { status: 'validee', timestamp: recent(30), superviseurId: 'sup1' }, // outside window
      noSup: { status: 'validee', timestamp: recent(1) }, // no superviseurId
    };
    const usersMap = { sup1: { firstName: 'Amine', lastName: 'Ben Salah' }, sup2: { fullName: 'Other Sup' } };
    const top = _topSupervisorWeek(alertsMap, usersMap);
    expect(top).toMatchObject({ name: 'Amine Ben Salah', count: 2, topType: 'maintenance', avgMin: 15 });
  });

  test('scopes to a single factory when a filter is given', () => {
    const alertsMap = {
      a1: { status: 'validee', timestamp: recent(1), superviseurId: 'sup1', usine: 'Plant A', type: 'x', elapsedTime: 1 },
      a2: { status: 'validee', timestamp: recent(1), superviseurId: 'sup2', usine: 'Plant B', type: 'x', elapsedTime: 1 },
    };
    const top = _topSupervisorWeek(alertsMap, { sup2: { fullName: 'B Sup' } }, 'Plant B');
    expect(top.name).toBe('B Sup');
    expect(top.count).toBe(1);
  });

  test('falls back to the uid when the user record is missing a name', () => {
    const alertsMap = { a1: { status: 'validee', timestamp: recent(1), superviseurId: 'ghost', type: 'x' } };
    const top = _topSupervisorWeek(alertsMap, {});
    expect(top.name).toBe('ghost');
    expect(top.avgMin).toBe(0); // totalTime stays 0 with no finite elapsedTime anywhere
  });
});

describe('_shiftContainsTime / pickActiveShift', () => {
  test('same-day window: contains only within [start, end)', () => {
    expect(_shiftContainsTime({ startMinutes: 480, endMinutes: 960 }, 500)).toBe(true);
    expect(_shiftContainsTime({ startMinutes: 480, endMinutes: 960 }, 960)).toBe(false);
    expect(_shiftContainsTime({ startMinutes: 480, endMinutes: 960 }, 100)).toBe(false);
  });

  test('overnight window wraps past midnight', () => {
    expect(_shiftContainsTime({ startMinutes: 1320, endMinutes: 300 }, 30)).toBe(true); // 00:30
    expect(_shiftContainsTime({ startMinutes: 1320, endMinutes: 300 }, 1350)).toBe(true); // 22:30
    expect(_shiftContainsTime({ startMinutes: 1320, endMinutes: 300 }, 700)).toBe(false); // midday
  });

  test('pickActiveShift finds the first shift whose window contains now, or null', () => {
    const now = new Date(Date.UTC(2026, 0, 1, 10, 0)); // 10:00 UTC = minute 600
    const shifts = {
      morning: { startMinutes: 480, endMinutes: 960 }, // 08:00-16:00 — contains 600
      night: { startMinutes: 1200, endMinutes: 240 },
    };
    expect(pickActiveShift(shifts, now)).toMatchObject({ id: 'morning' });
    expect(pickActiveShift(null, now)).toBeNull();
    expect(pickActiveShift({ bad: null, alsoBad: 'nope' }, now)).toBeNull();
    expect(pickActiveShift({ x: { startMinutes: 0, endMinutes: 1 } }, now)).toBeNull(); // outside window
  });
});

describe('loadFactoryLocations', () => {
  const env = { FB_DB_URL: 'https://db.example/' };

  test('merges hierarchy/factories then factories/, first-writer-wins per id, skipping non-finite coords', async () => {
    globalThis.fetch = jest.fn(async (url) => {
      const u = String(url);
      if (u.includes('hierarchy/factories.json')) {
        return new Response(JSON.stringify({
          'Plant A': { location: { lat: 36.8, lng: 10.1 } },
          'Bad Plant': { location: { lat: 'nope', lng: 10 } },
          'No Loc Plant': {},
        }), { status: 200 });
      }
      if (u.includes('/factories.json')) {
        return new Response(JSON.stringify({
          'Plant A': { location: { lat: 0, lng: 0 } }, // should NOT override hierarchy's value
          'Plant B': { location: { lat: 34.0, lng: 9.0 } },
        }), { status: 200 });
      }
      throw new Error(`unexpected ${u}`);
    });
    const locs = await loadFactoryLocations(env, 'tok');
    expect(locs.plant_a).toEqual({ lat: 36.8, lng: 10.1 });
    expect(locs.plant_b).toEqual({ lat: 34.0, lng: 9.0 });
    expect(locs.bad_plant).toBeUndefined();
    expect(locs.no_loc_plant).toBeUndefined();
  });

  test('returns an empty map when both reads fail, without throwing', async () => {
    globalThis.fetch = jest.fn(async () => new Response('nope', { status: 500 }));
    await expect(loadFactoryLocations(env, 'tok')).resolves.toEqual({});
  });

  test('returns an empty map when fetch itself throws', async () => {
    globalThis.fetch = jest.fn(async () => { throw new Error('network down'); });
    await expect(loadFactoryLocations(env, 'tok')).resolves.toEqual({});
  });
});
