import Foundation
import SwiftData
#if canImport(AuthenticationServices)
import AuthenticationServices

/// Sign-in and token lifecycle for Google accounts. Three calendars may sit
/// on three separate accounts, so everything here is multi-account: one
/// Keychain entry, one CalendarAccount record, and one set of CalendarRef
/// rows per signed-in address.
@MainActor
public final class GoogleAccountService: NSObject {
    public static let shared = GoogleAccountService()

    private let oauth = GoogleOAuthClient()
    private let api = GoogleCalendarClient()
    /// Short-lived access tokens, refreshed on demand, never persisted.
    private var accessTokens: [String: (token: String, expiresAt: Date)] = [:]

    // MARK: - Sign in

    /// Runs the whole flow: consent in ASWebAuthenticationSession, PKCE code
    /// exchange, calendar list fetch, Keychain save, and account + calendar
    /// records. Returns the account's email.
    @discardableResult
    public func signIn(context: ModelContext) async throws -> String {
        let pkce = PKCE.generate()
        let authURL = oauth.authorizationURL(pkce: pkce)

        let callbackURL = try await presentAuthSession(url: authURL)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            let error = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            throw GoogleOAuthError.authorizationFailed(error ?? "no authorization code returned")
        }

        let tokens = try await oauth.exchangeCode(code, verifier: pkce.verifier)
        guard let refreshToken = tokens.refreshToken else {
            throw GoogleOAuthError.noRefreshToken
        }

        // The primary calendar's id is the account email — no extra scope
        // needed to identify the account.
        let calendars = try await api.calendarList(accessToken: tokens.accessToken)
        let email = calendars.first(where: { $0.primary == true })?.id ?? "google-account"

        try GoogleKeychain.save(refreshToken: refreshToken, email: email)
        accessTokens[email] = (
            tokens.accessToken, Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
        )

        try persist(email: email, calendars: calendars, context: context)
        return email
    }

    /// Removes the account, its calendars, and its Keychain entry.
    public func removeAccount(_ account: CalendarAccount, context: ModelContext) throws {
        let accountID = account.id
        let refs = try context.fetch(FetchDescriptor<CalendarRef>(
            predicate: #Predicate { $0.accountID == accountID }
        ))
        refs.forEach(context.delete)
        GoogleKeychain.delete(email: account.email)
        accessTokens[account.email] = nil
        context.delete(account)
        try context.save()
    }

    // MARK: - Tokens

    /// A live access token for the account, refreshing through the Keychain
    /// refresh token when the cached one has expired.
    public func accessToken(for email: String) async throws -> String {
        if let cached = accessTokens[email], cached.expiresAt > Date() {
            return cached.token
        }
        guard let refreshToken = GoogleKeychain.refreshToken(email: email) else {
            throw GoogleOAuthError.refreshTokenRevoked
        }
        let tokens = try await oauth.refresh(refreshToken: refreshToken)
        accessTokens[email] = (
            tokens.accessToken, Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60))
        )
        return tokens.accessToken
    }

    /// Re-fetches the calendar list for an existing account.
    public func refreshCalendars(for account: CalendarAccount, context: ModelContext) async throws {
        let token = try await accessToken(for: account.email)
        let calendars = try await api.calendarList(accessToken: token)
        try persist(email: account.email, calendars: calendars, context: context)
    }

    // MARK: - Persistence

    private func persist(
        email: String,
        calendars: [GoogleCalendarClient.CalendarEntry],
        context: ModelContext
    ) throws {
        let accounts = try context.fetch(FetchDescriptor<CalendarAccount>(
            predicate: #Predicate { $0.email == email }
        ))
        let account: CalendarAccount
        if let existing = accounts.first {
            account = existing
        } else {
            account = CalendarAccount(provider: .google, email: email)
            context.insert(account)
        }
        account.isActive = true

        let accountID = account.id
        let existingRefs = try context.fetch(FetchDescriptor<CalendarRef>(
            predicate: #Predicate { $0.accountID == accountID }
        ))

        for calendar in calendars {
            if let ref = existingRefs.first(where: { $0.remoteCalendarID == calendar.id }) {
                ref.title = calendar.summary ?? calendar.id
                ref.isWritable = calendar.isWritable
                if let color = calendar.backgroundColor {
                    ref.colorHex = color
                }
            } else {
                let ref = CalendarRef(
                    accountID: account.id,
                    remoteCalendarID: calendar.id,
                    title: calendar.summary ?? calendar.id,
                    role: .personal
                )
                ref.isWritable = calendar.isWritable
                if let color = calendar.backgroundColor {
                    ref.colorHex = color
                }
                // Sync opt-in per calendar; only the primary starts enabled,
                // the rest are a settings decision.
                ref.syncEnabled = calendar.primary == true
                ref.isDefaultForRole = calendar.primary == true
                context.insert(ref)
            }
        }

        // Calendars that vanished remotely stop syncing but keep their row
        // visible in settings (spec edge 2: tell, don't silently drop).
        for ref in existingRefs where !calendars.contains(where: { $0.id == ref.remoteCalendarID }) {
            ref.syncEnabled = false
        }

        try context.save()
    }

    // MARK: - Auth session

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleOAuthConfig.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthError.authorizationFailed("cancelled"))
                } else {
                    continuation.resume(throwing: GoogleOAuthError.authorizationFailed(
                        error?.localizedDescription ?? "unknown"
                    ))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

extension GoogleAccountService: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
#endif
