import { getFirebaseToken, base64UrlEncode } from './auth.js';
import { processAlerts } from './alerts.js';
import { handleAiProxy, handleAiSuggest } from './ai_suggest.js';
import { handleAutoFix, handleAutoFixFull } from './auto_fix.js';
import { handleBriefing } from './briefing.js';
import { corsHeaders, handleConfigRequest } from './config.js';
import { checkEscalations } from './escalation.js';
import { fanOutPendingNotifications, getFcmTokensForFactory, notifTitle } from './fcm.js';
import { _writeCronHealth } from './health.js';
import { loadCoreData } from './load_core.js';
import { buildPredictiveModel, handlePredictions, handleValidatePredictions, validatePredictions } from './predictive.js';
import { buildSupStats, countActiveSupervisorsInFactory, scoreSupervisor } from './scoring.js';
import { handleShiftAiAction, processShiftCollaborations, processShiftEnding, runAIAssignments, suspendAcceptedAssistantAlerts } from './shift_commander.js';
import { handleSuggestAssignee } from './suggest_assignee.js';
import { _aggregateWeek, _briefingDateKey, _briefingFactorySlug, _historyKey, _shiftContainsTime, _toMs, _topSupervisorWeek, _typeName, aiResolveFactory, aiSanitizeFactoryId, pickActiveShift } from './utils.js';

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        const runStart = Date.now();
        const healthErrors = [];
        let assignmentsMade = 0;
        let collaborationsApproved = 0;
        let handoversGenerated = 0;
        let cronToken;
        let lockUrl;

        try {
          cronToken = await getFirebaseToken(env);
          lockUrl = `${env.FB_DB_URL}cron_lock/latest.json?auth=${cronToken}`;
          const lockGet = await fetch(lockUrl, { headers: { 'X-Firebase-ETag': 'true' } });
          const lockEtag = lockGet.ok ? lockGet.headers.get('ETag') : null;
          const lockData = lockGet.ok ? (await lockGet.json()) : null;
          if (lockData && typeof lockData.ts === 'number' && Date.now() - lockData.ts < 55000) {
            console.log('[CRON] Skipping: another execution in flight (' + (Date.now() - lockData.ts) + 'ms ago)');
            return;
          }
          const lockPut = await fetch(lockUrl, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'if-match': lockEtag ?? '*' },
            body: JSON.stringify({ ts: Date.now() }),
          });
          if (lockPut.status === 412) {
            console.log('[CRON] Skipping: concurrent execution acquired lock');
            return;
          }
        } catch (e) {
          console.warn('[CRON] Lock acquisition failed, proceeding anyway: ' + e.message);
          healthErrors.push('lock: ' + e.message);
        }

        let coreCtx;
        try {
          coreCtx = await loadCoreData(env);
        } catch (e) {
          console.error('[CRON] Failed to load core data: ' + e.message);
          healthErrors.push('loadCoreData: ' + e.message);
          await _writeCronHealth(cronToken, env, { runStart, assignmentsMade, collaborationsApproved, handoversGenerated, errors: healthErrors });
          if (lockUrl) fetch(lockUrl, { method: 'DELETE' }).catch(() => {});
          return;
        }

        try { await processAlerts(env, coreCtx); }
        catch (e) { console.error('[CRON] processAlerts: ' + e.message); healthErrors.push('processAlerts: ' + e.message); }

        try { await checkEscalations(env, coreCtx); }
        catch (e) { console.error('[CRON] checkEscalations: ' + e.message); healthErrors.push('checkEscalations: ' + e.message); }

        try { assignmentsMade = (await runAIAssignments(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] runAIAssignments: ' + e.message); healthErrors.push('runAIAssignments: ' + e.message); }

        try { collaborationsApproved = (await processShiftCollaborations(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] processShiftCollaborations: ' + e.message); healthErrors.push('processShiftCollaborations: ' + e.message); }

        try { handoversGenerated = (await processShiftEnding(env, coreCtx)) ?? 0; }
        catch (e) { console.error('[CRON] processShiftEnding: ' + e.message); healthErrors.push('processShiftEnding: ' + e.message); }

        try { await validatePredictions(env, coreCtx); }
        catch (e) { console.error('[CRON] validatePredictions: ' + e.message); healthErrors.push('validatePredictions: ' + e.message); }

        await _writeCronHealth(coreCtx.token, env, { runStart, assignmentsMade, collaborationsApproved, handoversGenerated, errors: healthErrors });

        if (lockUrl) fetch(lockUrl, { method: 'DELETE' }).catch(() => {});
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }
    if (url.pathname === '/config') return handleConfigRequest();
    if (url.pathname === '/ai-proxy') return handleAiProxy(request, env);
    if (url.pathname === '/ai-suggest') return handleAiSuggest(request, env);
    if (url.pathname === '/predict') return handlePredictions(env);
    if (url.pathname === '/briefing') return handleBriefing(request, env);
    if (url.pathname === '/suggest-assignee') return handleSuggestAssignee(request, env);
    if (url.pathname === '/auto-fix') return handleAutoFix(request, env);
    if (url.pathname === '/auto-fix-full') return handleAutoFixFull(request, env);
    if (url.pathname === '/shift-ai-action') return handleShiftAiAction(request, env);
    if (url.pathname === '/validate-predictions') return handleValidatePredictions(env);

    if (url.pathname === '/ai-retry') {
      ctx.waitUntil(runAIAssignments(env, null));
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (url.pathname === '/notify') {
      ctx.waitUntil(
        (async () => {
          try {
            const coreCtx = await loadCoreData(env);
            await fanOutPendingNotifications(env, coreCtx);
          } catch (e) {}
        })(),
      );
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    try {
      const coreCtx = await loadCoreData(env);
      await runAIAssignments(env, coreCtx);
      await processAlerts(env, coreCtx);
      await checkEscalations(env, coreCtx);
      await processShiftCollaborations(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error: ' + e.message);
    }
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};

export {
  aiSanitizeFactoryId,
  aiResolveFactory,
  buildSupStats,
  scoreSupervisor,
  countActiveSupervisorsInFactory,
  buildPredictiveModel,
  notifTitle,
  base64UrlEncode,
  getFcmTokensForFactory,
  _toMs,
  _briefingDateKey,
  _aggregateWeek,
  _briefingFactorySlug,
  _topSupervisorWeek,
  _typeName,
  pickActiveShift,
  _shiftContainsTime,
  _writeCronHealth,
  validatePredictions,
  _historyKey,
  runAIAssignments,
  processShiftCollaborations,
  suspendAcceptedAssistantAlerts,
};
