import SwiftUI

/// Light / dark / system appearance, persisted across launches.
@MainActor
final class AppearanceManager: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
    }

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private static let key = "appearance.mode"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? Mode.system.rawValue
        mode = Mode(rawValue: raw) ?? .system
    }

    /// `nil` lets the system decide.
    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
