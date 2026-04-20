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
  const title = payload.notification?.title || 'New Alert';
  const options = {
    body: payload.notification?.body || payload.data?.message,
    icon: '/icons/icon-192.png',
    data: payload.data,
  };
  return self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      if (clientList.length > 0) {
        return clientList[0].focus();
      }
      return clients.openWindow('/');
    })
  );
});