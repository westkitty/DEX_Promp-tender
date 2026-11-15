import AppKit
import SwiftUI

// Native semantic tokens for DEX//PROMPTENDER. Keep the established restrained
// glass identity, but distinguish primary work surfaces from secondary insets.
enum PromptenderTheme {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let divider = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let groupSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 18
}

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.42)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PromptenderTheme.divider.opacity(0.48), lineWidth: 0.7)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glassInset(cornerRadius: CGFloat = 8) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PromptenderTheme.surface.opacity(0.22))
        )
    }
}
