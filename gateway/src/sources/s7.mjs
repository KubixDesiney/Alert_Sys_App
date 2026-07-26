// Siemens S7 source — polls DB addresses via the optional `nodes7` peer.
// Reading keys are the S7 address strings (e.g. "DB10,REAL4").
import { lazyImport } from '../lazy.mjs';

/** Pure: nodes7 value → numeric reading value (or null). */
export function s7Value(v) {
  if (typeof v === 'boolean') return v ? 1 : 0;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export async function createS7Source(cfg, { onReadings, log = console }) {
  const mod = await lazyImport('nodes7', { protocol: 's7' });
  const NodeS7 = mod.default || mod;
  const host = cfg.host;
  if (!host) throw new Error('s7 source needs "host"');
  const addresses = Array.isArray(cfg.addresses) && cfg.addresses.length
    ? cfg.addresses
    : (cfg.map || []).map((r) => r.match).filter((m) => m && !/[+#]/.test(m));
  if (!addresses.length) throw new Error('s7 source needs "addresses" (e.g. ["DB10,REAL4"]) or exact map rules');

  const conn = new NodeS7({ silent: true });
  await new Promise((resolve, reject) => {
    conn.initiateConnection(
      { host, port: Number(cfg.port) || 102, rack: Number(cfg.rack) || 0, slot: Number(cfg.slot) || 1 },
      (err) => (err ? reject(new Error(`s7 connect failed: ${err}`)) : resolve()),
    );
  });
  conn.setTranslationCB((tag) => tag);
  conn.addItems(addresses);

  const pollMs = Number(cfg.pollIntervalMs) || 2000;
  const timer = setInterval(() => {
    conn.readAllItems((err, values) => {
      if (err) { log.warn?.(`[sias-gateway] s7 read failed: ${err}`); return; }
      const ts = Date.now();
      const readings = [];
      for (const [addr, raw] of Object.entries(values || {})) {
        const value = s7Value(raw);
        if (value !== null) readings.push({ key: addr, value, ts });
      }
      if (readings.length) onReadings(readings);
    });
  }, pollMs);

  log.info?.(`[sias-gateway] s7 source: polling ${addresses.length} address(es) on ${host} every ${pollMs}ms`);
  return { stop: async () => { clearInterval(timer); try { conn.dropConnection(() => {}); } catch { /* shutdown */ } } };
}
