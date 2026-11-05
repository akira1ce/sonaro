import SwiftUI

/// A minimal press affordance for small icon buttons that don't carry a system
/// style: squashes to 94% while held, springs back on release. No bounce — a
/// single `easeOut` settle.
struct PressableScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A gentle breathing opacity for redacted skeleton placeholders, so loading
/// reads as "working" instead of dead gray. Disabled under Reduce Motion.
struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.4 : 0.9)
            .task {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func skeletonPulse() -> some View {
        modifier(SkeletonPulse())
    }
}
