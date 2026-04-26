// UPDATED WORKER CODE - Filter out supervisors with claimed alerts
// Replace the getFcmTokensForFactory function with this new one

async function getFcmTokensForFactory(authToken, env, factoryName) {
  const usersUrl = `${env.FB_DB_URL}users.json?auth=${authToken}`;
  const alertsUrl = `${env.FB_DB_URL}alerts.json?auth=${authToken}`;
  
  // Fetch users
  const usersRes = await fetch(usersUrl);
  const usersData = await usersRes.json();
  
  // Fetch all alerts to get supervisor IDs with claimed alerts
  const alertsRes = await fetch(alertsUrl);
  const alertsData = await alertsRes.json();
  
  // Build set of supervisors with active/claimed alerts
  const supervisorsWithActivAlerts = new Set();
  if (alertsData) {
    for (const [alertId, alert] of Object.entries(alertsData)) {
      // Only skip if alert is claimed (en_cours) and assigned to a supervisor
      if (alert.status === 'en_cours' && alert.superviseurId) {
        supervisorsWithActivAlerts.add(alert.superviseurId);
        console.log(`Supervisor ${alert.superviseurId} has claimed alert ${alertId}`);
      }
    }
  }
  
  const tokens = [];
  if (usersData) {
    for (const [uid, user] of Object.entries(usersData)) {
      const role = user.role;
      const usine = user.usine;
      const token = user.fcmToken;
      
      // Skip if no token
      if (!token) continue;
      
      // Skip if supervisor with claimed alert
      if (role === 'supervisor' && supervisorsWithActivAlerts.has(uid)) {
        console.log(`Skipping notification for supervisor ${uid} (has claimed alert)`);
        continue;
      }
      
      // Add token if admin OR supervisor without claimed alerts for this factory
      if (role === 'admin' || (role === 'supervisor' && usine === factoryName)) {
        tokens.push(token);
      }
    }
  }
  
  console.log(`Found ${tokens.length} FCM tokens for factory ${factoryName} (filtered out ${supervisorsWithActivAlerts.size} with claimed alerts)`);
  return [...new Set(tokens)];
}
