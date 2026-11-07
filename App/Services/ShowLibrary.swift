import Foundation
import Observation

/// The two kinds of list a podcast can be saved in.
enum ShowList: String, CaseIterable, Identifiable, Hashable {
    /// All podcasts in this list share one random pick: the episode can come from any of them.
    case randomFromAll
    /// The user selects one podcast and gets a random episode from that podcast only.
    case onePodcast

    var id: Self { self }

    /// Name shown in the main screen, the search screen and the add menu.
    var title: LocalizedStringResource {
        switch self {
        case .randomFromAll: "Random from all"
        case .onePodcast: "One podcast at a time"
        }
    }

    /// `savedShows` is the key used before there were two lists, so existing saved podcasts stay in "Random from all".
    fileprivate var storageKey: String {
        switch self {
        case .randomFromAll: "savedShows"
        case .onePodcast: "onePodcastShows"
        }
    }
}

/// Podcasts the user has saved in the app, one array per list, persisted in UserDefaults.
@MainActor
@Observable
final class ShowLibrary {
    private var lists: [ShowList: [PodcastShow]]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var lists: [ShowList: [PodcastShow]] = [:]
        for list in ShowList.allCases {
            lists[list] = defaults.data(forKey: list.storageKey)
                .flatMap { try? JSONDecoder().decode([PodcastShow].self, from: $0) } ?? []
        }
        self.lists = lists
    }

    func shows(in list: ShowList) -> [PodcastShow] {
        lists[list] ?? []
    }

    func contains(_ show: PodcastShow, in list: ShowList) -> Bool {
        shows(in: list).contains { $0.id == show.id }
    }

    func toggle(_ show: PodcastShow, in list: ShowList) {
        var shows = shows(in: list)
        if let index = shows.firstIndex(where: { $0.id == show.id }) {
            shows.remove(at: index)
        } else {
            shows.append(show)
        }
        update(list, with: shows)
    }

    func remove(at offsets: IndexSet, from list: ShowList) {
        var shows = shows(in: list)
        for index in offsets.sorted(by: >) {
            shows.remove(at: index)
        }
        update(list, with: shows)
    }

    private func update(_ list: ShowList, with shows: [PodcastShow]) {
        lists[list] = shows
        if let data = try? JSONEncoder().encode(shows) {
            defaults.set(data, forKey: list.storageKey)
        }
    }
}
