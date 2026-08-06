import Foundation

/// Thin authenticated REST client for the Calendar API. M9 reads the
/// calendar list; the events engine with syncTokens arrives in M10.
public struct GoogleCalendarClient: Sendable {
    public struct CalendarEntry: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let summary: String?
        public let primary: Bool?
        public let backgroundColor: String?
        /// "owner", "writer", "reader", "freeBusyReader"
        public let accessRole: String?

        public var isWritable: Bool {
            accessRole == "owner" || accessRole == "writer"
        }
    }

    struct CalendarListResponse: Codable {
        let items: [CalendarEntry]
        let nextPageToken: String?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// All calendars visible to the account, paged through to the end.
    /// The `primary` entry's id is the account's email address.
    public func calendarList(accessToken: String) async throws -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(
                string: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
            )!
            if let pageToken {
                components.queryItems = [URLQueryItem(name: "pageToken", value: pageToken)]
            }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw GoogleAPIError.requestFailed(
                    status: status, body: String(decoding: data, as: UTF8.self)
                )
            }
            let page = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            entries.append(contentsOf: page.items)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return entries
    }
}

public enum GoogleAPIError: Error, LocalizedError, Sendable {
    case requestFailed(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let status, _):
            "Google Calendar request failed (HTTP \(status))."
        }
    }
}
