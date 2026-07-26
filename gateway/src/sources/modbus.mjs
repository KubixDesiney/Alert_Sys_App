// Modbus TCP source — polls holding/input registers via the optional
// `modbus-serial` peer. Reading keys are "modbus/<unitId>/<register>".
import { lazyImport } from '../lazy.mjs';

/** Pure: raw register words + register spec → numeric value. */
export function decodeRegister(words, spec = {}) {
  if (!Array.isArray(words) || words.length === 0) return null;
  const kind = spec.kind || 'uint16';
  if (kind === 'uint16') return words[0];
  if (kind === 'int16') return words[0] > 0x7fff ? words[0] - 0x10000 : words[0];
  if (kind === 'uint32') return words.length >= 2 ? words[0] * 0x10000 + words[1] : null;
  if (kind === 'float32') {
    if (words.length < 2) return null;
    const buf = new ArrayBuffer(4);
    const view = new DataView(buf);
    view.setUint16(0, words[0]);
    view.setUint16(2, words[1]);
    const f = view.getFloat32(0);
    return Number.isFinite(f) ? Math.round(f * 1000) / 1000 : null;
  }
  return null;
}

export function modbusKey(unitId, register) {
  return `modbus/${unitId}/${register}`;
}

export async function createModbusSource(cfg, { onReadings, log = console }) {
  const { default: ModbusRTU } = await lazyImport('modbus-serial', { protocol: 'modbus' });
  const host = cfg.host;
  if (!host) throw new Error('modbus source needs "host"');
  const registers = Array.isArray(cfg.registers) ? cfg.registers : [];
  if (!registers.length) throw new Error('modbus source needs "registers": [{ register, length?, kind?, input?, unitId? }]');

  const client = new ModbusRTU();
  await client.connectTCP(host, { port: Number(cfg.port) || 502 });
  client.setTimeout(Number(cfg.timeoutMs) || 3000);

  const pollMs = Number(cfg.pollIntervalMs) || 2000;
  const timer = setInterval(async () => {
    const readings = [];
    for (const spec of registers) {
      try {
        client.setID(Number(spec.unitId ?? cfg.unitId ?? 1));
        const len = Number(spec.length) || (spec.kind === 'float32' || spec.kind === 'uint32' ? 2 : 1);
        const res = spec.input
          ? await client.readInputRegisters(Number(spec.register), len)
          : await client.readHoldingRegisters(Number(spec.register), len);
        const value = decodeRegister(res.data, spec);
        if (value !== null) {
          readings.push({ key: modbusKey(spec.unitId ?? cfg.unitId ?? 1, spec.register), value, ts: Date.now() });
        }
      } catch (e) {
        log.warn?.(`[sias-gateway] modbus read failed (register ${spec.register}): ${e?.message || e}`);
      }
    }
    if (readings.length) onReadings(readings);
  }, pollMs);

  log.info?.(`[sias-gateway] modbus source: polling ${registers.length} register(s) on ${host} every ${pollMs}ms`);
  return { stop: async () => { clearInterval(timer); try { client.close(() => {}); } catch { /* shutdown */ } } };
}
