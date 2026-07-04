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
    expect(rules.alerts.$alertId['.write']).toContain('auth != null &&');
    expect(rules.alerts['.write']).toContain('auth != null &&');
  });

  test('alert writes require ownership or a privileged role (no blanket authed write)', () => {
    const write = rules.alerts.$alertId['.write'];
    // Privileged roles keep full control.
    expect(write).toContain("val() === 'admin'");
    expect(write).toContain("'superadmin'");
    expect(write).toContain("auth.token.role === 'admin'");
    // Supervisors only touch alerts they own, claim, assist, were recommended,
    // or share through a collaboration — and can never delete one.
    expect(write).toContain("val() === 'supervisor'");
    expect(write).toContain('newData.exists()');
    expect(write).toContain("data.child('superviseurId').val() === auth.uid");
    expect(write).toContain(
      "!data.child('superviseurId').exists() && newData.child('superviseurId').val() === auth.uid",
    );
    expect(write).toContain("data.child('assistantId').val() === auth.uid");
    expect(write).toContain("data.child('aiRecommendedSupervisorId').val() === auth.uid");
    expect(write).toContain("root.child('collaboration_alerts').child(auth.uid).child($alertId).exists()");
    // Push bookkeeping fields stay writable by any authed client so the
    // stream fan-out dedup keeps working without alert ownership.
    for (const field of ['push_sent', 'push_sent_at', 'push_delivery_mode', 'notificationSent']) {
      expect(rules.alerts.$alertId[field]['.write']).toBe('auth != null');
    }
  });

  test('alertCounter is only writable by privileged roles', () => {
    expect(rules.alertCounter['.write']).toContain("val() === 'admin'");
    expect(rules.alertCounter['.write']).not.toBe('auth != null');
  });

  test('users cannot self-escalate their role and PII fields are blocked in users/*', () => {
    const user = rules.users.$userId;
    const roleValidate = user.role['.validate'];
    // Role changes require an admin/superadmin/worker writer; an unchanged
    // role always passes so self profile updates keep working.
    expect(roleValidate).toContain('newData.val() === data.val()');
    expect(roleValidate).toContain("val() === 'admin'");
    expect(roleValidate).toContain("auth.token.role === 'admin'");
    // email/phone/GPS may never be written into the broadly-readable node —
    // they live in the access-scoped users_private node instead.
    expect(user.email['.validate']).toBe(false);
    expect(user.phone['.validate']).toBe(false);
    expect(user.currentLocation['.validate']).toBe(false);
    expect(rules.users_private.$userId.email).toBeDefined();
  });

  test('per-user queues have no blanket parent write grant', () => {
    // A parent-level "auth != null" .write cascades past every child
    // restriction in RTDB — none of these nodes may have one.
    expect(rules.supervisor_active_alerts['.write']).toBeUndefined();
    expect(rules.collaboration_alerts['.write']).toBeUndefined();
    expect(rules.pm_actions['.write']).toBeUndefined();
    expect(rules.shift_presence['.write']).toBeUndefined();
    expect(rules.notifications['.write']).toBe("auth != null && auth.token.role === 'admin'");
    // Producers can still create (not overwrite) rows for other users.
    expect(rules.notifications.$userId.$notifId['.write']).toContain('!data.exists()');
    expect(rules.pm_actions.$userId.$actionId['.write']).toContain('!data.exists()');
  });

  test('configurable alert-type registry is app-readable, superadmin-write only', () => {
    const node = rules.app_config.alertTypes;
    // Every authed client (PM dashboards, supervisors, the forecaster) reads
    // the vocabulary; only the SuperAdmin console may change it.
    expect(node['.read']).toBe('auth != null');
    expect(node['.write']).toContain("'superadmin'");
    expect(node['.write']).toContain("'SuperAdmin'");
    // Plain app-admin role must not be able to rewrite the type set.
    expect(node['.write']).not.toContain("child('role').val() === 'admin'");
    expect(node['.indexOn']).toEqual(['order']);
    // A type entry validates its identifying fields.
    expect(node.$code.code['.validate']).toContain('isString');
    expect(node.$code.label['.validate']).toContain('isString');
  });

  test('alert source/sourceType are optional string fields', () => {
    const alert = rules.alerts.$alertId;
    for (const field of ['source', 'sourceType']) {
      expect(alert[field]['.validate']).toContain('!newData.exists()');
      expect(alert[field]['.validate']).toContain('isString');
    }
  });
});
