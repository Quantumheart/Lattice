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
            NSLog("[LatticeNSE] Invalid URL for event fetch")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[LatticeNSE] Event fetch failed with status %d", code)
                return nil
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            NSLog("[LatticeNSE] Event fetch error: %@", error.localizedDescription)
            return nil
        }
    }
}
