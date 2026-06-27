import fs from 'node:fs';

describe('security database rules', () => {
  const rules = JSON.parse(
    fs.readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'),
  ).rules;

  // Reads are limited to the worker service token and the SuperAdmin console.
  // Normal app admins (Production Managers) must stay excluded.
  const privilegedRead =
    "auth != null && (auth.token.role === 'admin' || root.child('users').child(auth.uid).child('role').val() === 'superadmin' || root.child('users').child(auth.uid).child('role').val() === 'SuperAdmin')";
  const serviceWrite = "auth != null && auth.token.role === 'admin'";

  test('security audit and SIEM paths are service-token or superadmin read, service-token write', () => {
    const security = rules.security;

    expect(security['.read']).toBe(privilegedRead);
    expect(security['.write']).toBe(serviceWrite);
    expect(security.logs['.read']).toBe(privilegedRead);
    expect(security.logs['.write']).toBe(serviceWrite);
    expect(security.actions['.read']).toBe(privilegedRead);
    expect(security.actions['.write']).toBe(serviceWrite);
    expect(security.siem_outbox['.indexOn']).toEqual([
      'status',
      'nextAttemptAt',
      'exportedAt',
    ]);
    // Plain app-admin role must never unlock security telemetry.
    expect(JSON.stringify(security)).not.toContain("val() === 'admin'");
  });

  test('worker health is readable by superadmin console but not normal app admins', () => {
    expect(rules.workers['.read']).toBe(privilegedRead);
    expect(rules.workers.health['.read']).toBe(privilegedRead);
    expect(rules.workers['.write']).toBe(serviceWrite);
    expect(rules.workers.health['.write']).toBe(serviceWrite);
    expect(JSON.stringify(rules.workers)).not.toContain("val() === 'admin'");
  });

  test('bug records are writable by clients but readable only by privileged roles', () => {
    const bugs = rules.bugs;
    expect(bugs['.read']).toContain("'superadmin'");
    expect(bugs.client.$bugId['.write']).toBe('auth != null');
  });

  test('ai_forecast model is world-readable for inference and privileged-write', () => {
    const forecast = rules.ai_forecast;
    expect(forecast['.read']).toBe('auth != null');
    expect(forecast['.write']).toContain("'superadmin'");
  });

  test('ai_agents fleet controls are app-readable but superadmin/service-token write only', () => {
    const agents = rules.ai_agents;
    // Dashboards (PM + learner) read switches; only the console and the
    // worker service token may flip them.
    expect(agents['.read']).toBe('auth != null');
    expect(agents['.write']).toContain("'superadmin'");
    expect(agents['.write']).toContain("auth.token.role === 'admin'");
    // Plain app-admin role must not be able to rewrite agent prompts.
    expect(agents['.write']).not.toContain("child('role').val() === 'admin'");
  });

  test('ai_agent_secrets credential vault is write-only from the client (superadmin write, no client read)', () => {
    const secrets = rules.ai_agent_secrets;
    const superadminOnly =
      "auth != null && (root.child('users').child(auth.uid).child('role').val() === 'superadmin' || root.child('users').child(auth.uid).child('role').val() === 'SuperAdmin')";

    // The client can never read the vault back — the worker reads it via its
    // admin OAuth token, which bypasses rules entirely.
    expect(secrets['.read']).toBe(false);
    expect(secrets['.write']).toBe(superadminOnly);
    // Plain app-admin role and the worker service-token claim must never unlock
    // the vault through a rule.
    expect(JSON.stringify(secrets)).not.toContain("val() === 'admin'");
    expect(JSON.stringify(secrets)).not.toContain('auth.token.role');
  });

  test('LLM provider secrets are split: non-secret config vs worker-only key vault', () => {
    // Selection metadata is client-readable (superadmin) + worker-readable.
    const cfg = rules.ai_model_config;
    expect(cfg['.read']).toContain("auth.token.role === 'admin'");
    expect(cfg['.read']).toContain("'superadmin'");
    expect(cfg.$agent.apiKey).toBeUndefined(); // the key never lives here anymore

    // The key vault is unreadable by any rule-bound auth, including the worker's
    // own admin-claim idToken; the worker reads it via OAuth, which bypasses rules.
    const vault = rules.ai_model_secrets;
    expect(vault['.read']).toBe(false);
    expect(vault['.write']).toContain("'superadmin'");
  });

  test('connector_secrets vault is worker-only, exposing only the ingest key to the operator', () => {
    const cs = rules.connector_secrets;
    expect(cs['.read']).toBe(false); // worker bypasses via OAuth; clients cannot read
    expect(cs['.write']).toContain("'superadmin'");
    expect(cs.$connectorId.ingestKey['.read']).toContain("'superadmin'");
  });

  test('anonymous alert creation is closed (auth required on every alert write)', () => {
    expect(rules.alerts.$alertId['.write']).toBe('auth != null');
  });
});
