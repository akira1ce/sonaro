import SwiftUI

/// A centered icon + message, used for empty and error states.
struct InfoState: View {
    @EnvironmentObject private var fontManager: FontManager
    
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(fontManager.font(.headline))
            if let message {
                Text(message)
                    .font(fontManager.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 320)
        .padding(32)
    }
}

/// A section header with an optional trailing accessory.
struct SectionHeader: View {
    @EnvironmentObject private var fontManager: FontManager
    
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(fontManager.customFont(size: 20, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(fontManager.font(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
