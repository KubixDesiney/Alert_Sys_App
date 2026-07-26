// =============================================================================
// Forwarder — POSTs reading batches to the SIAS ingest endpoint, with retries.
// =============================================================================
// Failure policy:
//   - network errors, 429 and 5xx  → queue on disk, retry with exponential
//     backoff (these are the "plant network blip" cases; nothing is lost)
//   - 401/403                      → queue + loud warning (key rotation window)
//   - other 4xx                    → drop the batch with an error (bad config;
//     retrying a permanently-rejected payload forever would wedge the queue)
// fetch/clock are injectable so every path is unit-testable without sockets.

export class Forwarder {
  constructor({
    ingestUrl,
    ingestKey,
    queue,
    fetchImpl = globalThis.fetch,
    log = console,
    backoffBaseMs = 1000,
    backoffMaxMs = 60000,
    now = Date.now,
  } = {}) {
    if (!ingestUrl) throw new Error('Forwarder requires ingestUrl');
    this.ingestUrl = ingestUrl;
    this.ingestKey = ingestKey || '';
    this.queue = queue;
    this.fetchImpl = fetchImpl;
    this.log = log;
    this.backoffBaseMs = backoffBaseMs;
    this.backoffMaxMs = backoffMaxMs;
    this.now = now;
    this.consecutiveFailures = 0;
    this.nextRetryAt = 0;
    this.stats = { sent: 0, batches: 0, requeued: 0, droppedPermanent: 0, created: 0 };
  }

  nextDelay(attempt = this.consecutiveFailures) {
    return Math.min(this.backoffBaseMs * 2 ** Math.max(0, attempt - 1), this.backoffMaxMs);
  }

  async _post(readings) {
    return this.fetchImpl(this.ingestUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-alertsys-ingest': this.ingestKey,
      },
      body: JSON.stringify({ readings }),
    });
  }

  /** Sends one batch; on retryable failure it lands in the disk queue. */
  async send(readings) {
    if (!Array.isArray(readings) || readings.length === 0) return { ok: true, sent: 0 };
    let res;
    try {
      res = await this._post(readings);
    } catch (e) {
      this._requeue(readings, `network error: ${e?.message || e}`);
      return { ok: false, retryable: true };
    }
    if (res.ok) {
      this.consecutiveFailures = 0;
      this.nextRetryAt = 0;
      this.stats.sent += readings.length;
      this.stats.batches += 1;
      try {
        const body = await res.json();
        if (Number.isFinite(Number(body?.created))) this.stats.created += Number(body.created);
      } catch { /* status-only response is fine */ }
      return { ok: true, sent: readings.length };
    }
    if (res.status === 429 || res.status >= 500) {
      this._requeue(readings, `HTTP ${res.status}`);
      return { ok: false, retryable: true, status: res.status };
    }
    if (res.status === 401 || res.status === 403) {
      this._requeue(readings, `HTTP ${res.status} — check the connector ingest key`);
      return { ok: false, retryable: true, status: res.status };
    }
    this.stats.droppedPermanent += readings.length;
    this.log.error?.(`[sias-gateway] batch of ${readings.length} permanently rejected (HTTP ${res.status}) — dropped; check source mapping/config`);
    return { ok: false, retryable: false, status: res.status };
  }

  _requeue(readings, reason) {
    this.consecutiveFailures += 1;
    this.nextRetryAt = this.now() + this.nextDelay();
    this.stats.requeued += readings.length;
    this.queue?.enqueue(readings, this.now());
    this.log.warn?.(`[sias-gateway] send failed (${reason}) — ${readings.length} readings queued, retry in ${Math.round(this.nextDelay() / 1000)}s`);
  }

  /** Drains queued batches (oldest first) while the endpoint accepts them. */
  async drain() {
    if (!this.queue) return { drained: 0 };
    if (this.now() < this.nextRetryAt) return { drained: 0, waiting: true };
    let drained = 0;
    while (this.queue.peek()) {
      const batch = this.queue.shift();
      let res;
      try {
        res = await this._post(batch.readings);
      } catch {
        // still down — put it back at the FRONT and back off
        this.queue.batches.unshift(batch);
        this.queue._persist();
        this.consecutiveFailures += 1;
        this.nextRetryAt = this.now() + this.nextDelay();
        return { drained, waiting: true };
      }
      if (res.ok) {
        this.consecutiveFailures = 0;
        this.stats.sent += batch.readings.length;
        drained += batch.readings.length;
        continue;
      }
      if (res.status === 429 || res.status >= 500 || res.status === 401 || res.status === 403) {
        this.queue.batches.unshift(batch);
        this.queue._persist();
        this.consecutiveFailures += 1;
        this.nextRetryAt = this.now() + this.nextDelay();
        return { drained, waiting: true };
      }
      this.stats.droppedPermanent += batch.readings.length;
      this.log.error?.(`[sias-gateway] queued batch permanently rejected (HTTP ${res.status}) — dropped`);
    }
    return { drained };
  }
}
