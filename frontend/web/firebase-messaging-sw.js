importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

// إعدادات مشروعك
firebase.initializeApp({
  apiKey: "AIzaSyC1K1Mu8MJdTohr9cG8qPdEH2I1uqUBu3c",
  appId: "1:708857098134:web:db3aaf099888f0df9377b7",
  messagingSenderId: "708857098134",
  projectId: "diyah-app",
  authDomain: "diyah-app.firebaseapp.com",
  storageBucket: "diyah-app.firebasestorage.app"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  return self.registration.showNotification(
    notificationTitle,
    notificationOptions
  );
});
