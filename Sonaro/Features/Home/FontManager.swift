import SwiftUI
import AppKit

/// Global font configuration, persisted across launches.
@MainActor
final class FontManager: ObservableObject {
    
    @Published var selectedFontName: String {
        didSet { UserDefaults.standard.set(selectedFontName, forKey: Self.fontNameKey) }
    }
    
    @Published var size: FontSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey) }
    }
    
    private static let fontNameKey = "font.name"
    private static let sizeKey = "font.size"

    /// Sentinel stored value for the system font (also shown as an empty field).
    static let systemFontName = ".AppleSystemUIFont"

    /// 系统中当前已安装的字体家族
    static let availableFontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    private static let installedFontFamilies = Set(availableFontFamilies)

    /// Resolving an on-demand font (e.g. 华文黑体 "STHeiti") through `NSFont` makes
    /// macOS offer to download it, so only installed family names are ever used.
    static func isInstalled(_ name: String) -> Bool {
        name == systemFontName || installedFontFamilies.contains(name)
    }
    
    enum FontSize: String, CaseIterable, Identifiable {
        case small = "small"
        case medium = "medium"
        case large = "large"
        case extraLarge = "extraLarge"
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .small: return "小"
            case .medium: return "标准"
            case .large: return "大"
            case .extraLarge: return "特大"
            }
        }
        
        /// Scale factor relative to the base font size
        var scale: CGFloat {
            switch self {
            case .small: return 0.9
            case .medium: return 1.0
            case .large: return 1.1
            case .extraLarge: return 1.2
            }
        }
    }
    
    init() {
        let fontName = UserDefaults.standard.string(forKey: Self.fontNameKey) ?? Self.systemFontName
        selectedFontName = fontName
        
        let sizeRaw = UserDefaults.standard.string(forKey: Self.sizeKey) ?? FontSize.medium.rawValue
        size = FontSize(rawValue: sizeRaw) ?? .medium
    }
    
    /// Creates a font with the current family and size settings
    func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        if selectedFontName == Self.systemFontName {
            return .system(style).weight(weight)
        }
        
        // 获取对应 TextStyle 的默认大小
        let baseSize = NSFont.preferredFont(forTextStyle: textStyleToNS(style)).pointSize
        return customFont(size: baseSize, weight: weight)
    }
    
    /// Creates a custom-sized font with the current family and scale applied
    func customFont(size baseSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaledSize = baseSize * size.scale

        guard selectedFontName != Self.systemFontName,
              Self.isInstalled(selectedFontName),
              let nsFont = NSFont(name: selectedFontName, size: scaledSize) else {
            // 留空、未安装或按需字体：回退到系统字体
            return .system(size: scaledSize).weight(weight)
        }
        return Font(nsFont)
    }
    
    /// 将 SwiftUI 的 TextStyle 转换为 AppKit 的 NSFont.TextStyle
    private func textStyleToNS(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
