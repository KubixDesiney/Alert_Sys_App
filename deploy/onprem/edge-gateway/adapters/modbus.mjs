// Modbus TCP adapter — STRICTLY READ-ONLY BY CONSTRUCTION.
//
// The frame builder can only emit function codes 0x03 (Read Holding
// Registers) and 0x04 (Read Input Registers). Write function codes
// (0x05/0x06/0x0F/0x10) do not exist in this module, so the gateway is
// physically incapable of writing values or setpoints to a PLC.
//
// Pure parts (frame build/parse, register decode, register-map evaluation)
// are unit-tested against simulated byte buffers. NO REAL PLC HAS BEEN
// TESTED — validate against your own equipment in a safe environment.
import { readingToAlert } from '../mapping.mjs';

export const FC_READ_HOLDING = 0x03;
export const FC_READ_INPUT = 0x04;
const READ_ONLY_FCS = new Set([FC_READ_HOLDING, FC_READ_INPUT]);

/** Builds a Modbus TCP ADU (MBAP header + PDU) for a READ request. */
export function buildReadRequest({ txnId = 1, unitId = 1, fc = FC_READ_HOLDING, address = 0, count = 1 }) {
  if (!READ_ONLY_FCS.has(fc)) {
    throw new Error(`function code 0x${fc.toString(16)} is not a read — this gateway is read-only`);
  }
  if (count < 1 || count > 125) throw new Error('count must be 1..125');
  const buf = Buffer.alloc(12);
  buf.writeUInt16BE(txnId, 0); // transaction id
  buf.writeUInt16BE(0, 2); // protocol id
  buf.writeUInt16BE(6, 4); // length (unit + pdu)
  buf.writeUInt8(unitId, 6);
  buf.writeUInt8(fc, 7);
  buf.writeUInt16BE(address, 8);
  buf.writeUInt16BE(count, 10);
  return buf;
}

/** Parses a Modbus TCP read response into raw 16-bit registers. */
export function parseReadResponse(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 9) return { ok: false, error: 'short frame' };
  const txnId = buf.readUInt16BE(0);
  const unitId = buf.readUInt8(6);
  const fc = buf.readUInt8(7);
  if (fc & 0x80) {
    return { ok: false, error: `modbus exception 0x${buf.readUInt8(8).toString(16)}`, txnId, unitId, fc: fc & 0x7f };
  }
  if (!READ_ONLY_FCS.has(fc)) return { ok: false, error: `unexpected function code ${fc}` };
  const byteCount = buf.readUInt8(8);
  if (buf.length < 9 + byteCount) return { ok: false, error: 'truncated frame' };
  const registers = [];
  for (let i = 0; i < byteCount / 2; i++) {
    registers.push(buf.readUInt16BE(9 + i * 2));
  }
  return { ok: true, txnId, unitId, fc, registers };
}

/** Decodes registers into a typed value. wordOrder 'HL' (big, default) | 'LH'. */
export function decodeRegisters(registers, { dataType = 'uint16', wordOrder = 'HL' } = {}) {
  const regs = registers || [];
  const two = () => {
    const [a, b] = wordOrder === 'LH' ? [regs[1], regs[0]] : [regs[0], regs[1]];
    const buf = Buffer.alloc(4);
    buf.writeUInt16BE(a ?? 0, 0);
    buf.writeUInt16BE(b ?? 0, 2);
    return buf;
  };
  switch (dataType) {
    case 'uint16': return regs[0] ?? null;
    case 'int16': {
      if (regs[0] == null) return null;
      const b = Buffer.alloc(2);
      b.writeUInt16BE(regs[0], 0);
      return b.readInt16BE(0);
    }
    case 'uint32': return regs.length >= 2 ? two().readUInt32BE(0) : null;
    case 'int32': return regs.length >= 2 ? two().readInt32BE(0) : null;
    case 'float32': return regs.length >= 2 ? two().readFloatBE(0) : null;
    case 'bool': return regs[0] == null ? null : regs[0] !== 0;
    default: return regs[0] ?? null;
  }
}

/**
 * Register map entry:
 * { name, fc?, address, count?, dataType?, wordOrder?, factory, line, station,
 *   machine?, metric?, type, severity?, thresholds?, scale?, offset? }
 */
export function registerToAlert(entry, registers, { now } = {}) {
  const value = decodeRegisters(registers, entry);
  if (value == null) return null;
  return readingToAlert(
    { key: entry.name || `reg:${entry.address}` , value: typeof value === 'boolean' ? (value ? 1 : 0) : value },
    { key: entry.name, metric: entry.metric || entry.name, ...entry },
    { source: `modbus:${entry.name || entry.address}`, ...(now ? { now } : {}) },
  );
}

/**
 * Runtime poller over raw TCP (node:net — zero external deps). Read-only by
 * construction (see builder). config: { host, port?, unitId?, pollMs?,
 * registers: [entry, ...] }
 */
export async function startModbus(config, onAlert, log) {
  const net = await import('node:net');
  let txn = 0;
  let stopped = false;
  let socket = null;

  const poll = () => new Promise((resolve) => {
    socket = net.createConnection({ host: config.host, port: config.port || 502 }, async () => {
      for (const entry of config.registers || []) {
        if (stopped) break;
        // eslint-disable-next-line no-await-in-loop
        const registers = await new Promise((res) => {
          const req = buildReadRequest({
            txnId: ++txn % 0xffff,
            unitId: config.unitId || 1,
            fc: entry.fc || FC_READ_HOLDING,
            address: entry.address,
            count: entry.count || (['uint32', 'int32', 'float32'].includes(entry.dataType) ? 2 : 1),
          });
          const onData = (data) => {
            socket.off('data', onData);
            const parsed = parseReadResponse(data);
            res(parsed.ok ? parsed.registers : null);
          };
          socket.on('data', onData);
          socket.write(req);
          setTimeout(() => { socket.off('data', onData); res(null); }, config.timeoutMs || 2000);
        });
        if (registers) {
          const alert = registerToAlert(entry, registers);
          if (alert) onAlert(alert);
        }
      }
      socket.end();
      resolve();
    });
    socket.on('error', (err) => {
      if (log) log.warn('modbus poll failed', { host: config.host, err: String(err.message || err) });
      resolve();
    });
  });

  const timer = setInterval(() => { poll(); }, config.pollMs || 10000);
  poll();
  return () => { stopped = true; clearInterval(timer); if (socket) socket.destroy(); };
}
