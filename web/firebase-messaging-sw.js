importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Your Firebase config – copy from firebase_options.dart (web section)
// measurementId is optional – you can omit it
firebase.initializeApp({
  apiKey: "AIzaSyAr9G-E1G_HDf2DOBoUvoqfuCXBed8mPUM",
  authDomain: "alertappsys.firebaseapp.com",
  projectId: "alertappsys",
  storageBucket: "alertappsys.firebasestorage.app",
  messagingSenderId: "284893821377",
  appId: "1:284893821377:web:cc49bb5284b409e989d740"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('Background message: ', payload);
  const title = payload.notification?.title || payload.data?.title || 'New Alert';
  const body = payload.notification?.body || payload.data?.body || payload.data?.message || '';
  const alertId = payload.data?.alertId || '';
  const options = {
    body,
    icon: '/icons/icon-192.png',
    badge: '/icons/icon-192.png',
    vibrate: [200, 100, 200, 100, 200],
    data: { ...payload.data, alertId },
    tag: alertId || 'alertsys',
    renotify: !!alertId,
  };
  return self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const alertId = event.notification.data?.alertId;
  const target = alertId ? `/?alertId=${alertId}` : '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      return clients.openWindow(target);
    })
  );
});