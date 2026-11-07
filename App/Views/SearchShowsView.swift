import SwiftUI

struct SearchShowsView: View {
    @Environment(SpotifyAuth.self) private var auth
    @Environment(ShowLibrary.self) private var library

    /// List that tapping a result saves to or removes from. The picker at the top changes it.
    @State private var list: ShowList
    @State private var query = ""
    @State private var results: [PodcastShow] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    init(list: ShowList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        List {
            Section {
                Picker(selection: $list) {
                    ForEach(ShowList.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text("Save to")
                }
                .pickerStyle(.menu)
            } footer: {
                Text(listDescription)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(results) { show in
                    Button {
                        library.toggle(show, in: list)
                    } label: {
                        HStack {
                            ShowRow(show: show)
                            Spacer()
                            Image(systemName: library.contains(show, in: list) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title2)
                                .foregroundStyle(library.contains(show, in: list) ? Color.green : Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
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

    private var listDescription: LocalizedStringKey {
        switch list {
        case .randomFromAll:
            "The random episode can come from any podcast in this list."
        case .onePodcast:
            "You select one podcast from this list and get a random episode from that podcast only."
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
