// Load/scale benchmark for the Smart Industrial Alert AI assignment engine.
// Exercises the REAL worker compute hot-paths (buildSupStats + scoreSupervisor)
// at industrial volume. Measures pure compute scale (not Firebase network I/O).
//
//   node tool/load_benchmark.mjs [--sups=300] [--alerts=10000] [--decisions=2000]
//
import * as W from '../cloudflare_worker.js';

const arg = (k, d) => {
  const m = process.argv.find((a) => a.startsWith(`--${k}=`));
  return m ? Number(m.split('=')[1]) : d;
};
const NUM_SUPS = arg('sups', 300);
const NUM_ALERTS = arg('alerts', 10000);
const NUM_DECISIONS = arg('decisions', 2000);

const FACTORIES = ['AeroFloat', 'Delta', 'Delice_B', 'Usine A'];
const TYPES = ['qualite', 'maintenance', 'securite', 'production'];
const rnd = (n) => Math.floor(Math.random() * n);

const sups = Array.from({ length: NUM_SUPS }, (_, i) => ({
  uid: `sup_${i}`,
  usine: FACTORIES[i % FACTORIES.length],
  status: 'active',
}));

const alertsMap = {};
for (let i = 0; i < NUM_ALERTS; i++) {
  alertsMap[`a_${i}`] = {
    status: 'validee',
    superviseurId: `sup_${rnd(NUM_SUPS)}`,
    type: TYPES[rnd(TYPES.length)],
    elapsedTime: 5 + rnd(120),
    usine: FACTORIES[rnd(FACTORIES.length)],
    convoyeur: 1 + rnd(8),
    poste: 1 + rnd(20),
  };
}

const fmt = (n) => n.toLocaleString('en-US');
const ms = (t) => `${t.toFixed(1)} ms`;
console.log('============================================================');
console.log(' SIA AI assignment engine - load/scale benchmark');
console.log('============================================================');
console.log(` node ${process.version} | supervisors=${fmt(NUM_SUPS)} | history alerts=${fmt(NUM_ALERTS)} | decisions=${fmt(NUM_DECISIONS)}`);
console.log('');

// Phase 1: build supervisor stats from full alert history
let t0 = performance.now();
const stats = W.buildSupStats(alertsMap);
let t1 = performance.now();
const statKeys = Object.keys(stats).length;
console.log(`[1] buildSupStats over ${fmt(NUM_ALERTS)} alerts  -> ${ms(t1 - t0)}  (${fmt(statKeys)} supervisor profiles)`);

// Phase 2: assignment decisions - score EVERY supervisor for each new alert
const now = Date.now();
let calls = 0;
const perDecision = [];
const t2 = performance.now();
for (let d = 0; d < NUM_DECISIONS; d++) {
  const alert = {
    type: TYPES[rnd(TYPES.length)],
    usine: FACTORIES[rnd(FACTORIES.length)],
    convoyeur: 1 + rnd(8),
    poste: 1 + rnd(20),
    isCritical: Math.random() < 0.1,
  };
  const ds = performance.now();
  let best = null;
  for (const s of sups) {
    const r = W.scoreSupervisor(s, alert, stats[s.uid] || {}, {}, 0, now);
    calls++;
    if (!best || r.score > best.score) best = { uid: s.uid, score: r.score };
  }
  perDecision.push(performance.now() - ds);
}
const t3 = performance.now();
perDecision.sort((a, b) => a - b);
const p = (q) => perDecision[Math.min(perDecision.length - 1, Math.floor(perDecision.length * q))];
const totalScoring = t3 - t2;
const opsPerSec = calls / (totalScoring / 1000);

console.log(`[2] assignment decisions: ${fmt(NUM_DECISIONS)} alerts x ${fmt(NUM_SUPS)} supervisors = ${fmt(calls)} score ops -> ${ms(totalScoring)}`);
console.log('');
console.log('    scoreSupervisor throughput : ' + fmt(Math.round(opsPerSec)) + ' ops/sec');
console.log('    per-assignment-decision    : p50 ' + ms(p(0.5)) + ' | p95 ' + ms(p(0.95)) + ' | p99 ' + ms(p(0.99)));
console.log('');
const heap = process.memoryUsage().heapUsed / 1048576;
console.log(`    peak heap used             : ${heap.toFixed(0)} MB`);
console.log('============================================================');
console.log(' VERDICT: one worker invocation can score a ' + fmt(NUM_SUPS) +
            '-supervisor plant in ~' + p(0.5).toFixed(1) + ' ms/alert (p50).');
console.log('============================================================');
