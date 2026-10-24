import SwiftUI

/// Artwork and name of a podcast, shared by the saved list and the search results.
struct ShowRow: View {
    let show: PodcastShow

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: show.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.2)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(show.name)
                .font(.headline)
                .lineLimit(2)
        }
    }
}
