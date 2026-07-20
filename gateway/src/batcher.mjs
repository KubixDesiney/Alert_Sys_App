// =============================================================================
// Batcher — coalesces mapped readings into bounded POSTs.
// =============================================================================
// Flush triggers: 20 readings (the ingest worker caps batches well above this)
// or 2 seconds since the first unflushed reading — whichever comes first.
// Timer functions are injectable so tests run without real time.

export class Batcher {
  constructor({ maxItems = 20, maxDelayMs = 2000, onFlush, setTimer = setTimeout, clearTimer = clearTimeout } = {}) {
    if (typeof onFlush !== 'function') throw new Error('Batcher requires an onFlush callback');
    this.maxItems = maxItems;
    this.maxDelayMs = maxDelayMs;
    this.onFlush = onFlush;
    this.setTimer = setTimer;
    this.clearTimer = clearTimer;
    this.pending = [];
    this.timer = null;
  }

  push(reading) {
    this.pending.push(reading);
    if (this.pending.length >= this.maxItems) {
      this.flush();
      return;
    }
    if (!this.timer) {
      this.timer = this.setTimer(() => this.flush(), this.maxDelayMs);
      // Never keep the process alive just for a pending flush.
      if (this.timer && typeof this.timer.unref === 'function') this.timer.unref();
    }
  }

  pushMany(readings) {
    for (const r of Array.isArray(readings) ? readings : []) this.push(r);
  }

  flush() {
    if (this.timer) {
      this.clearTimer(this.timer);
      this.timer = null;
    }
    if (this.pending.length === 0) return;
    const batch = this.pending.splice(0, this.pending.length);
    // Hand out in maxItems-sized chunks so a burst never exceeds the contract.
    for (let i = 0; i < batch.length; i += this.maxItems) {
      this.onFlush(batch.slice(i, i + this.maxItems));
    }
  }
}
