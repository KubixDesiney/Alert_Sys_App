import fs from 'node:fs';

describe('security database rules', () => {
  const rules = JSON.parse(
    fs.readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'),
  ).rules;

  test('security audit and SIEM paths are service-token only', () => {
    const security = rules.security;

    expect(security['.read']).toBe("auth != null && auth.token.role === 'admin'");
    expect(security['.write']).toBe("auth != null && auth.token.role === 'admin'");
    expect(security.logs['.read']).toBe("auth != null && auth.token.role === 'admin'");
    expect(security.actions['.write']).toBe("auth != null && auth.token.role === 'admin'");
    expect(security.siem_outbox['.indexOn']).toEqual([
      'status',
      'nextAttemptAt',
      'exportedAt',
    ]);
    expect(JSON.stringify(security)).not.toContain("root.child('users')");
  });

  test('worker health is no longer readable by normal app admins', () => {
    expect(rules.workers.health['.read']).toBe("auth != null && auth.token.role === 'admin'");
    expect(JSON.stringify(rules.workers)).not.toContain("root.child('users')");
  });
});
