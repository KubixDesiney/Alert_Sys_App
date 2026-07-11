// Pluggable data store for the on-prem worker-runner.
// MemoryStore = tests/dev. PocketBaseStore = self-hosted PocketBase backend.
import { withRetry, retryableHttp } from './retry.mjs';

export class MemoryStore {
  constructor({ users = [], alerts = [], active = {}, escalationSettings = {}, notifications = [], auditLogs = [] } = {}) {
    this.users = users;
    this.alerts = alerts;
    this._active = { ...active };
    this.escalationSettings = escalationSettings;
    this.notifications = notifications;
    this.auditLogs = auditLogs;
    this._seq = 0;
  }
  async ping() { return true; }
  async listUsers() { return this.users; }
  async listAlerts() { return this.alerts; }
  async activeCounts() { return { ...this._active }; }
  async getEscalationSettings() { return this.escalationSettings; }
  async assign(alertId, uid, name, reason) {
    const a = this.alerts.find((x) => x.id === alertId);
    if (!a) return;
    a.status = 'en_cours';
    a.superviseurId = uid;
    a.superviseurName = name;
    a.aiAssigned = true;
    a.aiAssignmentReason = reason;
    this._active[uid] = (this._active[uid] || 0) + 1;
  }
  async escalate(alertId, reason) {
    const a = this.alerts.find((x) => x.id === alertId);
    if (!a) return;
    a.isEscalated = true;
    a.escalatedAt = new Date().toISOString();
    a.escalationReason = reason;
  }
  async createAlert(data) {
    const id = data.id || `mem-${++this._seq}`;
    this.alerts.push({ ...data, id });
    return id;
  }
  async deleteAlert(alertId) {
    this.alerts = this.alerts.filter((a) => a.id !== alertId);
  }
  async addNotification(n) {
    const id = n.id || `ntf-${++this._seq}`;
    this.notifications.push({ ...n, id });
    return id;
  }
  async listNotifications() { return this.notifications; }
  async deleteNotification(id) {
    this.notifications = this.notifications.filter((n) => n.id !== id);
  }
  async addAudit(entry) {
    this.auditLogs.push({ ...entry, id: `aud-${++this._seq}` });
  }
  async listCollection(name) {
    switch (name) {
      case 'alerts': return this.alerts;
      case 'users': return this.users;
      case 'notifications': return this.notifications;
      case 'audit_logs': return this.auditLogs;
      case 'escalation_settings': return [this.escalationSettings];
      default: return [];
    }
  }
  async restoreCollection(name, rows) {
    switch (name) {
      case 'alerts': this.alerts = [...rows]; break;
      case 'users': this.users = [...rows]; break;
      case 'notifications': this.notifications = [...rows]; break;
      case 'audit_logs': this.auditLogs = [...rows]; break;
      case 'escalation_settings': this.escalationSettings = rows[0] || {}; break;
      default: return 0;
    }
    return rows.length;
  }
}

export class PocketBaseStore {
  constructor(baseUrl, token, { retry = {} } = {}) {
    this.base = String(baseUrl || '').replace(/\/+$/, '');
    this.token = token || '';
    this.retry = { attempts: 3, baseMs: 200, shouldRetry: retryableHttp, ...retry };
  }
  _headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.token) h.Authorization = this.token;
    return h;
  }
  async _fetch(path, opts = {}) {
    return withRetry(async () => {
      const r = await fetch(`${this.base}${path}`, { headers: this._headers(), ...opts });
      if (!r.ok) {
        const err = new Error(`PB ${opts.method || 'GET'} ${path}: ${r.status}`);
        err.status = r.status;
        throw err;
      }
      return r;
    }, this.retry);
  }
  async ping() {
    try {
      const r = await fetch(`${this.base}/api/health`);
      return r.ok;
    } catch (_) { return false; }
  }
  async _list(collection) {
    const r = await this._fetch(`/api/collections/${collection}/records?perPage=500`);
    return (await r.json()).items || [];
  }
  async _post(collection, body) {
    const r = await this._fetch(`/api/collections/${collection}/records`, {
      method: 'POST', body: JSON.stringify(body),
    });
    return r.json();
  }
  async _patchAlert(alertId, body) {
    await this._fetch(`/api/collections/alerts/records/${alertId}`, {
      method: 'PATCH', body: JSON.stringify(body),
    });
  }
  async _delete(collection, id) {
    await this._fetch(`/api/collections/${collection}/records/${id}`, { method: 'DELETE' });
  }
  async listUsers() { return (await this._list('users')).map((u) => ({ uid: u.id, ...u })); }
  async listAlerts() { return (await this._list('alerts')).map((a) => ({ id: a.id, ...a })); }
  async activeCounts() {
    const out = {};
    for (const r of await this._list('supervisor_active_alerts')) {
      if (r.supervisorId) out[r.supervisorId] = (out[r.supervisorId] || 0) + 1;
    }
    return out;
  }
  async getEscalationSettings() {
    try {
      const first = (await this._list('escalation_settings'))[0] || {};
      return first.settings && typeof first.settings === 'object' ? first.settings : first;
    } catch (_) { return {}; }
  }
  async assign(alertId, uid, name, reason) {
    await this._patchAlert(alertId, {
      status: 'en_cours', superviseurId: uid, superviseurName: name,
      aiAssigned: true, aiAssignmentReason: reason,
    });
  }
  async escalate(alertId, reason) {
    await this._patchAlert(alertId, {
      isEscalated: true, escalatedAt: new Date().toISOString(), escalationReason: reason,
    });
  }
  async createAlert(data) {
    const created = await this._post('alerts', data);
    return created && created.id;
  }
  async deleteAlert(alertId) { await this._delete('alerts', alertId); }
  async addNotification(n) {
    const created = await this._post('notifications', n);
    return created && created.id;
  }
  async listNotifications() { return this._list('notifications'); }
  async deleteNotification(id) { await this._delete('notifications', id); }
  async addAudit(entry) { await this._post('audit_logs', entry); }
  async listCollection(name) { return this._list(name); }
  async restoreCollection(name, rows) {
    let n = 0;
    for (const row of rows) {
      try {
        const { id, collectionId, collectionName, ...body } = row;
        if (id) {
          try {
            await this._fetch(`/api/collections/${name}/records/${id}`, {
              method: 'PATCH', body: JSON.stringify(body),
            });
          } catch (err) {
            if (err && err.status === 404) await this._post(name, { ...body, id });
            else throw err;
          }
        } else {
          await this._post(name, body);
        }
        n++;
      } catch (_) { /* keep restoring the rest */ }
    }
    return n;
  }
}
