import Foundation

/// Client for the Spotify Web API endpoints the app uses.
@MainActor
struct SpotifyAPI {
    static let pageSize = 50
    /// How many random pages to try for one show before giving up on it.
    private static let maxPageAttempts = 3

    let auth: SpotifyAuth

    /// Development Mode apps are limited to 10 search results per request.
    func searchShows(matching term: String) async throws -> [PodcastShow] {
        let url = makeURL("search", query: [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "type", value: "show"),
            URLQueryItem(name: "limit", value: "10"),
        ])
        let response: SpotifySearchResponse = try await get(url)
        return response.shows.items
            .compactMap { $0 }
            .map { PodcastShow(id: $0.id, name: $0.name, imageURL: $0.images?.first?.url) }
    }

    /// Picks a random episode from the saved shows.
    ///
    /// A show is chosen at random, then a random page of its paginated episode list,
    /// then a random episode inside that page. Shows without playable episodes are skipped.
    func randomEpisode(from shows: [PodcastShow]) async throws -> PodcastEpisode {
        guard !shows.isEmpty else { throw SpotifyError.noSavedShows }
        for show in shows.shuffled() {
            if let episode = try await randomEpisode(in: show) {
                return episode
            }
        }
        throw SpotifyError.noEpisodes
    }

    // MARK: - Private helpers

    private func randomEpisode(in show: PodcastShow) async throws -> PodcastEpisode? {
        let total = try await episodeCount(for: show)
        guard total > 0 else { return nil }

        let pageCount = (total + Self.pageSize - 1) / Self.pageSize
        // A page can contain only episodes that are unavailable in the market, so retry with another page.
        for _ in 0..<Self.maxPageAttempts {
            let page = Int.random(in: 0..<pageCount)
            let episodes = try await episodes(in: show, offset: page * Self.pageSize)
            if let episode = episodes.randomElement() {
                return episode
            }
        }
        return nil
    }

    private func episodeCount(for show: PodcastShow) async throws -> Int {
        let url = makeURL("shows/\(show.id)/episodes", query: [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
        ] + marketQuery)
        let page: SpotifyPage<SpotifyEpisodeDTO> = try await get(url)
        return page.total
    }

    private func episodes(in show: PodcastShow, offset: Int) async throws -> [PodcastEpisode] {
        let url = makeURL("shows/\(show.id)/episodes", query: [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ] + marketQuery)
        let page: SpotifyPage<SpotifyEpisodeDTO> = try await get(url)
        return page.items
            .compactMap { $0 }
            .map { dto in
                PodcastEpisode(
                    id: dto.id,
                    name: dto.name,
                    showName: show.name,
                    description: dto.description ?? "",
                    releaseDate: dto.releaseDate,
                    durationMs: dto.durationMs
                )
            }
    }

    /// Restricts episodes to the user's region so unplayable entries are skipped by the API.
    private var marketQuery: [URLQueryItem] {
        guard let region = Locale.current.region?.identifier else { return [] }
        return [URLQueryItem(name: "market", value: region)]
    }

    private func makeURL(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: "https://api.spotify.com/v1/\(path)")!
        components.queryItems = query
        return components.url!
    }

    /// Sends an authorized GET request. On 401 it refreshes the token once and retries.
    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var token = try await auth.accessToken()
        var (data, status) = try await send(url, token: token)
        if status == 401 {
            token = try await auth.refreshAccessToken()
            (data, status) = try await send(url, token: token)
        }
        guard (200..<300).contains(status) else {
            throw SpotifyError.httpStatus(status)
        }
        return try JSONDecoder.spotify.decode(T.self, from: data)
    }

    private func send(_ url: URL, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        return (data, http.statusCode)
    }
}

// MARK: - Response payloads

/// Spotify's paging envelope. Entries can be `null` when unavailable in the requested market.
struct SpotifyPage<Item: Decodable>: Decodable {
    let items: [Item?]
    let total: Int
}

struct SpotifySearchResponse: Decodable {
    let shows: SpotifyPage<SpotifyShowDTO>
}

struct SpotifyShowDTO: Decodable {
    let id: String
    let name: String
    let images: [SpotifyImageDTO]?
}

struct SpotifyImageDTO: Decodable {
    let url: URL
}

struct SpotifyEpisodeDTO: Decodable {
    let id: String
    let name: String
    let description: String?
    let releaseDate: String
    let durationMs: Int
}
