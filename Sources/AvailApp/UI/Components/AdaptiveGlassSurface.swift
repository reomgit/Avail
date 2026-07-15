import SwiftUI

struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AdaptiveGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let interactive: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = 18,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                content
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 7)
        }
    }
}
