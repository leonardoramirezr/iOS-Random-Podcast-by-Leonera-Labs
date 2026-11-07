import SwiftUI

/// An episode from the opened-episodes history, shared by the main screen and the podcast screen.
struct OpenedEpisodeRow: View {
    let episode: OpenedEpisode

    var body: some View {
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
