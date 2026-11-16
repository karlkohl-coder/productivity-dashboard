import SwiftUI

/// Basiscontainer für alle Inhaltsblöcke. Optionaler Titel + Trailing-Slot.
struct Card<Content: View, Trailing: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(Theme.Font.sectionTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    trailing()
                }
            }
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverSurface()
    }
}

extension Card where Trailing == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, content: content, trailing: { EmptyView() })
    }
}

/// Große Kennzahl mit Label – für die Übersichtszeile.
struct MetricTile: View {
    let label: String
    let value: String
    var detail: String?
    var tint: Color = Theme.Palette.textPrimary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(label.uppercased())
                    .font(Theme.Font.caption)
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(value)
                    .font(Theme.Font.metric)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }
}

/// Leerzustand – bewusst zurückhaltend.
struct EmptyStateView: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

/// Horizontaler Anteilsbalken (Produktiv / Neutral / Unproduktiv).
struct SegmentedBar: View {
    let segments: [(value: Double, color: Color)]
    var height: CGFloat = 8

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Capsule().fill(seg.color)
                        .frame(width: max(0, geo.size.width * seg.value / total))
                }
            }
        }
        .frame(height: height)
        .background(Theme.Palette.hairline, in: Capsule())
        .clipShape(Capsule())
    }
}
