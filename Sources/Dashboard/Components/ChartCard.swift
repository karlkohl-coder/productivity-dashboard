import Charts
import SwiftUI

/// Zeichnet eine von der Assistenz erzeugte Darstellung.
/// Die Werte stammen ausschließlich aus `ChartSpec`, also aus den
/// Aufzeichnungen – hier wird nichts errechnet und nichts ergänzt.
///
/// Unter dem Zeiger wächst das Diagramm, der Abschnitt darunter wird
/// hervorgehoben, und neben der Maus steht, was dort zu sehen ist.
struct ChartCard: View {
    let spec: ChartSpec

    @State private var isHovering = false
    @State private var hover: HoverReading?

    typealias HoverReading = ChartTooltip.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header

            if !spec.hasData {
                Text("Für diesen Zeitraum wurde nichts aufgezeichnet.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.lg)
            } else if spec.style == .table {
                table
            } else {
                chart
                    .frame(height: chartHeight)
                    .animation(.easeOut(duration: 0.18), value: isHovering)
                if spec.style != .horizontalBars {
                    legend
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverSurface(cornerRadius: Theme.Radius.md, lift: 0)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { hover = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(spec.subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Größe

    private var baseHeight: CGFloat {
        switch spec.style {
        case .horizontalBars: return CGFloat(spec.series.first?.points.count ?? 3) * 24 + 30
        case .donut:          return 170
        case .table:          return 0
        default:              return 190
        }
    }

    /// Unter dem Zeiger wächst die Darstellung, damit sich Werte leichter
    /// ablesen lassen.
    private var chartHeight: CGFloat {
        isHovering ? baseHeight * 1.35 : baseHeight
    }

    // MARK: - Diagrammarten

    @ViewBuilder
    private var chart: some View {
        switch spec.style {
        case .groupedBars:    groupedBars
        case .horizontalBars: horizontalBars
        case .line:           lineChart
        case .donut:          donut
        case .table:          EmptyView()
        }
    }

    private var groupedBars: some View {
        Chart {
            ForEach(spec.series) { series in
                ForEach(series.points) { point in
                    BarMark(
                        x: .value("Zeitpunkt", point.label),
                        y: .value(spec.unit, point.value)
                    )
                    .foregroundStyle(series.color)
                    .opacity(dimmed(point.label) ? 0.3 : 1)
                    .position(by: .value("Reihe", series.name))
                    .cornerRadius(2)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel(orientation: manyCategories ? .verticalReversed : .automatic)
                    .font(.system(size: 9))
            }
        }
        .chartOverlay { proxy in categoryTracker(proxy, axis: .horizontal) }
        .chartTooltip(hover)
    }

    private var horizontalBars: some View {
        Chart(spec.series.first?.points ?? []) { point in
            BarMark(
                x: .value(spec.unit, point.value),
                y: .value("Anwendung", point.label)
            )
            .foregroundStyle((point.color ?? Theme.Palette.accent).gradient)
            .opacity(dimmed(point.label) ? 0.35 : 1)
            .cornerRadius(3)
            .annotation(position: .trailing) {
                Text("\(Int(point.value))")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .chartXAxis { AxisMarks(position: .bottom) }
        .chartYAxis { AxisMarks(preset: .aligned, position: .leading) }
        .chartOverlay { proxy in categoryTracker(proxy, axis: .vertical) }
        .chartTooltip(hover)
    }

    private var lineChart: some View {
        Chart {
            ForEach(spec.series) { series in
                // Fläche nur bei einer einzigen Reihe – sonst verdecken
                // sich die Verläufe gegenseitig.
                if spec.series.count == 1 {
                    ForEach(series.points) { point in
                        AreaMark(
                            x: .value("Zeitpunkt", point.label),
                            y: .value(spec.unit, point.value)
                        )
                        .foregroundStyle(LinearGradient(colors: [series.color.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    }
                }
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("Zeitpunkt", point.label),
                        y: .value(spec.unit, point.value)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Zeitpunkt", point.label),
                        y: .value(spec.unit, point.value)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(hover?.key == point.label ? 60 : 18)
                }
                .foregroundStyle(by: .value("Reihe", series.name))
            }
        }
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartOverlay { proxy in categoryTracker(proxy, axis: .horizontal) }
        .chartTooltip(hover)
    }

    /// Die Farben kommen aus den Punkten selbst – so kann derselbe Ring
    /// Einstufungen wie auch Anwendungen zeigen.
    private var donut: some View {
        Chart(visiblePoints) { point in
            SectorMark(
                angle: .value(spec.unit, point.value),
                innerRadius: .ratio(0.62),
                outerRadius: .ratio(hover?.key == point.label ? 1.0 : 0.92),
                angularInset: 1.5
            )
            .foregroundStyle(point.color ?? Theme.Palette.accent)
            .opacity(dimmed(point.label) ? 0.4 : 1)
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .animation(.easeOut(duration: 0.15), value: hover?.key)
        .chartOverlay { _ in sectorTracker }
        .chartTooltip(hover)
    }

    // MARK: - Zeiger verfolgen

    private enum TrackAxis { case horizontal, vertical }

    /// Ermittelt die Kategorie unter dem Zeiger über den Chart-Proxy.
    private func categoryTracker(_ proxy: ChartProxy, axis: TrackAxis) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase else { hover = nil; return }
                    guard let anchor = proxy.plotFrame else { hover = nil; return }
                    let plot = geo[anchor]
                    let key: String? = axis == .horizontal
                        ? proxy.value(atX: location.x - plot.minX, as: String.self)
                        : proxy.value(atY: location.y - plot.minY, as: String.self)
                    guard let key else { hover = nil; return }
                    hover = reading(forCategory: key, at: location)
                }
        }
    }

    /// Der Ring lässt sich nicht über den Proxy abfragen: der Abschnitt wird
    /// aus dem Winkel zum Mittelpunkt bestimmt. Swift Charts beginnt oben
    /// und läuft im Uhrzeigersinn.
    private var sectorTracker: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase else { hover = nil; return }
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let dx = location.x - center.x
                    let dy = location.y - center.y
                    let radius = sqrt(dx * dx + dy * dy)
                    let outer = min(geo.size.width, geo.size.height) / 2
                    guard radius <= outer, radius >= outer * 0.55 else { hover = nil; return }

                    var angle = atan2(dx, -dy)
                    if angle < 0 { angle += 2 * .pi }
                    let total = visiblePoints.reduce(0) { $0 + $1.value }
                    guard total > 0 else { hover = nil; return }

                    var sweep = 0.0
                    for point in visiblePoints {
                        sweep += point.value / total * 2 * .pi
                        if angle <= sweep {
                            hover = reading(forCategory: point.label, at: location)
                            return
                        }
                    }
                    hover = nil
                }
        }
    }

    // MARK: - Ablesung zusammenstellen

    private func reading(forCategory key: String, at point: CGPoint) -> HoverReading? {
        switch spec.style {
        case .donut, .horizontalBars:
            // Ein Wert je Kategorie – Anteil am Ganzen ist die Aussage.
            let points = spec.style == .donut ? visiblePoints : (spec.series.first?.points ?? [])
            guard let hit = points.first(where: { $0.label == key }) else { return nil }
            let total = points.reduce(0) { $0 + $1.value }
            let share = total > 0 ? Int((hit.value / total * 100).rounded()) : 0
            return HoverReading(
                point: point, key: key, title: hit.label,
                entries: [.init(color: hit.color ?? Theme.Palette.accent,
                                label: "\(share) %",
                                value: "\(Int(hit.value)) \(spec.unit)")])

        default:
            // Mehrere Reihen an einem Zeitpunkt – alle nebeneinander zeigen.
            let entries = spec.series.compactMap { series -> HoverReading.Entry? in
                guard let hit = series.points.first(where: { $0.label == key }) else { return nil }
                return .init(color: series.color,
                             label: series.name,
                             value: "\(Int(hit.value)) \(spec.unit)")
            }
            guard !entries.isEmpty else { return nil }
            return HoverReading(point: point, key: key, title: key, entries: entries)
        }
    }

    /// Abschnitte, die nicht unter dem Zeiger liegen, treten zurück.
    private func dimmed(_ label: String) -> Bool {
        guard let hover, spec.style != .groupedBars, spec.style != .line else { return false }
        return hover.key != label
    }

    // MARK: - Tabelle

    /// Schlichte Tabelle: Kopfzeile, Trennlinie, Zeilen. Die erste Spalte
    /// darf umbrechen, die übrigen bleiben schmal und rechtsbündig.
    private var table: some View {
        let columns = spec.table?.columns ?? []
        let rows = spec.table?.rows ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, title in
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: alignment(index, of: columns.count))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 5)

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        Text(cell)
                            .font(.system(size: 11))
                            .foregroundStyle(index == 0 ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                            .multilineTextAlignment(index == 0 ? .leading : .center)
                            .frame(maxWidth: .infinity, alignment: alignment(index, of: row.count))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .hoverRow()

                if rowIndex < rows.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    /// Erste Spalte links, letzte rechts, dazwischen mittig – sonst reißt
    /// eine rechtsbündige Mittelspalte eine Lücke auf.
    private func alignment(_ index: Int, of count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }

    // MARK: - Legende

    private var manyCategories: Bool {
        (spec.series.first?.points.count ?? 0) > 8
    }

    /// Anteile mit dem Wert null erzeugen im Ring nur unsichtbare Segmente.
    private var visiblePoints: [ChartPoint] {
        (spec.series.first?.points ?? []).filter { $0.value > 0 }
    }

    /// Umbricht als Ganzes, nicht innerhalb eines Eintrags – sonst steht da
    /// „Dashbo / ard“.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: Theme.Spacing.sm)],
                  alignment: .leading, spacing: 4) {
            ForEach(legendEntries, id: \.name) { entry in
                HStack(spacing: 4) {
                    Circle().fill(entry.color).frame(width: 7, height: 7)
                    Text(entry.name)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.total)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .opacity(hover == nil || hover?.key == entry.name ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: hover?.key)
            }
        }
    }

    /// „Minuten“ ist in der Legende zu lang und drängt den App-Namen ins
    /// Abschneiden.
    private static func shortUnit(_ unit: String) -> String {
        unit == "Minuten" ? "Min" : unit
    }

    private var legendEntries: [(name: String, color: Color, total: String)] {
        if spec.style == .donut {
            let total = visiblePoints.reduce(0) { $0 + $1.value }
            return visiblePoints.map {
                ($0.label,
                 $0.color ?? Theme.Palette.accent,
                 "\(Int($0.value)) \(Self.shortUnit(spec.unit)) · \(Int($0.value / max(total, 1) * 100)) %")
            }
        }
        return spec.series.map { ($0.name, $0.color, "\(Int($0.total)) \(Self.shortUnit(spec.unit))") }
    }
}
