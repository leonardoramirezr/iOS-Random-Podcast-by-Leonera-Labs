import SwiftUI

struct ContentView: View {
    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library
    @Environment(OpenedEpisodes.self) private var openedEpisodes

    @State private var isShowingRandomEpisode = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Spotify") {
                    connectionRows
                }

                Section("Saved podcasts") {
                    if library.shows.isEmpty {
                        Text("Search for podcasts and save them here to pick random episodes.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.shows) { show in
                        ShowRow(show: show)
                    }
                    .onDelete { offsets in
                        library.remove(at: offsets)
                    }
                }

                Section("Opened episodes") {
                    if openedEpisodes.episodes.isEmpty {
                        Text("Episodes you open in Spotify appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(openedEpisodes.episodes) { episode in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(episode.showName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(episode.openedAt, style: .date)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Random Podcast")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchShowsView()
                    } label: {
                        Label("Add podcasts", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isShowingRandomEpisode = true
                } label: {
                    Label("Random episode", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!auth.isConnected || library.shows.isEmpty)
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $isShowingRandomEpisode) {
                RandomEpisodeView()
            }
            .alert("Something went wrong", isPresented: isShowingError) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var connectionRows: some View {
        if auth.isConnected {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Disconnect", role: .destructive) {
                auth.signOut()
            }
        } else {
            Button {
                connect()
            } label: {
                Label("Connect with Spotify", systemImage: "link")
            }
            .disabled(isConnecting || !auth.isConfigured)

            if !auth.isConfigured {
                Text("Set SPOTIFY_CLIENT_ID in the build settings to enable Spotify.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func connect() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await auth.signIn()
            } catch SpotifyError.cancelled {
                // The user closed the sign-in sheet; nothing to report.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
