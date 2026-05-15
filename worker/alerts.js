import { MAX_ALERTS_TO_PUSH, PUSH_LOCK_TTL_MS } from './config.js';
import { getFcmRecipientsForFactory, sendFcmDetailed } from './fcm.js';
import { _toMs } from './utils.js';

function _alertNotifId(alertId) {
  let h = 0;
  for (let i = 0; i < alertId.length; i++) {
    h = (h * 31 + alertId.charCodeAt(i)) % 0x7FFFFFFF;
  }
  return h || 1;
}

function _pushLockIsFresh(alert) {
  if (!alert || alert.push_sending !== true) return false;
  const started = _toMs(alert.push_sending_at);
  return started != null && Date.now() - started < PUSH_LOCK_TTL_MS;
}

async function claimAlertPush(env, token, alertId) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return null;
  const etag = getRes.headers.get('ETag');
  const current = await getRes.json();
  if (!current || current.push_sent !== false || current.status !== 'disponible') return null;
  if (_pushLockIsFresh(current)) return null;

  const nowIso = new Date().toISOString();
  const claimRes = await fetch(alertUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': etag },
    body: JSON.stringify({
      ...current,
      push_sending: true,
      push_sending_at: nowIso,
    }),
  });
  if (claimRes.status === 412 || !claimRes.ok) return null;
  return { alertUrl, alert: { id: alertId, ...current } };
}

async function finishAlertPush(alertUrl, sent) {
  const nowIso = new Date().toISOString();
  await fetch(alertUrl, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(
      sent
        ? {
            push_sent: true,
            push_sent_at: nowIso,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: null,
          }
        : {
            push_sent: false,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: nowIso,
          },
    ),
  });
}

async function skipAlertPush(alertUrl, reason) {
  const nowIso = new Date().toISOString();
  await fetch(alertUrl, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      push_sent: true,
      push_sent_at: nowIso,
      push_sending: null,
      push_sending_at: null,
      push_last_error_at: null,
      push_skip_reason: String(reason || 'skipped'),
    }),
  });
}

async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap, supervisorActiveAlertsMap } = ctx;
  const unsent = Object.entries(alertsMap || {})
    .filter(([, a]) => a && a.status === 'disponible' && a.push_sent === false && !_pushLockIsFresh(a))
    .slice(0, MAX_ALERTS_TO_PUSH)
    .map(([id]) => id);
  if (!unsent.length) return;

  for (const alertId of unsent) {
    const claimed = await claimAlertPush(env, token, alertId);
    if (!claimed) continue;
    const { alertUrl, alert } = claimed;
    const recipients = getFcmRecipientsForFactory(alert.factoryId || alert.usine, usersMap, alertsMap, {
      allSupervisors: false,
      includeAdmins: false,
      requireActiveSupervisors: true,
      supervisorActiveAlertsMap,
    });
    if (recipients.length === 0) {
      await skipAlertPush(alertUrl, 'no_recipients');
      continue;
    }

    let sentCount = 0;
    let retryableFailure = false;
    for (const recipient of recipients) {
      const result = await sendFcmDetailed(
        recipient.token,
        `🚨 New Alert: ${alert.type || 'Alert'}`,
        `${alert.usine || ''} — ${alert.description || ''}`,
        {
          alertId: alert.id,
          recipientId: recipient.uid,
          type: alert.type || 'Alert',
          usine: alert.usine || '',
          factoryId: String(alert.factoryId || ''),
          notifType: 'new_alert',
          notificationId: String(_alertNotifId(alert.id)),
        },
        env,
        { firebaseAuthToken: token, uid: recipient.uid },
      );
      if (result.ok) {
        sentCount++;
      } else if (result.unregistered) {
        if (usersMap?.[recipient.uid]?.fcmToken === recipient.token) {
          usersMap[recipient.uid].fcmToken = null;
        }
      } else {
        retryableFailure = true;
      }
    }
    await finishAlertPush(alertUrl, sentCount > 0 || !retryableFailure);
  }
}

export { processAlerts, claimAlertPush, finishAlertPush, skipAlertPush };
