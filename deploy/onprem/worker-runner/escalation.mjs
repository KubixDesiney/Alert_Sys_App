// On-prem escalation cycle. Mirrors the cloud worker's escalation_settings logic
// (per-type unclaimedMinutes / claimedMinutes, with a `default` fallback).

export function minutesSince(ts, now) {
  let ms = null;
  if (typeof ts === 'number') ms = ts;
  else if (typeof ts === 'string') {
    const p = Date.parse(ts);
    if (!Number.isNaN(p)) ms = p;
  }
  if (ms == null) return null;
  return (now - ms) / 60000;
}

/** Pure: returns [{id, reason}] for alerts that should escalate. */
export function findEscalations(alerts, settings, now = Date.now()) {
  const out = [];
  if (!settings || !Array.isArray(alerts)) return out;
  for (const alert of alerts) {
    if (!alert || alert.isEscalated) continue;
    if (alert.status !== 'disponible' && alert.status !== 'en_cours') continue;
    let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
    if (!threshold && settings.default) threshold = settings.default;
    if (!threshold) continue;
    let reason = null;
    if (alert.status === 'disponible') {
      const mins = minutesSince(alert.timestamp, now);
      if (mins != null && typeof threshold.unclaimedMinutes === 'number' && mins >= threshold.unclaimedMinutes) {
        reason = `Unclaimed for ${Math.floor(mins)} minutes`;
      }
    } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
      const mins = minutesSince(alert.takenAtTimestamp, now);
      if (mins != null && typeof threshold.claimedMinutes === 'number' && mins >= threshold.claimedMinutes) {
        reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
      }
    }
    if (reason) out.push({ id: alert.id, reason });
  }
  return out;
}

export async function runEscalationCycle(store, now = Date.now()) {
  const settings = await store.getEscalationSettings();
  const alerts = await store.listAlerts();
  const items = findEscalations(alerts, settings, now);
  for (const e of items) await store.escalate(e.id, e.reason);
  return { escalated: items.length, items };
}
