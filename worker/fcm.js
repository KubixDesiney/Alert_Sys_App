import { getFcmAccessToken } from './auth.js';
import { MAX_FANOUT } from './config.js';
import { aiSanitizeFactoryId } from './utils.js';

async function sendFcm(token, title, body, data, env) {
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
      console.error(`[FCM] Send failed (${res.status}):` + err);
    }
    return res.ok;
  } catch (e) {
    console.error('[FCM] Error:' + e.message);
    return false;
  }
}

// ============ Shift helpers ============

function getFcmTokensForFactory(factoryName, usersMap, alertsMap, { allSupervisors = false } = {}) {
  const targetId = aiSanitizeFactoryId(factoryName);
  const busySupervisors = new Set();
  if (!allSupervisors) {
    for (const a of Object.values(alertsMap)) {
      if (a.status === 'en_cours') {
        if (a.superviseurId) busySupervisors.add(a.superviseurId);
        if (a.assistantId) busySupervisors.add(a.assistantId);
      }
    }
  }
  const tokens = new Set();
  for (const [uid, user] of Object.entries(usersMap)) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (busySupervisors.has(uid)) continue;
      const userFid = aiSanitizeFactoryId(user.usine || user.factoryId || '');
      if (userFid !== targetId) continue;
    } else if (user.role !== 'admin') {
      continue;
    }
    tokens.add(user.fcmToken);
  }
  return [...tokens];
}

// ============ New‑alert FCM push ============

const COLLAB_NOTIF_TYPES = new Set([
  'collaboration_request',
  'collaboration_assistant_accepted',
  'collaboration_assistant_removed',
  'collaboration_removed',
  'collaboration_approved',
  'collaboration_rejected',
  'collaboration_request_admin',
  'assistant_assigned',
]);

function notifTitle(type) {
  switch (String(type || '')) {
    case 'ai_assigned': return 'AI Assignment';
    case 'collaboration_request': return 'Collaboration request';
    case 'collaboration_assistant_accepted':
    case 'collaboration_assistant_removed':
    case 'collaboration_removed':
    case 'collaboration_approved':
    case 'collaboration_rejected': return 'Collaboration update';
    case 'assistant_assigned': return 'Assistant assigned';
    case 'help_request':
    case 'assistance_request': return 'Help request';
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'AlertSys';
  }
}

async function fanOutPendingNotifications(env, ctx) {
  const { token, usersMap, alertsMap } = ctx;
  const nowIso = new Date().toISOString();
  const busySupervisors = new Set();
  for (const a of Object.values(alertsMap || {})) {
    if (a.status === 'en_cours' && a.superviseurId) busySupervisors.add(a.superviseurId);
  }
  const notifRes = await fetch(`${env.FB_DB_URL}notifications.json?auth=${token}`);
  if (!notifRes.ok) return;
  const allNotifs = (await notifRes.json()) || {};
  let processed = 0;
  outer: for (const [uid, bucket] of Object.entries(allNotifs)) {
    if (processed >= MAX_FANOUT) break;
    const user = usersMap[uid];
    const fcmToken = user?.fcmToken;
    if (!fcmToken) continue;
    const isBusySupervisor = user.role === 'supervisor' && busySupervisors.has(uid);
    for (const [notifId, notif] of Object.entries(bucket || {})) {
      if (processed >= MAX_FANOUT) break outer;
      if (!notif || notif.pushSent === true || notif.pushSending === true) continue;
      if (isBusySupervisor && !COLLAB_NOTIF_TYPES.has(String(notif.type || ''))) continue;
      const url = `${env.FB_DB_URL}notifications/${uid}/${notifId}.json?auth=${token}`;
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
      const body = String(current.message || current.type || 'AlertSys notification');
      const sent = await sendFcm(
        fcmToken,
        title,
        body,
        {
          notificationId: notifId,
          recipientId: uid,
          alertId: String(current.alertId || ''),
          collabRequestId: String(current.collabRequestId || ''),
          type: String(current.type || ''),
        },
        env,
      );
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
    }
  }
}

// ============ AI Assignment Engine (FULL SCORING) ============

export {
  sendFcm,
  getFcmTokensForFactory,
  fanOutPendingNotifications,
  notifTitle,
  COLLAB_NOTIF_TYPES,
};
