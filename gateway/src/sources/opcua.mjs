// OPC-UA source — subscribes to nodeIds via the optional `node-opcua` peer.
// Reading keys are the nodeId strings, so map rules bind directly to them.
import { lazyImport } from '../lazy.mjs';

/** Pure: OPC-UA DataValue → numeric reading value (or null). */
export function opcuaValue(dataValue) {
  const v = dataValue?.value?.value;
  if (typeof v === 'boolean') return v ? 1 : 0;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export async function createOpcuaSource(cfg, { onReadings, log = console }) {
  const { OPCUAClient, AttributeIds, TimestampsToReturn } = await lazyImport('node-opcua', { protocol: 'opcua' });
  const endpoint = cfg.endpoint;
  if (!endpoint) throw new Error('opcua source needs "endpoint" (e.g. opc.tcp://plc:4840)');
  const nodeIds = Array.isArray(cfg.nodeIds) && cfg.nodeIds.length
    ? cfg.nodeIds
    : (cfg.map || []).map((r) => r.match).filter((m) => m && !/[+#]/.test(m));
  if (!nodeIds.length) throw new Error('opcua source needs "nodeIds" or exact map rules');

  const client = OPCUAClient.create({ endpointMustExist: false, connectionStrategy: { maxRetry: -1, initialDelay: 2000, maxDelay: 30000 } });
  client.on('backoff', (retry, delay) => log.warn?.(`[sias-gateway] opcua reconnect #${retry} in ${delay}ms`));
  await client.connect(endpoint);
  const session = await client.createSession();
  const subscription = await session.createSubscription2({
    requestedPublishingInterval: Number(cfg.publishingIntervalMs) || 1000,
    requestedLifetimeCount: 100,
    requestedMaxKeepAliveCount: 10,
    publishingEnabled: true,
  });
  for (const nodeId of nodeIds) {
    const item = await subscription.monitor(
      { nodeId, attributeId: AttributeIds.Value },
      { samplingInterval: Number(cfg.samplingIntervalMs) || 1000, queueSize: 10, discardOldest: true },
      TimestampsToReturn.Source,
    );
    item.on('changed', (dataValue) => {
      const value = opcuaValue(dataValue);
      if (value === null) return;
      const ts = dataValue.sourceTimestamp ? new Date(dataValue.sourceTimestamp).getTime() : Date.now();
      onReadings([{ key: String(nodeId), value, ts }]);
    });
  }
  log.info?.(`[sias-gateway] opcua source: subscribed to ${nodeIds.length} node(s) on ${endpoint}`);
  return { stop: async () => { try { await session.close(); await client.disconnect(); } catch { /* shutdown */ } } };
}
