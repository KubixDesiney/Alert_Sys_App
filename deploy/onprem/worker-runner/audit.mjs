// Worker-side audit trail: every automated action (assignment, escalation,
// ingest, retention, backup, license transitions) lands in the PocketBase
// `audit_logs` collection AND a local append-only JSONL file, so the trail
// survives even a database restore.
import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export class AuditTrail {
  constructor(store, { file = null, actor = 'worker-runner', log = null } = {}) {
    this.store = store;
    this.file = file;
    this.actor = actor;
    this.log = log;
  }

  /** Never throws — an audit failure must not break the automated action. */
  async record(action, { targetType = 'system', targetId, factoryId, detail } = {}) {
    const entry = {
      at: new Date().toISOString(),
      action,
      actorId: this.actor,
      actorName: this.actor,
      targetType,
      ...(targetId ? { targetId } : {}),
      ...(factoryId ? { factoryId } : {}),
      ...(detail ? { detail } : {}),
    };
    try {
      if (this.store && typeof this.store.addAudit === 'function') {
        await this.store.addAudit(entry);
      }
    } catch (err) {
      if (this.log) this.log.warn('audit db write failed', { err: String((err && err.message) || err) });
    }
    try {
      if (this.file) {
        mkdirSync(dirname(this.file), { recursive: true });
        appendFileSync(this.file, `${JSON.stringify(entry)}\n`);
      }
    } catch (_) { /* local disk best-effort */ }
    return entry;
  }

  /** Bound helper matching the (action, fields) shape modules expect. */
  bind() {
    return (action, fields) => this.record(action, fields);
  }
}
