// Retention & cleanup: bounds the working set the per-minute cycles scan.
// Terminal (validee) alerts older than `retentionDays` are archived (JSON
// handed to the `archive` sink — the backup module writes it next to the
// snapshots) and then deleted; stale notifications are purged.

const DAY_MS = 24 * 60 * 60 * 1000;

function tsOf(v) {
  const p = Date.parse(String(v || ''));
  return Number.isNaN(p) ? null : p;
}

export function findExpiredAlerts(alerts, { retentionDays = 365, now = Date.now() } = {}) {
  const cutoff = now - retentionDays * DAY_MS;
  return alerts.filter((a) => {
    if (!a || a.status !== 'validee') return false; // only terminal alerts
    const t = tsOf(a.resolvedAt) ?? tsOf(a.timestamp);
    return t != null && t < cutoff;
  });
}

export function findExpiredNotifications(notifications, { notificationDays = 30, now = Date.now() } = {}) {
  const cutoff = now - notificationDays * DAY_MS;
  return notifications.filter((n) => {
    const t = tsOf(n && (n.createdAt || n.created));
    return t != null && t < cutoff;
  });
}

export async function runRetentionCycle(store, {
  retentionDays = 365,
  notificationDays = 30,
  batchCap = 200,
  now = Date.now(),
  archive = async () => {},
  audit = async () => {},
} = {}) {
  const alerts = await store.listAlerts();
  const expired = findExpiredAlerts(alerts, { retentionDays, now }).slice(0, batchCap);

  let alertsDeleted = 0;
  if (expired.length) {
    await archive('alerts_archive', expired); // archive BEFORE delete — never lose data
    for (const a of expired) {
      await store.deleteAlert(a.id);
      alertsDeleted++;
    }
  }

  let notificationsDeleted = 0;
  if (typeof store.listNotifications === 'function') {
    const stale = findExpiredNotifications(await store.listNotifications(), {
      notificationDays, now,
    }).slice(0, batchCap);
    for (const n of stale) {
      await store.deleteNotification(n.id);
      notificationsDeleted++;
    }
  }

  if (alertsDeleted || notificationsDeleted) {
    await audit('retention.cycle', {
      detail: `archived+deleted ${alertsDeleted} alerts, purged ${notificationsDeleted} notifications`,
    });
  }
  return { alertsArchived: expired.length, alertsDeleted, notificationsDeleted };
}
