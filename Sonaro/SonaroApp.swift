import SwiftUI

@main
struct SonaroApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var player = PlayerManager()
    @StateObject private var appearance = AppearanceManager()
    @StateObject private var fontManager = FontManager()
    @StateObject private var likes = LikeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(player)
                .environmentObject(player.playbackProgress)
                .environmentObject(player.lyricPlayback)
                .environmentObject(appearance)
                .environmentObject(fontManager)
                .environmentObject(likes)
                .tint(Theme.accent)
                // 应用全局字体 - 监听 fontManager 的变化
                .onChange(of: fontManager.selectedFontName) { _, _ in
                    // 触发视图重绘
                }
                .onChange(of: fontManager.size) { _, _ in
                    // 触发视图重绘
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.titleBar)
    }
}
