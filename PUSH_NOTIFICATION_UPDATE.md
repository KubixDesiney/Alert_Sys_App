# Push Notification Updates

## Overview
Implemented the following features:

### 1. **Notification Tap Navigation**
- When a user taps a push notification, the app navigates directly to the alert detail screen
- Shows claim/stop buzzing/AI assist buttons immediately
- Implemented via `FirebaseMessaging.onMessageOpenedApp` and `_navigateToAlertDetail()`

### 2. **Assisted Alert Credit**
- When a supervisor resolves an alert that was assisted, the assistant gets credit
- Assisted alerts appear in the "Fixed Alerts" tab with an "Assisted by Supervisor Name" label
- Added fields to `AlertModel`: `wasAssisted`, `assistedBySupervisorId`, `assistedBySupervisorName`

### 3. **Supervisor Notification Bypass** (REQUIRES WORKER UPDATE)
To prevent notifications being sent to supervisors who already have an alert claimed:

Update your Cloudflare Worker (`functions/index.js` or your worker code) to:

```javascript
// After getting all supervisors, filter out those with claimed alerts
const activeAlertIds = new Set();
const alertsSnapshot = await admin.database().ref('alerts').once('value');
alertsSnapshot.forEach((alertSnap) => {
  const alert = alertSnap.val();
  if (alert.status === 'en_cours' && alert.superviseurId) {
    activeAlertIds.add(alert.superviseurId);
  }
});

// Only notify supervisors without active alerts
const fcmTokens = [];
usersSnapshot.forEach((userSnap) => {
  const user = userSnap.val();
  const fcmToken = user.fcmToken;
  
  // Only send to supervisors/admins without claimed alerts
  if (fcmToken && (user.role === 'supervisor' || user.role === 'admin')) {
    if (!activeAlertIds.has(userSnap.key)) {  // Don't notify if they have an alert
      fcmTokens.push(fcmToken);
    }
  }
});
```

## Files Modified

### Backend (Dart/Flutter)
- `lib/models/alert_model.dart` - Added assisted alert tracking fields
- `lib/services/alert_service.dart` - Updated `resolveAlert()` to track who helped
- `lib/providers/alert_provider.dart` - Pass supervisor info when resolving
- `lib/screens/dashboard_screen.dart` - Display "Assisted by" label in Fixed Alerts
- `lib/services/fcm_service.dart` - Added notification tap handlers
- `lib/main.dart` - Added navigator key for FCM navigation

### Deploy/Configuration
- **Cloudflare Worker URL**: `https://alert-notifier.aziz-nagati01.workers.dev/`
- Ensure the worker filters notifications based on claimed alerts status

## Testing Checklist

- [ ] Create a new alert and verify notification is sent
- [ ] Tap the notification and verify navigation to alert detail screen
- [ ] Claim an alert and verify notification stops showing for that supervisor
- [ ] Have one supervisor claim and another assist - verify both get credited in "Fixed Alerts" tab
- [ ] Verify "Assisted by Supervisor Name" label appears for assisted alerts
