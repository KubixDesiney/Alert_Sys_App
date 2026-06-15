// SIA on-prem worker-runner.
// Runs the assignment cycle on a timer (instead of Cloudflare cron) against the
// on-prem PocketBase backend, reusing the cloud worker's exact scoring (vendored).
import http from 'node:http';
import { PocketBaseStore } from './store.mjs';
import { runAssignmentCycle } from './assignment.mjs';

const PB_URL = process.env.PB_URL || 'http://pocketbase:8090';
const PB_TOKEN = process.env.PB_TOKEN || '';
const INTERVAL = Number(process.env.CRON_INTERVAL_MS || 60000);

// Cloud-parity scoring is vendored into ./vendor at image build time.
let scoring = null;
try {
  scoring = await import('./vendor/cloudflare_worker.js');
  console.log('[worker-runner] scoring bundle loaded (cloud-parity assignment)');
} catch (_) {
  console.warn('[worker-runner] scoring bundle not vendored; heartbeat-only mode');
}

let lastTick = null;
let ticks = 0;
let lastSummary = null;
let lastError = null;

async function tick() {
  ticks++;
  lastTick = new Date().toISOString();
  if (!scoring) return;
  try {
    const store = new PocketBaseStore(PB_URL, PB_TOKEN);
    lastSummary = await runAssignmentCycle(store, scoring, Date.now());
    lastError = null;
    console.log(`[worker-runner] tick ${ticks}: assigned ${lastSummary.assigned}/${lastSummary.pending} pending`);
  } catch (e) {
    lastError = String((e && e.message) || e);
    console.error(`[worker-runner] tick ${ticks} error: ${lastError}`);
  }
}

setInterval(tick, INTERVAL);
tick();

http
  .createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        ok: !lastError, ticks, lastTick, lastSummary, lastError,
        scoring: !!scoring, backend: PB_URL,
      }));
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(8787, () => console.log('[worker-runner] health on :8787/health'));
