/* web/firebase-messaging-sw.js */
importScripts("https://www.gstatic.com/firebasejs/10.12.3/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.3/firebase-messaging-compat.js");

// !! غيّر هذه القيم لقيمك الفعلية من firebase_options.dart (قسم الويب):
firebase.initializeApp({
  apiKey: "AIzaSyACEABg7nBM0UpprrKozRZMromtzc6Y5SM",
  appId: "1:776894109088:web:67ac1d863053ddf96cc0c5",
  messagingSenderId: "776894109088",
  projectId: "twasol-5acdb",
  authDomain: "twasol-5acdb.firebaseapp.com",
  storageBucket: "twasol-5acdb.firebasestorage.app",
  measurementId: "G-DT7MGQEWRS",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  // عنوان ونص افتراضيان
  const title = (payload.notification && payload.notification.title) || (payload.data && payload.data.title) || "رسالة جديدة";
  const body  = (payload.notification && payload.notification.body)  || (payload.data && payload.data.body)  || "وصلك إشعار";
  const data  = payload.data || {};
  // خزّن البيانات في notification.data لفتح /chat عند النقر
  self.registration.showNotification(title, {
    body: body,
    data: data,
  });
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const data = event.notification.data || {};
  // افتح نفس الصفحة مع باراميترات (app سيقرأها ويفتح /chat)
  const url = `/?route=${data.route || ''}&roomId=${data.roomId || ''}&root=${data.root || ''}&title=${data.title || ''}&peerUid=${data.peerUid || ''}`;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
    for (const client of clientList) {
      if ('focus' in client) return client.focus();
    }
    if (clients.openWindow) return clients.openWindow(url);
  }));
});
