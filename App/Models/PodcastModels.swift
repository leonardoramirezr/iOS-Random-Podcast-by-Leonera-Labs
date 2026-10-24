import Foundation

/// A Spotify show (podcast) the user can save in the app.
struct PodcastShow: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: URL?
}

/// A single episode, enriched with the name of the show it belongs to.
struct PodcastEpisode: Identifiable, Hashable {
    let id: String
    let name: String
    let showName: String
    let description: String
    let releaseDate: String
    let durationMs: Int

    /// Universal link: opens the episode in the Spotify app when it is installed, otherwise in the browser.
    var spotifyURL: URL {
        URL(string: "https://open.spotify.com/episode/\(id)")!
    }
}
