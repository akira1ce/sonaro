import SwiftUI

/// Shared visual constants + cross-platform semantic colors (no direct UIKit/AppKit
/// use at the call site).
enum Theme {
    /// The stable system accent color for buttons and highlights.
    static let accent = Color.accentColor
    /// Netease-style red for the playlist "play all" action.
    static let playAction = Color(red: 236 / 255, green: 65 / 255, blue: 65 / 255)
    static let cardCorner: CGFloat = 12
    static let tileCorner: CGFloat = 10
}

extension Color {
    static var appBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var appSecondaryBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var appFill: Color {
        Color(nsColor: .quaternaryLabelColor)
    }
}

/// A simple backdrop for the main scrolling surfaces.
/// Pure system background with no color tinting.
struct AppBackground: View {
    var body: some View {
        Color.appBackground
            .ignoresSafeArea()
    }
}

/// The app icon (from the asset catalog) with a soft accent glow. Shared by the
/// splash and login screens so the brand mark stays consistent everywhere.
struct BrandMark: View {
    var size: CGFloat = 96

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.22, y: size * 0.07)
    }
}
