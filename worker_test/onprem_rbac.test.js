// Authorization tests for the on-prem PocketBase access rules.
// Evaluates the REAL rule strings from deploy/onprem/pocketbase/pb_schema.json
// against a persona matrix using the rules_eval mini-interpreter, so a rule
// regression (e.g. a supervisor reading another factory's alerts) fails CI.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { evalRule, can, tokenize } from '../deploy/onprem/pocketbase/rules_eval.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(
  readFileSync(join(here, '../deploy/onprem/pocketbase/pb_schema.json'), 'utf8'),
);
const col = (name) => schema.find((c) => c.name === name);

const NOW = '2026-07-11T12:00:00.000Z';

// ── Personas ────────────────────────────────────────────────────────────────
const owner = { id: 'u_owner', role: 'company_owner', disabled: false };
const pm = { id: 'u_pm', role: 'production_manager', disabled: false };
const supA = { id: 'u_supA', role: 'supervisor', usine: 'Usine A', disabled: false };
const supB = { id: 'u_supB', role: 'supervisor', usine: 'Usine B', disabled: false };
const supDisabled = { id: 'u_supA', role: 'supervisor', usine: 'Usine A', disabled: true };
const vendorActive = {
  id: 'u_vendor', role: 'vendor_support', disabled: false,
  vendorAccessExpiresAt: '2026-12-31T00:00:00.000Z',
};
const vendorExpired = {
  id: 'u_vendor', role: 'vendor_support', disabled: false,
  vendorAccessExpiresAt: '2026-01-01T00:00:00.000Z',
};
const vendorDefault = { id: 'u_vendor', role: 'vendor_support', disabled: true };
const anon = { id: '' };

const alertA = { id: 'al1', usine: 'Usine A', superviseurId: '', status: 'disponible' };
const alertB = { id: 'al2', usine: 'Usine B', superviseurId: '', status: 'disponible' };
const claimedByA = { id: 'al3', usine: 'Usine A', superviseurId: 'u_supA', status: 'en_cours' };

const ctx = (auth, record = {}, data = {}) => ({ auth, record, data, now: NOW });

describe('rules_eval interpreter', () => {
  test('tokenizes paths, operators and literals', () => {
    expect(tokenize('@request.auth.role = "supervisor" && usine = @request.auth.usine'))
      .toEqual(['@request.auth.role', '=', '"supervisor"', '&&', 'usine', '=', '@request.auth.usine']);
  });
  test('null rule is locked, empty rule is public', () => {
    expect(evalRule(null, ctx(owner))).toBe(false);
    expect(evalRule('', ctx(anon))).toBe(true);
  });
  test('date comparison uses ISO ordering against @now', () => {
    expect(evalRule('@request.auth.vendorAccessExpiresAt > @now', ctx(vendorActive))).toBe(true);
    expect(evalRule('@request.auth.vendorAccessExpiresAt > @now', ctx(vendorExpired))).toBe(false);
  });
});

describe('alerts collection', () => {
  const alerts = col('alerts');

  test('supervisors only see their own factory', () => {
    expect(can(alerts, 'view', ctx(supA, alertA))).toBe(true);
    expect(can(alerts, 'view', ctx(supA, alertB))).toBe(false);
    expect(can(alerts, 'view', ctx(supB, alertA))).toBe(false);
  });

  test('owner and PM see every factory', () => {
    for (const boss of [owner, pm]) {
      expect(can(alerts, 'view', ctx(boss, alertA))).toBe(true);
      expect(can(alerts, 'view', ctx(boss, alertB))).toBe(true);
    }
  });

  test('anonymous, disabled and vendor accounts are denied operational alerts', () => {
    expect(can(alerts, 'view', ctx(anon, alertA))).toBe(false);
    expect(can(alerts, 'view', ctx(supDisabled, alertA))).toBe(false);
    expect(can(alerts, 'view', ctx(vendorActive, alertA))).toBe(false);
  });

  test('supervisor can claim an unassigned alert in own factory only', () => {
    const claim = { superviseurId: 'u_supA' };
    expect(can(alerts, 'update', ctx(supA, alertA, claim))).toBe(true);
    expect(can(alerts, 'update', ctx(supA, alertB, claim))).toBe(false);
  });

  test('a supervisor cannot hijack a colleague\'s claimed alert', () => {
    expect(can(alerts, 'update', ctx(supB, { ...claimedByA, usine: 'Usine B' }, {}))).toBe(false);
    // the owner (managing role) still can intervene
    expect(can(alerts, 'update', ctx(owner, claimedByA, {}))).toBe(true);
  });

  test('nobody deletes alerts through the API', () => {
    for (const p of [owner, pm, supA, vendorActive]) {
      expect(can(alerts, 'delete', ctx(p, alertA))).toBe(false);
    }
  });

  test('supervisors cannot create alerts; owner/PM can', () => {
    expect(can(alerts, 'create', ctx(supA))).toBe(false);
    expect(can(alerts, 'create', ctx(pm))).toBe(true);
    expect(can(alerts, 'create', ctx(owner))).toBe(true);
  });
});

describe('users collection (account management)', () => {
  const users = col('users');

  test('only the company owner creates accounts', () => {
    expect(can(users, 'create', ctx(owner))).toBe(true);
    for (const p of [pm, supA, vendorActive, anon]) {
      expect(can(users, 'create', ctx(p))).toBe(false);
    }
  });

  test('self-service password change is allowed but role self-escalation is blocked', () => {
    const self = { id: 'u_supA' };
    expect(can(users, 'update', ctx(supA, self, { password: 'x', passwordConfirm: 'x', oldPassword: 'y' }))).toBe(true);
    expect(can(users, 'update', ctx(supA, self, { role: 'company_owner' }))).toBe(false);
    expect(can(users, 'update', ctx(supA, self, { disabled: false }))).toBe(false);
    expect(can(users, 'update', ctx(supA, self, { vendorAccessExpiresAt: '2030-01-01' }))).toBe(false);
  });

  test('owner manages any account, including roles and vendor windows', () => {
    expect(can(users, 'update', ctx(owner, { id: 'u_supA' }, { role: 'production_manager' }))).toBe(true);
    expect(can(users, 'update', ctx(owner, { id: 'u_vendor' }, { vendorAccessExpiresAt: NOW }))).toBe(true);
  });

  test('owner cannot delete their own account (no lock-out)', () => {
    expect(can(users, 'delete', ctx(owner, { id: 'u_owner' }))).toBe(false);
    expect(can(users, 'delete', ctx(owner, { id: 'u_supA' }))).toBe(true);
  });

  test('PM can list users (rosters) but a supervisor only reads self', () => {
    expect(can(users, 'view', ctx(pm, { id: 'u_supA' }))).toBe(true);
    expect(can(users, 'view', ctx(supA, { id: 'u_supA' }))).toBe(true);
    expect(can(users, 'view', ctx(supA, { id: 'u_supB' }))).toBe(false);
  });
});

describe('branding / connectors — company owner only', () => {
  test('branding: everyone signed-in reads, only owner writes', () => {
    const branding = col('branding');
    expect(can(branding, 'view', ctx(supA, {}))).toBe(true);
    expect(can(branding, 'update', ctx(owner, {}))).toBe(true);
    for (const p of [pm, supA, vendorActive, anon]) {
      expect(can(branding, 'update', ctx(p, {}))).toBe(false);
    }
  });

  test('connectors: PM cannot even list them (deployment concern, not ops)', () => {
    const connectors = col('connectors');
    expect(can(connectors, 'list', ctx(owner))).toBe(true);
    for (const p of [pm, supA, vendorActive, anon]) {
      expect(can(connectors, 'list', ctx(p))).toBe(false);
      expect(can(connectors, 'update', ctx(p))).toBe(false);
    }
  });

  test('connector secrets are write-only: no role can read them back', () => {
    const secrets = col('connector_secrets');
    expect(can(secrets, 'create', ctx(owner))).toBe(true);
    for (const p of [owner, pm, supA, vendorActive]) {
      expect(can(secrets, 'view', ctx(p))).toBe(false);
      expect(can(secrets, 'list', ctx(p))).toBe(false);
      expect(can(secrets, 'delete', ctx(p))).toBe(false);
    }
  });

  test('no deployment-secret collection exists in the schema at all', () => {
    // TLS keys, admin passwords, worker shared secrets and license keys live
    // in the host .env / encrypted store — never in PocketBase.
    const names = schema.map((c) => c.name);
    expect(names).toEqual(expect.not.arrayContaining(['deployment_secrets', 'env', 'secrets']));
  });
});

describe('audit_logs — append-only and author-pinned', () => {
  const audit = col('audit_logs');

  test('any active user can append, but only with their own actorId', () => {
    expect(can(audit, 'create', ctx(supA, {}, { actorId: 'u_supA' }))).toBe(true);
    expect(can(audit, 'create', ctx(supA, {}, { actorId: 'u_owner' }))).toBe(false);
    expect(can(audit, 'create', ctx(supDisabled, {}, { actorId: 'u_supA' }))).toBe(false);
  });

  test('records are immutable and only the owner reads the trail', () => {
    expect(can(audit, 'update', ctx(owner, {}))).toBe(false);
    expect(can(audit, 'delete', ctx(owner, {}))).toBe(false);
    expect(can(audit, 'list', ctx(owner))).toBe(true);
    expect(can(audit, 'list', ctx(pm))).toBe(false);
  });
});

describe('vendor_support — disabled by default, time-limited, diagnostics only', () => {
  const seclogs = col('security_logs');

  test('active window grants read-only diagnostics', () => {
    expect(can(seclogs, 'view', ctx(vendorActive, {}))).toBe(true);
  });

  test('expired or default-disabled vendor accounts get nothing', () => {
    expect(can(seclogs, 'view', ctx(vendorExpired, {}))).toBe(false);
    expect(can(seclogs, 'view', ctx(vendorDefault, {}))).toBe(false);
  });

  test('vendor accounts can never write anywhere in the schema', () => {
    for (const c of schema) {
      for (const op of ['create', 'update', 'delete']) {
        const allowed = can(c, op, ctx(vendorActive, { id: 'someone-elses' }, {}));
        expect({ collection: c.name, op, allowed }).toEqual(
          { collection: c.name, op, allowed: false },
        );
      }
    }
  });
});

describe('escalation_settings — factory operations stay with PM', () => {
  const esc = col('escalation_settings');
  test('PM manages escalation policy, supervisor does not', () => {
    expect(can(esc, 'update', ctx(pm, {}))).toBe(true);
    expect(can(esc, 'update', ctx(supA, {}))).toBe(false);
  });
});
