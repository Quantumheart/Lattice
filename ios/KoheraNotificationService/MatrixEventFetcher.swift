import Foundation

struct MatrixEventFetcher {

    static func fetchEvent(
        homeserver: String,
        roomId: String,
        eventId: String,
        accessToken: String
    ) async -> [String: Any]? {
        guard let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(homeserver)/_matrix/client/v3/rooms/\(encodedRoomId)/event/\(encodedEventId)")
        else {
            NSLog("[KoheraNSE] Invalid URL for event fetch")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[KoheraNSE] Event fetch failed with status %d", code)
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            NSLog("[KoheraNSE] Event fetch error: %@", error.localizedDescription)
            return nil
        }
    }

    // ── Profile fetch ──────────────────────────────────────────────

    static func fetchProfile(
        homeserver: String,
        userId: String,
        accessToken: String
    ) async -> (avatarUrl: String?, displayname: String?)? {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(homeserver)/_matrix/client/v3/profile/\(encodedUserId)")
        else {
            NSLog("[KoheraNSE] Invalid URL for profile fetch")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[KoheraNSE] Profile fetch failed with status %d", code)
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let avatarUrl = json["avatar_url"] as? String
            let displayname = json["displayname"] as? String
            return (avatarUrl: avatarUrl, displayname: displayname)
        } catch {
            NSLog("[KoheraNSE] Profile fetch error: %@", error.localizedDescription)
            return nil
        }
    }

    // ── Thumbnail download ─────────────────────────────────────────

    static func downloadThumbnail(
        homeserver: String,
        mxcUrl: String,
        accessToken: String
    ) async -> URL? {
        guard mxcUrl.hasPrefix("mxc://") else { return nil }
        let stripped = String(mxcUrl.dropFirst(6))
        let parts = stripped.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let serverName = String(parts[0])
        let mediaId = String(parts[1])

        let query = "?width=128&height=128&method=crop"
        let authPath = "\(homeserver)/_matrix/client/v1/media/thumbnail/\(serverName)/\(mediaId)\(query)"
        let legacyPath = "\(homeserver)/_matrix/media/v3/thumbnail/\(serverName)/\(mediaId)\(query)"

        var imageData: Data?

        if let url = URL(string: authPath) {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                imageData = data
            }
        }

        if imageData == nil, let url = URL(string: legacyPath) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                imageData = data
            }
        }

        guard let data = imageData, !data.isEmpty else {
            NSLog("[KoheraNSE] Thumbnail download failed for %@", mxcUrl)
            return nil
        }

        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("avatar_\(mediaId).png")
        do {
            try data.write(to: fileUrl)
            return fileUrl
        } catch {
            NSLog("[KoheraNSE] Failed to write avatar to disk: %@", error.localizedDescription)
            return nil
        }
    }
}
