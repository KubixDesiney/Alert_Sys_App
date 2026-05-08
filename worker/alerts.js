import { MAX_ALERTS_TO_PUSH } from './config.js';
import { getFcmTokensForFactory, sendFcm } from './fcm.js';

async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;
  // Filter directly from the already-loaded alertsMap – avoids a second
  // Firebase REST round-trip and removes the dependency on a Firebase
  // ".indexOn: push_sent" rule (missing index returns 400 → silent failure).
  const unsent = Object.entries(alertsMap || {})
    .filter(([, a]) => a && a.push_sent === false)
    .slice(0, MAX_ALERTS_TO_PUSH)
    .map(([id, a]) => ({
      id,
      type: a.type || 'Alert',
      usine: a.usine || '',
      description: a.description || '',
    }));
  if (!unsent.length) return;
  for (const alert of unsent) {
    const flagUrl = `${env.FB_DB_URL}alerts/${alert.id}/push_sent.json?auth=${token}`;
    const getRes = await fetch(flagUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) continue;
    const etag = getRes.headers.get('ETag');
    const current = await getRes.json();
    if (current !== false) continue;
    const claimRes = await fetch(flagUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag },
      body: JSON.stringify('sending'),
    });
    if (claimRes.status === 412 || !claimRes.ok) continue;
    // New-alert push: notify ALL supervisors in this factory, regardless of
    // whether they are currently handling another alert.
    const fcmTokens = getFcmTokensForFactory(alert.usine, usersMap, alertsMap, { allSupervisors: true });
    if (fcmTokens.length === 0) {
      await fetch(flagUrl, { method: 'PUT', body: JSON.stringify(false) });
      continue;
    }
    let allOk = true;
    for (const tok of fcmTokens) {
      const ok = await sendFcm(
        tok,
        `🚨 New Alert: ${alert.type}`,
        `${alert.usine} — ${alert.description}`,
        { alertId: alert.id, type: alert.type, usine: alert.usine },
        env,
      );
      if (!ok) allOk = false;
    }
    await fetch(flagUrl, { method: 'PUT', body: JSON.stringify(allOk ? true : false) });
  }
}

// ============ Escalation check ============

export { processAlerts };
