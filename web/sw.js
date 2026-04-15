'use strict';

// ── Push event ────────────────────────────────────────────────
self.addEventListener('push', function (event) {
  var roomName = 'New message';
  var body = 'You have a new message';
  var tag = 'kohera-push';
  var data = {};

  if (event.data) {
    try {
      var payload = event.data.json();
      var notification = payload.notification || {};
      var roomId = notification.room_id;
      var senderName = notification.sender_display_name;
      var counts = notification.counts || {};
      var content = notification.content || {};

      if (notification.room_name) roomName = notification.room_name;
      if (content.body) {
        body = senderName ? senderName + ': ' + content.body : content.body;
      } else if (senderName) {
        body = senderName + ': New message';
      }
      if (roomId) tag = roomId;
      data = { roomId: roomId || null, unreadCount: counts.unread || 0 };
    } catch (e) {}
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clientList) {
        var hasVisibleClient = clientList.some(function (c) {
          return c.visibilityState === 'visible' || c.focused;
        });
        if (hasVisibleClient) {
          return;
        }
        return self.registration.showNotification(roomName, {
          body: body,
          icon: 'icons/Icon-192.png',
          badge: 'icons/Icon-maskable-192.png',
          tag: tag,
          renotify: tag !== 'kohera-push',
          data: data,
          actions: [
            { action: 'mark_read', title: 'Mark as read' },
            { action: 'open', title: 'Open' },
          ],
        }).then(function () {
          try {
            if (self.navigator && self.navigator.setAppBadge && data.unreadCount) {
              self.navigator.setAppBadge(data.unreadCount);
            }
          } catch (e) {}
        });
      })
      .catch(function (e) {
        console.error('[Kohera SW] showNotification failed:', e);
      })
  );
});

// ── Notification click ────────────────────────────────────────
self.addEventListener('notificationclick', function (event) {
  event.notification.close();

  var action = event.action;
  var roomId = (event.notification.data || {}).roomId;
  var urlPath = roomId ? '/#/rooms/' + encodeURIComponent(roomId) : '/';

  if (action === 'mark_read') {
    event.waitUntil(
      self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
        if (clientList.length === 0) {
          try {
            if (self.navigator && self.navigator.clearAppBadge) self.navigator.clearAppBadge();
          } catch (e) {}
          return;
        }
        for (var i = 0; i < clientList.length; i++) {
          clientList[i].postMessage({ type: 'mark_read', roomId: roomId });
        }
      })
    );
    return;
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if (client.url.indexOf(self.registration.scope) !== -1) {
          client.postMessage({ type: 'notification_click', roomId: roomId });
          return client.focus().catch(function () {
            return self.clients.openWindow(urlPath);
          });
        }
      }
      try {
        if (self.navigator && self.navigator.clearAppBadge) self.navigator.clearAppBadge();
      } catch (e) {}
      return self.clients.openWindow(urlPath);
    })
  );
});

// ── Client messages ──────────────────────────────────────────
self.addEventListener('message', function (event) {
  if (!event.data || !event.data.type) return;

  var msg = event.data;

  if (msg.type === 'show_notification') {
    event.waitUntil(
      self.registration.showNotification(msg.title, {
        body: msg.body,
        icon: msg.icon || 'icons/Icon-192.png',
        badge: 'icons/Icon-maskable-192.png',
        tag: msg.tag,
        renotify: !!msg.renotify,
        silent: !!msg.silent,
        data: { roomId: msg.roomId || null, unreadCount: msg.unreadCount || 0 },
        actions: [
          { action: 'mark_read', title: 'Mark as read' },
          { action: 'open', title: 'Open' },
        ],
      }).then(function () {
        try {
          if (msg.unreadCount && self.navigator && self.navigator.setAppBadge) {
            self.navigator.setAppBadge(msg.unreadCount);
          }
        } catch (e) {}
      }).catch(function (e) {
        console.error('[Kohera SW] showNotification failed:', e);
      })
    );
  } else if (msg.type === 'close_notification') {
    event.waitUntil(
      self.registration.getNotifications({ tag: msg.tag }).then(function (notifications) {
        notifications.forEach(function (n) { n.close(); });
      })
    );
  } else if (msg.type === 'close_all_notifications') {
    event.waitUntil(
      self.registration.getNotifications().then(function (notifications) {
        notifications.forEach(function (n) { n.close(); });
        try {
          if (self.navigator && self.navigator.clearAppBadge) self.navigator.clearAppBadge();
        } catch (e) {}
      })
    );
  } else if (msg.type === 'clear_badge') {
    try {
      if (self.navigator && self.navigator.clearAppBadge) self.navigator.clearAppBadge();
    } catch (e) {}
  }
});

// ── Subscription change ──────────────────────────────────────
self.addEventListener('pushsubscriptionchange', function (event) {
  var options = (event.oldSubscription && event.oldSubscription.options) || {};
  event.waitUntil(
    self.registration.pushManager.subscribe(options)
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
      .catch(function (e) {
        return self.clients.matchAll({ type: 'window' }).then(function (clientList) {
          for (var i = 0; i < clientList.length; i++) {
            clientList[i].postMessage({ type: 'pushsubscriptionfailed', error: e.message });
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
