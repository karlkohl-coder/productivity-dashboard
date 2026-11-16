import Foundation

/// Reine Rechenlogik über Aktivitätssegmente – bewusst ohne UI-Bezug,
/// damit sie leicht testbar und wiederverwendbar bleibt.
struct DayStats: Identifiable {
    var id: Date { day }
    let day: Date
    let productive: TimeInterval
    let neutral: TimeInterval
    let unproductive: TimeInterval

    var total: TimeInterval { productive + neutral + unproductive }

    /// 0…1. Neutral zählt zur Hälfte.
    var score: Double {
        guard total > 0 else { return 0 }
        return (productive + neutral * 0.5) / total
    }

    func time(for category: ProductivityCategory) -> TimeInterval {
        switch category {
        case .productive:   return productive
        case .neutral:      return neutral
        case .unproductive: return unproductive
        }
    }
}

@MainActor
enum Statistics {

    static func dayStats(segments: [ActivitySegment], rules: CategoryRules, day: Date) -> DayStats {
        var buckets: [ProductivityCategory: TimeInterval] = [:]
        for seg in segments {
            let cat = rules.category(for: seg.bundleID)
            buckets[cat, default: 0] += seg.duration
        }
        return DayStats(day: day,
                        productive: buckets[.productive] ?? 0,
                        neutral: buckets[.neutral] ?? 0,
                        unproductive: buckets[.unproductive] ?? 0)
    }

    /// Statistik für die letzten `days` Tage, chronologisch aufsteigend.
    static func series(tracker: ActivityTracker, rules: CategoryRules, days: Int) -> [DayStats] {
        let cal = Calendar.german
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return dayStats(segments: tracker.segments(on: day), rules: rules, day: day)
        }
    }

    /// Zerlegt ein Segment an den Stundengrenzen.
    /// Wird für alle stundengenauen Auswertungen gebraucht.
    static func hourSlices(of segment: ActivitySegment) -> [(hour: Int, seconds: TimeInterval)] {
        let cal = Calendar.german
        var slices: [(hour: Int, seconds: TimeInterval)] = []
        var cursor = segment.start
        while cursor < segment.end {
            guard let hourEnd = cal.dateInterval(of: .hour, for: cursor)?.end else { break }
            let sliceEnd = min(segment.end, hourEnd)
            guard sliceEnd > cursor else { break }
            slices.append((cal.component(.hour, from: cursor), sliceEnd.timeIntervalSince(cursor)))
            cursor = sliceEnd
        }
        return slices
    }

    /// Nutzung je Stunde eines Tages – für das Tagesprofil.
    static func hourlyTotals(segments: [ActivitySegment], rules: CategoryRules, day: Date)
        -> [(hour: Int, category: ProductivityCategory, seconds: TimeInterval)] {
        let cal = Calendar.german
        var grid: [Int: [ProductivityCategory: TimeInterval]] = [:]

        for seg in segments {
            let cat = rules.category(for: seg.bundleID)
            // Segment auf Stundengrenzen aufteilen, damit Balken exakt sitzen.
            var cursor = seg.start
            while cursor < seg.end {
                guard let hourEnd = cal.dateInterval(of: .hour, for: cursor)?.end else { break }
                let sliceEnd = min(seg.end, hourEnd)
                guard sliceEnd > cursor else { break }
                let hour = cal.component(.hour, from: cursor)
                grid[hour, default: [:]][cat, default: 0] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }

        return grid.flatMap { hour, cats in
            cats.map { (hour: hour, category: $0.key, seconds: $0.value) }
        }
        .sorted { $0.hour < $1.hour }
    }
}

/// Alles, was die Statistikseite zeigt – in einem Durchgang berechnet.
struct StatsSnapshot {
    var series: [DayStats] = []
    var topApps: [AppUsage] = []
    var hourly: [(hour: Int, category: ProductivityCategory, seconds: TimeInterval)] = []
    var productive: TimeInterval = 0
    var neutral: TimeInterval = 0
    var unproductive: TimeInterval = 0

    var totalTime: TimeInterval { productive + neutral + unproductive }
    var activeDays: Int { series.filter { $0.total > 0 }.count }

    var averageScore: Double {
        let active = series.filter { $0.total > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.score } / Double(active.count)
    }

    func time(for category: ProductivityCategory) -> TimeInterval {
        switch category {
        case .productive:   return productive
        case .neutral:      return neutral
        case .unproductive: return unproductive
        }
    }
}

/// Hält das Ergebnis fest, bis sich Daten, Einstufung oder Zeitraum ändern.
///
/// SwiftUI wertet den Rumpf einer Ansicht bei jeder Zustandsänderung neu aus –
/// auch beim Bewegen der Maus über ein Diagramm. Ohne diesen Zwischenspeicher
/// liefe die gesamte Auswertung dabei jedes Mal erneut.
@MainActor
final class StatsCache {
    private var key: [Int] = []
    private var value = StatsSnapshot()

    func snapshot(tracker: ActivityTracker, rules: CategoryRules, days: Int) -> StatsSnapshot {
        let next = [tracker.revision, rules.revision, days]
        guard next != key else { return value }
        key = next
        value = Statistics.snapshot(tracker: tracker, rules: rules, days: days)
        return value
    }
}

extension Statistics {
    /// Ein Durchgang für die ganze Seite. Die Segmente des Zeitraums werden
    /// dabei nur einmal geholt – vorher taten das Tagesprofil und die
    /// Rangliste jeweils für sich.
    static func snapshot(tracker: ActivityTracker, rules: CategoryRules, days: Int) -> StatsSnapshot {
        var snap = StatsSnapshot()
        snap.series = series(tracker: tracker, rules: rules, days: days)
        for day in snap.series {
            snap.productive += day.productive
            snap.neutral += day.neutral
            snap.unproductive += day.unproductive
        }
        let ranged = tracker.segments(from: snap.series.first?.day ?? Date(), to: Date())
        snap.topApps = Array(tracker.usage(for: ranged, rules: rules).prefix(12))
        snap.hourly = hourlyTotals(segments: ranged, rules: rules, day: Date())
        return snap
    }
}
