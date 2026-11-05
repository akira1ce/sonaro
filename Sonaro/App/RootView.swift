import SwiftUI

/// Switches between splash (validating cached session), login, and the main app.
struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var appearance: AppearanceManager
    @EnvironmentObject private var fontManager: FontManager
    @EnvironmentObject private var likes: LikeManager

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                SplashView()
            case .loggedOut:
                QRLoginView()
                    .transition(.opacity)
            case .loggedIn:
                MainShell()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.state)
        .preferredColorScheme(appearance.colorScheme)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SONARO_UIDEMO"] == "1" {
                player.seedDemo()
                likes.seedDemo()
                auth.enterDemoMode()
                return
            }
            #endif
            await auth.bootstrap()
        }
    }
}

/// Brief launch state shown while the cached cookie is validated. Presents the
/// brand mark with a soft entrance + gentle breathing animation.
private struct SplashView: View {
    @EnvironmentObject private var fontManager: FontManager
    @State private var appear = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            // Accent-tinted backdrop with a soft radial glow behind the logo.
            Color.appBackground.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.06), .clear],
                center: .center, startRadius: 8, endRadius: 460
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                BrandMark(size: 128)
                    .scaleEffect(breathe ? 1.04 : 1.0)
                    .scaleEffect(appear ? 1.0 : 0.82)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 6) {
                    Text("Sonaro")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("聆听你的世界")
                        .font(fontManager.font(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)
            }

            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(Theme.accent)
                    .opacity(appear ? 0.9 : 0)
                    .padding(.bottom, 54)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
                appear = true
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
