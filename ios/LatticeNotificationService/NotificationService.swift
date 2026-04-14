import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let notification = request.content.userInfo["notification"] as? [String: Any]
        let eventId = notification?["event_id"] as? String
        let roomId = notification?["room_id"] as? String

        guard let eventId = eventId, let roomId = roomId else {
            contentHandler(content)
            return
        }

        content.threadIdentifier = roomId
        content.categoryIdentifier = "MESSAGE"

        Task {
            await processNotification(content: content, eventId: eventId, roomId: roomId)
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    // ── Processing ───────────────────────────────────────────────

    private func processNotification(
        content: UNMutableNotificationContent,
        eventId: String,
        roomId: String
    ) async {
        guard let accessToken = SharedKeychainReader.read(key: "lattice_default_access_token"),
              let homeserver = SharedKeychainReader.read(key: "lattice_default_homeserver"),
              let userId = SharedKeychainReader.read(key: "lattice_default_user_id") else {
            NSLog("[LatticeNSE] Missing credentials in shared keychain")
            return
        }

        guard let event = await MatrixEventFetcher.fetchEvent(
            homeserver: homeserver,
            roomId: roomId,
            eventId: eventId,
            accessToken: accessToken
        ) else {
            NSLog("[LatticeNSE] Failed to fetch event %@", eventId)
            return
        }

        let senderName = extractSenderName(from: event)
        let eventType = event["type"] as? String ?? ""

        if eventType == "m.room.encrypted" {
            decryptAndUpdate(content: content, event: event, userId: userId, senderName: senderName)
        } else {
            let msgContent = event["content"] as? [String: Any]
            let body = msgContent?["body"] as? String ?? "New message"
            updateContent(content: content, senderName: senderName, body: body)
        }
    }

    private func decryptAndUpdate(
        content: UNMutableNotificationContent,
        event: [String: Any],
        userId: String,
        senderName: String?
    ) {
        guard let encContent = event["content"] as? [String: Any],
              let sessionId = encContent["session_id"] as? String,
              let ciphertext = encContent["ciphertext"] as? String else {
            content.body = "Encrypted message"
            return
        }

        if let body = MegolmDecryptor.decrypt(
            sessionId: sessionId,
            ciphertext: ciphertext,
            userId: userId
        ) {
            updateContent(content: content, senderName: senderName, body: body)
        } else {
            content.body = "Encrypted message"
        }
    }

    private func updateContent(content: UNMutableNotificationContent, senderName: String?, body: String) {
        if let senderName = senderName {
            content.body = "\(senderName): \(body)"
        } else {
            content.body = body
        }
    }

    private func extractSenderName(from event: [String: Any]) -> String? {
        if let unsigned = event["unsigned"] as? [String: Any],
           let displayName = unsigned["displayname"] as? String {
            return displayName
        }
        if let sender = event["sender"] as? String {
            let withoutSigil = sender.dropFirst()
            let localpart = withoutSigil.prefix(while: { $0 != ":" })
            return String(localpart)
        }
        return nil
    }
}
