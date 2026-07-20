// =============================================================================
// DiskQueue — on-disk retry queue so plant network blips lose nothing.
// =============================================================================
// One JSONL file of { at, readings[] } batches, mirrored in memory. Constant
// memory by construction: the queue is capped at `capReadings` total readings
// and drops OLDEST batches (with a warning) when full — under a long outage
// the freshest telemetry survives, which is what operators want. Persisted
// atomically (tmp + rename) so a crash never leaves a torn file; corrupt lines
// from an unclean shutdown are skipped on load.

import fs from 'node:fs';
import path from 'node:path';

export class DiskQueue {
  constructor(dir, { capReadings = 10000, log = console } = {}) {
    this.dir = dir;
    this.file = path.join(dir, 'queue.jsonl');
    this.capReadings = capReadings;
    this.log = log;
    this.batches = [];
    this.dropped = 0;
    fs.mkdirSync(dir, { recursive: true });
    this._load();
  }

  _load() {
    if (!fs.existsSync(this.file)) return;
    const lines = fs.readFileSync(this.file, 'utf8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const batch = JSON.parse(line);
        if (Array.isArray(batch?.readings) && batch.readings.length) this.batches.push(batch);
      } catch {
        // torn tail line from a crash — skip it, the rest of the queue is intact
      }
    }
  }

  _persist() {
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, this.batches.map((b) => JSON.stringify(b)).join('\n') + (this.batches.length ? '\n' : ''));
    fs.renameSync(tmp, this.file);
  }

  /** Total queued readings (not batches). */
  get size() {
    return this.batches.reduce((n, b) => n + b.readings.length, 0);
  }

  enqueue(readings, at = Date.now()) {
    if (!Array.isArray(readings) || readings.length === 0) return;
    this.batches.push({ at, readings });
    while (this.size > this.capReadings && this.batches.length > 1) {
      const dropped = this.batches.shift();
      this.dropped += dropped.readings.length;
      this.log.warn?.(`[sias-gateway] queue full (cap ${this.capReadings} readings) — dropped oldest batch of ${dropped.readings.length} (total dropped: ${this.dropped})`);
    }
    this._persist();
  }

  peek() {
    return this.batches[0] ?? null;
  }

  shift() {
    const batch = this.batches.shift() ?? null;
    if (batch) this._persist();
    return batch;
  }

  clear() {
    this.batches = [];
    this._persist();
  }
}
