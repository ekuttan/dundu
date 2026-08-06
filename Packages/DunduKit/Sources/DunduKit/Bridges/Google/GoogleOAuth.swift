import Foundation
import CryptoKit

/// OAuth 2.0 with PKCE for an installed-app (iOS-type) client. The client ID
/// is a public identifier, safe to embed; the secrets are the per-user
/// tokens, which live in the Keychain and nowhere else.
///
/// Testing-mode caveat from the spec: until the OAuth consent screen is
/// verified, refresh tokens expire every 7 days and only listed test users
/// can sign in. Both surface as readable errors, not mysteries.
public enum GoogleOAuthConfig {
    public static let clientID = "616629809640-db2euu6uf4q8e7sjun8mqh0c9hql2r27.apps.googleusercontent.com"

    /// iOS-type clients redirect to the reversed client ID as a scheme.
    public static let redirectScheme = "com.googleusercontent.apps.616629809640-db2euu6uf4q8e7sjun8mqh0c9hql2r27"
    public static let redirectURI = redirectScheme + ":/oauth2redirect"

    /// Full calendar scope: write access to events plus the calendar list.
    public static let scope = "https://www.googleapis.com/auth/calendar"

    public static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
}

// MARK: - PKCE

public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCE {
        // 64 random bytes, base64url — comfortably inside the 43–128 char
        // verifier window.
        var bytes = [UInt8](repeating: 0, count: 64)
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: 0...255)
        }
        let verifier = Data(bytes).base64URLEncoded()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Tokens

public struct GoogleTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    /// Present on first authorization; absent on refresh responses.
    public let refreshToken: String?
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public enum GoogleOAuthError: Error, LocalizedError, Sendable {
    case authorizationFailed(String)
    case tokenExchangeFailed(status: Int, body: String)
    /// Testing mode's 7-day expiry lands here: the refresh token is dead
    /// and the account needs a fresh sign-in.
    case refreshTokenRevoked
    case noRefreshToken

    public var errorDescription: String? {
        switch self {
        case .authorizationFailed(let reason):
            "Google sign-in failed: \(reason)"
        case .tokenExchangeFailed(let status, _):
            "Google rejected the token request (HTTP \(status))."
        case .refreshTokenRevoked:
            "This Google account needs signing in again. In testing mode Google expires sessions every 7 days."
        case .noRefreshToken:
            "Google did not return a refresh token. Remove the app from your Google account permissions and sign in again."
        }
    }
}

// MARK: - Client

public struct GoogleOAuthClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The browser URL for the consent screen.
    public func authorizationURL(pkce: PKCE) -> URL {
        var components = URLComponents(
            url: GoogleOAuthConfig.authEndpoint, resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Force the consent screen so a refresh token always arrives,
            // even on re-authorization.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    public func exchangeCode(_ code: String, verifier: String) async throws -> GoogleTokens {
        try await tokenRequest(body: [
            "client_id": GoogleOAuthConfig.clientID,
            "redirect_uri": GoogleOAuthConfig.redirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
        ])
    }

    public func refresh(refreshToken: String) async throws -> GoogleTokens {
        do {
            return try await tokenRequest(body: [
                "client_id": GoogleOAuthConfig.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
        } catch GoogleOAuthError.tokenExchangeFailed(let status, let body)
            where status == 400 && body.contains("invalid_grant") {
            // Expired or revoked (testing mode's 7-day limit): re-auth needed.
            throw GoogleOAuthError.refreshTokenRevoked
        }
    }

    private func tokenRequest(body: [String: String]) async throws -> GoogleTokens {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(body).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw GoogleOAuthError.tokenExchangeFailed(
                status: status, body: String(decoding: data, as: UTF8.self)
            )
        }
        return try JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }
}
