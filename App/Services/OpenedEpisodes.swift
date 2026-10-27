import Foundation
import Observation

/// Episodes the user has opened in Spotify, newest first, persisted in UserDefaults.
@MainActor
@Observable
final class OpenedEpisodes {
    private static let storageKey = "openedEpisodes"
    /// IDs saved by the previous version, which did not keep names or dates.
    private static let legacyStorageKey = "openedEpisodeIDs"

    private(set) var episodes: [OpenedEpisode]
    @ObservationIgnored private let legacyIDs: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        episodes = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([OpenedEpisode].self, from: $0) } ?? []
        legacyIDs = defaults.data(forKey: Self.legacyStorageKey)
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    func contains(_ episode: PodcastEpisode) -> Bool {
        legacyIDs.contains(episode.id) || episodes.contains { $0.id == episode.id }
    }

    func markOpened(_ episode: PodcastEpisode) {
        episodes.removeAll { $0.id == episode.id }
        episodes.insert(
            OpenedEpisode(id: episode.id, name: episode.name, showName: episode.showName, openedAt: .now),
            at: 0
        )
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(episodes) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
