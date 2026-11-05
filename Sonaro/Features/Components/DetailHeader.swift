import SwiftUI

/// Cover + title + metadata + action buttons, shared by the playlist detail page
/// and the daily recommendations page.
struct DetailHeader<Actions: View>: View {
    @EnvironmentObject private var fontManager: FontManager

    let artworkURL: URL?
    let title: String
    var creator: Profile?
    var stats: String = ""
    var description: String?
    /// Half the artwork size renders the cover as a circle (artist portraits).
    var artworkCorner: CGFloat = Theme.cardCorner
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Artwork(url: artworkURL, corner: artworkCorner)
                .frame(width: 184, height: 184)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(fontManager.customFont(size: 30, weight: .bold))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if let creator, !creator.nickname.isEmpty {
                        HStack(spacing: 8) {
                            Avatar(url: creator.avatarURL(48), size: 22)
                            Text(creator.nickname)
                                .font(fontManager.font(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !stats.isEmpty {
                        Text(stats)
                            .font(fontManager.font(.footnote))
                            .foregroundStyle(.tertiary)
                    }

                    if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        Text(description)
                            .font(fontManager.font(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(.top, 2)
                    }
                }

                // Pin the buttons to the bottom of the column, aligned with the
                // cover, while the text block stays at the top (flex space-between).
                Spacer(minLength: 12)

                actions()
            }
            .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
