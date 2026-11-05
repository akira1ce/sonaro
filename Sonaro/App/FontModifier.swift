import SwiftUI

/// ViewModifier that applies the global font configuration
struct GlobalFontModifier: ViewModifier {
    @EnvironmentObject private var fontManager: FontManager
    
    func body(content: Content) -> some View {
        content
            .font(fontManager.font(.body))
    }
}

extension View {
    /// Applies the global font configuration to this view
    func globalFont() -> some View {
        modifier(GlobalFontModifier())
    }
}

/// Custom text styles that respect the global font configuration
struct CustomText: View {
    @EnvironmentObject private var fontManager: FontManager
    
    let text: String
    let style: Font.TextStyle
    let weight: Font.Weight
    
    init(_ text: String, style: Font.TextStyle = .body, weight: Font.Weight = .regular) {
        self.text = text
        self.style = style
        self.weight = weight
    }
    
    var body: some View {
        Text(text)
            .font(fontManager.font(style, weight: weight))
    }
}
