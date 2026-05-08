import { aiSanitizeFactoryId, aiResolveFactory } from './utils.js';

function buildSupStats(alertsMap = {}) {
  const stats = {};
  const ensure = (uid) => {
    if (!stats[uid]) {
      stats[uid] = {
        typeCounts: {},
        typeTotalTimes: {},
        stationCounts: {},
        conveyorCounts: {},
      };
    }
    return stats[uid];
  };
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || alert.status !== 'validee') continue;
    if (typeof alert.elapsedTime !== 'number' || !Number.isFinite(alert.elapsedTime)) continue;
    const ids = [alert.superviseurId, alert.assistantId].filter(Boolean);
    if (ids.length === 0) continue;
    const type = String(alert.type || 'unknown');
    const factory = String(alert.usine || '');
    const stationKey = `${factory}|${alert.convoyeur}|${alert.poste}`;
    const conveyorKey = `${factory}|${alert.convoyeur}`;
    for (const uid of ids) {
      const entry = ensure(uid);
      entry.typeCounts[type] = (entry.typeCounts[type] || 0) + 1;
      entry.typeTotalTimes[type] = (entry.typeTotalTimes[type] || 0) + alert.elapsedTime;
      entry.stationCounts[stationKey] = (entry.stationCounts[stationKey] || 0) + 1;
      entry.conveyorCounts[conveyorKey] = (entry.conveyorCounts[conveyorKey] || 0) + 1;
    }
  }
  for (const id of Object.keys(stats)) {
    const s = stats[id];
    s.typeAvgRes = {};
    for (const type of Object.keys(s.typeTotalTimes)) {
      if (s.typeCounts[type] > 0) {
        s.typeAvgRes[type] = Math.round(s.typeTotalTimes[type] / s.typeCounts[type]);
      }
    }
  }
  return stats;
}

function scoreSupervisor(sup, alert, stats, feedbackSummary, recentAssignments, now, { isCommander = false, reinforcementAdjustment = 0 } = {}) {
  let score = 0;
  const reasons = [];
  const supFactory = aiSanitizeFactoryId(sup?.usine || sup?.factoryId || '');
  const alertFactory = aiSanitizeFactoryId(alert?.usine || alert?.factoryId || '');
  const supStats = stats[sup.uid] || {};
  const type = alert.type || '';
  const typeCount = supStats.typeCounts?.[type] || 0;

  if (alertFactory && supFactory && alertFactory === supFactory) {
    score += 30;
    reasons.push('Same factory (+30)');
  } else if (!isCommander) {
    // Under AI Shift Commander the cross-factory penalty is waived so that
    // experienced shift members from other factories can compete fairly.
    score -= 25;
    reasons.push('Different factory (−25)');
  }

  if (typeCount > 0) {
    const bonus = Math.min(typeCount * 4, 40);
    score += bonus;
    reasons.push(`${typeCount} past ${type} resolved (+${bonus})`);
  } else {
    reasons.push(`No prior ${type} experience`);
  }

  const avgTime = supStats.typeAvgRes?.[type];
  if (avgTime !== undefined && avgTime !== null) {
    const speedBonus = Math.min(Math.max(0, 60 - avgTime), 25);
    score += speedBonus;
    reasons.push(`Avg resolution ${Math.floor(avgTime)}min (+${Math.floor(speedBonus)})`);
  }

  const stationKey = `${alert.usine || ''}|${alert.convoyeur}|${alert.poste}`;
  const stationCount = supStats.stationCounts?.[stationKey] || 0;
  if (stationCount > 0) {
    const bonus = Math.min(stationCount * 6, 30);
    score += bonus;
    reasons.push(`${stationCount} fixes at workstation (+${bonus})`);
  }

  const convKey = `${alert.usine || ''}|${alert.convoyeur}`;
  const convCount = supStats.conveyorCounts?.[convKey] || 0;
  if (convCount > 0) {
    const bonus = Math.min(convCount * 1.5, 15);
    score += bonus;
    reasons.push(`${convCount} fixes on line (+${bonus})`);
  }

  if (!alert.isCritical && recentAssignments > 0) {
    const penalty = recentAssignments * 8;
    score -= penalty;
    reasons.push(`Recent load (−${penalty})`);
  }

  const fb = feedbackSummary[sup.uid] || {};
  const adjustment = Math.min(Math.max(
    (fb.acceptedAssignments || 0) * 2 +
    (fb.resolvedOutcomes || 0) * 3 -
    (fb.rejectedAssignments || 0) * 2 -
    (fb.abortedAssignments || 0) * 1.5,
    -20
  ), 20);
  if (adjustment !== 0) {
    score += adjustment;
    reasons.push(`Feedback adjustment (${adjustment > 0 ? '+' : ''}${adjustment})`);
  }

  // Reinforcement adjustment — same ±15% cap as the Dart AIScoringEngine.
  // Only apply if the base score is positive (to match Dart's maxAdj > 0 check).
  if (reinforcementAdjustment !== 0) {
    const raw = score;
    const maxAdj = raw * 0.15;
    if (maxAdj > 0) {
      const clamped = Math.max(-maxAdj, Math.min(maxAdj, reinforcementAdjustment));
      if (Math.abs(clamped) >= 0.01) {
        score += clamped;
        const rounded = Math.round(clamped);
        reasons.push(`Reinforcement adjustment (${rounded > 0 ? '+' : ''}${rounded})`);
      }
    }
  }

  return { score: Math.max(0, Math.round(score)), reasons };
}

// ============ Predictive model ============

const AI_COOLDOWN_MS = 10 * 60 * 1000;
const AI_ACTIVE_STATUSES = new Set(['active', 'available']);

// Cross-factory transfers are a last-resort safety valve.
// "Busy" supervisors still count as present in their own factory, so another
// plant can only lend help when the destination factory has zero active or
// available supervisors overall.
function countActiveSupervisorsInFactory(usersMap = {}, factoryId) {
  const fid = aiSanitizeFactoryId(factoryId);
  if (!fid) return 0;
  let count = 0;
  for (const user of Object.values(usersMap || {})) {
    if (!user || user.role !== 'supervisor') continue;
    if (!AI_ACTIVE_STATUSES.has(String(user.status || '').toLowerCase())) continue;
    if (aiResolveFactory(user) !== fid) continue;
    count++;
  }
  return count;
}

export {
  buildSupStats,
  scoreSupervisor,
  AI_COOLDOWN_MS,
  AI_ACTIVE_STATUSES,
  countActiveSupervisorsInFactory,
};
