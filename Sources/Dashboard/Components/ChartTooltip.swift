import Charts
import SwiftUI

/// Kurzinfo, die neben dem Mauszeiger steht und sagt, was dort zu sehen ist.
/// Wird von den Diagrammen der Assistenz und der Statistikseite gemeinsam
/// verwendet, damit sich beide gleich anfühlen.
struct ChartTooltip: View {

    struct Reading: Equatable {
        let point: CGPoint
        /// Kennung des Abschnitts unter dem Zeiger – steuert Hervorhebungen.
        let key: String
        let title: String
        let entries: [Entry]

        struct Entry: Equatable {
            let color: Color
            let label: String
            let value: String
        }
    }

    let reading: Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            ForEach(Array(reading.entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 5) {
                    Circle().fill(entry.color).frame(width: 6, height: 6)
                    Text(entry.label)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 6)
                    Text(entry.value)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 96, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .strokeBorder(Theme.Palette.hairlineStrong))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

extension View {
    /// Legt die Kurzinfo über ein Diagramm und hält sie im sichtbaren Bereich.
    func chartTooltip(_ reading: ChartTooltip.Reading?) -> some View {
        overlay(alignment: .topLeading) {
            if let reading {
                GeometryReader { geo in
                    ChartTooltip(reading: reading)
                        .fixedSize()
                        .offset(x: min(max(reading.point.x + 14, 0), max(geo.size.width - 180, 0)),
                                y: min(max(reading.point.y - 10, 0), max(geo.size.height - 64, 0)))
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Verfolgt den Zeiger über der Zeichenfläche und meldet die Position
    /// samt Ausschnitt der Zeichenfläche zurück.
    func chartPointerTracking(_ handler: @escaping (ChartProxy, CGPoint, CGRect) -> Void,
                              onExit: @escaping () -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let point) = phase else { onExit(); return }
                        let plot = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                        handler(proxy, point, plot)
                    }
            }
        }
    }
}
