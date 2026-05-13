import { getFirebaseToken } from './auth.js';
import { pickActiveShift } from './utils.js';

async function loadCoreData(env) {
  const token = await getFirebaseToken(env);
  const [alertsRes, usersRes, shiftsRes, activeClaimsRes] = await Promise.all([
    fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}shifts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}supervisor_active_alerts.json?auth=${token}`),
  ]);
  const shiftsMap = shiftsRes.ok ? ((await shiftsRes.json()) || {}) : {};
  return {
    token,
    alertsMap: alertsRes.ok ? ((await alertsRes.json()) || {}) : {},
    usersMap: usersRes.ok ? ((await usersRes.json()) || {}) : {},
    shiftsMap,
    supervisorActiveAlertsMap: activeClaimsRes.ok ? ((await activeClaimsRes.json()) || {}) : {},
    activeShift: pickActiveShift(shiftsMap, new Date()),
  };
}

// ============ FCM tokens for a factory ============
// allSupervisors=true → notify every supervisor in the factory (new alerts).
// allSupervisors=false → skip supervisors who already own an in-progress alert
//                        (used for escalations / AI-assignment notifications).

export { loadCoreData };
