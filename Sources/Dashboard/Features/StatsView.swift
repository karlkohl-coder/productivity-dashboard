import Charts
import SwiftUI

struct StatsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week, month, quarter
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: return "7 Tage"
            case .month: return "30 Tage"
            case .quarter: return "90 Tage"
            }
        }
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }

    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var rules: CategoryRules
    @EnvironmentObject private var tasks: TaskStore

    @State private var range: Range = .week
    @State private var dailyHover: ChartTooltip.Reading?
    @State private var scoreHover: ChartTooltip.Reading?
    @State private var hourlyHover: ChartTooltip.Reading?
    @State private var shareHover: ChartTooltip.Reading?
    @State private var enlarged: Set<String> = []
    @State private var donutSize: CGSize = .zero

    /// Überlebt die Neuauswertung des Rumpfs und rechnet nur neu, wenn sich
    /// wirklich etwas geändert hat.
    @State private var cache = StatsCache()

    private var stats: StatsSnapshot {
        cache.snapshot(tracker: tracker, rules: rules, days: range.days)
    }

    /// Diagramme wachsen unter dem Zeiger, damit sich Werte ablesen lassen.
    private func height(_ id: String, _ base: CGFloat) -> CGFloat {
        enlarged.contains(id) ? base * 1.35 : base
    }

    private func trackEnlarge(_ id: String) -> some View {
        Color.clear.onHover { inside in
            withAnimation(.easeOut(duration: 0.18)) {
                if inside { enlarged.insert(id) } else { enlarged.remove(id) }
            }
        }
    }


    var body: some View {
        Page(title: "Statistik", subtitle: "Auswertung der letzten \(range.days) Tage") {
            TileGrid {
                MetricTile(label: "Erfasst gesamt", value: Format.durationShort(stats.totalTime))
                MetricTile(label: "Produktiv", value: Format.durationShort(stats.productive),
                           detail: stats.totalTime > 0 ? Format.percent(stats.productive / stats.totalTime) : "–",
                           tint: Theme.Palette.productive)
                MetricTile(label: "Ø Score", value: "\(Int((stats.averageScore * 100).rounded()))",
                           detail: "von 100", tint: Theme.Palette.accent)
                MetricTile(label: "Ø pro Tag",
                           value: Format.durationShort(stats.totalTime / Double(max(stats.activeDays, 1))),
                           detail: "\(stats.activeDays) aktive Tage")
            }

            dailyChart
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                scoreChart
                distributionCard.frame(width: 300)
            }
            hourlyChart
            topAppsList
        } actions: {
            Picker("", selection: $range) {
                ForEach(Range.allCases) { r in Text(r.label).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .controlSize(.small)
        }
    }


    // MARK: - Diagramme

    private var dailyChart: some View {
        Card(title: "Zeit pro Tag", subtitle: "gestapelt nach Einstufung") {
            if stats.totalTime == 0 {
                EmptyStateView(symbol: "chart.bar", message: "Noch keine Daten im gewählten Zeitraum.")
            } else {
                Chart {
                    ForEach(stats.series) { day in
                        ForEach(ProductivityCategory.allCases) { cat in
                            BarMark(
                                x: .value("Tag", day.day, unit: .day),
                                y: .value("Stunden", day.time(for: cat) / 3600)
                            )
                            .foregroundStyle(by: .value("Kategorie", cat.label))
                            .cornerRadius(2)
                        }
                    }
                }
                .chartForegroundStyleScale(categoryScale)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : range == .month ? 5 : 14)) { value in
                        AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartLegend(position: .bottom, spacing: Theme.Spacing.sm)
                .chartPointerTracking({ proxy, point, plot in
                    guard let day: Date = proxy.value(atX: point.x - plot.minX) else {
                        dailyHover = nil; return
                    }
                    let cal = Calendar.german
                    guard let stats = stats.series.first(where: { cal.isDate($0.day, inSameDayAs: day) }),
                          stats.total > 0 else { dailyHover = nil; return }
                    dailyHover = .init(
                        point: point,
                        key: Format.dayMonth.string(from: stats.day),
                        title: Format.weekdayFull.string(from: stats.day) + ", " + Format.dayMonth.string(from: stats.day),
                        entries: ProductivityCategory.allCases.compactMap { cat in
                            let seconds = stats.time(for: cat)
                            guard seconds > 0 else { return nil }
                            return .init(color: cat.color,
                                         label: cat.label,
                                         value: "\(Format.durationShort(seconds)) · \(Int(seconds / stats.total * 100)) %")
                        })
                }, onExit: { dailyHover = nil })
                .chartTooltip(dailyHover)
                .frame(height: height("daily", 220))
                .background(trackEnlarge("daily"))
            }
        }
    }

    private var scoreChart: some View {
        Card(title: "Produktivitäts-Score", subtitle: "0 – 100 je Tag") {
            if stats.activeDays == 0 {
                EmptyStateView(symbol: "chart.line.uptrend.xyaxis", message: "Noch keine Daten.")
            } else {
                Chart(stats.series.filter { $0.total > 0 }) { day in
                    AreaMark(
                        x: .value("Tag", day.day, unit: .day),
                        y: .value("Score", day.score * 100)
                    )
                    .foregroundStyle(LinearGradient(colors: [Theme.Palette.accent.opacity(0.25), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    LineMark(
                        x: .value("Tag", day.day, unit: .day),
                        y: .value("Score", day.score * 100)
                    )
                    .foregroundStyle(Theme.Palette.accent)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Tag", day.day, unit: .day),
                        y: .value("Score", day.score * 100)
                    )
                    .foregroundStyle(Theme.Palette.accent)
                    .symbolSize(18)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) }
                .chartPointerTracking({ proxy, point, plot in
                    guard let day: Date = proxy.value(atX: point.x - plot.minX) else {
                        scoreHover = nil; return
                    }
                    let cal = Calendar.german
                    guard let stats = stats.series.first(where: { cal.isDate($0.day, inSameDayAs: day) }),
                          stats.total > 0 else { scoreHover = nil; return }
                    scoreHover = .init(
                        point: point,
                        key: Format.dayMonth.string(from: stats.day),
                        title: Format.weekdayFull.string(from: stats.day) + ", " + Format.dayMonth.string(from: stats.day),
                        entries: [.init(color: Theme.Palette.accent,
                                        label: "Score",
                                        value: "\(Int((stats.score * 100).rounded())) von 100"),
                                  .init(color: Theme.Palette.textTertiary,
                                        label: "Erfasst",
                                        value: Format.durationShort(stats.total))])
                }, onExit: { scoreHover = nil })
                .chartTooltip(scoreHover)
                .frame(height: height("score", 200))
                .background(trackEnlarge("score"))
            }
        }
    }

    private var distributionCard: some View {
        Card(title: "Verteilung") {
            if stats.totalTime == 0 {
                EmptyStateView(symbol: "chart.pie", message: "Keine Daten.")
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    Chart(ProductivityCategory.allCases) { cat in
                        SectorMark(
                            angle: .value("Zeit", value(for: cat)),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(3)
                    }
                    .chartPointerTracking({ _, point, _ in
                        shareHover = donutReading(at: point, in: donutSize)
                    }, onExit: { shareHover = nil })
                    .chartTooltip(shareHover)
                    .frame(height: 150)
                    .background(GeometryReader { geo in
                        Color.clear.onAppear { donutSize = geo.size }
                            .onChange(of: geo.size) { _, new in donutSize = new }
                    })

                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(ProductivityCategory.allCases) { cat in
                            HStack(spacing: Theme.Spacing.xs) {
                                Circle().fill(cat.color).frame(width: 7, height: 7)
                                Text(cat.label).font(Theme.Font.caption)
                                Spacer()
                                Text(Format.percent(value(for: cat) / stats.totalTime))
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var hourlyChart: some View {
        Card(title: "Tagesprofil", subtitle: "wann im Tagesverlauf gearbeitet wird") {
            let data = stats.hourly
            if data.isEmpty {
                EmptyStateView(symbol: "clock", message: "Noch keine Daten.")
            } else {
                Chart(data, id: \.hour) { entry in
                    BarMark(
                        x: .value("Stunde", entry.hour),
                        y: .value("Stunden", entry.seconds / 3600),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(by: .value("Kategorie", entry.category.label))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(categoryScale)
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: 0, through: 23, by: 3))) { value in
                        AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                        AxisValueLabel {
                            if let h = value.as(Int.self) { Text(String(format: "%02d", h)) }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom, spacing: Theme.Spacing.sm)
                .chartPointerTracking({ proxy, point, plot in
                    guard let hour: Int = proxy.value(atX: point.x - plot.minX) else {
                        hourlyHover = nil; return
                    }
                    let slice = data.filter { $0.hour == hour && $0.seconds > 0 }
                    guard !slice.isEmpty else { hourlyHover = nil; return }
                    hourlyHover = .init(
                        point: point,
                        key: "\(hour)",
                        title: String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24),
                        entries: slice.map { .init(color: $0.category.color,
                                                   label: $0.category.label,
                                                   value: Format.durationShort($0.seconds)) })
                }, onExit: { hourlyHover = nil })
                .chartTooltip(hourlyHover)
                .frame(height: height("hourly", 180))
                .background(trackEnlarge("hourly"))
            }
        }
    }

    /// Rangliste statt Balkendiagramm – so passen Icon und Einstufung
    /// direkt neben die App, was auf einen Blick mehr sagt.
    private var topAppsList: some View {
        let usage = stats.topApps

        return Card(title: "Top-Anwendungen", subtitle: "im gewählten Zeitraum") {
            if usage.isEmpty {
                EmptyStateView(symbol: "app.dashed", message: "Noch keine Daten.")
            } else {
                VStack(spacing: 0) {
                    ForEach(usage) { app in
                        AppUsageRow(usage: app,
                                    maximum: usage.first?.seconds ?? 1,
                                    barWidth: 140)
                        if app.id != usage.last?.id { Divider().opacity(0.35) }
                    }
                }
            }
        }
    }

    private var categoryScale: KeyValuePairs<String, Color> {
        [ProductivityCategory.productive.label: ProductivityCategory.productive.color,
         ProductivityCategory.neutral.label: ProductivityCategory.neutral.color,
         ProductivityCategory.unproductive.label: ProductivityCategory.unproductive.color]
    }

    /// Der Ring lässt sich nicht über den Proxy abfragen – der Abschnitt
    /// ergibt sich aus dem Winkel zum Mittelpunkt. Swift Charts beginnt oben
    /// und läuft im Uhrzeigersinn.
    private func donutReading(at point: CGPoint, in size: CGSize) -> ChartTooltip.Reading? {
        guard size.width > 0, stats.totalTime > 0 else { return nil }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = sqrt(dx * dx + dy * dy)
        let outer = min(size.width, size.height) / 2
        guard radius <= outer, radius >= outer * 0.55 else { return nil }

        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }

        var sweep = 0.0
        for cat in ProductivityCategory.allCases {
            let seconds = value(for: cat)
            guard seconds > 0 else { continue }
            sweep += seconds / stats.totalTime * 2 * .pi
            if angle <= sweep {
                return .init(point: point, key: cat.rawValue, title: cat.label,
                             entries: [.init(color: cat.color,
                                             label: "\(Int((seconds / stats.totalTime * 100).rounded())) %",
                                             value: Format.durationShort(seconds))])
            }
        }
        return nil
    }

    private func value(for cat: ProductivityCategory) -> Double {
        switch cat {
        case .productive:   return stats.productive
        case .neutral:      return stats.neutral
        case .unproductive: return stats.unproductive
        }
    }
}
