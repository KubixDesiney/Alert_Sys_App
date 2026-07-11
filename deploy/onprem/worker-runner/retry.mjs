// Retry with exponential backoff + full jitter. Used for every PocketBase
// call the worker-runner makes, so a PocketBase restart mid-cycle degrades to
// a delayed tick instead of a failed one.
export async function withRetry(fn, {
  attempts = 4,
  baseMs = 250,
  maxMs = 5000,
  shouldRetry = () => true,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  rand = Math.random,
} = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn(attempt);
    } catch (err) {
      lastErr = err;
      if (attempt === attempts || !shouldRetry(err)) break;
      const cap = Math.min(maxMs, baseMs * 2 ** (attempt - 1));
      await sleep(Math.floor(rand() * cap));
    }
  }
  throw lastErr;
}

/** HTTP-ish retry policy: retry network errors and 5xx/429, not other 4xx. */
export function retryableHttp(err) {
  const status = err && (err.status ?? err.statusCode);
  if (status == null) return true; // network / DNS / reset
  return status >= 500 || status === 429;
}
