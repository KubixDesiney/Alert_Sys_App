// =============================================================================
// Gateway runtime — wires sources → mapping → batcher → forwarder (+ queue).
// =============================================================================
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mapReadings } from './mapping.mjs';
import { Batcher } from './batcher.mjs';
import { DiskQueue } from './queue.mjs';
import { Forwarder } from './forwarder.mjs';
import { SimSource, simMapRules } from './sources/sim.mjs';

const GATEWAY_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function createSource(sourceCfg, handlers) {
  switch (sourceCfg.type) {
    case 'sim':
      return new SimSource({
        machines: sourceCfg.machines,
        faultEveryMs: sourceCfg.faultEveryMs,
        intervalMs: sourceCfg.intervalMs,
        seed: sourceCfg.seed,
      }).start(handlers);
    case 'opcua': return (await import('./sources/opcua.mjs')).createOpcuaSource(sourceCfg, handlers);
    case 'modbus': return (await import('./sources/modbus.mjs')).createModbusSource(sourceCfg, handlers);
    case 's7': return (await import('./sources/s7.mjs')).createS7Source(sourceCfg, handlers);
    case 'mqtt': return (await import('./sources/mqtt.mjs')).createMqttSource(sourceCfg, handlers);
    default: throw new Error(`Unknown source type: ${sourceCfg.type}`);
  }
}

export class Gateway {
  constructor(config, { dryRun = false, log = console, queueDir } = {}) {
    this.config = config;
    this.dryRun = dryRun;
    this.log = log;
    this.sources = [];
    this.stats = { mapped: 0, unmapped: 0 };
    if (!dryRun) {
      this.queue = new DiskQueue(queueDir || path.join(GATEWAY_DIR, 'queue'), { log });
      this.forwarder = new Forwarder({
        ingestUrl: config.ingestUrl,
        ingestKey: config.ingestKey,
        queue: this.queue,
        log,
      });
    }
    this.batcher = new Batcher({
      maxItems: 20,
      maxDelayMs: 2000,
      onFlush: (batch) => this._onFlush(batch),
    });
  }

  _onFlush(batch) {
    if (this.dryRun) {
      for (const payload of batch) this.log.info?.(JSON.stringify(payload));
      return;
    }
    this.forwarder.send(batch).catch((e) => this.log.error?.(`[sias-gateway] send crashed: ${e?.message || e}`));
  }

  _onReadings(sourceCfg, rules) {
    return (readings) => {
      const { mapped, unmapped } = mapReadings(readings, rules, { source: sourceCfg.type });
      this.stats.mapped += mapped.length;
      this.stats.unmapped += unmapped;
      this.batcher.pushMany(mapped);
    };
  }

  async start() {
    for (const sourceCfg of this.config.sources) {
      const rules = sourceCfg.type === 'sim' && (!sourceCfg.map || !sourceCfg.map.length)
        ? simMapRules(sourceCfg.machines || 6, sourceCfg.factory)
        : sourceCfg.map || [];
      const src = await createSource(sourceCfg, {
        onReadings: this._onReadings(sourceCfg, rules),
        log: this.log,
      });
      this.sources.push(src);
    }
    if (!this.dryRun) {
      // One clean status line per cycle + periodic queue drain.
      this._statusTimer = setInterval(() => {
        this.forwarder.drain().catch(() => {});
        const f = this.forwarder.stats;
        this.log.info?.(
          `[sias-gateway] sent=${f.sent} alerts=${f.created} queued=${this.queue.size} ` +
          `requeued=${f.requeued} dropped=${this.queue.dropped + f.droppedPermanent} unmapped=${this.stats.unmapped}`,
        );
      }, parseInt(this.config.statusIntervalMs, 10) || 10000);
      if (this._statusTimer.unref) this._statusTimer.unref();
    }
    return this;
  }

  async stop() {
    for (const s of this.sources) {
      try { await s.stop?.(); } catch { /* shutdown */ }
    }
    if (this._statusTimer) clearInterval(this._statusTimer);
    this.batcher.flush();
  }
}
