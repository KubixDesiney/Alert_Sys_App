async function _writeCronHealth(token, env, { runStart, assignmentsMade, collaborationsApproved, handoversGenerated, errors }) {
  if (!token || !env?.FB_DB_URL) return;
  try {
    await fetch(`${env.FB_DB_URL}workers/health/lastRun.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        timestamp: new Date().toISOString(),
        assignmentsMade,
        collaborationsApproved,
        handoversGenerated,
        errors,
        durationMs: Date.now() - runStart,
      }),
    });
  } catch (e) {
    console.error('[CRON] Health write failed: ' + e.message);
  }
}

// ============ Main export ============

export { _writeCronHealth };
