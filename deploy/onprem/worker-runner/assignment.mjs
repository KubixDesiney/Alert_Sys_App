// On-prem assignment cycle. Reuses the SAME pure scoring as the cloud worker
// (buildSupStats + scoreSupervisor are injected) so on-prem and cloud assign
// identically — no algorithm drift.

const ACTIVE_STATES = new Set(['active', 'available', 'online', 'ready']);

export function isActiveSupervisor(u) {
  if (!u) return false;
  const role = String(u.role || '').toLowerCase();
  if (role && role !== 'supervisor') return false;
  if (u.active === true || u.isActive === true) return true;
  return ACTIVE_STATES.has(String(u.status || '').toLowerCase());
}

export function eligibleSupervisors(alert, users, activeCounts = {}) {
  const factory = String(alert.usine || '').trim().toLowerCase();
  return users.filter((u) => {
    if (!isActiveSupervisor(u)) return false;
    if ((activeCounts[u.uid] || 0) > 0) return false; // one active claim at a time
    const uf = String(u.usine || '').trim().toLowerCase();
    return !factory || uf === factory;
  });
}

function alertsToMap(alerts) {
  const m = {};
  for (const a of alerts) m[a.id] = a;
  return m;
}
function fullName(u) {
  return [u.firstName, u.lastName].filter(Boolean).join(' ') || u.uid;
}

/** Run one assignment pass. `scoring` = { buildSupStats, scoreSupervisor }. */
export async function runAssignmentCycle(store, scoring, now = Date.now()) {
  const users = await store.listUsers();
  const alerts = await store.listAlerts();
  const activeCounts = await store.activeCounts();
  const stats = scoring.buildSupStats(alertsToMap(alerts));
  const pending = alerts.filter((a) => a && a.status === 'disponible' && !a.superviseurId);
  let assigned = 0;
  const decisions = [];
  for (const alert of pending) {
    let best = null;
    for (const s of eligibleSupervisors(alert, users, activeCounts)) {
      const r = scoring.scoreSupervisor(
        s, alert, stats[s.uid] || {}, {}, activeCounts[s.uid] || 0, now,
      );
      if (!best || r.score > best.score) {
        best = { uid: s.uid, name: fullName(s), score: r.score, reason: (r.reasons || []).join('; ') };
      }
    }
    if (best) {
      await store.assign(alert.id, best.uid, best.name, best.reason);
      activeCounts[best.uid] = (activeCounts[best.uid] || 0) + 1; // no double-assign this cycle
      assigned++;
      decisions.push({ alertId: alert.id, uid: best.uid, score: best.score });
    }
  }
  return { pending: pending.length, assigned, decisions };
}
