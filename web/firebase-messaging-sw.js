importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Per-tenant web delivery: this ONE service worker serves every customer. The
// shared sias-app Cloudflare worker serves the current tenant's Firebase
// messaging config at /__swconfig (resolved from the request Host) — see
// cloudflare_app_worker.js. We fetch it at runtime instead of hardcoding a
// single project, so Company A's SW can never initialize against Company B.
//
// (Local `flutter run -d chrome` has no worker in front, so /__swconfig 404s and
// background messaging simply stays uninitialized — foreground FCM still works.)

// Notification-click routing needs no Firebase, so register it eagerly.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const alertId = event.notification.data && event.notification.data.alertId;
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

(async () => {
  try {
    const res = await fetch('/__swconfig', { cache: 'no-store' });
    if (!res.ok) throw new Error('swconfig HTTP ' + res.status);
    const config = await res.json();
    if (!config || !config.projectId) throw new Error('swconfig missing projectId');

    firebase.initializeApp(config);
    const messaging = firebase.messaging();

    messaging.onBackgroundMessage((payload) => {
      const title = (payload.notification && payload.notification.title) ||
        (payload.data && payload.data.title) || 'New Alert';
      const body = (payload.notification && payload.notification.body) ||
        (payload.data && (payload.data.body || payload.data.message)) || '';
      const alertId = (payload.data && payload.data.alertId) || '';
      const options = {
        body,
        icon: '/icons/icon-192.png',
        badge: '/icons/icon-192.png',
        vibrate: [200, 100, 200, 100, 200],
        data: Object.assign({}, payload.data, { alertId }),
        tag: alertId || 'alertsys',
        renotify: !!alertId,
      };
      return self.registration.showNotification(title, options);
    });
  } catch (e) {
    console.warn('[SIAS SW] background messaging not initialized:', e && e.message);
  }
})();
