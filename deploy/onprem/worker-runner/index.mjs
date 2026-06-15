// SIA on-prem worker-runner (scaffold).
// Runs assignment / escalation / notification logic on a timer instead of Cloudflare
// cron, against the on-prem PocketBase backend.
//
// PORT TODO: import the pure worker functions (scoreSupervisor, buildSupStats,
// runAIAssignments, escalation checks, notification fan-out) from ../../worker/ and swap
// the Firebase RTDB REST calls for PocketBase queries. Those functions already pass 188 tests.
import http from 'node:http';

const PB_URL = process.env.PB_URL || 'http://pocketbase:8090';
const INTERVAL = Number(process.env.CRON_INTERVAL_MS || 60000);
let lastTick = null;
let ticks = 0;

async function tick() {
  ticks++;
  lastTick = new Date().toISOString();
  // TODO: loadCoreData(PB) -> checkEscalations -> runAIAssignments ->
  //       processShiftCollaborations -> fan out notifications over LAN WebSocket/SSE.
  console.log(`[worker-runner] tick ${ticks} @ ${lastTick} (backend ${PB_URL})`);
}

setInterval(tick, INTERVAL);
tick();

http
  .createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, ticks, lastTick, backend: PB_URL }));
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(8787, () => console.log('[worker-runner] health on :8787/health'));
