const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

exports.sendAlertPush = functions.database
  .ref('/alerts/{alertId}')
  .onCreate(async (snapshot, context) => {
    const alert = snapshot.val();
    const alertId = context.params.alertId;

    // Avoid duplicate sends
    if (alert.notificationSent) return;
    await snapshot.ref.update({ notificationSent: true });

    const usine = alert.usine || 'Unknown plant';
    const alertType = alert.type || 'Alert';
    const description = alert.description || '';

    // Get all OneSignal player IDs from users
    const usersSnapshot = await admin.database().ref('users').once('value');
    const playerIds = [];
    usersSnapshot.forEach((userSnap) => {
      const user = userSnap.val();
      const onesignalId = user.onesignalId;
      if (onesignalId && (user.role === 'supervisor' || user.role === 'admin')) {
        playerIds.push(onesignalId);
      }
    });

    if (playerIds.length === 0) {
      console.log('No OneSignal player IDs found');
      return;
    }

    const ONESIGNAL_APP_ID = '322abcb7-c4e5-4630-811f-ccea86a6f481';
    const ONESIGNAL_REST_KEY = 'os_v2_app_givlzn6e4vddbai7ztvinjxuqex4akbbf2fuwsvkc4xdwsz3gh5ves6vdzpixnhfob23ohyfc4dknmroh2q2qgkag6dbfsw6ctj34ly';

    const payload = {
      app_id: ONESIGNAL_APP_ID,
      include_player_ids: playerIds,
      headings: { en: `🚨 New Alert: ${alertType}` },
      contents: { en: `${usine} - ${description}` },
      data: { alertId, type: alertType, usine },
      android_channel_id: 'alerts',
    };

    try {
      await axios.post('https://onesignal.com/api/v1/notifications', payload, {
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Basic ${ONESIGNAL_REST_KEY}`,
        },
      });
      console.log('✅ OneSignal push sent');
    } catch (error) {
      console.error('❌ OneSignal push failed:', error.response?.data || error.message);
    }
  });