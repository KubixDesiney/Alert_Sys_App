const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

const db = admin.database();

const AI_COOLDOWN_MS = 5 * 60 * 1000;
const LOCK_TTL_MS = 15 * 1000;
const ATTEMPT_DEBOUNCE_MS = 1500;

const ACTIVE_SUPERVISOR_STATUSES = new Set(['active', 'available']);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sanitizeFactoryId(input) {
  return String(input || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function resolveFactoryId(source) {
  if (!source || typeof source !== 'object') return null;
  const explicitFactoryId = String(source.factoryId || '').trim();
  if (explicitFactoryId) return sanitizeFactoryId(explicitFactoryId);

  const usine = String(source.usine || '').trim();
  if (usine) return sanitizeFactoryId(usine);
  return null;
}

async function isAiEnabled(factoryId) {
  const snap = await db.ref(`factories/${factoryId}/aiConfig/enabled`).get();
  return snap.exists() && snap.val() === true;
}

async function acquireFactoryLock(factoryId, reason) {
  const ref = db.ref(`ai_runtime/locks/${factoryId}`);
  const now = Date.now();
  const tx = await ref.transaction((current) => {
    if (current && current.expiresAt && current.expiresAt > now) {
      return;
    }
    return {
      reason,
      createdAt: now,
      expiresAt: now + LOCK_TTL_MS,
    };
  });
  return tx.committed;
}

async function releaseFactoryLock(factoryId) {
  await db.ref(`ai_runtime/locks/${factoryId}`).remove();
}

async function isDebounced(factoryId) {
  const ref = db.ref(`ai_runtime/lastAttemptAt/${factoryId}`);
  const now = Date.now();
  const tx = await ref.transaction((current) => {
    if (typeof current === 'number' && now - current < ATTEMPT_DEBOUNCE_MS) {
      return;
    }
    return now;
  });
  return !tx.committed;
}

function pickOldestUnassignedAlert(alertMap, factoryId) {
  const alerts = [];
  for (const [alertId, raw] of Object.entries(alertMap || {})) {
    if (!raw || typeof raw !== 'object') continue;
    if (raw.status !== 'disponible') continue;
    if (raw.superviseurId) continue;
    const alertFactoryId = resolveFactoryId(raw);
    if (!alertFactoryId || alertFactoryId !== factoryId) continue;

    const ts = Date.parse(raw.timestamp || raw.createdAt || raw.updatedAt || '') ||
      Number(raw.createdAtEpoch || 0) ||
      Number(raw.timestampMs || 0) ||
      Date.now();

    alerts.push({
      alertId,
      alert: raw,
      sortTs: ts,
    });
  }

  alerts.sort((a, b) => a.sortTs - b.sortTs);
  return alerts[0] || null;
}

function buildBusySupervisorSet(alertMap) {
  const busy = new Set();
  for (const raw of Object.values(alertMap || {})) {
    if (!raw || typeof raw !== 'object') continue;
    if (raw.status !== 'en_cours') continue;
    if (raw.superviseurId) busy.add(String(raw.superviseurId));
    if (raw.assistantId) busy.add(String(raw.assistantId));
  }
  return busy;
}

function pickEligibleSupervisor(usersMap, factoryId, busySupervisorIds) {
  const now = Date.now();
  const candidates = [];

  for (const [uid, raw] of Object.entries(usersMap || {})) {
    if (!raw || typeof raw !== 'object') continue;
    if (raw.role !== 'supervisor') continue;
    if (raw.aiOptOut === true) continue;
    if (!ACTIVE_SUPERVISOR_STATUSES.has(String(raw.status || '').toLowerCase())) {
      continue;
    }
    if (busySupervisorIds.has(uid)) continue;

    const cooldownUntil = Date.parse(String(raw.aiCooldownUntil || ''));
    if (!Number.isNaN(cooldownUntil) && cooldownUntil > now) continue;

    const userFactoryId = resolveFactoryId(raw);
    if (!userFactoryId || userFactoryId !== factoryId) continue;

    const lastSeenTs = Date.parse(String(raw.lastSeen || '')) || 0;
    candidates.push({
      uid,
      firstName: String(raw.firstName || ''),
      lastName: String(raw.lastName || ''),
      fullName: String(raw.fullName || '').trim(),
      lastSeenTs,
    });
  }

  candidates.sort((a, b) => b.lastSeenTs - a.lastSeenTs);
  return candidates[0] || null;
}

function supervisorDisplayName(sup) {
  if (sup.fullName) return sup.fullName;
  const composed = `${sup.firstName} ${sup.lastName}`.trim();
  return composed || 'Supervisor';
}

async function assignSingleOldestUnassignedAlert({ factoryId, trigger }) {
  const lockAcquired = await acquireFactoryLock(factoryId, trigger);
  if (!lockAcquired) return { assigned: false, reason: 'locked' };

  try {
    const debounced = await isDebounced(factoryId);
    if (debounced) return { assigned: false, reason: 'debounced' };

    const enabled = await isAiEnabled(factoryId);
    if (!enabled) return { assigned: false, reason: 'ai_disabled' };

    const [alertsSnap, usersSnap] = await Promise.all([
      db.ref('alerts').get(),
      db.ref('users').get(),
    ]);

    if (!alertsSnap.exists() || !usersSnap.exists()) {
      return { assigned: false, reason: 'missing_data' };
    }

    const alertsMap = alertsSnap.val() || {};
    const usersMap = usersSnap.val() || {};

    const oldest = pickOldestUnassignedAlert(alertsMap, factoryId);
    if (!oldest) return { assigned: false, reason: 'no_unassigned_alert' };

    const busySupervisorIds = buildBusySupervisorSet(alertsMap);
    const supervisor = pickEligibleSupervisor(usersMap, factoryId, busySupervisorIds);
    if (!supervisor) return { assigned: false, reason: 'no_eligible_supervisor' };

    const nowIso = new Date().toISOString();
    const supervisorName = supervisorDisplayName(supervisor);

    const alertRef = db.ref(`alerts/${oldest.alertId}`);
    const tx = await alertRef.transaction((current) => {
      if (!current || current.status !== 'disponible') return;
      if (current.superviseurId) return;
      const currentFactoryId = resolveFactoryId(current);
      if (!currentFactoryId || currentFactoryId !== factoryId) return;

      return {
        ...current,
        status: 'en_cours',
        superviseurId: supervisor.uid,
        superviseurName: supervisorName,
        takenAtTimestamp: nowIso,
        aiAssigned: true,
        aiAssignmentReason: `Event retry (${trigger})`,
        aiAssignedAt: nowIso,
        aiRetry: {
          lastAttemptAt: nowIso,
          trigger,
        },
      };
    });

    if (!tx.committed) {
      return { assigned: false, reason: 'race_lost' };
    }

    await Promise.all([
      db.ref(`notifications/${supervisor.uid}`).push().set({
        type: 'ai_assigned',
        alertId: oldest.alertId,
        alertType: oldest.alert.type || 'alert',
        alertDescription: oldest.alert.description || '',
        alertUsine: oldest.alert.usine || '',
        message: `Auto-assigned by AI retry engine (${trigger})`,
        aiAssigned: true,
        timestamp: nowIso,
        status: 'pending',
      }),
      db.ref(`alerts/${oldest.alertId}/aiHistory`).push().set({
        event: 'assigned_retry',
        trigger,
        supervisorId: supervisor.uid,
        supervisorName,
        timestamp: nowIso,
      }),
      db.ref(`ai_decisions/${oldest.alertId}`).set({
        alertId: oldest.alertId,
        assignedTo: supervisor.uid,
        assignedToName: supervisorName,
        decisionMode: 'retry_single_oldest',
        trigger,
        timestamp: nowIso,
      }),
      db.ref(`users/${supervisor.uid}/aiCooldownUntil`).set(
        new Date(Date.now() + AI_COOLDOWN_MS).toISOString(),
      ),
      db.ref(`ai_runtime/lastAssignedAt/${factoryId}`).set(nowIso),
      db.ref(`ai_runtime/cooldownSignals/${factoryId}/${supervisor.uid}`).set({
        cooldownUntil: new Date(Date.now() + AI_COOLDOWN_MS).toISOString(),
        createdAt: nowIso,
        sourceAlertId: oldest.alertId,
      }),
    ]);

    return { assigned: true, alertId: oldest.alertId, supervisorId: supervisor.uid };
  } finally {
    await releaseFactoryLock(factoryId);
  }
}

async function retryFactoryFromEvent(factoryId, trigger) {
  if (!factoryId) return null;
  return assignSingleOldestUnassignedAlert({ factoryId, trigger });
}

exports.sendAlertPush = functions.database
  .ref('/alerts/{alertId}')
  .onCreate(async (snapshot, context) => {
    const alert = snapshot.val();
    const alertId = context.params.alertId;

    // Avoid duplicate sends
    if (alert.notificationSent) return;
    await snapshot.ref.update({ notificationSent: true });

    const usine = alert.usine || 'Unknown plant';
    const alertType = alert.type || 'Alert';
    const description = alert.description || '';

    // Get all OneSignal player IDs from users
    const usersSnapshot = await admin.database().ref('users').once('value');
    const playerIds = [];
    usersSnapshot.forEach((userSnap) => {
      const user = userSnap.val();
      const onesignalId = user.onesignalId;
      if (onesignalId && (user.role === 'supervisor' || user.role === 'admin')) {
        playerIds.push(onesignalId);
      }
    });

    if (playerIds.length === 0) {
      console.log('No OneSignal player IDs found');
      return;
    }

    const ONESIGNAL_APP_ID = '322abcb7-c4e5-4630-811f-ccea86a6f481';
    const ONESIGNAL_REST_KEY = 'os_v2_app_givlzn6e4vddbai7ztvinjxuqex4akbbf2fuwsvkc4xdwsz3gh5ves6vdzpixnhfob23ohyfc4dknmroh2q2qgkag6dbfsw6ctj34ly';

    const payload = {
      app_id: ONESIGNAL_APP_ID,
      include_player_ids: playerIds,
      headings: { en: `🚨 New Alert: ${alertType}` },
      contents: { en: `${usine} - ${description}` },
      data: { alertId, type: alertType, usine },
      android_channel_id: 'alerts',
    };

    try {
      await axios.post('https://onesignal.com/api/v1/notifications', payload, {
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Basic ${ONESIGNAL_REST_KEY}`,
        },
      });
      console.log('✅ OneSignal push sent');
    } catch (error) {
      console.error('❌ OneSignal push failed:', error.response?.data || error.message);
    }
  });

exports.retryAIAssignmentOnAlertAvailable = functions.database
  .ref('/alerts/{alertId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) return null;

    const before = change.before.val();
    const after = change.after.val();
    if (!after || typeof after !== 'object') return null;

    const becameAvailable =
      (!before || before.status !== 'disponible') && after.status === 'disponible';
    const becameUnassigned =
      before && before.superviseurId && !after.superviseurId && after.status === 'disponible';

    if (!becameAvailable && !becameUnassigned) return null;

    const factoryId = resolveFactoryId(after);
    if (!factoryId) return null;

    await retryFactoryFromEvent(factoryId, 'alert_available');
    return null;
  });

exports.retryAIAssignmentOnSupervisorAvailable = functions.database
  .ref('/users/{userId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) return null;

    const before = change.before.val() || {};
    const after = change.after.val() || {};
    if (after.role !== 'supervisor') return null;

    const beforeStatus = String(before.status || '').toLowerCase();
    const afterStatus = String(after.status || '').toLowerCase();
    const becameAvailable =
      !ACTIVE_SUPERVISOR_STATUSES.has(beforeStatus) &&
      ACTIVE_SUPERVISOR_STATUSES.has(afterStatus);

    if (!becameAvailable) return null;

    const factoryId = resolveFactoryId(after);
    if (!factoryId) return null;

    await retryFactoryFromEvent(factoryId, 'supervisor_available');
    return null;
  });

exports.retryAIAssignmentOnCooldownSignal = functions
  .runWith({ timeoutSeconds: 540, memory: '256MB' })
  .database.ref('/ai_runtime/cooldownSignals/{factoryId}/{supervisorId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) return null;

    const payload = change.after.val() || {};
    const cooldownUntil = Date.parse(String(payload.cooldownUntil || ''));
    if (Number.isNaN(cooldownUntil)) {
      await change.after.ref.remove();
      return null;
    }

    const delay = cooldownUntil - Date.now();
    if (delay > 0) {
      await sleep(delay);
    }

    await retryFactoryFromEvent(context.params.factoryId, 'cooldown_expired');
    await change.after.ref.remove();
    return null;
  });

// Fires when the client (or CF) writes aiCooldownUntil on a supervisor.
// Sleeps until expiry, then checks if any unassigned alerts are waiting.
// This catches client-side assignments that don't write cooldown signals.
exports.retryAIAssignmentOnUserCooldown = functions
  .runWith({ timeoutSeconds: 540, memory: '256MB' })
  .database.ref('/users/{userId}/aiCooldownUntil')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) return null;

    const cooldownUntil = Date.parse(String(change.after.val() || ''));
    if (Number.isNaN(cooldownUntil)) return null;

    const delay = cooldownUntil - Date.now();
    if (delay <= 0) return null;
    // Skip if delay exceeds safe execution window (leave 20s headroom).
    if (delay > 520 * 1000) return null;

    await sleep(delay);

    const userSnap = await db.ref(`users/${context.params.userId}`).get();
    if (!userSnap.exists()) return null;
    const factoryId = resolveFactoryId(userSnap.val() || {});
    if (!factoryId) return null;

    await retryFactoryFromEvent(factoryId, 'user_cooldown_expired');
    return null;
  });

// Fires when a supervisor resolves an alert (status → validee).
// At that point the supervisor is finishing up; any unassigned alert
// for the same factory should be picked up if the cooldown has passed.
exports.retryAIAssignmentOnAlertResolved = functions.database
  .ref('/alerts/{alertId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists()) return null;

    const before = change.before.val();
    const after = change.after.val();
    if (!after || typeof after !== 'object') return null;

    const becameResolved =
      before && before.status !== 'validee' && after.status === 'validee';
    if (!becameResolved) return null;

    const factoryId = resolveFactoryId(after);
    if (!factoryId) return null;

    await retryFactoryFromEvent(factoryId, 'alert_resolved');
    return null;
  });