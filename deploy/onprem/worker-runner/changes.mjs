// Snapshot differ: turns consecutive alert-list snapshots into lifecycle
// events. This is how the on-prem runner replaces the Firebase-client side
// effects (new-alert buzz, critical broadcast, suspend notice) — the client
// no longer fans anything out; the runner watches the data and pushes.
export class ChangeWatcher {
  constructor() {
    this.prev = null; // Map<id, {status,isCritical,superviseurId}>
  }

  /** @returns {Array<{type:string, alert:object}>} */
  diff(alerts) {
    const cur = new Map();
    for (const a of alerts) {
      if (a && a.id != null) {
        cur.set(a.id, {
          status: a.status,
          isCritical: !!a.isCritical,
          superviseurId: a.superviseurId || '',
          alert: a,
        });
      }
    }
    const events = [];
    if (this.prev !== null) {
      for (const [id, now] of cur) {
        const before = this.prev.get(id);
        if (!before) {
          events.push({ type: 'new_alert', alert: now.alert });
          if (now.isCritical) events.push({ type: 'critical_update', alert: now.alert });
          continue;
        }
        if (!before.isCritical && now.isCritical) {
          events.push({ type: 'critical_update', alert: now.alert });
        }
        if (before.status === 'en_cours' && now.status === 'disponible') {
          events.push({ type: 'alert_suspended', alert: now.alert, previousSupervisorId: before.superviseurId });
        }
        if (before.status !== 'validee' && now.status === 'validee') {
          events.push({ type: 'alert_resolved', alert: now.alert });
        }
        if (!before.superviseurId && now.superviseurId && now.status === 'en_cours') {
          events.push({ type: 'alert_claimed', alert: now.alert });
        }
      }
    }
    this.prev = new Map([...cur].map(([id, v]) => [id, { status: v.status, isCritical: v.isCritical, superviseurId: v.superviseurId }]));
    return events;
  }
}
