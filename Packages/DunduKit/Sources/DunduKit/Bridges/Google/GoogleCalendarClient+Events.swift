import Foundation

/// Events API: incremental sync via syncToken, idempotent inserts, etag'd
/// patches, and exponential backoff with jitter on rate limits.
extension GoogleCalendarClient {
    public struct EventsDelta: Sendable {
        public var events: [GEvent]
        public var nextSyncToken: String?
        /// True when this was a first/full fetch rather than a token delta —
        /// missing items must NOT be treated as deletions either way, but
        /// callers may want to know.
        public var wasFullFetch: Bool
    }

    public enum EventsError: Error, Sendable {
        /// HTTP 410: the sync token expired. Clear it and full-resync.
        case syncTokenExpired
        /// HTTP 412: someone else changed the event. Re-pull and merge.
        case etagConflict
        case requestFailed(status: Int, body: String)
    }

    /// Pulls changes. With a token: just the delta. Without: a full window
    /// from `historyWindow` back, single events expanded.
    public func eventChanges(
        calendarID: String,
        syncToken: String?,
        accessToken: String,
        historyWindow: TimeInterval = 90 * 24 * 3600
    ) async throws -> EventsDelta {
        var events: [GEvent] = []
        var pageToken: String?
        var nextSyncToken: String?

        repeat {
            var items = [URLQueryItem(name: "singleEvents", value: "true")]
            if let syncToken {
                // A syncToken request may carry no other filters.
                items.append(URLQueryItem(name: "syncToken", value: syncToken))
                items.append(URLQueryItem(name: "showDeleted", value: "true"))
            } else {
                let timeMin = GDates.timestampString(Date().addingTimeInterval(-historyWindow))
                items.append(URLQueryItem(name: "timeMin", value: timeMin))
                items.append(URLQueryItem(name: "showDeleted", value: "false"))
            }
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let url = eventsURL(calendarID: calendarID, queryItems: items)
            let data = try await send(request: authorized(url: url, accessToken: accessToken))
            let page = try JSONDecoder().decode(GEventsPage.self, from: data)
            events.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
            nextSyncToken = page.nextSyncToken ?? nextSyncToken
        } while pageToken != nil

        return EventsDelta(events: events, nextSyncToken: nextSyncToken, wasFullFetch: syncToken == nil)
    }

    /// Insert with a client-generated id — retries after timeouts are
    /// idempotent. A 409 means the id already exists (an earlier attempt
    /// landed); treat as success by re-fetching.
    public func insertEvent(
        calendarID: String,
        eventID: String,
        payload: EventWritePayload,
        accessToken: String
    ) async throws -> GEvent {
        var wireEvent = payload.asGEvent()
        wireEvent.id = eventID

        var request = authorized(
            url: eventsURL(calendarID: calendarID, queryItems: []),
            accessToken: accessToken
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(wireEvent)

        do {
            let data = try await send(request: request)
            return try JSONDecoder().decode(GEvent.self, from: data)
        } catch EventsError.requestFailed(let status, _) where status == 409 {
            return try await getEvent(calendarID: calendarID, eventID: eventID, accessToken: accessToken)
        }
    }

    /// Patch with If-Match so a concurrent remote edit surfaces as a 412
    /// conflict instead of a silent overwrite.
    public func patchEvent(
        calendarID: String,
        eventID: String,
        etag: String?,
        payload: EventWritePayload,
        accessToken: String
    ) async throws -> GEvent {
        var request = authorized(
            url: eventsURL(calendarID: calendarID, path: eventID, queryItems: []),
            accessToken: accessToken
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        request.httpBody = try JSONEncoder().encode(payload.asGEvent())

        let data = try await send(request: request)
        return try JSONDecoder().decode(GEvent.self, from: data)
    }

    /// Delete; already-gone (404/410) counts as success.
    public func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws {
        var request = authorized(
            url: eventsURL(calendarID: calendarID, path: eventID, queryItems: []),
            accessToken: accessToken
        )
        request.httpMethod = "DELETE"
        do {
            _ = try await send(request: request)
        } catch EventsError.requestFailed(let status, _) where status == 404 || status == 410 {
            // Deleting something already deleted is the outcome we wanted.
        }
    }

    public func getEvent(calendarID: String, eventID: String, accessToken: String) async throws -> GEvent {
        let data = try await send(request: authorized(
            url: eventsURL(calendarID: calendarID, path: eventID, queryItems: []),
            accessToken: accessToken
        ))
        return try JSONDecoder().decode(GEvent.self, from: data)
    }

    // MARK: - Plumbing

    private func eventsURL(calendarID: String, path: String? = nil, queryItems: [URLQueryItem]) -> URL {
        let escaped = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var string = "https://www.googleapis.com/calendar/v3/calendars/\(escaped)/events"
        if let path {
            string += "/\(path)"
        }
        var components = URLComponents(string: string)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func authorized(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// One request with backoff: 403 rateLimitExceeded and 429 retry with
    /// exponential delay and jitter, starting at 1 second (spec §7).
    private func send(request: URLRequest, attempt: Int = 0) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data, as: UTF8.self)

        switch status {
        case 200...299:
            return data
        case 410 where body.contains("fullSyncRequired") || request.url?.query?.contains("syncToken") == true:
            throw EventsError.syncTokenExpired
        case 412:
            throw EventsError.etagConflict
        case 429, 403 where body.contains("rateLimitExceeded") || body.contains("userRateLimitExceeded"):
            guard attempt < 3 else {
                throw EventsError.requestFailed(status: status, body: body)
            }
            let delay = pow(2.0, Double(attempt)) + Double.random(in: 0...0.5)
            try await Task.sleep(for: .seconds(delay))
            return try await send(request: request, attempt: attempt + 1)
        default:
            throw EventsError.requestFailed(status: status, body: body)
        }
    }
}
