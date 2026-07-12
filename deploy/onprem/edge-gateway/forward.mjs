// Forwarder: delivers canonical alerts to the worker-runner's /ingest with a
// bounded retry queue, so a runner restart never loses an edge alert.
import { withRetry, retryableHttp } from '../worker-runner/retry.mjs';

export class Forwarder {
  constructor({
    ingestUrl,
    sharedSecret,
    maxQueue = 500,
    fetchImpl = globalThis.fetch,
    log = null,
    retry = {},
  }) {
    this.ingestUrl = ingestUrl;
    this.sharedSecret = sharedSecret;
    this.maxQueue = maxQueue;
    this.fetch = fetchImpl;
    this.log = log;
    this.retry = { attempts: 5, baseMs: 500, maxMs: 15000, shouldRetry: retryableHttp, ...retry };
    this.queue = [];
    this.stats = { sent: 0, deduped: 0, suppressed: 0, dropped: 0, failed: 0 };
    this._draining = false;
  }

  /** Enqueue + drain. Oldest alerts are dropped past maxQueue (bounded memory). */
  async send(alert) {
    this.queue.push(alert);
    if (this.queue.length > this.maxQueue) {
      this.queue.shift();
      this.stats.dropped++;
      if (this.log) this.log.warn('forward queue overflow — oldest alert dropped');
    }
    return this.drain();
  }

  async drain() {
    if (this._draining) return this.stats;
    this._draining = true;
    try {
      while (this.queue.length) {
        const alert = this.queue[0];
        try {
          const res = await withRetry(async () => {
            const r = await this.fetch(this.ingestUrl, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${this.sharedSecret}`,
              },
              body: JSON.stringify(alert),
            });
            if (!r.ok && r.status !== 422) {
              const err = new Error(`ingest ${r.status}`);
              err.status = r.status;
              throw err;
            }
            return r;
          }, this.retry);
          const body = await res.json().catch(() => ({}));
          if (body.status === 'duplicate') this.stats.deduped++;
          else if (body.status === 'suppressed') this.stats.suppressed++;
          else if (res.ok) this.stats.sent++;
          else this.stats.failed++; // 422 invalid — counted, not retried
          this.queue.shift();
        } catch (err) {
          // Retries exhausted — keep the alert queued for the next drain and
          // stop hammering; the caller's next send() (or timer) re-drains.
          this.stats.failed++;
          if (this.log) this.log.warn('forward failed, will retry on next drain', { err: String((err && err.message) || err) });
          break;
        }
      }
    } finally {
      this._draining = false;
    }
    return this.stats;
  }
}
