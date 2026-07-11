// Alert ingestion for the on-prem runner. Accepts the canonical SIAS alert
// payload (produced by the Edge Gateway or any authorized integration),
// validates it, applies dedup + storm protection, and writes the alert with
// the same field shape the Flutter app and assignment cycle use.

/** Canonical SIAS alert payload (the gateway's output contract). */
export function validateCanonicalAlert(p = {}) {
  const errors = [];
  const str = (v) => (v == null ? '' : String(v).trim());
  const factory = str(p.factory || p.usine);
  const type = str(p.type).toLowerCase();
  if (!factory) errors.push('factory is required');
  if (!type) errors.push('type is required');
  const line = Number(p.line ?? p.convoyeur ?? 0);
  const station = Number(p.station ?? p.poste ?? 0);
  if (!Number.isFinite(line) || line < 0) errors.push('line must be a non-negative number');
  if (!Number.isFinite(station) || station < 0) errors.push('station must be a non-negative number');
  const severity = str(p.severity || 'normal').toLowerCase();
  if (!['normal', 'critical'].includes(severity)) errors.push('severity must be normal|critical');
  let ts = str(p.timestamp);
  if (ts) {
    const parsed = Date.parse(ts);
    if (Number.isNaN(parsed)) errors.push('timestamp must be ISO-8601');
    else ts = new Date(parsed).toISOString();
  }
  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    normalized: {
      factory,
      line: Math.trunc(line),
      station: Math.trunc(station),
      machine: str(p.machine || p.assetId) || null,
      metric: str(p.metric) || null,
      value: p.value == null || p.value === '' ? null : Number(p.value),
      severity,
      type,
      description: str(p.description).slice(0, 2000),
      timestamp: ts || null,
      source: str(p.source) || 'ingest',
    },
  };
}

export function canonicalToAlertRecord(n, { alertNumber, now = new Date() } = {}) {
  return {
    type: n.type,
    usine: n.factory,
    convoyeur: n.line,
    poste: n.station,
    alertNumber: alertNumber ?? 0,
    adresse: `${n.factory.replace(/ /g, '_')}_C${n.line}_P${n.station}`,
    ...(n.machine ? { assetId: n.machine } : {}),
    source: n.source,
    timestamp: n.timestamp || now.toISOString(),
    description: n.description ||
      `${n.type} signal${n.metric ? ` (${n.metric}${n.value != null ? `=${n.value}` : ''})` : ''} from ${n.source}`,
    status: 'disponible',
    comments: [],
    isCritical: n.severity === 'critical',
  };
}

/**
 * Full ingestion pass: validate -> dedup/storm -> persist -> audit.
 * @returns {{status:'created'|'duplicate'|'suppressed'|'invalid', id?:string,
 *            errors?:string[], stormAlertId?:string}}
 */
export async function ingestAlert(store, guard, payload, {
  now = Date.now(),
  audit = async () => {},
} = {}) {
  const v = validateCanonicalAlert(payload);
  if (!v.ok) return { status: 'invalid', errors: v.errors };
  const n = v.normalized;

  const verdict = guard.check(
    { usine: n.factory, convoyeur: n.line, poste: n.station, type: n.type, source: n.source },
    now,
  );

  if (verdict.action === 'duplicate') {
    await audit('ingest.duplicate', { detail: `dedup ${verdict.key}` });
    return { status: 'duplicate' };
  }

  if (verdict.action === 'suppress') {
    let stormAlertId;
    if (verdict.stormStarted !== undefined) {
      // One meta-alert per storm, flagged critical so operators see the flood
      // as a single actionable event instead of a thousand buzzes.
      const rec = canonicalToAlertRecord(
        {
          ...n,
          type: 'maintenance',
          severity: 'critical',
          description:
            `ALERT STORM detected from source "${verdict.stormStarted || 'all sources'}" — ` +
            'further alerts from it are being suppressed. Check the equipment/gateway.',
          source: 'worker-runner',
        },
        { alertNumber: await nextAlertNumber(store), now: new Date(now) },
      );
      stormAlertId = await store.createAlert(rec);
      await audit('ingest.storm_started', {
        detail: `source=${verdict.stormStarted || 'global'}`,
        targetId: stormAlertId,
      });
    }
    return { status: 'suppressed', stormAlertId };
  }

  const rec = canonicalToAlertRecord(n, {
    alertNumber: await nextAlertNumber(store),
    now: new Date(now),
  });
  const id = await store.createAlert(rec);
  await audit('ingest.created', {
    targetId: id,
    factoryId: n.factory,
    detail: `${n.type} @ ${n.factory} C${n.line} P${n.station} (${n.source})`,
  });
  return { status: 'created', id };
}

export async function nextAlertNumber(store) {
  try {
    const alerts = await store.listAlerts();
    let max = 0;
    for (const a of alerts) {
      const num = Number(a.alertNumber);
      if (Number.isFinite(num) && num > max) max = num;
    }
    return max + 1;
  } catch (_) {
    return 0;
  }
}
