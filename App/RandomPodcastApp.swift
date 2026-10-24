import SwiftUI

@main
struct RandomPodcastApp: App {
    @State private var auth = SpotifyAuth()
    @State private var library = ShowLibrary()
    @State private var openedEpisodes = OpenedEpisodes()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(library)
                .environment(openedEpisodes)
        }
    }
}
