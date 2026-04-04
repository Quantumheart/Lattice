'use strict';

// Import Flutter's service worker for caching/offline support.
// This file is generated during `flutter build web` and may not exist in dev.
try {
  importScripts('./flutter_service_worker.js');
} catch (e) {
  // flutter_service_worker.js not available (e.g. dev mode) — continue without caching.
}

// ── Push event ────────────────────────────────────────────────
self.addEventListener('push', function (event) {
  if (!event.data) return;

  var payload;
  try {
    payload = event.data.json();
  } catch (e) {
    return;
  }

  var notification = payload.notification || {};
  var roomId = notification.room_id;
  var roomName = notification.room_name || 'New message';
  var senderName = notification.sender_display_name;
  var body = senderName ? senderName + ': New message' : 'You have a new message';
  var counts = notification.counts || {};

  event.waitUntil(
    self.registration.showNotification(roomName, {
      body: body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-maskable-192.png',
      tag: roomId || 'lattice-push',
      renotify: !!roomId,
      data: { roomId: roomId, unreadCount: counts.unread || 0 },
    }).then(function () {
      if (navigator.setAppBadge) {
        navigator.setAppBadge(counts.unread || 0);
      }
    })
  );
});

// ── Notification click ────────────────────────────────────────
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  if (navigator.clearAppBadge) {
    navigator.clearAppBadge();
  }

  var roomId = (event.notification.data || {}).roomId;
  var urlPath = roomId ? '/#/rooms/' + encodeURIComponent(roomId) : '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if (client.url.indexOf(self.registration.scope) !== -1) {
          client.postMessage({ type: 'notification_click', roomId: roomId });
          return client.focus();
        }
      }
      return self.clients.openWindow(urlPath);
    })
  );
});

// ── Subscription change ──────────────────────────────────────
self.addEventListener('pushsubscriptionchange', function (event) {
  event.waitUntil(
    self.registration.pushManager.subscribe(event.oldSubscription.options)
      .then(function (newSubscription) {
        return self.clients.matchAll({ type: 'window' }).then(function (clientList) {
          for (var i = 0; i < clientList.length; i++) {
            clientList[i].postMessage({
              type: 'pushsubscriptionchange',
              oldEndpoint: event.oldSubscription ? event.oldSubscription.endpoint : null,
              newSubscription: newSubscription.toJSON(),
            });
          }
        });
      })
  );
});

// ── Lifecycle ─────────────────────────────────────────────────
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});
