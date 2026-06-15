// Pluggable data store for the on-prem worker-runner.
// MemoryStore = tests/dev. PocketBaseStore = self-hosted PocketBase backend.

export class MemoryStore {
  constructor({ users = [], alerts = [], active = {}, escalationSettings = {} } = {}) {
    this.users = users;
    this.alerts = alerts;
    this._active = { ...active };
    this.escalationSettings = escalationSettings;
  }
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
}

export class PocketBaseStore {
  constructor(baseUrl, token) {
    this.base = String(baseUrl || '').replace(/\/+$/, '');
    this.token = token || '';
  }
  _headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.token) h.Authorization = this.token;
    return h;
  }
  async _list(collection) {
    const r = await fetch(
      `${this.base}/api/collections/${collection}/records?perPage=500`,
      { headers: this._headers() },
    );
    if (!r.ok) throw new Error(`PB list ${collection}: ${r.status}`);
    return (await r.json()).items || [];
  }
  async _patchAlert(alertId, body) {
    const r = await fetch(`${this.base}/api/collections/alerts/records/${alertId}`, {
      method: 'PATCH', headers: this._headers(), body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`PB patch ${alertId}: ${r.status}`);
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
    try { return (await this._list('escalation_settings'))[0] || {}; } catch (_) { return {}; }
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
}
