import Foundation
import Observation

/// Episodes the user has opened in Spotify, persisted in UserDefaults.
@MainActor
@Observable
final class OpenedEpisodes {
    private static let storageKey = "openedEpisodeIDs"

    private(set) var ids: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    func contains(_ episode: PodcastEpisode) -> Bool {
        ids.contains(episode.id)
    }

    func markOpened(_ episode: PodcastEpisode) {
        guard ids.insert(episode.id).inserted else { return }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
