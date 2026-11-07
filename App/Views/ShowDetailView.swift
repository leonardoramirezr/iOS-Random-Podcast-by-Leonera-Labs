import SwiftUI

/// Screen for one podcast of the "One podcast at a time" list: picks random episodes from this podcast only.
struct ShowDetailView: View {
    let show: PodcastShow

    @Environment(SpotifyAuth.self) private var auth
    @Environment(OpenedEpisodes.self) private var openedEpisodes

    @State private var isShowingRandomEpisode = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    AsyncImage(url: show.imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(show.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } footer: {
                Text("The random episode comes from this podcast only.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            Section("Opened episodes") {
                if openedFromShow.isEmpty {
                    Text("Episodes you open in Spotify appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(openedFromShow) { episode in
                    OpenedEpisodeRow(episode: episode)
                }
            }
        }
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isShowingRandomEpisode = true
            } label: {
                Label("Random episode from this podcast", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!auth.isConnected)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $isShowingRandomEpisode) {
            RandomEpisodeView(shows: [show])
        }
    }

    /// Opened episodes are stored with the show name, not its ID, so they are matched by name.
    private var openedFromShow: [OpenedEpisode] {
        openedEpisodes.episodes.filter { $0.showName == show.name }
    }
}
