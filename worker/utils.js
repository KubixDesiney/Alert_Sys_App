function _briefingDateKey(date) {
  const d = new Date(date);
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function _typeName(type) {
  switch (String(type || '')) {
    case 'qualite': return 'Quality';
    case 'maintenance': return 'Maintenance';
    case 'defaut_produit': return 'Damaged Product';
    case 'manque_ressource': return 'Resource Deficiency';
    default: return String(type || '');
  }
}

function _toMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function _aggregateWeek(alertsMap = {}, factoryFilter = null) {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const stats = {
    total: 0,
    solved: 0,
    inProgress: 0,
    pending: 0,
    critical: 0,
    aiAssigned: 0,
    fastestMin: 0,
    slowestMin: 0,
    avgResolutionMin: 0,
    byType: {},
    byFactory: {},
  };
  let resolutionCount = 0;
  let resolutionTotal = 0;
  for (const alert of Object.values(alertsMap || {})) {
    const ts = _toMs(alert?.timestamp);
    if (ts == null || ts < cutoff) continue;
    if (factoryFilter && String(alert?.usine || '') !== factoryFilter) continue;
    stats.total++;
    if (alert?.isCritical === true) stats.critical++;
    if (alert?.aiAssigned === true) stats.aiAssigned++;
    const type = String(alert?.type || '');
    const factory = String(alert?.usine || '');
    stats.byType[type] = (stats.byType[type] || 0) + 1;
    stats.byFactory[factory] = (stats.byFactory[factory] || 0) + 1;
    if (alert?.status === 'validee') {
      stats.solved++;
      const elapsed = Number(alert?.elapsedTime);
      if (Number.isFinite(elapsed)) {
        resolutionCount++;
        resolutionTotal += elapsed;
        if (stats.fastestMin === 0 || elapsed < stats.fastestMin) stats.fastestMin = elapsed;
        if (elapsed > stats.slowestMin) stats.slowestMin = elapsed;
      }
    } else if (alert?.status === 'en_cours') {
      stats.inProgress++;
    } else if (alert?.status === 'disponible') {
      stats.pending++;
    }
  }
  if (resolutionCount > 0) {
    stats.avgResolutionMin = Math.round(resolutionTotal / resolutionCount);
  }
  return stats;
}

// Returns a safe slug for a factory name usable as a Firebase path segment.

function _briefingFactorySlug(factory) {
  return String(factory || '').toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');
}

// Returns the top performing supervisor (by resolved alert count) in the past 7 days.

function _topSupervisorWeek(alertsMap = {}, usersMap = {}, factoryFilter = null) {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const counts = {};
  for (const alert of Object.values(alertsMap || {})) {
    const ts = _toMs(alert?.timestamp);
    if (ts == null || ts < cutoff || alert?.status !== 'validee') continue;
    if (factoryFilter && String(alert?.usine || '') !== factoryFilter) continue;
    const uid = alert?.superviseurId;
    if (!uid) continue;
    if (!counts[uid]) {
      const user = usersMap[uid] || {};
      const fullName = user.fullName || `${user.firstName || ''} ${user.lastName || ''}`.trim() || uid;
      counts[uid] = { name: fullName, count: 0, totalTime: 0, byType: {} };
    }
    counts[uid].count++;
    const type = String(alert?.type || '');
    counts[uid].byType[type] = (counts[uid].byType[type] || 0) + 1;
    const elapsed = Number(alert?.elapsedTime);
    if (Number.isFinite(elapsed)) counts[uid].totalTime += elapsed;
  }
  const entries = Object.values(counts).sort((a, b) => b.count - a.count);
  if (entries.length === 0) return null;
  const top = entries[0];
  const topTypeEntry = Object.entries(top.byType).sort((a, b) => b[1] - a[1])[0];
  return {
    name: top.name,
    count: top.count,
    topType: topTypeEntry ? topTypeEntry[0] : null,
    avgMin: top.count > 0 ? Math.round(top.totalTime / top.count) : null,
  };
}

// ============ Scoring helpers ============

function _shiftContainsTime(shift, nowMin) {
  const s = Number(shift?.startMinutes ?? 0);
  const e = Number(shift?.endMinutes ?? 0);
  if (e >= s) return nowMin >= s && nowMin < e;
  return nowMin >= s || nowMin < e;
}

function pickActiveShift(shiftsMap, now = new Date()) {
  if (!shiftsMap) return null;
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  for (const [id, shift] of Object.entries(shiftsMap || {})) {
    if (!shift || typeof shift !== 'object') continue;
    if (_shiftContainsTime(shift, nowMin)) {
      return { id, ...shift };
    }
  }
  return null;
}

// ============ Core data loader ============

const _AI_FALLBACK = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';

const _TYPE_LABELS = {
  qualite: 'Quality',
  maintenance: 'Maintenance',
  defaut_produit: 'Damaged Product',
  manque_ressource: 'Resource Deficiency',
};

function _historyKey(iso) {
  return String(iso).replace(/[:.]/g, '-');
}

function aiSanitizeFactoryId(input) {
  return String(input || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function aiResolveFactory(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const fid = String(obj.factoryId || '').trim();
  if (fid) return aiSanitizeFactoryId(fid);
  const usine = String(obj.usine || '').trim();
  return usine ? aiSanitizeFactoryId(usine) : null;
}

// Great-circle distance in kilometres between two {lat,lng} pairs.
// Returns null when either coordinate is missing or non-numeric.
function haversineKm(a, b) {
  if (!a || !b) return null;
  const lat1 = Number(a.lat);
  const lng1 = Number(a.lng);
  const lat2 = Number(b.lat);
  const lng2 = Number(b.lng);
  if (!Number.isFinite(lat1) || !Number.isFinite(lng1)) return null;
  if (!Number.isFinite(lat2) || !Number.isFinite(lng2)) return null;
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const s1 = Math.sin(dLat / 2);
  const s2 = Math.sin(dLng / 2);
  const x = s1 * s1 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * s2 * s2;
  return 2 * R * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

// Read factory locations once, keyed by sanitized factory id.
// Sourced from `hierarchy/factories/{id}/location` first, falling back to
// the worker-managed `factories/{id}/location` mirror used elsewhere.
async function loadFactoryLocations(env, token) {
  const out = {};
  const merge = (raw) => {
    if (!raw || typeof raw !== 'object') return;
    for (const [key, value] of Object.entries(raw)) {
      if (!value || typeof value !== 'object') continue;
      const loc = value.location;
      if (!loc || typeof loc !== 'object') continue;
      const lat = Number(loc.lat);
      const lng = Number(loc.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const id = aiSanitizeFactoryId(key);
      if (!out[id]) out[id] = { lat, lng };
    }
  };
  try {
    const [hRes, fRes] = await Promise.all([
      fetch(`${env.FB_DB_URL}hierarchy/factories.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}factories.json?auth=${token}`),
    ]);
    if (hRes.ok) merge(await hRes.json());
    if (fRes.ok) merge(await fRes.json());
  } catch (_) {}
  return out;
}

export {
  _briefingDateKey,
  _typeName,
  _toMs,
  _aggregateWeek,
  _briefingFactorySlug,
  _topSupervisorWeek,
  _shiftContainsTime,
  pickActiveShift,
  _AI_FALLBACK,
  _TYPE_LABELS,
  _historyKey,
  aiSanitizeFactoryId,
  aiResolveFactory,
  haversineKm,
  loadFactoryLocations,
};
