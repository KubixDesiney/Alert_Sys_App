import { MAX_ESCALATION_CHECKS } from './config.js';
import { getFcmRecipientsForFactory, sendFcmDetailed } from './fcm.js';

async function checkEscalations(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;
  const settingsRes = await fetch(`${env.FB_DB_URL}escalation_settings.json?auth=${token}`);
  if (!settingsRes.ok) {
    console.error('[ESCALATION] Failed to fetch escalation_settings');
    return;
  }
  const settings = await settingsRes.json();
  if (!settings || typeof settings !== 'object') {
    console.error('[ESCALATION] escalation_settings empty or invalid');
    return;
  }
  const now = Date.now();

  // Pre-filter to only active, unescalated alerts so the MAX_ESCALATION_CHECKS
  // budget is not consumed by already-handled entries.
  const candidates = Object.entries(alertsMap).filter(
    ([, a]) => a && !a.isEscalated && a.status !== 'validee' && a.status !== 'cancelled',
  );

  let escalated = 0;
  for (const [alertId, alert] of candidates) {
    if (escalated >= MAX_ESCALATION_CHECKS) break;
    try {
      let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
      if (!threshold && settings.default) threshold = settings.default;
      if (!threshold) continue;

      let createdAtMs;
      if (typeof alert.timestamp === 'number') {
        createdAtMs = alert.timestamp;
      } else if (typeof alert.timestamp === 'string') {
        const parsed = Date.parse(alert.timestamp);
        if (isNaN(parsed)) continue;
        createdAtMs = parsed;
      } else { continue; }

      let shouldEscalate = false;
      let reason = '';
      if (alert.status === 'disponible') {
        const mins = (now - createdAtMs) / 60000;
        if (typeof threshold.unclaimedMinutes === 'number' && mins >= threshold.unclaimedMinutes) {
          shouldEscalate = true;
          reason = `Unclaimed for ${Math.floor(mins)} minutes`;
        }
      } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
        let takenMs;
        if (typeof alert.takenAtTimestamp === 'number') {
          takenMs = alert.takenAtTimestamp;
        } else {
          const parsed = Date.parse(alert.takenAtTimestamp);
          if (isNaN(parsed)) continue;
          takenMs = parsed;
        }
        const mins = (now - takenMs) / 60000;
        if (typeof threshold.claimedMinutes === 'number' && mins >= threshold.claimedMinutes) {
          shouldEscalate = true;
          reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
        }
      } else { continue; }

      if (!shouldEscalate) continue;

      const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
      });
      if (!patchRes.ok) {
        console.error(`[ESCALATION] Failed to patch alert ${alertId}: ${patchRes.status}`);
        continue;
      }
      try {
        await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event: 'escalated_worker', reason, timestamp: new Date().toISOString() }),
        });
      } catch (e) { console.error('[ESCALATION] Failed to write aiHistory: ' + e.message); }

      const escalMsg = `⚠️ Alert Escalated: ${alert.type}`;
      const escalBody = `${alert.usine} — ${alert.description}\n${reason}`;
      const escalData = {
        alertId,
        type: alert.type || '',
        usine: alert.usine || '',
        factoryId: String(alert.factoryId || ''),
        escalated: 'true',
        notifType: 'escalation',
      };
      const recipients = getFcmRecipientsForFactory(alert.factoryId || alert.usine || '', usersMap, alertsMap, {
        allSupervisors: true,
        allFactories: true,
        includeAdmins: true,
        requireActiveSupervisors: false,
      });
      const notifiedTokens = new Set();
      for (const recipient of recipients) {
        notifiedTokens.add(recipient.token);
        const result = await sendFcmDetailed(
          recipient.token,
          escalMsg,
          escalBody,
          { ...escalData, recipientId: recipient.uid },
          env,
          { firebaseAuthToken: token, uid: recipient.uid },
        );
        if (result.unregistered && usersMap?.[recipient.uid]?.fcmToken === recipient.token) {
          usersMap[recipient.uid].fcmToken = null;
        }
      }
      if (alert.status === 'en_cours' && alert.superviseurId) {
        const claimant = usersMap[alert.superviseurId];
        const claimantToken = claimant?.fcmToken;
        if (claimantToken && !notifiedTokens.has(claimantToken)) {
          await sendFcmDetailed(
            claimantToken,
            escalMsg,
            escalBody,
            { ...escalData, recipientId: alert.superviseurId },
            env,
            { firebaseAuthToken: token, uid: alert.superviseurId },
          );
        }
      }
      console.log(`[ESCALATION] Escalated alert ${alertId} (${alert.type}) reason=${reason}`);
      escalated++;
    } catch (e) {
      console.error('[ESCALATION] Error processing alert: ' + e.message);
    }
  }
}

// ============ Workers AI helpers ============

export { checkEscalations };
