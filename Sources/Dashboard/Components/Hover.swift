import SwiftUI

/// Einheitliche Rückmeldung, wenn der Zeiger über einem Element steht:
/// die Fläche hellt sich eine Spur auf, die Kante wird kräftiger, und das
/// Element hebt sich minimal an. Bewusst zurückhaltend – das Design soll
/// ruhig bleiben.
struct HoverSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var lift: CGFloat = 1
    var enabled = true

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering && enabled ? Theme.Palette.cardHover : Theme.Palette.card,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(hovering && enabled ? Theme.Palette.hairlineStrong : Theme.Palette.hairline,
                                  lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering && enabled ? 0.10 : 0),
                    radius: hovering ? 8 : 0, y: hovering ? 2 : 0)
            .offset(y: hovering && enabled ? -lift : 0)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Zeilenhervorhebung innerhalb einer Karte – ohne Rahmen und ohne Anheben.
struct HoverRow: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.sm
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.Palette.hairline.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverSurface(cornerRadius: CGFloat = Theme.Radius.lg,
                      lift: CGFloat = 1,
                      enabled: Bool = true) -> some View {
        modifier(HoverSurface(cornerRadius: cornerRadius, lift: lift, enabled: enabled))
    }

    func hoverRow(cornerRadius: CGFloat = Theme.Radius.sm) -> some View {
        modifier(HoverRow(cornerRadius: cornerRadius))
    }
}
