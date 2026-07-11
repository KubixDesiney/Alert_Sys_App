// On-prem notification targeting + LAN delivery (SSE). For air-gapped sites,
// devices subscribe over the LAN and the runner pushes events — no FCM needed.
import { isActiveSupervisor } from './assignment.mjs';

export function recipientsForNewAlert(alert, users, activeCounts = {}) {
  const factory = String(alert.usine || '').trim().toLowerCase();
  return users
    .filter((u) => isActiveSupervisor(u)
      && (activeCounts[u.uid] || 0) === 0
      && (!factory || String(u.usine || '').trim().toLowerCase() === factory))
    .map((u) => u.uid);
}

export function recipientsForEscalation(alert, users) {
  const set = new Set(
    users.filter((u) => ['admin', 'superadmin'].includes(String(u.role || '').toLowerCase()))
      .map((u) => u.uid),
  );
  if (alert && alert.superviseurId) set.add(alert.superviseurId);
  return [...set];
}

export function recipientsForAssignment(alert) {
  return alert && alert.superviseurId ? [alert.superviseurId] : [];
}

/** In-memory SSE hub: uid -> set of open responses. */
export class SseHub {
  constructor() { this.clients = new Map(); this._heartbeat = null; }

  /** Comment-line heartbeat keeps idle LAN connections open through proxies
   *  and lets clients detect a dead runner and reconnect (`retry:` is sent on
   *  connect). */
  startHeartbeat(intervalMs = 25000) {
    if (this._heartbeat) return;
    this._heartbeat = setInterval(() => {
      for (const set of this.clients.values()) {
        for (const res of set) {
          try { res.write(': ping\n\n'); } catch (_) { /* closed */ }
        }
      }
    }, intervalMs);
    if (this._heartbeat.unref) this._heartbeat.unref();
  }

  stopHeartbeat() {
    if (this._heartbeat) clearInterval(this._heartbeat);
    this._heartbeat = null;
  }
  connect(uid, res) {
    if (!this.clients.has(uid)) this.clients.set(uid, new Set());
    this.clients.get(uid).add(res);
    if (res && typeof res.on === 'function') {
      res.on('close', () => {
        const s = this.clients.get(uid);
        if (s) { s.delete(res); if (!s.size) this.clients.delete(uid); }
      });
    }
  }
  deliver(uid, event) {
    const s = this.clients.get(uid);
    if (!s) return 0;
    const payload = `data: ${JSON.stringify(event)}\n\n`;
    let n = 0;
    for (const res of s) { try { res.write(payload); n++; } catch (_) { /* drop */ } }
    return n;
  }
  broadcast(uids, event) {
    let n = 0;
    for (const uid of uids) n += this.deliver(uid, event);
    return n;
  }
  connectedCount() {
    let n = 0;
    for (const s of this.clients.values()) n += s.size;
    return n;
  }
}
