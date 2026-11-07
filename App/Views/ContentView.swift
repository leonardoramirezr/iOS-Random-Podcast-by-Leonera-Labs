import SwiftUI

struct ContentView: View {
    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library
    @Environment(OpenedEpisodes.self) private var openedEpisodes

    @State private var isShowingRandomEpisode = false
    @State private var searchList: ShowList?
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Spotify") {
                    connectionRows
                }

                Section {
                    let shows = library.shows(in: .randomFromAll)
                    if shows.isEmpty {
                        Text("No podcasts saved yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shows) { show in
                        ShowRow(show: show)
                    }
                    .onDelete { offsets in
                        library.remove(at: offsets, from: .randomFromAll)
                    }
                } header: {
                    Text(ShowList.randomFromAll.title)
                } footer: {
                    Text("“Random episode from all” picks an episode from any podcast in this list.")
                }

                Section {
                    let shows = library.shows(in: .onePodcast)
                    if shows.isEmpty {
                        Text("No podcasts saved yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shows) { show in
                        NavigationLink {
                            ShowDetailView(show: show)
                        } label: {
                            ShowRow(show: show)
                        }
                    }
                    .onDelete { offsets in
                        library.remove(at: offsets, from: .onePodcast)
                    }
                } header: {
                    Text(ShowList.onePodcast.title)
                } footer: {
                    Text("Tap a podcast to get a random episode from that podcast only.")
                }

                Section("Opened episodes") {
                    if openedEpisodes.episodes.isEmpty {
                        Text("Episodes you open in Spotify appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(openedEpisodes.episodes) { episode in
                        OpenedEpisodeRow(episode: episode)
                    }
                }
            }
            .navigationTitle("Random Podcast")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(ShowList.allCases) { list in
                            Button {
                                searchList = list
                            } label: {
                                Text("Add to “\(String(localized: list.title))”")
                            }
                        }
                    } label: {
                        Label("Add podcasts", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $searchList) { list in
                SearchShowsView(list: list)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isShowingRandomEpisode = true
                } label: {
                    Label("Random episode from all", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!auth.isConnected || library.shows(in: .randomFromAll).isEmpty)
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $isShowingRandomEpisode) {
                RandomEpisodeView(shows: library.shows(in: .randomFromAll))
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
