import Intents
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

        let clientName = resolveClientName(userInfo: request.content.userInfo)

        Task { @MainActor in
            await self.processNotification(
                content: content, eventId: eventId, roomId: roomId, clientName: clientName
            )
            contentHandler(self.bestAttemptContent ?? content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    // ── Client resolution ────────────────────────────────────────

    private func resolveClientName(userInfo: [AnyHashable: Any]) -> String {
        if let notification = userInfo["notification"] as? [String: Any],
           let userId = notification["user_id"] as? String,
           !userId.isEmpty {
            let safe = userId
                .replacingOccurrences(of: "@", with: "")
                .replacingOccurrences(of: ":", with: "_")
            return safe
        }
        return "default"
    }

    // ── Processing ───────────────────────────────────────────────

    private func processNotification(
        content: UNMutableNotificationContent,
        eventId: String,
        roomId: String,
        clientName: String
    ) async {
        guard let accessToken = SharedKeychainReader.read(key: "kohera_\(clientName)_access_token"),
              let homeserver = SharedKeychainReader.read(key: "kohera_\(clientName)_homeserver"),
              let userId = SharedKeychainReader.read(key: "kohera_\(clientName)_user_id") else {
            NSLog("[KoheraNSE] Missing credentials in shared keychain for client %@", clientName)
            return
        }

        guard let event = await MatrixEventFetcher.fetchEvent(
            homeserver: homeserver,
            roomId: roomId,
            eventId: eventId,
            accessToken: accessToken
        ) else {
            NSLog("[KoheraNSE] Failed to fetch event %@", eventId)
            return
        }

        let senderId = event["sender"] as? String

        let profileTask = Task { () -> (avatarUrl: String?, displayname: String?)? in
            guard let senderId = senderId else { return nil }
            return await MatrixEventFetcher.fetchProfile(
                homeserver: homeserver, userId: senderId, accessToken: accessToken
            )
        }

        let body = resolveBody(event: event, userId: userId, clientName: clientName)

        let profile = await profileTask.value
        let senderName = nonEmpty(profile?.displayname) ?? extractSenderName(from: event)
        updateContent(content: content, senderName: senderName, body: body)

        await applySenderIntent(
            content: content,
            senderId: senderId,
            senderName: senderName,
            avatarMxc: profile?.avatarUrl,
            homeserver: homeserver,
            accessToken: accessToken
        )
    }

    // ── Body resolution ────────────────────────────────────────────

    private func resolveBody(event: [String: Any], userId: String, clientName: String) -> String {
        let eventType = event["type"] as? String ?? ""
        if eventType == "m.room.encrypted" {
            return decryptBody(event: event, userId: userId, clientName: clientName)
        }
        let msgContent = event["content"] as? [String: Any]
        return msgContent?["body"] as? String ?? "New message"
    }

    private func decryptBody(event: [String: Any], userId: String, clientName: String) -> String {
        guard let encContent = event["content"] as? [String: Any],
              let sessionId = encContent["session_id"] as? String,
              let ciphertext = encContent["ciphertext"] as? String else {
            return "Encrypted message"
        }
        return MegolmDecryptor.decrypt(
            sessionId: sessionId, ciphertext: ciphertext,
            userId: userId, clientName: clientName
        ) ?? "Encrypted message"
    }

    // ── Communication notification (sender avatar as icon) ────────

    private func applySenderIntent(
        content: UNMutableNotificationContent,
        senderId: String?,
        senderName: String?,
        avatarMxc: String?,
        homeserver: String,
        accessToken: String
    ) async {
        guard #available(iOS 15.0, *) else { return }
        guard let senderId = senderId else { return }

        var avatarImage: INImage?
        if let mxcUrl = avatarMxc,
           let fileUrl = await MatrixEventFetcher.downloadThumbnail(
               homeserver: homeserver, mxcUrl: mxcUrl, accessToken: accessToken
           ),
           let data = try? Data(contentsOf: fileUrl) {
            avatarImage = INImage(imageData: data)
        }

        let handle = INPersonHandle(value: senderId, type: .unknown)
        let sender = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: senderName ?? senderId,
            image: avatarImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: content.threadIdentifier,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        if let updated = try? content.updating(from: intent) as? UNMutableNotificationContent {
            self.bestAttemptContent = updated
        }
    }

    // ── Helpers ────────────────────────────────────────────────────

    private func updateContent(content: UNMutableNotificationContent, senderName: String?, body: String) {
        if let senderName = senderName {
            content.body = "\(senderName): \(body)"
        } else {
            content.body = body
        }
    }

    private func extractSenderName(from event: [String: Any]) -> String? {
        if let sender = event["sender"] as? String {
            let withoutSigil = sender.dropFirst()
            let localpart = withoutSigil.prefix(while: { $0 != ":" })
            return String(localpart)
        }
        return nil
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        return string
    }
}
