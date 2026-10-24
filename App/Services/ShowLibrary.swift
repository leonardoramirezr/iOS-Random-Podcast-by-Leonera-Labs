import Foundation
import Observation

/// Podcasts the user has saved in the app, persisted in UserDefaults.
@MainActor
@Observable
final class ShowLibrary {
    private static let storageKey = "savedShows"

    private(set) var shows: [PodcastShow]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shows = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PodcastShow].self, from: $0) } ?? []
    }

    func contains(_ show: PodcastShow) -> Bool {
        shows.contains { $0.id == show.id }
    }

    func toggle(_ show: PodcastShow) {
        if let index = shows.firstIndex(where: { $0.id == show.id }) {
            shows.remove(at: index)
        } else {
            shows.append(show)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            shows.remove(at: index)
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shows) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
