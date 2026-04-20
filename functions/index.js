const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendNewAlertNotification = functions.database
  .ref('/alerts/{alertId}')
  .onCreate(async (snapshot, context) => {
    const alert = snapshot.val();
    const alertId = context.params.alertId;

    const usersSnapshot = await admin.database().ref('users').once('value');
    const users = usersSnapshot.val();

    const tokens = [];
    for (const [uid, user] of Object.entries(users)) {
      if (user.fcmToken && (user.role === 'supervisor' || user.role === 'admin')) {
        tokens.push(user.fcmToken);
      }
    }

    if (tokens.length === 0) return;

    const payload = {
      notification: {
        title: `🔔 New ${alert.type} alert`,
        body: alert.description,
      },
      data: {
        alertId: alertId,
        alertType: alert.type,
        alertDescription: alert.description,
      },
      webpush: {
        headers: {TTL: '86400'},
      },
    };

    try {
      await admin.messaging().sendEachForMulticast({tokens, ...payload});
      console.log(`Sent notifications to ${tokens.length} devices`);
    } catch (error) {
      console.error('Error sending notifications:', error);
    }
  });