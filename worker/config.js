
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_ESCALATION_CHECKS = 5;
const MAX_FANOUT = 2;

function handleConfigRequest() {
  return new Response(JSON.stringify({ message: 'Config endpoint deprecated' }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ============ Health monitoring helper ============

export {
  corsHeaders,
  MAX_ALERTS_TO_PUSH,
  MAX_ESCALATION_CHECKS,
  MAX_FANOUT,
  handleConfigRequest,
};
