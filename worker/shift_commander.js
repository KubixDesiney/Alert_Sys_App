import { getFirebaseToken } from './auth.js';
import { corsHeaders } from './config.js';
import { sendFcm } from './fcm.js';
import { loadCoreData } from './load_core.js';
import { AI_ACTIVE_STATUSES, AI_COOLDOWN_MS, buildSupStats, countActiveSupervisorsInFactory, scoreSupervisor } from './scoring.js';
import { _shiftContainsTime, _toMs, aiResolveFactory, aiSanitizeFactoryId, pickActiveShift } from './utils.js';

function commanderCapabilities(shift) {
  const aiCommander = !!(shift && shift.aiCommander === true);
  const fullControl = !!(shift && shift.fullControl === true);
  const hasExplicitTaskConfig =
    shift &&
    (Object.prototype.hasOwnProperty.call(shift, 'handleAssignments') ||
      Object.prototype.hasOwnProperty.call(shift, 'handleCollaborations') ||
      Object.prototype.hasOwnProperty.call(shift, 'handleCrossFactoryTransfer') ||
      Object.prototype.hasOwnProperty.call(shift, 'fullControl'));
  return {
    aiCommander,
    fullControl,
    handleAssignments:
      aiCommander &&
      (fullControl ||
        shift?.handleAssignments === true ||
        (!hasExplicitTaskConfig && aiCommander)),
    handleCollaborations:
      aiCommander &&
      (fullControl ||
        shift?.handleCollaborations === true ||
        (!hasExplicitTaskConfig && aiCommander)),
    handleCrossFactoryTransfer:
      aiCommander && (fullControl || shift?.handleCrossFactoryTransfer === true),
  };
}

async function writeShiftAiLog(env, token, shiftId, entry) {
  if (!shiftId) return null;
  try {
    const nowIso = new Date().toISOString();
    const res = await fetch(`${env.FB_DB_URL}shift_ai_logs/${shiftId}.json?auth=${token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        at: entry.at || nowIso,
        kind: String(entry.kind || 'action'),
        shiftId,
        alertLabel: entry.alertLabel || null,
        supervisorName: entry.supervisorName || null,
        supervisorId: entry.supervisorId || null,
        factory: entry.factory || null,
        confidence: Number(entry.confidence || 0),
        reason: String(entry.reason || ''),
      }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => null);
    return data?.name || null;
  } catch (e) {
    console.error('[SHIFT-AI] log write failed: ' + e.message);
    return null;
  }
}

function cloneCtxWithShift(ctx, shift) {
  return {
    ...ctx,
    activeShift: shift ?? null,
    targetShift: shift ?? null,
  };
}

async function aiAssignAlert(alertId, supervisor, reasonSummary, confidence, env, token, allCandidates = []) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  // Deterministic idempotency key — stable for a given alert+supervisor within the same minute.
  const actionId = `worker_${alertId}_${Math.floor(Date.now() / 60000)}`;

  // Skip if this exact action was already persisted this minute (duplicate cron tick guard).
  try {
    const existingRes = await fetch(`${env.FB_DB_URL}ai_decisions/${alertId}/actionId.json?auth=${token}`);
    if (existingRes.ok) {
      const existingId = await existingRes.json();
      if (existingId === actionId) {
        console.log(`[AI-ASSIGN] Idempotency skip: ${actionId} already recorded`);
        return false;
      }
    }
  } catch (_) { /* non-fatal — proceed */ }

  // Retry loop: attempt the ETag-guarded PUT up to twice.
  // On a 412 (concurrent write) we re-fetch a fresh ETag and try once more.
  for (let attempt = 1; attempt <= 2; attempt++) {
    const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) return false;
    const etag = getRes.headers.get('ETag');
    const current = await getRes.json();
    if (!current || current.status !== 'disponible' || current.superviseurId) return false;

    const nowIso = new Date().toISOString();
    const putRes = await fetch(alertUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag },
      body: JSON.stringify({
        ...current,
        status: 'en_cours',
        superviseurId: supervisor.uid,
        superviseurName: supervisor.name,
        takenAtTimestamp: nowIso,
        aiAssigned: true,
        aiAssignmentReason: reasonSummary,
        aiConfidence: confidence,
        aiAssignedAt: nowIso,
        push_sent: true,
      }),
    });

    if (putRes.status === 412) {
      console.log(`[AI-ASSIGN] ETag mismatch attempt ${attempt} for alert ${alertId}`);
      if (attempt < 2) continue; // re-fetch and retry once
      return false;
    }
    if (!putRes.ok) return false;

    // Assignment succeeded — persist side-effects fire-and-forget.
    const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();
    await Promise.allSettled([
      fetch(`${env.FB_DB_URL}users/${supervisor.uid}/aiCooldownUntil.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(cooldownUntil),
      }),
      fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          event: 'assigned_worker',
          supervisorId: supervisor.uid,
          supervisorName: supervisor.name,
          reason: reasonSummary,
          confidence,
          actionId,
          timestamp: nowIso,
        }),
      }),
      fetch(`${env.FB_DB_URL}ai_decisions/${alertId}.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          alertId,
          assignedTo: supervisor.uid,
          assignedToName: supervisor.name,
          confidence,
          reasonSummary,
          breakdown: supervisor.reasons || [],
          decisionMode: 'worker_auto',
          actionId,
          timestamp: nowIso,
          // Full candidate list so the app can show "why not others".
          consideredCandidates: allCandidates.map((c) => ({
            supervisorId: c.uid,
            name: c.name,
            score: c.score,
            reasons: c.reasons || [],
            skipReason: c.skipReason ?? null,
          })),
        }),
      }),
    ]);
    if (supervisor.fcmToken) {
      await sendFcm(
        supervisor.fcmToken,
        'AI Assignment',
        `Auto-assigned: ${current.type || 'alert'}${current.usine ? ` at ${current.usine}` : ''}`,
        {
          type: 'ai_assigned',
          alertId: String(alertId),
          recipientId: String(supervisor.uid),
          reason: reasonSummary,
        },
        env,
      );
    }
    return true;
  }
  return false;
}

async function runAIAssignments(env, ctx) {
  const token = ctx?.token ?? (await getFirebaseToken(env));
  let alertsMap, usersMap, activeShift;
  if (ctx) {
    alertsMap = ctx.alertsMap;
    usersMap = ctx.usersMap;
    activeShift = ctx.targetShift ?? ctx.activeShift ?? null;
  } else {
    const [ar, ur, sr] = await Promise.all([
      fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}shifts.json?auth=${token}`),
    ]);
    if (!ar.ok || !ur.ok) return;
    alertsMap = (await ar.json()) || {};
    usersMap = (await ur.json()) || {};
    const shiftsMap = sr.ok ? ((await sr.json()) || {}) : {};
    activeShift = pickActiveShift(shiftsMap, new Date());
  }
  const capabilities = commanderCapabilities(activeShift);
  const aiCommander = capabilities.aiCommander;
  const shiftRandomize = !!(activeShift && activeShift.randomize === true);
  const shiftMaxSupervisors =
    activeShift && Number.isFinite(Number(activeShift.maxSupervisors))
      ? Number(activeShift.maxSupervisors)
      : null;
  const shiftSupervisorIds = new Set(
    (activeShift && activeShift.supervisors && typeof activeShift.supervisors === 'object'
      ? Object.keys(activeShift.supervisors)
      : []),
  );
  if (aiCommander && !capabilities.handleAssignments) {
    await writeShiftAiLog(env, token, activeShift?.id, {
      kind: 'skipped',
      reason: `Assignments were skipped because "Handle Assignments" is disabled for shift "${activeShift?.name || activeShift?.id || 'Unknown'}".`,
    });
    return 0;
  }
  let feedbackSummary = {};
  try {
    const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${token}`);
    if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
  } catch (e) {}
  let reinforcementAdjustments = {};
  try {
    const adjRes = await fetch(`${env.FB_DB_URL}ai_feedback/adjustments.json?auth=${token}`);
    if (adjRes.ok) reinforcementAdjustments = (await adjRes.json()) || {};
  } catch (_) {}
  const supStats = buildSupStats(alertsMap);
  const busy = new Set();
  for (const a of Object.values(alertsMap)) {
    if (a.status === 'en_cours') {
      if (a.superviseurId) busy.add(a.superviseurId);
      if (a.assistantId) busy.add(a.assistantId);
    }
  }
  const byFactory = {};
  for (const [id, a] of Object.entries(alertsMap)) {
    if (a.status !== 'disponible' || a.superviseurId) continue;
    const fid = aiResolveFactory(a);
    if (!fid) continue;
    if (!byFactory[fid]) byFactory[fid] = [];
    byFactory[fid].push({ id, ...a });
  }
  if (Object.keys(byFactory).length === 0) return;
  const now = Date.now();
  const factoryIds = Object.keys(byFactory);
  const activeSupervisorCounts = {};
  for (const factoryId of factoryIds) {
    activeSupervisorCounts[factoryId] = countActiveSupervisorsInFactory(usersMap, factoryId);
  }
  let assignedCount = 0;
  for (let i = 0; i < Math.min(factoryIds.length, 20); i++) {
    if (assignedCount >= 1) break;
    const factoryId = factoryIds[i];
    let enabled = false;
    if (aiCommander) {
      // AI Shift Commander overrides per-factory toggle.
      enabled = true;
    } else {
      const enaRes = await fetch(`${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`);
      enabled = enaRes.ok ? await enaRes.json() : false;
    }
    if (enabled !== true) continue;
    let factoryAlerts = byFactory[factoryId];
    factoryAlerts.sort((a, b) => {
      const ap = a.isEscalated ? 2 : (a.isCritical ? 1 : 0);
      const bp = b.isEscalated ? 2 : (b.isCritical ? 1 : 0);
      if (ap !== bp) return bp - ap;
      return (Date.parse(a.timestamp || '') || 0) - (Date.parse(b.timestamp || '') || 0);
    });
    const alert = factoryAlerts[0];
    if (!alert) continue;
    const allowCrossFactoryCandidates =
      aiCommander &&
      capabilities.handleCrossFactoryTransfer &&
      (activeSupervisorCounts[factoryId] || 0) === 0;
    const candidates = [];
    for (const [uid, u] of Object.entries(usersMap)) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      if (!AI_ACTIVE_STATUSES.has(String(u.status || '').toLowerCase())) continue;
      if (busy.has(uid)) continue;
      const cooldown = Date.parse(String(u.aiCooldownUntil || ''));
      if (!isNaN(cooldown) && cooldown > now) continue;
      const userFactory = aiResolveFactory(u);

      if (aiCommander) {
        // Under AI Commander, ONLY assign supervisors in this shift's roster.
        // Cross-factory transfers are only allowed when enabled for the shift
        // AND the alert factory is completely unstaffed.
        if (!shiftSupervisorIds.has(uid)) continue;
        if (!userFactory) continue;
        if (userFactory !== factoryId && !allowCrossFactoryCandidates) {
          continue;
        }
      } else {
        // Normal mode: same factory only.
        if (!userFactory || userFactory !== factoryId) continue;
      }

      candidates.push({
        ...u,
        uid,
        factoryId: userFactory,
        factoryName: u.usine || null,
      });
    }
    if (candidates.length === 0) continue;
    const recentCounts = {};
    for (const a of Object.values(alertsMap)) {
      if (a.superviseurId && a.takenAtTimestamp && (now - new Date(a.takenAtTimestamp).getTime()) < 10 * 60 * 1000) {
        recentCounts[a.superviseurId] = (recentCounts[a.superviseurId] || 0) + 1;
      }
    }
    const scored = candidates.map((u) => {
      const recent = recentCounts[u.uid] || 0;
      const adj = reinforcementAdjustments[u.uid] || 0;
      const { score, reasons } = scoreSupervisor(
        { ...u, uid: u.uid, name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(), fcmToken: u.fcmToken },
        alert,
        supStats,
        feedbackSummary,
        recent,
        now,
        { isCommander: aiCommander, reinforcementAdjustment: adj },
      );
      return {
        uid: u.uid,
        name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(),
        fcmToken: u.fcmToken,
        factoryId: u.factoryId || null,
        factoryName: u.factoryName || u.usine || null,
        score,
        reasons,
      };
    });

    // Step 1: sort by score so the confidence calculation reflects the true best candidates.
    scored.sort((a, b) => b.score - a.score);

    // Step 2: check confidence floor against the sorted pool BEFORE any shuffle.
    // This ensures a randomly-ordered low-score pick can never falsely block a valid pool.
    const topSum = scored.slice(0, 3).reduce((s, c) => s + c.score, 0);
    const confidence = topSum > 0 ? Math.min(scored[0].score / topSum, 1.0) : 1.0;
    // Step 3: optionally shuffle so the AI Commander picks randomly from the confident pool.
    if (shiftRandomize) {
      for (let k = scored.length - 1; k > 0; k--) {
        const j = Math.floor(Math.random() * (k + 1));
        const tmp = scored[k]; scored[k] = scored[j]; scored[j] = tmp;
      }
    }
    const best = scored[0];
    let reasonSummary = best.reasons.join(' • ');
    if (aiCommander) {
      reasonSummary = `[Shift "${activeShift.name || activeShift.id}"] ` + reasonSummary;
    }
    const ok = await aiAssignAlert(alert.id, best, reasonSummary, confidence, env, token, scored);
    if (ok) {
      const transferUsed =
        aiCommander &&
        capabilities.handleCrossFactoryTransfer &&
        best.factoryId &&
        best.factoryId !== factoryId;
      const detailParts = [
        `Auto-assigned "${alert.type || 'alert'}"`,
        alert.usine ? `for ${alert.usine}` : null,
        `to ${best.name}.`,
        transferUsed
            ? `Cross-factory transfer used from ${best.factoryName || best.factoryId} to ${alert.usine || factoryId}.`
            : 'Assignment stayed within the allowed factory scope.',
        `Confidence ${(confidence * 100).toFixed(0)}%.`,
        `Reasoning: ${best.reasons.join(' | ') || 'No score breakdown provided.'}`,
      ].filter(Boolean);
      await writeShiftAiLog(env, token, activeShift?.id, {
        kind: transferUsed ? 'transfer' : 'assigned',
        alertLabel: `${alert.type || 'Alert'}${alert.usine ? ` • ${alert.usine}` : ''}`,
        supervisorName: best.name,
        supervisorId: best.uid,
        factory: alert.usine || null,
        confidence,
        reason: detailParts.join(' '),
      });
      busy.add(best.uid);
      assignedCount++;
    }
  }
  return assignedCount;
}

// ============ Shift collaboration auto-approve ============
// When AI Shift Commander is on, auto-approve collaboration requests that
// have all assistant approvals but are awaiting PM approval. Also handles
// cross-factory transfers without human intervention.

const COLLAB_LONG_FIX_MINUTES = 180;
const COLLAB_OVERLOAD_UNCLAIMED = 3;
const COLLAB_OVERLOAD_ESCALATED = 2;
const COLLAB_OVERLOAD_SCORE = 5;

function _collabDecisionAccepted(decision) {
  if (!decision) return false;
  if (typeof decision === 'string') return decision === 'accepted';
  if (typeof decision === 'object') return decision.status === 'accepted';
  return false;
}

function _collabAcceptedCollaborators(req = {}) {
  const accepted = [];
  const targetIds = Array.isArray(req.targetSupervisorIds) ? req.targetSupervisorIds : [];
  const targetNames = Array.isArray(req.targetSupervisorNames) ? req.targetSupervisorNames : [];
  for (let i = 0; i < targetIds.length; i++) {
    const supId = String(targetIds[i] || '');
    const supName = String(targetNames[i] || '');
    const decision = req.assistantDecisions?.[supId] || 'pending';
    if (_collabDecisionAccepted(decision)) {
      accepted.push({ id: supId, name: supName || supId });
    }
  }
  if (
    accepted.length === 0 &&
    req.assistantId &&
    req.assistantName &&
    req.assistantDecision === 'accepted'
  ) {
    accepted.push({
      id: String(req.assistantId),
      name: String(req.assistantName),
    });
  }
  return accepted;
}

function _buildAssistantAlertSuspensionPatch() {
  return {
    status: 'disponible',
    superviseurId: null,
    superviseurName: null,
    takenAtTimestamp: null,
    aiAssigned: false,
    aiAssignmentReason: null,
    aiConfidence: null,
    aiAssignedAt: null,
  };
}

async function suspendAcceptedAssistantAlerts(env, token, acceptedCollaborators = [], alertsMap = {}, {
  activeShift = null,
  collaborationRequestId = null,
} = {}) {
  const nowIso = new Date().toISOString();
  const suspended = [];

  for (const collaborator of acceptedCollaborators || []) {
    const assistantId = String(collaborator?.id || '');
    if (!assistantId) continue;
    const ownedAlerts = Object.entries(alertsMap || {}).filter(
      ([, alert]) =>
        alert &&
        typeof alert === 'object' &&
        String(alert.status || '').toLowerCase() === 'en_cours' &&
        String(alert.superviseurId || '') === assistantId,
    );

    for (const [alertId] of ownedAlerts) {
      try {
        const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(_buildAssistantAlertSuspensionPatch()),
        });
        if (!patchRes.ok) {
          console.error(
            `[AI-COLLAB] Failed to suspend alert ${alertId} for assistant ${assistantId}: HTTP ${patchRes.status}`,
          );
          continue;
        }

        if (alertsMap?.[alertId]) {
          Object.assign(alertsMap[alertId], _buildAssistantAlertSuspensionPatch());
        }
        suspended.push({ assistantId, alertId });

        try {
          await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              event: 'suspended_for_collaboration',
              assistantId,
              assistantName: collaborator?.name || null,
              collaborationRequestId,
              shiftId: activeShift?.id || null,
              timestamp: nowIso,
              reason:
                'AI Shift Commander suspended the assistant\'s existing claimed alert before auto-approving collaboration.',
            }),
          });
        } catch (historyErr) {
          console.error(
            `[AI-COLLAB] Failed to write suspension history for alert ${alertId}: ${historyErr.message}`,
          );
        }
      } catch (err) {
        console.error(
          `[AI-COLLAB] Failed to suspend alert ${alertId} for assistant ${assistantId}: ${err.message}`,
        );
      }
    }
  }

  return suspended;
}

function _collabAlertFactory(req = {}, alert = {}) {
  return aiResolveFactory(alert) || aiResolveFactory(req) || aiSanitizeFactoryId(req.factoryName || '');
}

function _collabAlertFactoryName(req = {}, alert = {}) {
  return String(alert?.usine || alert?.factoryName || req?.usine || req?.factoryName || _collabAlertFactory(req, alert) || '');
}

function _collabAlertIsCritical(req = {}, alert = {}) {
  return alert?.isCritical === true || req?.isCritical === true || req?.alertIsCritical === true;
}

function _collabFactoryLoad(alertsMap = {}, factoryId, now = Date.now()) {
  const fid = aiSanitizeFactoryId(factoryId);
  const load = {
    factoryId: fid,
    factoryName: fid,
    active: 0,
    unclaimed: 0,
    escalated: 0,
    critical: 0,
    staleUnclaimed: 0,
    oldestUnattendedMin: 0,
    score: 0,
    overloaded: false,
  };
  if (!fid) return load;

  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    const alertFid = aiResolveFactory(alert);
    if (!alertFid || alertFid !== fid) continue;
    if (alert.usine && load.factoryName === fid) load.factoryName = String(alert.usine);

    const status = String(alert.status || '').toLowerCase();
    if (status === 'validee' || status === 'cancelled' || status === 'canceled') continue;

    load.active++;
    if (alert.isCritical === true) load.critical++;
    if (alert.isEscalated === true) load.escalated++;

    if (status === 'disponible') {
      load.unclaimed++;
      const ts = _toMs(alert.timestamp);
      if (ts != null) {
        const ageMin = Math.max(0, Math.floor((now - ts) / 60000));
        if (ageMin > load.oldestUnattendedMin) load.oldestUnattendedMin = ageMin;
        if (ageMin >= 30) load.staleUnclaimed++;
      }
    }
  }

  load.score =
    load.unclaimed +
    load.escalated * 2 +
    load.critical * 1.5 +
    load.staleUnclaimed;
  load.overloaded =
    load.unclaimed >= COLLAB_OVERLOAD_UNCLAIMED ||
    load.escalated >= COLLAB_OVERLOAD_ESCALATED ||
    load.score >= COLLAB_OVERLOAD_SCORE;
  return load;
}

function _collabLoadReason(load) {
  const parts = [
    `${load.unclaimed} unclaimed`,
    `${load.escalated} escalated`,
    `${load.critical} critical`,
  ];
  if (load.oldestUnattendedMin > 0) {
    parts.push(`oldest unattended ${load.oldestUnattendedMin} min`);
  }
  return `${load.factoryName || load.factoryId} is overloaded: ${parts.join(', ')}.`;
}

function _collabWindowPressure(alertsMap = {}, factoryId, startMs, endMs) {
  const fid = aiSanitizeFactoryId(factoryId);
  const pressure = { unclaimed: 0, escalated: 0, slow: 0, score: 0 };
  if (!fid || startMs == null || endMs == null) return pressure;
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || typeof alert !== 'object') continue;
    const alertFid = aiResolveFactory(alert);
    if (!alertFid || alertFid !== fid) continue;
    const ts = _toMs(alert.timestamp);
    if (ts == null || ts < startMs || ts > endMs) continue;
    const status = String(alert.status || '').toLowerCase();
    if (status === 'disponible') pressure.unclaimed++;
    if (alert.isEscalated === true) pressure.escalated++;
    const elapsed = Number(alert.elapsedTime);
    if (Number.isFinite(elapsed) && elapsed >= 60) pressure.slow++;
  }
  pressure.score = pressure.unclaimed + pressure.escalated * 2 + pressure.slow;
  return pressure;
}

function _collabDurationMin(req = {}, alert = {}) {
  const elapsed = Number(alert?.elapsedTime);
  if (Number.isFinite(elapsed) && elapsed > 0) return elapsed;
  const startMs =
    _toMs(alert?.takenAtTimestamp) ??
    _toMs(req?.pmApprovedAt) ??
    _toMs(req?.approvedAt) ??
    _toMs(req?.assistantRespondedAt) ??
    _toMs(req?.timestamp);
  const endMs =
    _toMs(alert?.resolvedAt) ??
    _toMs(alert?.validatedAt) ??
    _toMs(alert?.closedAt) ??
    _toMs(req?.completedAt);
  if (startMs == null || endMs == null || endMs <= startMs) return null;
  return Math.round((endMs - startMs) / 60000);
}

function buildCollaborationLearning(reqs = {}, alertsMap = {}, usersMap = {}, now = Date.now()) {
  const learning = {
    generatedAt: new Date(now).toISOString(),
    longFixMinutes: COLLAB_LONG_FIX_MINUTES,
    pairs: {},
    assistantFactories: {},
  };

  const ensurePair = (key, requesterId, assistantId, assistantName, assistantFactoryId) => {
    if (!learning.pairs[key]) {
      learning.pairs[key] = {
        requesterId,
        assistantId,
        assistantName,
        assistantFactoryId,
        approved: 0,
        longFixes: 0,
        crossFactoryLongFixes: 0,
        overloadAfter: 0,
        worstDurationMin: 0,
        lastConcern: null,
      };
    }
    return learning.pairs[key];
  };
  const ensureFactory = (factoryId, factoryName) => {
    const fid = aiSanitizeFactoryId(factoryId);
    if (!fid) return null;
    if (!learning.assistantFactories[fid]) {
      learning.assistantFactories[fid] = {
        factoryId: fid,
        factoryName: factoryName || fid,
        approved: 0,
        longFixes: 0,
        overloadAfter: 0,
        worstDurationMin: 0,
      };
    }
    return learning.assistantFactories[fid];
  };

  for (const [reqId, req] of Object.entries(reqs || {})) {
    if (!req || typeof req !== 'object') continue;
    if (req.pmApproved !== true && req.status !== 'approved') continue;
    const alert = alertsMap?.[req.alertId] || {};
    const alertFactoryId = _collabAlertFactory(req, alert);
    const durationMin = _collabDurationMin(req, alert);
    const accepted = _collabAcceptedCollaborators(req);
    if (accepted.length === 0) continue;
    const startMs =
      _toMs(req.pmApprovedAt) ??
      _toMs(req.approvedAt) ??
      _toMs(req.assistantRespondedAt) ??
      _toMs(req.timestamp) ??
      _toMs(alert.takenAtTimestamp) ??
      _toMs(alert.timestamp);
    const endMs =
      _toMs(alert.resolvedAt) ??
      _toMs(alert.validatedAt) ??
      (startMs != null && durationMin != null ? startMs + durationMin * 60000 : null);

    for (const collaborator of accepted) {
      const user = usersMap?.[collaborator.id] || {};
      const assistantFactoryId = aiResolveFactory(user);
      if (!assistantFactoryId) continue;
      const assistantFactoryName = user.usine || user.factoryName || assistantFactoryId;
      const crossFactory = alertFactoryId && assistantFactoryId && alertFactoryId !== assistantFactoryId;
      const pairKey = `${req.requesterId || 'unknown'}|${collaborator.id}`;
      const pair = ensurePair(
        pairKey,
        String(req.requesterId || ''),
        collaborator.id,
        collaborator.name,
        assistantFactoryId,
      );
      const factory = ensureFactory(assistantFactoryId, assistantFactoryName);
      pair.approved++;
      if (factory) factory.approved++;

      if (durationMin != null && durationMin >= COLLAB_LONG_FIX_MINUTES) {
        const pressure = _collabWindowPressure(alertsMap, assistantFactoryId, startMs, endMs);
        pair.longFixes++;
        if (crossFactory) pair.crossFactoryLongFixes++;
        if (pressure.score > 0) pair.overloadAfter++;
        pair.worstDurationMin = Math.max(pair.worstDurationMin, durationMin);
        pair.lastConcern =
          `Request ${reqId} took ${Math.round(durationMin)} min` +
          (pressure.score > 0
            ? ` and ${assistantFactoryName} saw ${pressure.unclaimed} unclaimed, ${pressure.escalated} escalated, ${pressure.slow} slow alerts during that window.`
            : '.');

        if (factory) {
          factory.longFixes++;
          if (pressure.score > 0) factory.overloadAfter++;
          factory.worstDurationMin = Math.max(factory.worstDurationMin, durationMin);
        }
      }
    }
  }

  return learning;
}

function mergeCollaborationLearning(current = {}, prior = {}) {
  const merged = {
    generatedAt: current.generatedAt || new Date().toISOString(),
    longFixMinutes: COLLAB_LONG_FIX_MINUTES,
    pairs: { ...(prior?.pairs || {}) },
    assistantFactories: { ...(prior?.assistantFactories || {}) },
  };

  for (const [key, cur] of Object.entries(current?.pairs || {})) {
    const old = merged.pairs[key];
    if (!old) {
      merged.pairs[key] = cur;
      continue;
    }
    merged.pairs[key] = {
      ...old,
      ...cur,
      approved: Math.max(Number(old.approved || 0), Number(cur.approved || 0)),
      longFixes: Math.max(Number(old.longFixes || 0), Number(cur.longFixes || 0)),
      crossFactoryLongFixes: Math.max(
        Number(old.crossFactoryLongFixes || 0),
        Number(cur.crossFactoryLongFixes || 0),
      ),
      overloadAfter: Math.max(Number(old.overloadAfter || 0), Number(cur.overloadAfter || 0)),
      worstDurationMin: Math.max(
        Number(old.worstDurationMin || 0),
        Number(cur.worstDurationMin || 0),
      ),
      lastConcern: cur.lastConcern || old.lastConcern || null,
    };
  }

  for (const [key, cur] of Object.entries(current?.assistantFactories || {})) {
    const old = merged.assistantFactories[key];
    if (!old) {
      merged.assistantFactories[key] = cur;
      continue;
    }
    merged.assistantFactories[key] = {
      ...old,
      ...cur,
      approved: Math.max(Number(old.approved || 0), Number(cur.approved || 0)),
      longFixes: Math.max(Number(old.longFixes || 0), Number(cur.longFixes || 0)),
      overloadAfter: Math.max(Number(old.overloadAfter || 0), Number(cur.overloadAfter || 0)),
      worstDurationMin: Math.max(
        Number(old.worstDurationMin || 0),
        Number(cur.worstDurationMin || 0),
      ),
    };
  }

  return merged;
}

function _collabLearningRisk(req = {}, accepted = [], usersMap = {}, learning = {}) {
  let best = null;
  for (const collaborator of accepted) {
    const user = usersMap?.[collaborator.id] || {};
    const assistantFactoryId = aiResolveFactory(user);
    if (!assistantFactoryId) continue;
    const pairKey = `${req.requesterId || 'unknown'}|${collaborator.id}`;
    const pair = learning?.pairs?.[pairKey];
    const factory = learning?.assistantFactories?.[assistantFactoryId];
    const pairRisk =
      pair &&
      pair.crossFactoryLongFixes > 0 &&
      (pair.overloadAfter > 0 || pair.longFixes / Math.max(1, pair.approved) >= 0.5);
    const factoryRisk =
      factory &&
      factory.longFixes >= 2 &&
      factory.longFixes / Math.max(1, factory.approved) >= 0.5 &&
      factory.overloadAfter > 0;
    if (!pairRisk && !factoryRisk) continue;

    const risk = {
      collaborator,
      assistantFactoryId,
      assistantFactoryName: user.usine || user.factoryName || assistantFactoryId,
      confidence: Math.min(
        0.95,
        0.7 +
          (pair?.crossFactoryLongFixes || 0) * 0.08 +
          (pair?.overloadAfter || 0) * 0.07 +
          (factory?.overloadAfter || 0) * 0.03,
      ),
      reason:
        pair?.lastConcern ||
        `Past cross-factory collaborations involving ${user.usine || collaborator.name || collaborator.id} repeatedly ran long and were followed by factory pressure.`,
      worstDurationMin: Math.max(pair?.worstDurationMin || 0, factory?.worstDurationMin || 0),
    };
    if (!best || risk.confidence > best.confidence) best = risk;
  }
  return best;
}

function evaluateShiftCollaborationDecision(reqId, req, {
  acceptedCollaborators,
  alertsMap = {},
  usersMap = {},
  learning = {},
  confidence = 1,
  activeShift = null,
} = {}) {
  const alert = alertsMap?.[req.alertId] || {};
  const alertFactoryId = _collabAlertFactory(req, alert);
  const alertFactoryName = _collabAlertFactoryName(req, alert);
  const isCritical = _collabAlertIsCritical(req, alert);
  const crossFactoryAssistants = [];

  for (const collaborator of acceptedCollaborators || []) {
    const user = usersMap?.[collaborator.id] || {};
    const assistantFactoryId = aiResolveFactory(user);
    if (!assistantFactoryId || !alertFactoryId || assistantFactoryId === alertFactoryId) continue;
    crossFactoryAssistants.push({
      ...collaborator,
      factoryId: assistantFactoryId,
      factoryName: user.usine || user.factoryName || assistantFactoryId,
    });
  }

  if (!isCritical && crossFactoryAssistants.length > 0) {
    for (const assistant of crossFactoryAssistants) {
      const load = _collabFactoryLoad(alertsMap, assistant.factoryId);
      if (load.overloaded) {
        return {
          action: 'decline',
          confidence: Math.max(confidence, 0.92),
          reason:
            `AI Shift Commander declined this non-critical cross-factory collaboration to protect the whole company. ` +
            `${_collabLoadReason(load)} Pulling ${assistant.name || 'the assistant'} from that factory would likely leave unattended alerts waiting longer.`,
          checks: {
            rule: 'assistant_factory_overloaded',
            requestId: reqId,
            alertFactoryId,
            alertFactoryName,
            assistantFactoryId: assistant.factoryId,
            assistantFactoryName: assistant.factoryName,
            load,
          },
        };
      }
    }

    const learnedRisk = _collabLearningRisk(req, crossFactoryAssistants, usersMap, learning);
    if (learnedRisk) {
      return {
        action: 'decline',
        confidence: Math.max(confidence, learnedRisk.confidence),
        reason:
          `AI Shift Commander declined this non-critical cross-factory collaboration based on learned operational patterns. ` +
          `${learnedRisk.reason} The request can be retried if the alert becomes critical or the assistant factory stabilizes.`,
        checks: {
          rule: 'learned_long_fix_overload_risk',
          requestId: reqId,
          alertFactoryId,
          alertFactoryName,
          assistantFactoryId: learnedRisk.assistantFactoryId,
          assistantFactoryName: learnedRisk.assistantFactoryName,
          worstDurationMin: learnedRisk.worstDurationMin,
        },
      };
    }
  }

  const shiftName = activeShift?.name || activeShift?.id || 'active shift';
  return {
    action: 'approve',
    confidence,
    reason:
      `Auto-approved by AI Shift Commander during "${shiftName}" after company-wide load and learning checks. ` +
      (crossFactoryAssistants.length > 0
        ? `Cross-factory assistance is allowed because the alert ${isCritical ? 'is critical' : 'is not blocked by overload or learned risk'}.`
        : 'Collaboration stays within the alert factory.'),
    checks: {
      rule: 'approved_company_wide',
      requestId: reqId,
      alertFactoryId,
      alertFactoryName,
      crossFactory: crossFactoryAssistants.length > 0,
      critical: isCritical,
    },
  };
}

async function processShiftCollaborations(env, ctx) {
  const activeShift = ctx?.targetShift ?? ctx?.activeShift;
  const capabilities = commanderCapabilities(activeShift);
  if (!capabilities.aiCommander) return 0;

  const token = ctx?.token ?? (await getFirebaseToken(env));
  if (!capabilities.handleCollaborations) {
    await writeShiftAiLog(env, token, activeShift?.id, {
      kind: 'skipped',
      reason: `Collaboration approvals were skipped because "Handle Collaborations" is disabled for shift "${activeShift?.name || activeShift?.id || 'Unknown'}".`,
    });
    return 0;
  }
  const res = await fetch(`${env.FB_DB_URL}collaboration_requests.json?auth=${token}`);
  if (!res.ok) return 0;
  const reqs = (await res.json()) || {};
  let alertsMap = ctx?.alertsMap || {};
  if (Object.keys(alertsMap).length === 0) {
    try {
      const alertsRes = await fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`);
      if (alertsRes.ok) alertsMap = (await alertsRes.json()) || {};
    } catch (_) {}
  }
  const usersMap = ctx?.usersMap || {};
  let priorLearning = {};
  try {
    const learningRes = await fetch(`${env.FB_DB_URL}ai_collaboration_learning/latest.json?auth=${token}`);
    if (learningRes.ok) priorLearning = (await learningRes.json()) || {};
  } catch (_) {}
  const learning = mergeCollaborationLearning(
    buildCollaborationLearning(reqs, alertsMap, usersMap),
    priorLearning,
  );
  try {
    await fetch(`${env.FB_DB_URL}ai_collaboration_learning/latest.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(learning),
    });
  } catch (_) {}
  const minConfidence =
    typeof activeShift?.aiConfidence === 'number' ? Number(activeShift.aiConfidence) : 0.65;

  let processed = 0;
  for (const [reqId, req] of Object.entries(reqs)) {
    if (processed >= 5) break;
    if (!req || typeof req !== 'object') continue;
    if (req.status === 'approved' || req.status === 'rejected') continue;
    if (req.pmApproved === true) continue;
    if (req.requiresPMApproval === false) continue;

    const assistantDecisions = req.assistantDecisions
      ? Object.values(req.assistantDecisions)
      : [];
    const acceptedCount = assistantDecisions.filter(
      (d) => d && (d === 'accepted' || d.status === 'accepted'),
    ).length;
    const hasTopLevelAcceptance = req.assistantDecision === 'accepted';
    if (acceptedCount === 0 && !hasTopLevelAcceptance) continue;
    const denominator = assistantDecisions.length > 0 ? assistantDecisions.length : 1;
    const collabConfidence = Math.min(
      1,
      acceptedCount > 0 ? acceptedCount / denominator : 1,
    );
    if (collabConfidence < minConfidence) continue;
    const acceptedCollaborators = _collabAcceptedCollaborators(req);
    const nowIso = new Date().toISOString();
    const decision = evaluateShiftCollaborationDecision(reqId, req, {
      acceptedCollaborators,
      alertsMap,
      usersMap,
      learning,
      confidence: collabConfidence,
      activeShift,
    });
    if (decision.action === 'decline') {
      const patch = {
        status: 'rejected',
        pmApproved: false,
        pmApprovedBy: 'ai_shift_commander',
        pmApprovedShiftId: activeShift.id,
        pmDecision: 'declined',
        rejectedBy: 'ai_shift_commander',
        rejectedAt: nowIso,
        rejectionReason: decision.reason,
        aiDecision: 'declined',
        aiConfidence: Number(decision.confidence.toFixed(4)),
        aiReason: decision.reason,
        aiChecks: decision.checks,
      };
      const [patchRes] = await Promise.all([
        fetch(`${env.FB_DB_URL}collaboration_requests/${reqId}.json?auth=${token}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        }),
        req.alertId
          ? fetch(`${env.FB_DB_URL}alerts/${req.alertId}.json?auth=${token}`, {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ collaborationRequestId: null }),
            })
          : Promise.resolve({ ok: true }),
      ]);
      if (patchRes.ok) {
        processed++;
        await writeShiftAiLog(env, token, activeShift.id, {
          kind: 'collaboration_declined',
          alertLabel:
            req.alertTitle ||
            req.alertLabel ||
            req.alertType ||
            req.alertId ||
            'Collaboration request',
          supervisorName: req.requesterName || req.requesterFullName || null,
          supervisorId: req.requesterId || null,
          factory: req.factoryName || req.usine || null,
          confidence: decision.confidence,
          reason: `Declined collaboration request ${reqId}. ${decision.reason}`,
        });
        const notifyTargets = new Map();
        if (req.requesterId) notifyTargets.set(String(req.requesterId), 'requester');
        for (const collaborator of acceptedCollaborators) {
          if (collaborator.id) notifyTargets.set(String(collaborator.id), 'assistant');
        }
        for (const [uid, role] of notifyTargets.entries()) {
          await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              type: 'collaboration_rejected',
              collabRequestId: reqId,
              collaborationId: reqId,
              alertId: req.alertId || null,
              message:
                role === 'requester'
                  ? `AI Shift Commander declined your collaboration request. Reason: ${decision.reason}`
                  : `AI Shift Commander declined the collaboration request you accepted. Reason: ${decision.reason}`,
              timestamp: nowIso,
              status: 'unread',
              pushSent: false,
            }),
          });
        }
      }
      continue;
    }
    const leadAssistant = acceptedCollaborators[0];
    // Mirror the manual PM rule: an assistant cannot carry their own claimed
    // alert into a new collaboration. Suspension is best-effort and must never
    // block approval if a network write fails.
    const suspendedAlerts = await suspendAcceptedAssistantAlerts(
      env,
      token,
      acceptedCollaborators,
      alertsMap,
      {
        activeShift,
        collaborationRequestId: reqId,
      },
    );
    const patch = {
      status: 'approved',
      pmApproved: true,
      pmApprovedBy: 'ai_shift_commander',
      pmApprovedShiftId: activeShift.id,
      pmApprovedAt: nowIso,
      aiDecision: 'approved',
      aiConfidence: Number(decision.confidence.toFixed(4)),
      aiReason: decision.reason,
      aiChecks: decision.checks,
    };
    const [patchRes, alertUpdateRes] = await Promise.all([
      fetch(
        `${env.FB_DB_URL}collaboration_requests/${reqId}.json?auth=${token}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        },
      ),
      req.alertId
        ? fetch(`${env.FB_DB_URL}alerts/${req.alertId}.json?auth=${token}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              collaborators: acceptedCollaborators,
              assistantId: leadAssistant?.id || null,
              assistantName: leadAssistant?.name || null,
            }),
          })
        : Promise.resolve({ ok: true }),
    ]);
    if (patchRes.ok) {
      processed++;
      await writeShiftAiLog(env, token, activeShift.id, {
      kind: 'collaboration',
        alertLabel:
          req.alertTitle ||
          req.alertLabel ||
          req.alertType ||
          req.alertId ||
          'Collaboration request',
        supervisorName: req.requesterName || req.requesterFullName || null,
        supervisorId: req.requesterId || null,
        factory: req.factoryName || req.usine || null,
        confidence: decision.confidence,
        reason:
          `Approved collaboration request ${reqId} for shift "${activeShift.name || activeShift.id}". ` +
          `Assistant approvals: ${acceptedCount}/${denominator}. ` +
          `AI judgement: ${decision.reason} ` +
          `${suspendedAlerts.length > 0
            ? `Suspended ${suspendedAlerts.length} pre-existing claimed alert(s) so assistants start collaboration with a clean workload. `
            : ''}` +
          `Requester: ${req.requesterName || req.requesterFullName || req.requesterId || 'Unknown'}. ` +
          `${acceptedCollaborators.length > 0
            ? (alertUpdateRes.ok
                ? `Attached ${acceptedCollaborators.length} collaborator(s) to alert ${req.alertId || 'unknown'}.`
                : 'Alert collaborator sync failed.')
            : 'No collaborator roster was supplied, so only the collaboration request was approved.'}`,
      });
      // Notify the requester so the UI updates.
      if (req.requesterId) {
        await fetch(
          `${env.FB_DB_URL}notifications/${req.requesterId}.json?auth=${token}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              type: 'collab_auto_approved',
              message: `AI Shift Commander approved your collaboration request. Reason: ${decision.reason}`,
              alertId: req.alertId || null,
              collabRequestId: reqId,
              collaborationId: reqId,
              timestamp: nowIso,
              status: 'unread',
              pushSent: false,
            }),
          },
        );
      }
      if (acceptedCollaborators.length > 0) {
        for (const collaborator of acceptedCollaborators) {
          await fetch(
            `${env.FB_DB_URL}notifications/${collaborator.id}.json?auth=${token}`,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                type: 'collaboration_approved',
                message: `AI Shift Commander approved your collaboration request. You can now assist on this alert. Reason: ${decision.reason}`,
                alertId: req.alertId || null,
                collabRequestId: reqId,
                collaborationId: reqId,
                timestamp: nowIso,
                status: 'unread',
                pushSent: false,
              }),
            },
          );
        }
      }
    }
  }
  return processed;
}

// ============ Workers AI shift handover ============

async function generateShiftHandoverSummary(env, ctx, shift) {
  const alertsMap = ctx?.alertsMap || {};
  // Aggregate alerts that fell within this shift window since shift start.
  const items = [];
  let resolved = 0;
  let pending = 0;
  let critical = 0;
  for (const [, a] of Object.entries(alertsMap)) {
    if (!a) continue;
    const ts = _toMs(a.timestamp);
    if (ts == null) continue;
    // Cap to the last 12 hours to keep the prompt small.
    if (ts < Date.now() - 12 * 60 * 60 * 1000) continue;
    if (a.status === 'validee') resolved++;
    if (a.status !== 'validee') pending++;
    if (a.isCritical === true) critical++;
    if (items.length < 12) {
      items.push({
        type: a.type,
        usine: a.usine,
        status: a.status,
        critical: !!a.isCritical,
        elapsedMin: a.elapsedTime,
        description: (a.description || '').slice(0, 120),
      });
    }
  }
  let summary = `Shift "${shift.name || shift.id}" summary — Resolved: ${resolved}, Pending: ${pending}, Critical: ${critical}.`;
  // Try Workers AI for a richer summary.
  if (env && env.AI && typeof env.AI.run === 'function') {
    try {
      const prompt =
        `You are an industrial shift handover assistant. Write a concise (5 lines max) handover summary for the incoming shift. ` +
        `Resolved: ${resolved}, Pending: ${pending}, Critical: ${critical}. ` +
        `Recent alerts JSON: ${JSON.stringify(items).slice(0, 1800)}. ` +
        `Highlight risks, what needs attention next, and any cross-factory follow-ups.`;
      const out = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
        messages: [
          { role: 'system', content: 'You are concise, factual, and action-oriented.' },
          { role: 'user', content: prompt },
        ],
      });
      const text = out?.response || out?.result?.response;
      if (text && typeof text === 'string') {
        summary = text.trim();
      }
    } catch (e) {
      console.error('[SHIFT-AI] handover failed: ' + e.message);
    }
  }
  return { summary, resolved, pending, critical };
}

// Detects shifts within ~10 minutes of ending with AI Commander enabled and
// generates a handover summary exactly once (idempotent: skips if one was
// already produced within the last 15 minutes).

async function processShiftEnding(env, ctx) {
  const shiftsMap = ctx?.shiftsMap;
  if (!shiftsMap) return 0;
  const now = new Date();
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  let handoverCount = 0;
  for (const [id, shift] of Object.entries(shiftsMap || {})) {
    if (!shift || shift.aiCommander !== true) continue;
    if (!_shiftContainsTime(shift, nowMin)) continue;
    const e = Number(shift.endMinutes ?? 0);
    const s = Number(shift.startMinutes ?? 0);
    const endAbs = e >= s ? e : 1440 + e;
    const nowAbs = nowMin >= s ? nowMin : 1440 + nowMin;
    const minsToEnd = endAbs - nowAbs;
    if (minsToEnd > 10 || minsToEnd < 0) continue;
    // Skip if a handover was already generated within the last 15 minutes.
    const lastIso = shift.lastHandoverAt;
    if (lastIso && Date.now() - Date.parse(lastIso) < 15 * 60 * 1000) continue;
    const result = await generateShiftHandoverSummary(env, ctx, { id, ...shift });
    const nowIso = new Date().toISOString();
    await fetch(`${env.FB_DB_URL}shifts/${id}.json?auth=${ctx.token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        lastHandoverSummary: result.summary,
        lastHandoverAt: nowIso,
      }),
    });
    const supIds =
      shift.supervisors && typeof shift.supervisors === 'object'
        ? Object.keys(shift.supervisors)
        : [];
    for (const uid of supIds) {
      await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${ctx.token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'shift_handover',
          message: `Auto handover for "${shift.name || id}"`,
          alertDescription: result.summary,
          shiftId: id,
          timestamp: nowIso,
          status: 'unread',
        }),
      });
    }
    await writeShiftAiLog(env, ctx.token, id, {
      kind: 'handover',
      confidence: 1,
      reason:
        `Generated live handover for shift "${shift.name || id}". ` +
        `Resolved ${result.resolved}, pending ${result.pending}, critical ${result.critical}. ` +
        `Summary: ${result.summary}`,
    });
    handoverCount++;
  }
  return handoverCount;
}

async function handleShiftAiAction(request, env) {
  try {
    const body = await request.json().catch(() => ({}));
    const action = String(body?.action || 'evaluate').toLowerCase();
    const shiftId = body?.shiftId ? String(body.shiftId) : null;
    const coreCtx = await loadCoreData(env);
    let shift = null;
    if (shiftId && coreCtx.shiftsMap?.[shiftId]) {
      shift = { id: shiftId, ...coreCtx.shiftsMap[shiftId] };
    } else {
      shift = coreCtx.activeShift;
    }

    if (action === 'evaluate' || action === 'created' || action === 'updated') {
      const targetShiftId = shift?.id ?? null;
      const actionCtx = shift ? cloneCtxWithShift(coreCtx, shift) : coreCtx;
      if (targetShiftId) {
        await writeShiftAiLog(env, coreCtx.token, targetShiftId, {
          kind: action,
          reason: `AI Shift Commander received "${action}" for shift "${shift?.name || targetShiftId}" and started a live evaluation cycle.`,
        });
      }
      // Re-run AI assignment + collaboration approval immediately.
      const assignedCount = await runAIAssignments(env, actionCtx);
      const collaborationCount = await processShiftCollaborations(env, actionCtx);
      if (targetShiftId && assignedCount === 0 && collaborationCount === 0) {
        await writeShiftAiLog(env, coreCtx.token, targetShiftId, {
          kind: 'idle',
          reason:
            `Evaluation finished for shift "${shift?.name || targetShiftId}" with no new assignments or collaboration approvals to apply.`,
        });
      }
      return new Response(
        JSON.stringify({
          ok: true,
          action,
          shiftId: shift?.id ?? null,
          assignedCount,
          collaborationCount,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (action === 'handover') {
      if (!shift) {
        return new Response(JSON.stringify({ ok: false, error: 'No shift' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      const result = await generateShiftHandoverSummary(env, coreCtx, shift);
      const nowIso = new Date().toISOString();
      // Persist last handover on the shift node.
      await fetch(`${env.FB_DB_URL}shifts/${shift.id}.json?auth=${coreCtx.token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          lastHandoverSummary: result.summary,
          lastHandoverAt: nowIso,
        }),
      });
      // Notify each shift supervisor with the summary.
      const supIds =
        shift.supervisors && typeof shift.supervisors === 'object'
          ? Object.keys(shift.supervisors)
          : [];
      for (const uid of supIds) {
        await fetch(`${env.FB_DB_URL}notifications/${uid}.json?auth=${coreCtx.token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            type: 'shift_handover',
            message: `Handover for "${shift.name || shift.id}"`,
            alertDescription: result.summary,
            shiftId: shift.id,
            timestamp: nowIso,
            status: 'unread',
          }),
        });
      }
      await writeShiftAiLog(env, coreCtx.token, shift.id, {
        kind: 'handover',
        confidence: 1,
        reason:
          `Generated on-demand handover for shift "${shift.name || shift.id}". ` +
          `Resolved ${result.resolved}, pending ${result.pending}, critical ${result.critical}. ` +
          `Summary: ${result.summary}`,
      });
      return new Response(
        JSON.stringify({
          ok: true,
          summary: result.summary,
          stats: {
            resolved: result.resolved,
            pending: result.pending,
            critical: result.critical,
          },
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(JSON.stringify({ ok: false, error: 'Unknown action' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: e.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ /suggest-assignee (scoring restored) ============

export {
  commanderCapabilities,
  writeShiftAiLog,
  cloneCtxWithShift,
  aiAssignAlert,
  runAIAssignments,
  suspendAcceptedAssistantAlerts,
  buildCollaborationLearning,
  mergeCollaborationLearning,
  evaluateShiftCollaborationDecision,
  processShiftCollaborations,
  generateShiftHandoverSummary,
  processShiftEnding,
  handleShiftAiAction,
};
