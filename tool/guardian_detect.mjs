// Guardian detection brain (pure, tested). Maps an error / failed-log signature
// to a category, severity, target area, fix hint, and the model to use (per the
// severity routing). The autonomous fix pipeline calls this to triage a detected
// failure before generating a fix.
//
// Detection sources feed `text` here: GitHub Actions run logs (via the GitHub
// worker, conclusion=failure), Sentry/console errors, bugs/client, worker health.

export const DEFAULT_ROUTING = {
  high: 'claude-opus-4-8',     // max thinking
  medium: 'claude-sonnet-4-6', // max
  low: 'claude-haiku-4-5',
};

// Ordered — first match wins.
export const SIGNATURES = [
  { category: 'ci_node_version', severity: 'high', area: '.github/workflows',
    hint: 'A tool requires a newer Node major — bump node-version in the workflows.',
    test: (t) => /requires at least node\.?js v?\d+/i.test(t) || /wrangler requires.*node/i.test(t) },
  { category: 'ci_build', severity: 'high', area: '.github/workflows / build',
    hint: 'CI build/deploy step failed — inspect the failing job log.',
    test: (t) => /(build|compil\w+|deploy)\s+failed/i.test(t) || /process completed with exit code [1-9]/i.test(t) },
  { category: 'notifications', severity: 'high', area: 'cloudflare_notify_worker.js + FCM',
    hint: 'New-alert push not reaching supervisors.',
    test: (t) => /(alert|notif\w*|push).*(not|never|fail\w*).*(reach\w*|deliver\w*|sent|supervisor)/i.test(t) ||
                 /supervisors?.*(not|never).*(notif\w*|alert|push)/i.test(t) },
  { category: 'escalation', severity: 'high', area: 'worker/escalation.js',
    hint: 'Alerts not escalating past threshold.',
    test: (t) => /escalat\w*.*(not|never|fail\w*|stuck)/i.test(t) },
  { category: 'auth_login', severity: 'high', area: 'auth / RoleRouter',
    hint: 'Login / role routing broken.',
    test: (t) => /(login|sign[- ]?in|auth\w*).*(fail\w*|broken|denied|loop|error)/i.test(t) },
  { category: 'collaboration', severity: 'medium', area: 'collaboration_service',
    hint: 'Collaboration requests not received.',
    test: (t) => /collab\w*.*(not|never|fail\w*|miss\w*)/i.test(t) },
  { category: 'commands', severity: 'medium', area: 'voice/command dispatch',
    hint: 'Commands not sent / dispatched.',
    test: (t) => /command\w*.*(not|fail\w*).*(sent|dispatch\w*|exec\w*)/i.test(t) },
  { category: 'supervisor_ui', severity: 'medium', area: 'dashboard / supervisor tab',
    hint: 'Supervisor tab blank / not visible.',
    test: (t) => /supervisor.*(tab|view|screen).*(blank|empty|not\s+(visible|shown|load\w*))/i.test(t) },
  { category: 'forecaster', severity: 'low', area: 'lib/services/forecast',
    hint: 'Forecaster not adapting / AI not learning.',
    test: (t) => /(forecaster|model).*(not).*(learn\w*|adapt\w*|train\w*)/i.test(t) || /ai\s+not\s+learn/i.test(t) },
];

export function modelForSeverity(severity, routing = DEFAULT_ROUTING) {
  return routing[severity] || routing.medium;
}

export function classifyFailure(text, routing = DEFAULT_ROUTING) {
  const t = String(text || '');
  for (const sig of SIGNATURES) {
    if (sig.test(t)) {
      return {
        category: sig.category, severity: sig.severity, area: sig.area,
        hint: sig.hint, model: modelForSeverity(sig.severity, routing),
      };
    }
  }
  return {
    category: 'unknown', severity: 'medium', area: '',
    hint: 'Unclassified failure — manual triage.',
    model: modelForSeverity('medium', routing),
  };
}
