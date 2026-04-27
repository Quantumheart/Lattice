# Privacy Policy

**Effective date:** April 27, 2026

Kohera is a client application for [Matrix](https://matrix.org), an open and federated communication network. This policy explains how Kohera handles your information.

## Summary

- The developer of Kohera operates **no servers that store your messages, contacts, or account data**.
- Your messages, room memberships, and identity live on the Matrix homeserver **you choose** when you sign in.
- Direct and group conversations are protected with **end-to-end encryption by default** using the Olm and Megolm protocols.
- Kohera does not contain advertising, analytics, tracking, or telemetry SDKs.

## Information Collected by Kohera

The developer of Kohera does not operate a backend that stores user accounts, messages, or contacts, and does not collect any data through the app for analytics, tracking, advertising, or profiling.

The developer does operate a Matrix push notification gateway (`push.quantum-matrix.xyz`), which transiently processes notification metadata in order to deliver push notifications. See the **Push notifications** section below for details.

## Information Stored on Your Device

To provide its functionality, Kohera stores the following on your device:

- Your Matrix account credentials (access token), held in the operating system keychain.
- A local cache of rooms, messages, and media you have access to, so the app works offline and starts quickly.
- End-to-end encryption keys required to read your encrypted conversations.
- App preferences such as theme, default homeserver, and notification settings.

This data stays on your device. You can remove all of it by signing out or deleting the app.

## Third-Party Services

Kohera connects to several third-party services to function. Each has its own privacy practices.

### Your Matrix homeserver

When you sign in, Kohera communicates with the homeserver you chose (by default, `matrix.org`). Your account, contacts, room memberships, and message history are held by that homeserver. The privacy practices of the homeserver are governed by its operator. If you use `matrix.org`, see [the matrix.org privacy notice](https://matrix.org/legal/privacy-notice/).

### Push notifications

To deliver notifications when the app is closed or backgrounded, Kohera uses a Matrix push gateway operated by the developer at `push.quantum-matrix.xyz`. When you sign in, your device registers an opaque push token with your homeserver, which the homeserver hands to the push gateway. When a notification needs to be delivered, your homeserver sends a notification payload over TLS to the gateway, which repackages it and forwards it to Apple's Push Notification service (APNs).

The notification payload typically contains an event ID, a room ID, the sender's identifier, and unread/missed-call counters. For **end-to-end encrypted rooms**, the message body is not present in the payload — the notification only wakes the app, and Kohera fetches and decrypts the message content on your device. For **unencrypted rooms**, the homeserver may include the message body in the notification so it can be displayed in the lock-screen alert; in that case, the body passes through the gateway in transit.

The gateway does not use a database and does not persist data to disk. It maintains short-lived in-memory state only (a deduplication cache to suppress double-deliveries, and per-device rate-limit counters), and these are purged automatically. Operational logs may include a truncated push token, the Matrix event ID of duplicate-suppressed notifications, and error responses from APNs.

The gateway is not used for any purpose other than relaying notifications to APNs. Its source code and configuration are available at [https://github.com/Quantumheart/matrix-push-gateway](https://github.com/Quantumheart/matrix-push-gateway). Apple's handling of push notifications is governed by [Apple's privacy policy](https://www.apple.com/legal/privacy/).

You can disable push notifications at any time in your iOS Settings or in Kohera's notification preferences.

### Voice and video calls

Voice and video calls are delivered using [LiveKit](https://livekit.io). The LiveKit server you connect to is determined by your homeserver or by the room you are calling in. Audio and video streams are routed through that server. Call media is encrypted in transit.

### Giphy

If you use the GIF picker, search queries are sent to [Giphy](https://giphy.com) to retrieve matching results. Giphy's data practices are governed by [Giphy's privacy policy](https://support.giphy.com/hc/en-us/articles/360032872931-Giphy-Privacy-Policy). Selecting a GIF results in that GIF being shared into your conversation; no other information about you is sent to Giphy.

### CAPTCHA during registration

If your chosen homeserver requires a CAPTCHA to register a new account, Kohera will load Google reCAPTCHA in order to satisfy that requirement. Google's data practices are governed by [Google's privacy policy](https://policies.google.com/privacy).

## End-to-End Encryption

Direct messages and rooms marked as encrypted are protected with the Olm and Megolm cryptographic protocols. Message content is encrypted on your device before being sent and is decrypted only on the recipients' devices. The developer of Kohera, your homeserver operator, the push gateway, and any network operators in between cannot read your encrypted messages.

If you lose access to your devices and have not enabled secure key backup, you may permanently lose access to encrypted message history. This is by design and is a property of end-to-end encryption.

## Children

Kohera is rated 17+ on the App Store because the federated Matrix network may contain user-generated content not suitable for children. The app is not directed at children under 13, and the developer does not knowingly collect information from children.

## Open Source

Kohera is open source. You can review the source code at [https://github.com/quantumheart/Kohera](https://github.com/quantumheart/Kohera).

## Changes to This Policy

If this policy changes, the updated version will be published in this repository and the effective date above will be updated. Material changes will also be noted in the app's release notes.

## Contact

Questions about this policy can be sent by opening an issue at [https://github.com/quantumheart/Kohera/issues](https://github.com/quantumheart/Kohera/issues).
