import Foundation

enum SpotifyError: LocalizedError {
    case notConfigured
    case notConnected
    case sessionExpired
    case cancelled
    case invalidCallback
    case stateMismatch
    case authorizationDenied(String)
    case tokenRejected
    case httpStatus(Int)
    case invalidResponse
    case noSavedShows
    case noEpisodes

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "Spotify is not configured yet. Set SPOTIFY_CLIENT_ID in the build settings.")
        case .notConnected:
            String(localized: "Connect Spotify first.")
        case .sessionExpired:
            String(localized: "Your Spotify session expired. Connect again.")
        case .cancelled:
            String(localized: "Sign-in was cancelled.")
        case .invalidCallback, .invalidResponse:
            String(localized: "Spotify returned an unexpected response.")
        case .stateMismatch:
            String(localized: "The sign-in response did not match the request. Try again.")
        case .authorizationDenied(let reason):
            String(localized: "Spotify denied access: \(reason)")
        case .tokenRejected:
            String(localized: "Spotify rejected the sign-in. Connect again.")
        case .httpStatus(let status):
            String(localized: "Spotify request failed with status \(status).")
        case .noSavedShows:
            String(localized: "Save at least one podcast first.")
        case .noEpisodes:
            String(localized: "None of your saved podcasts has episodes available.")
        }
    }
}

extension JSONDecoder {
    /// Decoder for Spotify's snake_case JSON payloads.
    static var spotify: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
