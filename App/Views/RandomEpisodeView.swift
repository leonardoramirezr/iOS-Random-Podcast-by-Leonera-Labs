import SwiftUI

/// Sheet that picks a random episode from the saved podcasts and shows it.
struct RandomEpisodeView: View {
    /// How many times to pick again when the random pick is an episode the user already opened.
    private static let maxRepeatRetries = 10

    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library
    @Environment(OpenedEpisodes.self) private var openedEpisodes
    @Environment(\.dismiss) private var dismiss

    @State private var phase = Phase.loading

    private enum Phase {
        case loading
        case loaded(PodcastEpisode)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Finding an episode…")
                case .loaded(let episode):
                    EpisodeDetailView(episode: episode)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not pick an episode", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") {
                            Task { await pickEpisode() }
                        }
                    }
                }
            }
            .navigationTitle("Random episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await pickEpisode() }
                    } label: {
                        Label("Pick another", systemImage: "shuffle")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await pickEpisode()
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func pickEpisode() async {
        phase = .loading
        do {
            let spotify = SpotifyAPI(auth: auth)
            var episode = try await spotify.randomEpisode(from: library.shows)
            // Pick again while the episode was already opened. After the retry limit, show the last pick.
            var retries = 0
            while openedEpisodes.contains(episode), retries < Self.maxRepeatRetries {
                episode = try await spotify.randomEpisode(from: library.shows)
                retries += 1
            }
            phase = .loaded(episode)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct EpisodeDetailView: View {
    let episode: PodcastEpisode

    @Environment(OpenedEpisodes.self) private var openedEpisodes
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(episode.showName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(episode.name)
                    .font(.title2.bold())

                HStack(spacing: 16) {
                    Label(episode.releaseDate, systemImage: "calendar")
                    Label(durationText, systemImage: "clock")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    openedEpisodes.markOpened(episode)
                    openURL(episode.spotifyURL)
                } label: {
                    Label("Open in Spotify", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(episode.description.isEmpty ? String(localized: "No description available.") : episode.description)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var durationText: String {
        Duration.milliseconds(episode.durationMs)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
