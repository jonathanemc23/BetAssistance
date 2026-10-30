// BetPilot's service worker: shows the live bet alerts the alert server
// pushes (kick-off, goals, full time), also when the app is closed. On
// iPhone this works for the home-screen app on iOS 16.4 and later.
// Registered by lib/data/push_channel_web.dart.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  // Safari stops delivering to a site that receives a push without showing
  // a notification, so one is always shown.
  event.waitUntil(
    self.registration.showNotification(data.title || 'BetPilot', {
      body: data.body || '',
      // One notification per match, replaced as the game goes on.
      tag: data.tag,
      renotify: Boolean(data.tag),
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { url: data.url || './' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || './', self.registration.scope).href;
  event.waitUntil(
    (async () => {
      const open = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of open) {
        if (client.url.startsWith(self.registration.scope) && 'focus' in client) return client.focus();
      }
      return self.clients.openWindow(url);
    })(),
  );
});
