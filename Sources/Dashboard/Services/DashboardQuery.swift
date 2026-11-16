import EventKit
import Foundation

/// Deterministische Abfrageschicht über alle Dashboard-Daten.
///
/// Sämtliche Rechenarbeit passiert hier, nicht im Sprachmodell: das Modell
/// bekommt fertig ausgewertete Sätze und muss nur noch formulieren. Damit
/// stimmen die Zahlen auch dann, wenn das Modell klein ist.
@MainActor
struct DashboardQuery {
    let tracker: ActivityTracker
    let rules: CategoryRules
    let tasks: TaskStore
    let calendar: CalendarService

    private var cal: Calendar { .german }

    // MARK: - Hilfen

    /// Zeitraum der letzten `days` Tage, einschließlich heute.
    private func range(days: Int) -> (start: Date, end: Date) {
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
        return (start, Date())
    }

    /// Findet die Bundle-ID zu einer vom Benutzer genannten Bezeichnung.
    /// „chrome“ trifft „Google Chrome“, „vscode“ trifft „Code“ usw.
    private func resolve(_ query: String) -> (bundleID: String, name: String)? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        var candidates: [String: String] = [:]
        for seg in tracker.segments { candidates[seg.bundleID] = seg.appName }
        for app in tracker.runningApps where app.bundleIdentifier != nil {
            candidates[app.bundleIdentifier!] = app.localizedName ?? app.bundleIdentifier!
        }

        // Exakt, dann enthalten, dann Bundle-ID.
        if let hit = candidates.first(where: { $0.value.lowercased() == needle }) {
            return (hit.key, hit.value)
        }
        if let hit = candidates.first(where: { $0.value.lowercased().contains(needle) || needle.contains($0.value.lowercased()) }) {
            return (hit.key, hit.value)
        }
        if let hit = candidates.first(where: { $0.key.lowercased().contains(needle) }) {
            return (hit.key, hit.value)
        }
        return nil
    }

    /// Einzahl/Mehrzahl, damit die Sätze für das Modell sauber lesbar sind.
    private func plural(_ count: Int, _ singular: String, _ many: String) -> String {
        "\(count) \(count == 1 ? singular : many)"
    }

    /// „1 Std 23 Min“ – für das Modell zusätzlich die reine Minutenzahl.
    private func time(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0 Min" }
        if seconds < 60 { return "weniger als 1 Min" }
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(Format.duration(seconds)) (\(minutes) Min)" : "\(minutes) Min"
    }

    // MARK: - Abfragen

    /// Meistgenutzte Anwendungen eines Zeitraums.
    func appUsage(days: Int, limit: Int) -> String {
        let r = range(days: days)
        let segments = tracker.segments(from: r.start, to: r.end)
        let usage = tracker.usage(for: segments, rules: rules)
        guard !usage.isEmpty else {
            return "Für die letzten \(days) Tage wurde keine App-Nutzung aufgezeichnet."
        }
        let total = usage.reduce(0) { $0 + $1.seconds }
        var lines = ["Aufgezeichnete App-Nutzung der letzten \(days) Tage (gesamt \(time(total))):"]
        for (index, app) in usage.prefix(max(limit, 1)).enumerated() {
            let share = Int((app.seconds / total * 100).rounded())
            lines.append("\(index + 1). \(app.appName) – \(time(app.seconds)), \(share) % der Zeit, eingestuft als \(app.category.label)")
        }
        if usage.count > limit {
            lines.append("(\(usage.count - limit) weitere Anwendungen nicht aufgeführt)")
        }
        return lines.joined(separator: "\n")
    }

    /// Direkter Vergleich zweier Anwendungen samt Tagesverlauf.
    func compareApps(_ first: String, _ second: String, days: Int) -> String {
        // Fehlt ein Name oder ist er unbekannt, entscheiden die Daten statt
        // des Modells – sonst tauchen Anwendungen auf, die nie liefen.
        let ranked = tracker.usage(for: tracker.segments(from: range(days: days).start, to: Date()),
                                   rules: rules).filter { $0.seconds > 0 }
        var unknown: [String] = []

        // Ein genannter Name wird nie durch eine andere Anwendung ersetzt.
        // Nur wenn gar kein Name kommt, entscheidet die Rangliste.
        func pick(_ name: String, excluding other: (bundleID: String, name: String)?) -> (bundleID: String, name: String)? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let hit = resolve(trimmed), hit.bundleID != other?.bundleID { return hit }
                unknown.append(trimmed)
                return nil
            }
            guard let top = ranked.first(where: { $0.bundleID != other?.bundleID }) else { return nil }
            return (top.bundleID, top.appName)
        }

        let a = pick(first, excluding: nil)
        let b = pick(second, excluding: a)
        if !unknown.isEmpty {
            return "Zu \(unknown.map { "„\($0)“" }.joined(separator: " und ")) liegen keine Aufzeichnungen vor, ein Vergleich ist damit nicht möglich. \(knownAppsHint())"
        }
        guard let a else { return "In den letzten \(days) Tagen wurde keine Anwendung aufgezeichnet." }
        guard let b else { return "Es wurde nur eine Anwendung aufgezeichnet (\(a.name)); für einen Vergleich fehlt die zweite." }
        let notice = ""
        guard a.bundleID != b.bundleID else {
            return "„\(first)“ und „\(second)“ bezeichnen dieselbe Anwendung (\(a.name))."
        }

        let today = cal.startOfDay(for: Date())
        var totalA: TimeInterval = 0
        var totalB: TimeInterval = 0
        var daily: [String] = []

        for offset in stride(from: max(days, 1) - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let segs = tracker.segments(on: day)
            let secA = segs.filter { $0.bundleID == a.bundleID }.reduce(0) { $0 + $1.duration }
            let secB = segs.filter { $0.bundleID == b.bundleID }.reduce(0) { $0 + $1.duration }
            totalA += secA
            totalB += secB
            let label = cal.isDateInToday(day) ? "heute" : Format.weekdayFull.string(from: day) + ", " + Format.dayMonth.string(from: day)
            daily.append("\(label): \(a.name) \(Int((secA / 60).rounded())) Min, \(b.name) \(Int((secB / 60).rounded())) Min")
        }

        guard totalA > 0 || totalB > 0 else {
            return "In den letzten \(days) Tagen wurde weder \(a.name) noch \(b.name) benutzt."
        }

        var lines = [notice + "Vergleich über die letzten \(days) Tage:"]
        lines.append("\(a.name): insgesamt \(time(totalA)), Durchschnitt \(Int((totalA / 60 / Double(days)).rounded())) Min pro Tag, eingestuft als \(rules.category(for: a.bundleID).label)")
        lines.append("\(b.name): insgesamt \(time(totalB)), Durchschnitt \(Int((totalB / 60 / Double(days)).rounded())) Min pro Tag, eingestuft als \(rules.category(for: b.bundleID).label)")

        let diff = abs(totalA - totalB)
        let leader = totalA >= totalB ? a.name : b.name
        let trailer = totalA >= totalB ? b.name : a.name
        let lo = min(totalA, totalB)
        if lo < 60 {
            // Unter einer Minute ist ein Verhältnis nicht aussagekräftig.
            let barely = lo == 0 ? "überhaupt nicht" : "so gut wie gar nicht"
            lines.append("Ergebnis: \(leader) wurde \(time(diff)) länger benutzt; \(trailer) kam \(barely) zum Einsatz.")
        } else {
            let factor = max(totalA, totalB) / lo
            let formatted = String(format: "%.1f", factor).replacingOccurrences(of: ".", with: ",")
            lines.append("Ergebnis: \(leader) wurde \(time(diff)) länger benutzt als \(trailer), das ist das \(formatted)-Fache.")
        }
        lines.append("Tagesverlauf:")
        lines.append(contentsOf: daily)
        return lines.joined(separator: "\n")
    }

    /// Produktivitätsauswertung eines Zeitraums.
    func productivitySummary(days: Int) -> String {
        let series = Statistics.series(tracker: tracker, rules: rules, days: max(days, 1))
        let active = series.filter { $0.total > 0 }
        guard !active.isEmpty else {
            return "Für die letzten \(days) Tage liegen keine Aufzeichnungen vor."
        }

        let productive = series.reduce(0) { $0 + $1.productive }
        let neutral = series.reduce(0) { $0 + $1.neutral }
        let unproductive = series.reduce(0) { $0 + $1.unproductive }
        let total = productive + neutral + unproductive
        let avgScore = active.reduce(0) { $0 + $1.score } / Double(active.count)

        var lines = ["Produktivität der letzten \(days) Tage (\(plural(active.count, "Tag", "Tage")) mit Aufzeichnung):"]
        lines.append("Erfasste Zeit gesamt: \(time(total))")
        lines.append("Anteil produktiv: \(time(productive)), das sind \(Int((productive / total * 100).rounded())) Prozent der erfassten Zeit")
        lines.append("Anteil neutral: \(time(neutral)), das sind \(Int((neutral / total * 100).rounded())) Prozent")
        lines.append("Anteil unproduktiv: \(time(unproductive)), das sind \(Int((unproductive / total * 100).rounded())) Prozent")
        lines.append("Produktivitäts-Score im Durchschnitt: \(Int((avgScore * 100).rounded())) von 100 Punkten (das ist keine Prozentangabe)")
        lines.append("Durchschnitt pro aktivem Tag: \(time(total / Double(active.count)))")

        if let best = active.max(by: { $0.score < $1.score }) {
            lines.append("Bester Tag: \(Format.weekdayFull.string(from: best.day)), \(Format.dayMonth.string(from: best.day)), mit \(Int((best.score * 100).rounded())) von 100 Punkten")
        }
        if let worst = active.min(by: { $0.score < $1.score }), active.count > 1 {
            lines.append("Schwächster Tag: \(Format.weekdayFull.string(from: worst.day)), \(Format.dayMonth.string(from: worst.day)), mit \(Int((worst.score * 100).rounded())) von 100 Punkten")
        }
        return lines.joined(separator: "\n")
    }

    /// Nutzung einer einzelnen Anwendung, Tag für Tag.
    func singleAppUsage(_ name: String, days: Int) -> String {
        guard let app = resolve(name) else {
            return "Zu „\(name)“ liegen keine Aufzeichnungen vor. \(knownAppsHint())"
        }
        let today = cal.startOfDay(for: Date())
        var total: TimeInterval = 0
        var daily: [String] = []
        for offset in stride(from: max(days, 1) - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let seconds = tracker.segments(on: day)
                .filter { $0.bundleID == app.bundleID }
                .reduce(0) { $0 + $1.duration }
            total += seconds
            let label = cal.isDateInToday(day) ? "heute" : Format.weekdayFull.string(from: day) + ", " + Format.dayMonth.string(from: day)
            daily.append("\(label): \(Int((seconds / 60).rounded())) Min")
        }
        guard total > 0 else {
            return "\(app.name) wurde in den letzten \(days) Tagen nicht benutzt."
        }
        var lines = ["\(app.name) in den letzten \(days) Tagen:"]
        lines.append("Insgesamt \(time(total)), Durchschnitt \(Int((total / 60 / Double(days)).rounded())) Min pro Tag.")
        lines.append("Eingestuft als \(rules.category(for: app.bundleID).label).")
        lines.append(contentsOf: daily)
        return lines.joined(separator: "\n")
    }

    /// Anstehende Termine.
    func upcomingEvents(daysAhead: Int) -> String {
        guard calendar.access == .granted else {
            return "Die Termine sind nicht abrufbar, weil das Dashboard noch keinen Kalenderzugriff hat. Der Benutzer kann ihn im Bereich Kalender des Dashboards erteilen."
        }
        let start = Date()
        guard let end = cal.date(byAdding: .day, value: max(daysAhead, 1), to: cal.startOfDay(for: start)) else {
            return "Zeitraum konnte nicht bestimmt werden."
        }
        let events = calendar.fetchEvents(from: start, to: end)
        guard !events.isEmpty else {
            return "In den nächsten \(daysAhead) Tagen stehen keine Termine an."
        }
        var lines = ["Termine der nächsten \(daysAhead) Tage (\(plural(events.count, "Termin", "Termine")) insgesamt):"]
        for event in events.prefix(25) {
            let day = Format.relativeDay(event.startDate)
            let clock = event.isAllDay ? "ganztägig" : "\(Format.time.string(from: event.startDate))–\(Format.time.string(from: event.endDate))"
            var line = "\(day), \(clock): \(event.title ?? "ohne Titel")"
            if let location = event.location, !location.isEmpty { line += " (Ort: \(location))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Aufgabenstand.
    func taskOverview(includeCompleted: Bool) -> String {
        let open = tasks.open
        var lines = ["Aufgaben: \(open.count) offen, \(tasks.completed.count) erledigt, davon \(tasks.completedCount(on: Date())) heute erledigt."]

        if open.isEmpty {
            lines.append("Es sind keine Aufgaben offen.")
        } else {
            lines.append("Offene Aufgaben:")
            for task in open.prefix(25) {
                var line = "- \(task.title) (Priorität \(task.priority.label)"
                if let due = task.dueDate {
                    line += ", fällig \(Format.relativeDay(due))"
                    if task.isOverdue { line += " – überfällig" }
                }
                line += ")"
                lines.append(line)
            }
        }

        if includeCompleted, !tasks.completed.isEmpty {
            lines.append("Zuletzt erledigt:")
            for task in tasks.completed.prefix(10) {
                let when = task.completedAt.map { Format.relativeDay($0) } ?? "unbekannt"
                lines.append("- \(task.title) (\(when))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Kurzer Lagebericht – geht als Kontext in die Systemanweisung.
    func snapshot() -> String {
        let today = Statistics.dayStats(segments: tracker.segments(on: Date()), rules: rules, day: Date())
        var lines = ["Heute ist \(Format.fullDate.string(from: Date())), es ist \(Format.time.string(from: Date())) Uhr."]
        if today.total > 0 {
            lines.append("Heute wurden bisher \(time(today.total)) erfasst, davon \(time(today.productive)) produktiv. Der Produktivitäts-Score liegt bei \(Int((today.score * 100).rounded())) von 100 Punkten.")
        } else {
            lines.append("Für heute wurde bisher keine Zeit erfasst.")
        }
        lines.append(tasks.open.count == 1 ? "Es ist 1 Aufgabe offen." : "Es sind \(tasks.open.count) Aufgaben offen.")
        lines.append("Aufzeichnungen liegen seit \(historyStart()) vor.")
        return lines.joined(separator: " ")
    }

    private func historyStart() -> String {
        guard let earliest = tracker.segments.map(\.start).min() else { return "heute" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: earliest), to: cal.startOfDay(for: Date())).day ?? 0
        return days <= 0 ? "heute" : "\(days) Tagen"
    }

    /// Namen, die tatsächlich in den Daten vorkommen – hilft bei Tippfehlern.
    private func knownAppsHint() -> String {
        let names = tracker.usage(for: tracker.segments(from: range(days: 30).start, to: Date()), rules: rules)
            .prefix(12).map(\.appName)
        guard !names.isEmpty else { return "Es liegen bisher überhaupt keine Aufzeichnungen vor." }
        return "Aufgezeichnet wurden bisher: \(names.joined(separator: ", "))."
    }
}
