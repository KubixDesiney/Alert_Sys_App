import { getFcmAccessToken } from './auth.js';
import { MAX_FANOUT } from './config.js';
import { _toMs, factoryCandidates, factoryMatches } from './utils.js';

// Freshness caps — mirror cloudflare_notify_worker.js. A new-alert buzz is
// time-critical; any queued row older than a day is dead weight.
const NEW_ALERT_MAX_AGE_MS = 15 * 60 * 1000;
const QUEUED_NOTIFICATION_MAX_AGE_MS = 24 * 60 * 60 * 1000;

function _alertNotifId(alertId) {
  let h = 0;
  for (let i = 0; i < alertId.length; i++) {
    h = (h * 31 + alertId.charCodeAt(i)) % 0x7FFFFFFF;
  }
  return h || 1;
}

function parseFcmFailure(status, text) {
  let errorCode = '';
  let message = text || '';
  try {
    const parsed = JSON.parse(text || '{}');
    const error = parsed?.error || {};
    message = error.message || message;
    errorCode = String(error.status || '');
    const detail = Array.isArray(error.details)
      ? error.details.find((d) => d && d.errorCode)
      : null;
    if (detail?.errorCode) errorCode = String(detail.errorCode);
  } catch (_) {
    errorCode = '';
  }
  const unregistered =
    status === 404 &&
    (errorCode === 'UNREGISTERED' ||
      errorCode === 'NOT_FOUND' ||
      /UNREGISTERED|Device unregistered/i.test(text || ''));
  return { errorCode, message, unregistered };
}

async function clearUnregisteredFcmToken(env, firebaseAuthToken, uid, staleToken) {
  if (!env?.FB_DB_URL || !firebaseAuthToken || !uid || !staleToken) return false;
  const tokenUrl = `${env.FB_DB_URL}users/${uid}/fcmToken.json?auth=${firebaseAuthToken}`;
  try {
    const currentRes = await fetch(tokenUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!currentRes.ok) return false;
    const etag = currentRes.headers.get('ETag');
    const current = await currentRes.json();
    if (current !== staleToken) return false;
    const clearRes = await fetch(tokenUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag ?? '*' },
      body: 'null',
    });
    return clearRes.ok;
  } catch (e) {
    console.warn('[FCM] Failed to clear unregistered token: ' + e.message);
    return false;
  }
}

async function sendFcmDetailed(token, title, body, data, env, options = {}) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          // Data-only message: no top-level "notification" field.
          // This guarantees firebaseMessagingBackgroundHandler is invoked even
          // when the app is terminated, so flutter_local_notifications can show
          // a fullScreenIntent notification that bypasses the Android lock screen.
          // Title/body are carried in the data map and read by the Flutter handler.
          data: { ...data, title, body },
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { 'content-available': 1 } },
          },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      const failure = parseFcmFailure(res.status, err);
      if (failure.unregistered) {
        const uid = String(options.uid || data?.recipientId || '').trim();
        console.warn(`[FCM] Dropping unregistered token${uid ? ` for ${uid}` : ''}`);
        await clearUnregisteredFcmToken(env, options.firebaseAuthToken, uid, token);
      } else {
        console.error(`[FCM] Send failed (${res.status}):` + err);
      }
      return { ok: false, status: res.status, ...failure };
    }
    return { ok: true, status: res.status, errorCode: '', message: '', unregistered: false };
  } catch (e) {
    console.error('[FCM] Error:' + e.message);
    return { ok: false, status: 0, errorCode: 'EXCEPTION', message: e.message, unregistered: false };
  }
}

async function sendFcm(token, title, body, data, env, options = {}) {
  const result = await sendFcmDetailed(token, title, body, data, env, options);
  return result.ok;
}

// ============ FCM token helpers ============

const NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES = new Set(['active', 'available', 'online', 'ready']);

function isActiveSupervisorForNotification(user) {
  const status = String(user?.status || '').toLowerCase();
  return NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES.has(status) ||
    user?.active === true ||
    user?.isActive === true;
}

function engagedSupervisorIds(alertsMap = {}, supervisorActiveAlertsMap = {}) {
  const ids = new Set();
  for (const a of Object.values(alertsMap || {})) {
    if (!a || a.status !== 'en_cours') continue;
    if (a.superviseurId) ids.add(String(a.superviseurId));
    if (a.assistantId) ids.add(String(a.assistantId));
  }

  for (const [uid, claim] of Object.entries(supervisorActiveAlertsMap || {})) {
    if (!claim) continue;
    const alertId =
      typeof claim === 'string'
        ? claim
        : String(claim.alertId || claim.id || '').trim();
    const alert = alertId ? alertsMap?.[alertId] : null;
    if (alert && alert.status === 'en_cours') ids.add(String(uid));
  }
  return ids;
}

// `factoryRef` accepts either a factory name/id string or a whole alert-like
// object; the object form matches on any of factoryId/usine/factoryName so a
// factoryId-only alert still reaches usine-keyed users (and vice versa).
function getFcmRecipientsForFactory(
  factoryRef,
  usersMap,
  alertsMap,
  {
    allSupervisors = false,
    allFactories = false,
    includeAdmins = true,
    requireActiveSupervisors = false,
    supervisorActiveAlertsMap = {},
  } = {},
) {
  const targetFactories = factoryCandidates(factoryRef);
  const busySupervisors = allSupervisors
    ? new Set()
    : engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const recipientsByToken = new Map();
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (requireActiveSupervisors && !isActiveSupervisorForNotification(user)) continue;
      if (busySupervisors.has(uid)) continue;
      if (!allFactories && !factoryMatches(targetFactories, factoryCandidates(user))) continue;
    } else if (user.role !== 'admin') {
      continue;
    } else if (!includeAdmins) {
      continue;
    }
    const token = String(user.fcmToken);
    if (!recipientsByToken.has(token)) {
      recipientsByToken.set(token, { uid, token, role: String(user.role || '') });
    }
  }
  return [...recipientsByToken.values()];
}

function getFcmTokensForFactory(factoryRef, usersMap, alertsMap, options = {}) {
  return getFcmRecipientsForFactory(factoryRef, usersMap, alertsMap, options)
    .map((recipient) => recipient.token);
}

// ============ New‑alert FCM push ============

// `new_alert` rows are broadcast fan-out rows: the busy + factory gates are
// enforced at send time no matter who queued them. Every other queued type is
// personally addressed by its producer and bypasses those gates. Mirrors
// cloudflare_notify_worker.js.
const BUSY_FACTORY_GATED_NOTIF_TYPES = new Set(['new_alert']);

function notifTitle(type) {
  switch (String(type || '')) {
    case 'new_alert': return 'New Alert';
    case 'ai_assigned': return 'AI Assignment';
    case 'collaboration_request': return 'Collaboration request';
    case 'collaboration_assistant_accepted':
    case 'collaboration_assistant_removed':
    case 'collaboration_removed':
    case 'collaboration_approved':
    case 'collaboration_rejected':
    case 'collaboration_refused':
    case 'collab_auto_approved': return 'Collaboration update';
    case 'assistant_assigned': return 'Assistant assigned';
    case 'cross_factory_transfer': return 'Cross-factory transfer';
    case 'help_request':
    case 'assistance_request': return 'Help request';
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'SIAS - Smart Industrial Alert System';
  }
}

// Send-time eligibility for one queued notification — same policy as
// cloudflare_notify_worker.js's evaluateNotificationDelivery:
//   'send'  — deliver via FCM
//   'skip'  — permanently ineligible: close the row (pushSent + pushSkipReason)
//   'defer' — transient: leave for a later retry
function evaluateQueuedNotification(uid, user, notif, busySupervisors) {
  if (!notif || notif.pushSent === true || notif.pushSending === true) return { action: 'defer' };
  const notifType = String(notif.type || '');
  if (!notifType) return { action: 'defer' };
  if (!uid || uid === 'undefined' || !user) return { action: 'skip', reason: 'unknown_user' };

  const userRole = String(user.role || '');
  const isSupervisor = userRole === 'supervisor';
  const isAdmin = userRole === 'admin';
  if (!isSupervisor && !isAdmin) return { action: 'skip', reason: 'role_mismatch' };
  if (notifType === 'new_alert' && !isSupervisor) return { action: 'skip', reason: 'role_mismatch' };

  const createdMs = _toMs(notif.timestamp);
  if (createdMs != null) {
    const maxAge = notifType === 'new_alert' ? NEW_ALERT_MAX_AGE_MS : QUEUED_NOTIFICATION_MAX_AGE_MS;
    if (Date.now() - createdMs > maxAge) return { action: 'skip', reason: 'expired' };
  }

  if (BUSY_FACTORY_GATED_NOTIF_TYPES.has(notifType) && isSupervisor) {
    if (busySupervisors.has(uid)) return { action: 'skip', reason: 'busy_supervisor' };
    if (!factoryMatches(factoryCandidates(notif), factoryCandidates(user))) {
      return { action: 'skip', reason: 'factory_mismatch' };
    }
  }

  if (!user.fcmToken) {
    return notifType === 'new_alert'
      ? { action: 'skip', reason: 'no_fcm_token' }
      : { action: 'defer' };
  }
  return { action: 'send' };
}

async function fanOutPendingNotifications(env, ctx, options = {}) {
  const { token, usersMap, alertsMap, supervisorActiveAlertsMap } = ctx;
  const limit = Math.max(0, Number(options.limit ?? MAX_FANOUT) || 0);
  if (limit <= 0) return;
  const nowIso = new Date().toISOString();
  const busySupervisors = engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const notifRes = await fetch(`${env.FB_DB_URL}notifications.json?auth=${token}`);
  if (!notifRes.ok) return;
  const allNotifs = (await notifRes.json()) || {};
  let processed = 0;
  outer: for (const [uid, bucket] of Object.entries(allNotifs)) {
    if (processed >= limit) break;
    const user = usersMap[uid];
    for (const [notifId, notif] of Object.entries(bucket || {})) {
      if (processed >= limit) break outer;
      const url = `${env.FB_DB_URL}notifications/${uid}/${notifId}.json?auth=${token}`;
      const verdict = evaluateQueuedNotification(uid, user, notif, busySupervisors);
      if (verdict.action === 'skip') {
        // Terminal close: the row can never be pushed (busy/wrong factory/
        // expired/…) — mark it so future crons stop rescanning it.
        await fetch(url, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            pushSent: true,
            pushSentAt: nowIso,
            pushSending: null,
            pushLastErrorAt: null,
            pushSkipReason: verdict.reason,
          }),
        });
        continue;
      }
      if (verdict.action !== 'send') continue;
      const fcmToken = user.fcmToken;
      const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
      if (!getRes.ok) continue;
      const etag = getRes.headers.get('ETag');
      const current = await getRes.json();
      if (!current || current.pushSent === true || current.pushSending === true) continue;
      const claimRes = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'if-match': etag },
        body: JSON.stringify({ ...current, pushSending: true }),
      });
      if (claimRes.status === 412 || !claimRes.ok) continue;
      const title = notifTitle(current.type);
      const body = String(current.message || current.type || 'SIAS - Smart Industrial Alert System notification');
      const result = await sendFcmDetailed(
        fcmToken,
        title,
        body,
        {
          notificationId: String(current.type || '') === 'new_alert' && current.alertId
            ? String(_alertNotifId(String(current.alertId)))
            : notifId,
          queueNotificationId: notifId,
          recipientId: uid,
          alertId: String(current.alertId || ''),
          collabRequestId: String(current.collabRequestId || ''),
          type: String(current.type || ''),
        },
        env,
        { firebaseAuthToken: token, uid },
      );
      const sent = result.ok;
      if (result.unregistered && user?.fcmToken === fcmToken) {
        user.fcmToken = null;
      }
      await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          sent
            ? { pushSent: true, pushSentAt: nowIso, pushSending: null }
            : { pushSending: null, pushLastErrorAt: nowIso },
        ),
      });
      processed++;
      if (result.unregistered) break;
    }
  }
}

// ============ AI Assignment Engine (FULL SCORING) ============

export {
  sendFcm,
  sendFcmDetailed,
  getFcmRecipientsForFactory,
  getFcmTokensForFactory,
  fanOutPendingNotifications,
  evaluateQueuedNotification,
  notifTitle,
  BUSY_FACTORY_GATED_NOTIF_TYPES,
};
