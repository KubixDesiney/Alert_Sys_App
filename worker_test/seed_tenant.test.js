import {
  DEFAULT_ALERT_TYPES,
  DEFAULT_ESCALATION_SETTINGS,
  buildTenantSeed,
  flattenSeedLeaves,
  missingSeedUpdates,
  validateSeedFlags,
} from '../tool/seed_tenant.mjs';

describe('tenant day-one seed', () => {
  test('builds the same alert vocabulary and escalation defaults as Flutter', () => {
    expect(Object.keys(DEFAULT_ALERT_TYPES)).toEqual([
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource',
    ]);
    expect(DEFAULT_ALERT_TYPES.maintenance).toMatchObject({
      code: 'maintenance',
      color: '#2563EB',
      order: 1,
    });
    expect(DEFAULT_ESCALATION_SETTINGS.maintenance).toEqual({
      type: 'maintenance',
      unclaimedMinutes: 20,
      claimedMinutes: 45,
    });
    expect(DEFAULT_ESCALATION_SETTINGS.default).toBeDefined();
  });

  test('Growth enables adaptive training while Starter remains safely gated', () => {
    const growth = buildTenantSeed({
      tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel Works',
      plan: 'growth',
      provisionedAt: '2026-07-26T00:00:00.000Z',
    });
    const starter = buildTenantSeed({
      tenantCode: 'NSW#7K2F',
      company: 'Nagati Steel Works',
      plan: 'starter',
      provisionedAt: '2026-07-26T00:00:00.000Z',
    });
    expect(growth.app_config.entitlements).toMatchObject({
      fullPackage: true,
      aiTraining: true,
      adaptiveAlertSchema: true,
      connectors: true,
    });
    expect(growth.ai_forecast.onboarding.status).toBe('awaiting_dataset');
    expect(starter.app_config.entitlements.aiTraining).toBe(false);
    expect(starter.ai_forecast.onboarding.status).toBe('not_entitled');
  });

  test('seeds a usable hierarchy, station, and matching asset index', () => {
    const seed = buildTenantSeed({
      tenantCode: 'T#1',
      company: 'Company',
      plan: 'growth',
      usine: 'Usine A',
      provisionedAt: '2026-07-26T00:00:00.000Z',
    });
    const station = seed.hierarchy.factories.factory_1.conveyors.conveyor_1.stations.station_1;
    expect(station.assetId).toBe('MACH-001');
    expect(seed.assets['MACH-001']).toMatchObject({
      factoryId: 'factory_1',
      conveyorId: 'conveyor_1',
      stationId: 'station_1',
      status: 'active',
    });
    expect(seed.assetCounter).toBe(1);
  });

  test('contains no buyer account PII', () => {
    const serialized = JSON.stringify(buildTenantSeed({
      tenantCode: 'T#1',
      company: 'Company',
      plan: 'growth',
    }));
    expect(serialized).not.toMatch(/pmEmail|supervisorEmail|@/);
  });

  test('reruns fill only missing leaves and never overwrite buyer changes', () => {
    const seed = buildTenantSeed({
      tenantCode: 'T#1',
      company: 'Company',
      plan: 'growth',
      usine: 'Usine A',
      provisionedAt: '2026-07-26T00:00:00.000Z',
    });
    const updates = missingSeedUpdates(seed, {
      hierarchy: { factories: { factory_1: { name: 'Buyer renamed plant' } } },
      assetCounter: 42,
    });
    expect(updates['hierarchy/factories/factory_1/name']).toBeUndefined();
    expect(updates.assetCounter).toBeUndefined();
    expect(updates['hierarchy/factories/factory_1/location']).toBe('Complete during onboarding');
  });

  test('flattening preserves synonym arrays as atomic Firebase values', () => {
    const leaves = flattenSeedLeaves({ app_config: { alertTypes: DEFAULT_ALERT_TYPES } });
    expect(leaves['app_config/alertTypes/qualite/synonyms']).toEqual(['qual']);
  });

  test('validates required flags and plan names', () => {
    expect(validateSeedFlags({})).toEqual([
      'missing --tenant',
      'missing --company',
      'missing --plan',
    ]);
    expect(validateSeedFlags({ tenant: 'T', company: 'C', plan: 'enterprise' }))
      .toContain('--plan must be starter or growth');
    expect(validateSeedFlags({ tenant: 'T', company: 'C', plan: 'growth' })).toEqual([]);
  });
});
