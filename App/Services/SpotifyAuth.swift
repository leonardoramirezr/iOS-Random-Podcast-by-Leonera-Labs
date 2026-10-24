import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Signs the user in to Spotify with Authorization Code + PKCE, so no client secret ships in the app.
@MainActor
@Observable
final class SpotifyAuth {
    static let redirectScheme = "randompodcast"
    static let redirectURI = "randompodcast://spotify-callback"

    private static let keychainAccount = "spotify.tokens"

    private struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }

    private var tokens: StoredTokens?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationContext = AuthPresentationContext()

    init() {
        tokens = Keychain.load(account: Self.keychainAccount)
            .flatMap { try? JSONDecoder().decode(StoredTokens.self, from: $0) }
    }

    var isConnected: Bool {
        tokens != nil
    }

    /// False until a real Spotify Client ID is set in the build settings.
    var isConfigured: Bool {
        clientID != nil
    }

    private var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String,
              !value.isEmpty,
              !value.hasPrefix("REPLACE_")
        else { return nil }
        return value
    }

    func signIn() async throws {
        guard let clientID else { throw SpotifyError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authorizeURL = components.url else { throw SpotifyError.invalidCallback }

        let callbackURL = try await authenticate(with: authorizeURL)
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let reason = value("error") { throw SpotifyError.authorizationDenied(reason) }
        guard value("state") == state else { throw SpotifyError.stateMismatch }
        guard let code = value("code") else { throw SpotifyError.invalidCallback }

        let response = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        try storeTokens(from: response, fallbackRefreshToken: nil)
    }

    /// Returns a valid access token, refreshing it first when it is about to expire.
    func accessToken() async throws -> String {
        guard let current = tokens else { throw SpotifyError.notConnected }
        if current.expiresAt > Date().addingTimeInterval(60) {
            return current.accessToken
        }
        return try await refreshAccessToken()
    }

    /// Exchanges the refresh token for a new access token. Signs out when Spotify rejects the refresh token.
    func refreshAccessToken() async throws -> String {
        guard let clientID, let refreshToken = tokens?.refreshToken else { throw SpotifyError.notConnected }
        do {
            let response = try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ])
            try storeTokens(from: response, fallbackRefreshToken: refreshToken)
            return response.accessToken
        } catch SpotifyError.tokenRejected {
            signOut()
            throw SpotifyError.sessionExpired
        }
    }

    func signOut() {
        tokens = nil
        Keychain.delete(account: Self.keychainAccount)
    }

    // MARK: - Private helpers

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SpotifyError.invalidCallback)
                }
            }
            session.presentationContextProvider = presentationContext
            // The session must stay alive until the callback arrives.
            webSession = session
            session.start()
        }
    }

    private func requestTokens(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // 400 and 401 mean the grant itself is no longer valid.
            if http.statusCode == 400 || http.statusCode == 401 {
                throw SpotifyError.tokenRejected
            }
            throw SpotifyError.httpStatus(http.statusCode)
        }
        return try JSONDecoder.spotify.decode(TokenResponse.self, from: data)
    }

    private func storeTokens(from response: TokenResponse, fallbackRefreshToken: String?) throws {
        // Spotify only returns a new refresh token sometimes, so keep the previous one otherwise.
        guard let refreshToken = response.refreshToken ?? fallbackRefreshToken else {
            throw SpotifyError.invalidResponse
        }
        let stored = StoredTokens(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        tokens = stored
        if let data = try? JSONEncoder().encode(stored) {
            Keychain.save(data, account: Self.keychainAccount)
        }
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = parameters.map { key, value -> String in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }
        return Data(pairs.sorted().joined(separator: "&").utf8)
    }
}

/// Supplies the window that hosts the Spotify sign-in sheet.
private final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// Base64URL without padding, as required by PKCE.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
