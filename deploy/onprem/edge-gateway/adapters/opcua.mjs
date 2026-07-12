// OPC UA adapter — READ-ONLY monitored-item subscriptions.
//
// Pure part: mapping an OPC UA data change (nodeId + DataValue) onto the
// canonical alert via the rule table — unit-tested with simulated values.
// Runtime part: startOpcua() lazily imports the optional `node-opcua` package,
// opens an ANONYMOUS/READ session and creates monitored items. This module
// contains no write/call service usage, so it cannot change PLC state.
// NO REAL PLC/OPC-UA SERVER HAS BEEN TESTED against this adapter — validate
// on your own equipment in a safe environment first.
import { readingToAlert, findRule } from '../mapping.mjs';

/** Extracts a numeric value from an OPC UA DataValue-shaped object. */
export function dataValueToNumber(dataValue) {
  const v = dataValue && dataValue.value ? dataValue.value.value : dataValue?.value ?? dataValue;
  if (typeof v === 'boolean') return v ? 1 : 0;
  const num = Number(v);
  return Number.isFinite(num) ? num : null;
}

/** nodeId + DataValue + rules -> canonical alert (or null). */
export function opcuaChangeToAlert(nodeId, dataValue, rules, { now } = {}) {
  const rule = findRule(rules, String(nodeId));
  if (!rule) return null;
  const value = dataValueToNumber(dataValue);
  const ts = dataValue && (dataValue.sourceTimestamp || dataValue.serverTimestamp);
  return readingToAlert(
    { key: String(nodeId), value, timestamp: ts },
    rule,
    { source: `opcua:${nodeId}`, ...(now ? { now } : {}) },
  );
}

/**
 * Runtime. config: { endpointUrl, securityMode?, rules: [{key: nodeId, ...}],
 * samplingMs? }. Requires optional `node-opcua` at runtime (not in tests).
 */
export async function startOpcua(config, onAlert, log) {
  let opcua;
  try {
    opcua = await import('node-opcua');
  } catch (_) {
    throw new Error('opcua adapter enabled but the "node-opcua" package is not installed');
  }
  const client = opcua.OPCUAClient.create({
    endpointMustExist: false,
    connectionStrategy: { initialDelay: 1000, maxRetry: -1, maxDelay: 10000 }, // endless reconnect
  });
  await client.connect(config.endpointUrl);
  const session = await client.createSession(); // anonymous, read-only usage
  const subscription = await session.createSubscription2({
    requestedPublishingInterval: config.samplingMs || 1000,
    requestedLifetimeCount: 100,
    requestedMaxKeepAliveCount: 10,
    publishingEnabled: true,
  });
  for (const rule of config.rules || []) {
    const item = await subscription.monitor(
      { nodeId: rule.key, attributeId: opcua.AttributeIds.Value },
      { samplingInterval: config.samplingMs || 1000, discardOldest: true, queueSize: 10 },
      opcua.TimestampsToReturn.Source,
    );
    item.on('changed', (dataValue) => {
      const alert = opcuaChangeToAlert(rule.key, dataValue, config.rules || []);
      if (alert) onAlert(alert);
    });
  }
  if (log) log.info('opcua subscribed', { endpoint: config.endpointUrl, nodes: (config.rules || []).length });
  return async () => {
    try { await subscription.terminate(); await session.close(); await client.disconnect(); } catch (_) { /* closing */ }
  };
}
