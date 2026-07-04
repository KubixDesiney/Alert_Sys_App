import fs from 'node:fs';
import { describe, expect, test } from '@jest/globals';

const rules = JSON.parse(
  fs.readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'),
).rules;

class RuleNode {
  constructor(value) {
    this.value = value;
  }

  child(key) {
    if (this.value && typeof this.value === 'object' && Object.prototype.hasOwnProperty.call(this.value, key)) {
      return new RuleNode(this.value[key]);
    }
    return new RuleNode(undefined);
  }

  val() {
    return this.exists() ? this.value : null;
  }

  exists() {
    return this.value !== undefined && this.value !== null;
  }

  isString() {
    return typeof this.value === 'string';
  }

  isNumber() {
    return typeof this.value === 'number' && Number.isFinite(this.value);
  }

  isBoolean() {
    return typeof this.value === 'boolean';
  }

  hasChildren(keys) {
    return this.value && typeof this.value === 'object' && keys.every((key) => this.child(key).exists());
  }
}

function user(uid, token = {}) {
  return uid ? { uid, token } : null;
}

function companyDb(users) {
  return {
    users: Object.fromEntries(
      Object.entries(users).map(([uid, role]) => [uid, { role }]),
    ),
  };
}

function evaluate(rule, { auth = null, rootData = {}, data = undefined, newData = undefined, vars = {} } = {}) {
  if (typeof rule === 'boolean') return rule;
  const names = ['auth', 'root', 'data', 'newData', ...Object.keys(vars)];
  const values = [auth, new RuleNode(rootData), new RuleNode(data), new RuleNode(newData), ...Object.values(vars)];
  return Boolean(Function(...names, `"use strict"; return (${rule});`)(...values));
}

const companies = {
  steelco: {
    root: companyDb({
      steelSuper: 'superadmin',
      steelAdmin: 'admin',
      steelSupervisor: 'supervisor',
      steelOperator: 'operator',
    }),
    superadmin: user('steelSuper'),
    admin: user('steelAdmin'),
    supervisor: user('steelSupervisor'),
    operator: user('steelOperator'),
  },
  pharma: {
    root: companyDb({
      pharmaSuper: 'SuperAdmin',
      pharmaAdmin: 'admin',
      pharmaSupervisor: 'supervisor',
    }),
    superadmin: user('pharmaSuper'),
    admin: user('pharmaAdmin'),
    supervisor: user('pharmaSupervisor'),
  },
};

const serviceAuth = user('worker-service', { role: 'admin' });

describe('Firebase rules company database template behavior', () => {
  test('Superadmin configuration paths are writable only by company superadmins', () => {
    for (const company of Object.values(companies)) {
      expect(evaluate(rules.auth_config['.write'], { auth: company.superadmin, rootData: company.root })).toBe(true);
      expect(evaluate(rules.monitoring_config['.write'], { auth: company.superadmin, rootData: company.root })).toBe(true);
      expect(evaluate(rules.infra_config['.write'], { auth: company.superadmin, rootData: company.root })).toBe(true);
      expect(evaluate(rules.branding_config['.write'], { auth: company.superadmin, rootData: company.root })).toBe(true);

      expect(evaluate(rules.auth_config['.write'], { auth: company.admin, rootData: company.root })).toBe(false);
      expect(evaluate(rules.monitoring_config['.write'], { auth: company.supervisor, rootData: company.root })).toBe(false);
      expect(evaluate(rules.infra_config['.write'], { auth: serviceAuth, rootData: company.root })).toBe(false);
    }

    expect(evaluate(rules.auth_config['.read'], { auth: null, rootData: companies.steelco.root })).toBe(true);
    expect(evaluate(rules.branding_config['.read'], { auth: null, rootData: companies.pharma.root })).toBe(true);
  });

  test('Role checks are scoped to the active company database root', () => {
    const steelAdminInSteelDb = { auth: companies.steelco.admin, rootData: companies.steelco.root };
    const steelAdminInPharmaDb = { auth: companies.steelco.admin, rootData: companies.pharma.root };

    expect(evaluate(rules.assets['.write'], steelAdminInSteelDb)).toBe(true);
    expect(evaluate(rules.factories.$factoryId.aiConfig['.write'], steelAdminInSteelDb)).toBe(true);

    expect(evaluate(rules.assets['.write'], steelAdminInPharmaDb)).toBe(false);
    expect(evaluate(rules.factories.$factoryId.aiConfig['.write'], steelAdminInPharmaDb)).toBe(false);

    // The worker service token is a per-deployment credential injected into the
    // configured company database runtime, not a customer user record.
    expect(evaluate(rules.assets['.write'], { auth: serviceAuth, rootData: companies.pharma.root })).toBe(true);
  });

  test('User records allow self, company admins, company superadmins, and service token only', () => {
    const expr = rules.users.$userId['.write'];

    expect(evaluate(expr, {
      auth: user('steelOperator'),
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(true);
    expect(evaluate(expr, {
      auth: companies.steelco.admin,
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(true);
    expect(evaluate(expr, {
      auth: companies.steelco.superadmin,
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(true);
    expect(evaluate(expr, {
      auth: serviceAuth,
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(true);

    expect(evaluate(expr, {
      auth: companies.pharma.admin,
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(false);
    expect(evaluate(expr, {
      auth: companies.steelco.supervisor,
      rootData: companies.steelco.root,
      vars: { $userId: 'steelOperator' },
    })).toBe(false);
  });

  test('Credential vault and security telemetry separate read and write authority', () => {
    const steel = companies.steelco;

    // The credential vault is write-only from the client: a superadmin may set a
    // secret but can never read it back (only the worker, via its admin OAuth
    // token, bypasses rules to read it).
    expect(evaluate(rules.ai_agent_secrets['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.ai_agent_secrets['.write'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.ai_agent_secrets['.write'], { auth: steel.admin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.ai_agent_secrets['.write'], { auth: serviceAuth, rootData: steel.root })).toBe(false);

    expect(evaluate(rules.security.logs['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.security.logs['.read'], { auth: steel.admin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.security.logs['.write'], { auth: steel.superadmin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.security.logs['.write'], { auth: serviceAuth, rootData: steel.root })).toBe(true);
  });

  test('Dangerous writes are denied by validation and append-only audit rules', () => {
    const appendOwnAudit = {
      at: '2026-06-16T00:00:00.000Z',
      actorId: 'steelSupervisor',
      action: 'alert.acknowledge',
    };
    const spoofedAudit = { ...appendOwnAudit, actorId: 'steelOperator' };
    const auditWrite = rules.audit_log.$entryId['.write'];

    expect(evaluate(auditWrite, {
      auth: companies.steelco.supervisor,
      rootData: companies.steelco.root,
      data: undefined,
      newData: appendOwnAudit,
    })).toBe(true);
    expect(evaluate(auditWrite, {
      auth: companies.steelco.supervisor,
      rootData: companies.steelco.root,
      data: undefined,
      newData: spoofedAudit,
    })).toBe(false);
    expect(evaluate(auditWrite, {
      auth: companies.steelco.supervisor,
      rootData: companies.steelco.root,
      data: appendOwnAudit,
      newData: appendOwnAudit,
    })).toBe(false);

    expect(evaluate(rules.alerts.$alertId.push_sent['.validate'], { newData: true })).toBe(true);
    expect(evaluate(rules.alerts.$alertId.push_sent['.validate'], { newData: 'true' })).toBe(false);
    expect(evaluate(rules.ai_agents.$agentId.promptTemplate['.validate'], { newData: 'x'.repeat(8001) })).toBe(false);
    expect(evaluate(rules.audit_log.$entryId.$other['.validate'], { newData: 'unexpected' })).toBe(false);
  });

  test('Alert writes require authentication (no anonymous create path)', () => {
    const steel = companies.steelco;
    const alertWrite = rules.alerts.$alertId['.write'];
    const sample = {
      adresse: 'A1', convoyeur: 1, poste: 2,
      timestamp: '2026-06-27T00:00:00.000Z', type: 'mechanical', usine: 'Usine A',
    };
    // Anonymous create is no longer permitted, even with a well-formed payload.
    expect(evaluate(alertWrite, {
      auth: null, rootData: steel.root, data: undefined, newData: sample, vars: { $alertId: 'a1' },
    })).toBe(false);
    // Privileged producers (PM admins, the worker service token) still write.
    expect(evaluate(alertWrite, {
      auth: steel.admin, rootData: steel.root, data: undefined, newData: sample, vars: { $alertId: 'a1' },
    })).toBe(true);
    expect(evaluate(alertWrite, {
      auth: serviceAuth, rootData: steel.root, data: undefined, newData: sample, vars: { $alertId: 'a1' },
    })).toBe(true);
  });

  test('Supervisor alert writes are ownership-scoped', () => {
    const steel = companies.steelco;
    const alertWrite = rules.alerts.$alertId['.write'];
    const supervisor = steel.supervisor; // uid: steelSupervisor
    const base = { rootData: steel.root, auth: supervisor, vars: { $alertId: 'a1' } };
    const unassigned = { status: 'disponible', usine: 'Usine A' };
    const ownedBySelf = { ...unassigned, status: 'en_cours', superviseurId: 'steelSupervisor' };
    const ownedByOther = { ...unassigned, status: 'en_cours', superviseurId: 'someoneElse' };

    // Claiming an unassigned alert for yourself: allowed.
    expect(evaluate(alertWrite, {
      ...base, data: unassigned, newData: { ...unassigned, superviseurId: 'steelSupervisor' },
    })).toBe(true);
    // Updating an alert you own (resolve, comment, return to queue): allowed.
    expect(evaluate(alertWrite, {
      ...base, data: ownedBySelf, newData: { ...ownedBySelf, status: 'validee' },
    })).toBe(true);
    // Touching someone else's alert — including stealing the claim: denied.
    expect(evaluate(alertWrite, {
      ...base, data: ownedByOther, newData: { ...ownedByOther, superviseurId: 'steelSupervisor' },
    })).toBe(false);
    expect(evaluate(alertWrite, {
      ...base, data: ownedByOther, newData: { ...ownedByOther, isCritical: true },
    })).toBe(false);
    // Accepting help: self-assignment as assistant on an assistant-less alert.
    expect(evaluate(alertWrite, {
      ...base, data: ownedByOther, newData: { ...ownedByOther, assistantId: 'steelSupervisor' },
    })).toBe(true);
    // Acting on your own AI recommendation (accept or reject): allowed —
    // the grant keys off the existing data, so clearing the recommendation
    // in the same write is fine.
    expect(evaluate(alertWrite, {
      ...base,
      data: { ...unassigned, aiRecommendedSupervisorId: 'steelSupervisor' },
      newData: { ...unassigned, aiRecommendationStatus: 'rejected' },
    })).toBe(true);
    // A supervisor who was NOT recommended cannot use that branch.
    expect(evaluate(alertWrite, {
      ...base,
      data: { ...unassigned, aiRecommendedSupervisorId: 'someoneElse' },
      newData: { ...unassigned, aiRecommendationStatus: 'rejected' },
    })).toBe(false);
    // Deleting an alert: never allowed for supervisors, fine for admins.
    expect(evaluate(alertWrite, { ...base, data: ownedBySelf, newData: undefined })).toBe(false);
    expect(evaluate(alertWrite, {
      auth: steel.admin, rootData: steel.root, data: ownedBySelf, newData: undefined, vars: { $alertId: 'a1' },
    })).toBe(true);
    // Collaboration-shared alerts stay writable for the collaborator.
    const rootWithCollab = {
      ...steel.root,
      collaboration_alerts: { steelSupervisor: { a1: true } },
    };
    expect(evaluate(alertWrite, {
      ...base, rootData: rootWithCollab, data: ownedByOther,
      newData: { ...ownedByOther, comments: { c1: 'on my way' } },
    })).toBe(true);
  });

  test('LLM provider keys live in a worker-only vault the client cannot read', () => {
    const steel = companies.steelco;

    // Non-secret model selection: worker + superadmin read, superadmin write,
    // plain app-admin denied.
    expect(evaluate(rules.ai_model_config['.read'], { auth: serviceAuth, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.ai_model_config['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.ai_model_config['.read'], { auth: steel.admin, rootData: steel.root })).toBe(false);

    // Secret vault: unreadable by any rule-bound auth, including the worker's own
    // admin-claim idToken; the worker reads it via OAuth, which bypasses rules.
    // Superadmin writes but cannot read; plain admin gets nothing either way.
    expect(evaluate(rules.ai_model_secrets['.read'], { auth: serviceAuth, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.ai_model_secrets['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.ai_model_secrets['.read'], { auth: steel.admin, rootData: steel.root })).toBe(false);
    expect(evaluate(rules.ai_model_secrets['.write'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.ai_model_secrets['.write'], { auth: steel.admin, rootData: steel.root })).toBe(false);
  });

  test('Connector PLC/historian credentials are worker-only; only the ingest key is retrievable', () => {
    const steel = companies.steelco;
    // The whole vault is unreadable by clients (worker bypasses via OAuth).
    expect(evaluate(rules.connector_secrets['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(false);
    // The per-connector edge-push ingest key is the one value the operator must
    // retrieve to configure a gateway, so it stays superadmin-readable.
    expect(evaluate(rules.connector_secrets.$connectorId.ingestKey['.read'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
    expect(evaluate(rules.connector_secrets.$connectorId.ingestKey['.read'], { auth: steel.admin, rootData: steel.root })).toBe(false);
    // Superadmin can still write the credentials.
    expect(evaluate(rules.connector_secrets['.write'], { auth: steel.superadmin, rootData: steel.root })).toBe(true);
  });

  test('Disabled shared provisioning and SCIM writes stay denied in the template', () => {
    expect(evaluate(rules.scim['.write'], { auth: companies.steelco.superadmin, rootData: companies.steelco.root })).toBe(false);
    expect(evaluate(rules.provisioning['.write'], { auth: companies.steelco.superadmin, rootData: companies.steelco.root })).toBe(false);
    expect(rules.companies).toBeUndefined();
  });
});
