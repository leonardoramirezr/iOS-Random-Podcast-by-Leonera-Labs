import SwiftUI

@main
struct RandomPodcastApp: App {
    @State private var auth = SpotifyAuth()
    @State private var library = ShowLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(library)
        }
    }
}
