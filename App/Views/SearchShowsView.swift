import SwiftUI

struct SearchShowsView: View {
    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library

    @State private var query = ""
    @State private var results: [PodcastShow] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            ForEach(results) { show in
                Button {
                    library.toggle(show)
                } label: {
                    HStack {
                        ShowRow(show: show)
                        Spacer()
                        Image(systemName: library.contains(show) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundStyle(library.contains(show) ? Color.green : Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Add podcasts")
        .searchable(text: $query, prompt: "Search podcasts")
        .task(id: query) {
            await runSearch(for: query)
        }
        .overlay {
            if isSearching {
                ProgressView()
            }
        }
        .overlay {
            if !query.isEmpty, !isSearching, results.isEmpty, errorMessage == nil {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func runSearch(for query: String) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        // Debounce: `.task(id:)` cancels this run as soon as the query changes.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            results = try await SpotifyAPI(auth: auth).searchShows(matching: term)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
