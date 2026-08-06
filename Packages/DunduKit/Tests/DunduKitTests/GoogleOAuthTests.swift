import Foundation
import CryptoKit
import Testing
@testable import DunduKit

@Suite("Google OAuth plumbing")
struct GoogleOAuthTests {
    @Test func pkceVerifierShapeAndChallenge() {
        let pkce = PKCE.generate()
        // RFC 7636: 43–128 chars from the unreserved set.
        #expect((43...128).contains(pkce.verifier.count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))

        let expected = Data(SHA256.hash(data: Data(pkce.verifier.utf8))).base64URLEncoded()
        #expect(pkce.challenge == expected)
        // Two generations never collide.
        #expect(PKCE.generate().verifier != pkce.verifier)
    }

    @Test func authorizationURLCarriesEverything() {
        let pkce = PKCE.generate()
        let url = GoogleOAuthClient().authorizationURL(pkce: pkce)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        #expect(url.host == "accounts.google.com")
        #expect(value("client_id") == GoogleOAuthConfig.clientID)
        #expect(value("redirect_uri") == GoogleOAuthConfig.redirectURI)
        #expect(value("response_type") == "code")
        #expect(value("code_challenge") == pkce.challenge)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("scope") == "https://www.googleapis.com/auth/calendar")
        #expect(value("prompt") == "consent")
    }

    @Test func redirectSchemeIsReversedClientID() {
        #expect(GoogleOAuthConfig.redirectScheme.hasPrefix("com.googleusercontent.apps."))
        let reversed = GoogleOAuthConfig.redirectScheme
            .replacingOccurrences(of: "com.googleusercontent.apps.", with: "")
        #expect(GoogleOAuthConfig.clientID == reversed + ".apps.googleusercontent.com")
    }

    @Test func tokenResponseDecodes() throws {
        let json = """
        {"access_token":"ya29.abc","expires_in":3599,"refresh_token":"1//xyz","scope":"https://www.googleapis.com/auth/calendar","token_type":"Bearer"}
        """
        let tokens = try JSONDecoder().decode(GoogleTokens.self, from: Data(json.utf8))
        #expect(tokens.accessToken == "ya29.abc")
        #expect(tokens.refreshToken == "1//xyz")
        #expect(tokens.expiresIn == 3599)

        // Refresh responses omit the refresh token.
        let refreshJSON = """
        {"access_token":"ya29.def","expires_in":3599,"token_type":"Bearer"}
        """
        let refreshed = try JSONDecoder().decode(GoogleTokens.self, from: Data(refreshJSON.utf8))
        #expect(refreshed.refreshToken == nil)
    }

    @Test func calendarListDecodes() throws {
        let json = """
        {"items":[
            {"id":"abid@scoop.app","summary":"Abid","primary":true,"backgroundColor":"#9fe1e7","accessRole":"owner"},
            {"id":"team@group.calendar.google.com","summary":"Team","accessRole":"reader"}
        ]}
        """
        let page = try JSONDecoder().decode(
            GoogleCalendarClient.CalendarListResponse.self, from: Data(json.utf8)
        )
        #expect(page.items.count == 2)
        #expect(page.items[0].primary == true)
        #expect(page.items[0].isWritable)
        #expect(!page.items[1].isWritable)
        #expect(page.nextPageToken == nil)
    }

    @Test func formEncodingEscapesReservedCharacters() {
        let encoded = GoogleOAuthClient.formEncode([
            "redirect_uri": "com.app:/oauth2redirect",
            "scope": "https://www.googleapis.com/auth/calendar",
        ])
        #expect(encoded.contains("redirect_uri=com.app%3A%2Foauth2redirect"))
        #expect(!encoded.contains("://"))
    }

    @Test func keychainRoundTrip() throws {
        let email = "dundu-test@example.com"
        defer { GoogleKeychain.delete(email: email) }

        try GoogleKeychain.save(refreshToken: "token-1", email: email)
        #expect(GoogleKeychain.refreshToken(email: email) == "token-1")

        // Update path.
        try GoogleKeychain.save(refreshToken: "token-2", email: email)
        #expect(GoogleKeychain.refreshToken(email: email) == "token-2")

        GoogleKeychain.delete(email: email)
        #expect(GoogleKeychain.refreshToken(email: email) == nil)
    }
}
