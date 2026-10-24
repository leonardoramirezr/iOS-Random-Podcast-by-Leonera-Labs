import SwiftUI

/// Sheet that picks a random episode from the saved podcasts and shows it.
struct RandomEpisodeView: View {
    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library
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
            let episode = try await SpotifyAPI(auth: auth).randomEpisode(from: library.shows)
            phase = .loaded(episode)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct EpisodeDetailView: View {
    let episode: PodcastEpisode

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

                Link(destination: episode.spotifyURL) {
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
