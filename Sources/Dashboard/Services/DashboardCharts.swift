import Foundation
import SwiftUI

/// Baut Diagramme aus den Aufzeichnungen.
///
/// Das Sprachmodell wählt nur Art, Zeitraum und Anwendungen; sämtliche Werte
/// stammen aus den Daten. So kann kein erfundener Zahlenwert in ein Diagramm
/// geraten – und keine Anwendung, die es nicht gibt.
@MainActor
struct DashboardCharts {
    let tracker: ActivityTracker
    let rules: CategoryRules
    let tasks: TaskStore
    let calendar: CalendarService
    let log: ChartLog

    private var cal: Calendar { .german }

    // MARK: - Absicht aus der Frage lesen

    /// Erkennt, ob überhaupt ein Diagramm gewünscht ist.
    static func isRequested(in question: String) -> Bool {
        ChartRequest.isChartRequest(question)
    }

    /// Wählt für einen Inhalt eine sinnvolle Form, wenn keine genannt wurde.
    private static func defaultShape(for subject: ChartRequest.Subject) -> ChartRequest.Shape {
        switch subject {
        case .tasks, .events: return .table   // Einträge, keine Größen
        case .score:          return .line
        case .categories:     return .pie
        case .apps:           return .unspecified
        }
    }

    static func inferredDays(from question: String) -> Int {
        ChartRequest.parse(question: question, availableApps: []).days
    }

    // MARK: - Einstieg

    /// Zeichnet, was das Modell zusammenstellt.
    ///
    /// Die Wahl des Modells hat Vorrang – nur so entstehen auch Diagramme
    /// für Wünsche, die niemand vorher bedacht hat. Die Auswertung der Frage
    /// dient als Rückfallebene für alles, was das Modell offenlässt, und als
    /// Korrektiv, wenn die Frage etwas ausdrücklich anders verlangt.
    /// Unverrückbar bleibt nur eines: die Zahlen kommen aus den Daten, und
    /// Anwendungen, die es nicht gibt, werden nicht gezeichnet.
    func make(question: String, form: String, content: String,
              days modelDays: Int, apps modelApps: String, count modelCount: Int) -> String {

        let names = knownAppNames()
        let asked = ChartRequest.parse(question: question, availableApps: names)

        // Geht aus der Frage nicht hervor, wovon die Rede ist, wird nichts
        // gezeichnet. Sonst käme für „Netzdiagramm meiner Schlafqualität“ ein
        // beliebiges Anwendungsdiagramm heraus – nachfragen ist ehrlicher als
        // raten. Anschlussfragen („und jetzt alle als Balken“) sind
        // ausgenommen, sie beziehen sich auf das vorige Diagramm.
        guard ChartRequest.hasKnownSubject(question, availableApps: names)
                || ChartRequest.isRefinement(question)
                || log.lastSummary == nil && question.isEmpty
        else {
            return "Dafür liegen im Dashboard keine Daten vor. Zeichnen kann ich die App-Nutzung, die Einstufung in produktiv, neutral und unproduktiv, den Produktivitäts-Score, die offenen Aufgaben und die anstehenden Termine. Frage den Benutzer, welches davon er sehen möchte."
        }

        // Rangfolge für Form und Inhalt: Was die Frage ausdrücklich nennt,
        // gilt. Sagt sie dazu nichts, entscheidet das Modell – dort liegt die
        // Freiheit für Wünsche, die niemand vorher bedacht hat.
        var shape = ChartRequest.explicitShape(question)
            ?? Self.shape(from: form)
        let subject = ChartRequest.explicitSubject(question, availableApps: names)
            ?? Self.subject(from: content)
            ?? .apps
        if shape == .unspecified { shape = Self.defaultShape(for: subject) }

        let days = (1...90).contains(modelDays) && !questionMentionsPeriod(question)
            ? modelDays : asked.days

        var request = ChartRequest(subject: subject,
                                   shape: shape,
                                   days: days,
                                   namedApps: [],
                                   count: 2,
                                   explicitCount: asked.explicitCount,
                                   mostUsed: true,
                                   allApps: false)

        // Anwendungen: benannte des Modells, gegen die Daten geprüft.
        let fromModel = modelApps
            .components(separatedBy: CharacterSet(charactersIn: ",;/&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let wantsAll = asked.allApps
            || fromModel.contains { ["alle", "all", "alles", "jede", "sämtliche"].contains($0.lowercased()) }

        if wantsAll {
            request.allApps = true
        } else if !asked.namedApps.isEmpty {
            // Namen aus der Frage haben Vorrang – sie sind die Quelle.
            request.namedApps = asked.namedApps
        } else {
            let matched = fromModel.compactMap { candidate in
                names.first { $0.lowercased() == candidate.lowercased() }
                    ?? names.first { $0.lowercased().contains(candidate.lowercased())
                                  || candidate.lowercased().contains($0.lowercased()) }
            }
            let unknown = fromModel.filter { candidate in
                !names.contains { $0.lowercased().contains(candidate.lowercased())
                               || candidate.lowercased().contains($0.lowercased()) }
            }
            if matched.isEmpty && !unknown.isEmpty && !asked.mostUsed {
                return "Zu \(list(unknown.map { "„\($0)“" })) liegen keine Aufzeichnungen vor, deshalb wurde nichts gezeichnet. Aufgezeichnet wurden: \(list(Array(names.prefix(6))))."
            }
            request.namedApps = matched
        }

        // Anzahl: 0 heißt alle. Sonst zählt das Modell, sonst die Frage.
        if modelCount == 0 && !modelApps.isEmpty { request.allApps = true }
        request.count = modelCount > 0
            ? min(modelCount, 12)
            : max(asked.count, request.namedApps.count)

        // Eine ausdrücklich genannte Anzahl gewinnt immer – auch gegen ein
        // „alle“, das aus dem vorigen Zug übrig geblieben ist.
        if let explicit = asked.explicitCount {
            request.explicitCount = explicit
            request.count = explicit
            request.allApps = false
        }

        switch request.subject {
        case .categories: return distribution(request)
        case .score:      return score(request)
        case .tasks:      return taskTable()
        case .events:     return eventTable(request)
        case .apps:       return apps(request)
        }
    }

    private static func shape(from raw: String) -> ChartRequest.Shape {
        let t = raw.lowercased()
        if t.isEmpty { return .unspecified }
        if ["kuchen", "torte", "ring", "pie", "donut", "kreis"].contains(where: { t.contains($0) }) { return .pie }
        if ["balken", "rang", "liste"].contains(where: { t.contains($0) }) { return .bars }
        if ["säulen", "saeulen", "spalten", "vergleich"].contains(where: { t.contains($0) }) { return .columns }
        if ["linie", "kurve", "verlauf"].contains(where: { t.contains($0) }) { return .line }
        return .unspecified
    }

    private static func subject(from raw: String) -> ChartRequest.Subject? {
        let t = raw.lowercased()
        if ["score", "punkte", "punktzahl"].contains(where: { t.contains($0) }) { return .score }
        if ["einstufung", "verteilung", "produktiv", "unproduktiv", "neutral", "kategorie"]
            .contains(where: { t.contains($0) }) { return .categories }
        if ["aufgabe", "todo", "to-do"].contains(where: { t.contains($0) }) { return .tasks }
        if ["termin", "kalender"].contains(where: { t.contains($0) }) { return .events }
        if ["app", "anwendung", "programm"].contains(where: { t.contains($0) }) { return .apps }
        return nil
    }

    private func questionMentionsPeriod(_ question: String) -> Bool {
        let t = question.lowercased()
        return ["heute", "gestern", "woche", "monat", "quartal", "tag"].contains { t.contains($0) }
    }

    // MARK: - Anwendungen

    private func apps(_ request: ChartRequest) -> String {
        let selected = selectApps(request)
        guard !selected.isEmpty else {
            return "Für \(periodLabel(request.days)) liegen keine Aufzeichnungen vor, aus denen sich ein Diagramm bauen ließe."
        }

        switch request.shape {
        case .table:
            return appTable(selected, request: request)
        case .pie:
            return pieOfApps(selected, request: request)
        case .bars:
            return ranking(selected, request: request)
        case .columns, .line, .unspecified:
            // Mehrere Anwendungen über die Zeit gegenüberstellen.
            let spec = request.days == 1
                ? hourlyComparison(selected, asLines: request.shape == .line)
                : dailyComparison(selected, days: request.days, asLines: request.shape == .line)
            log.record(spec)
            return "Das Diagramm stellt \(list(selected.map(\.name))) \(request.days == 1 ? "im heutigen Tagesverlauf" : "über \(periodLabel(request.days))") gegenüber: \(times(selected))."
        }
    }

    /// Kuchendiagramm über die reinen Nutzungszeiten der Anwendungen.
    private func pieOfApps(_ allApps: [ResolvedApp], request: ChartRequest) -> String {
        // Jenseits von acht Segmenten wird der Ring unleserlich; der Rest
        // wandert zusammengefasst in ein Segment „Weitere“.
        var apps = allApps
        var restSeconds: TimeInterval = 0
        if apps.count > 8 {
            restSeconds = apps.dropFirst(7).reduce(0) { $0 + $1.seconds }
            apps = Array(apps.prefix(7))
        }

        var points = apps.enumerated().map { index, app in
            ChartPoint(label: app.name,
                       value: (app.seconds / 60).rounded(),
                       color: color(index))
        }

        // Eine einzelne Anwendung ergäbe einen vollen Ring ohne Aussage.
        // Daneben gehört die übrige erfasste Zeit, dann wird der Anteil lesbar.
        if apps.count == 1, restSeconds == 0 {
            let others = topApps(days: request.days, count: 50)
                .filter { $0.bundleID != apps[0].bundleID }
                .reduce(0) { $0 + $1.seconds }
            if others > 0 {
                points.append(ChartPoint(label: "Übrige Anwendungen",
                                         value: (others / 60).rounded(),
                                         color: Theme.Palette.textTertiary))
            }
        }

        if restSeconds > 0 {
            points.append(ChartPoint(label: "Weitere",
                                     value: (restSeconds / 60).rounded(),
                                     color: Theme.Palette.textTertiary))
        }
        let labels = points.map(\.label)
        log.record(ChartSpec(title: "Nutzungszeit \(periodLabel(request.days))",
                             subtitle: labels.count > 4
                                 ? "\(labels.count) Anwendungen"
                                 : list(labels),
                             style: .donut,
                             unit: "Minuten",
                             series: [ChartSeries(name: "Nutzung", color: color(0), points: points)]))

        let total = allApps.reduce(0) { $0 + $1.seconds }
        let shares = points.map { "\($0.label) \(Int($0.value)) Minuten (\(Int($0.value * 60 / max(total, 1) * 100)) %)" }
        return "Das Kuchendiagramm zeigt die Nutzungszeit \(periodLabel(request.days)) für \(labels.count) Anwendungen: \(shares.joined(separator: ", "))."
    }

    private func ranking(_ apps: [ResolvedApp], request: ChartRequest) -> String {
        let points = apps.enumerated().map {
            ChartPoint(label: $1.name, value: ($1.seconds / 60).rounded(), color: color($0))
        }
        log.record(ChartSpec(title: "Meistgenutzt \(periodLabel(request.days))",
                             subtitle: "nach erfasster Zeit",
                             style: .horizontalBars,
                             unit: "Minuten",
                             series: [ChartSeries(name: "Nutzung", color: Theme.Palette.accent, points: points)]))

        var note = "Die Rangliste zeigt \(apps.count) Anwendungen, vorn \(apps[0].name) mit \(Int((apps[0].seconds / 60).rounded())) Minuten."
        // Sonst erzählt das Modell „Top 5“ nach, obwohl es nur vier gibt.
        if apps.count < request.count {
            note += " Mehr als \(apps.count) Anwendungen mit nennenswerter Zeit gibt es in diesem Zeitraum nicht; sprich deshalb von \(apps.count), nicht von \(request.count)."
        }
        return note
    }

    private func hourlyComparison(_ apps: [ResolvedApp], asLines: Bool) -> ChartSpec {
        let segments = tracker.segments(on: Date())
        let hours = activeHourRange(segments)

        let series = apps.enumerated().map { index, app -> ChartSeries in
            var minutes = [Int: Double]()
            for segment in segments where segment.bundleID == app.bundleID {
                for slice in Statistics.hourSlices(of: segment) {
                    minutes[slice.hour, default: 0] += slice.seconds / 60
                }
            }
            let points = hours.map {
                ChartPoint(label: String(format: "%02d", $0), value: (minutes[$0] ?? 0).rounded())
            }
            return ChartSeries(name: app.name, color: color(index), points: points)
        }

        return ChartSpec(title: "Tagesverlauf heute",
                         subtitle: list(apps.map(\.name)),
                         style: asLines ? .line : .groupedBars,
                         unit: "Minuten",
                         series: series)
    }

    private func dailyComparison(_ apps: [ResolvedApp], days: Int, asLines: Bool) -> ChartSpec {
        let today = cal.startOfDay(for: Date())
        let dayList = (0..<days).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }

        let series = apps.enumerated().map { index, app -> ChartSeries in
            let points = dayList.map { day -> ChartPoint in
                let seconds = tracker.segments(on: day)
                    .filter { $0.bundleID == app.bundleID }
                    .reduce(0) { $0 + $1.duration }
                return ChartPoint(label: shortDay(day), value: (seconds / 60).rounded())
            }
            return ChartSeries(name: app.name, color: color(index), points: points)
        }

        return ChartSpec(title: "Nutzung über \(periodLabel(days))",
                         subtitle: list(apps.map(\.name)),
                         style: asLines ? .line : .groupedBars,
                         unit: "Minuten",
                         series: series)
    }

    // MARK: - Weitere Diagrammarten

    private func ranking(days: Int) -> String {
        let usage = topApps(days: days, count: 8)
        guard !usage.isEmpty else {
            return "Für die letzten \(days) Tage liegen keine Aufzeichnungen vor."
        }
        let points = usage.map { ChartPoint(label: $0.appName, value: ($0.seconds / 60).rounded()) }
        log.record(ChartSpec(title: days == 1 ? "Meistgenutzt heute" : "Meistgenutzt in \(days) Tagen",
                             subtitle: "nach erfasster Zeit",
                             style: .horizontalBars,
                             unit: "Minuten",
                             series: [ChartSeries(name: "Nutzung", color: Theme.Palette.accent, points: points)]))
        return "Die Rangliste zeigt die \(usage.count) meistgenutzten Anwendungen. Vorn liegt \(usage[0].appName) mit \(Int((usage[0].seconds / 60).rounded())) Minuten."
    }

    // MARK: - Tabellen

    /// Aufgaben als Tabelle. Zahlen gibt es hier nicht zu vergleichen,
    /// deshalb ist die Tabelle die einzig sinnvolle Form.
    private func taskTable() -> String {
        let open = tasks.open
        guard !open.isEmpty else {
            return "Es sind derzeit keine Aufgaben offen, deshalb wurde keine Tabelle gezeichnet."
        }

        let rows = open.map { task -> [String] in
            var due = "—"
            if let date = task.dueDate {
                due = Format.relativeDay(date)
                if task.isOverdue { due += " (überfällig)" }
            }
            return [task.title, task.priority.label, due]
        }

        log.record(ChartSpec(title: "Offene Aufgaben",
                             subtitle: "\(open.count) zu erledigen",
                             style: .table,
                             unit: "",
                             series: [],
                             table: .init(columns: ["Aufgabe", "Priorität", "Fällig"], rows: rows)))

        let overdue = open.filter(\.isOverdue).count
        var note = "Die Tabelle listet \(open.count == 1 ? "die eine offene Aufgabe" : "alle \(open.count) offenen Aufgaben")."
        if overdue > 0 { note += " Davon \(overdue) überfällig." }
        return note
    }

    private func eventTable(_ request: ChartRequest) -> String {
        guard calendar.access == .granted else {
            return "Die Termine sind nicht abrufbar, weil das Dashboard keinen Kalenderzugriff hat."
        }
        let start = Date()
        guard let end = cal.date(byAdding: .day, value: request.days, to: cal.startOfDay(for: start)) else {
            return "Der Zeitraum konnte nicht bestimmt werden."
        }
        let events = calendar.fetchEvents(from: start, to: end)
        guard !events.isEmpty else {
            return "In \(periodLabel(request.days)) stehen keine Termine an, deshalb wurde keine Tabelle gezeichnet."
        }

        let rows = events.prefix(30).map { event -> [String] in
            let when = event.isAllDay
                ? "ganztägig"
                : "\(Format.time.string(from: event.startDate))–\(Format.time.string(from: event.endDate))"
            return [event.title ?? "ohne Titel", Format.relativeDay(event.startDate), when]
        }

        log.record(ChartSpec(title: "Anstehende Termine",
                             subtitle: periodLabel(request.days),
                             style: .table,
                             unit: "",
                             series: [],
                             table: .init(columns: ["Termin", "Tag", "Zeit"], rows: rows)))
        return "Die Tabelle listet \(events.count) Termine für \(periodLabel(request.days))."
    }

    private func appTable(_ apps: [ResolvedApp], request: ChartRequest) -> String {
        let total = apps.reduce(0) { $0 + $1.seconds }
        let rows = apps.map { app in
            [app.name,
             "\(Int((app.seconds / 60).rounded())) Min",
             "\(Int(app.seconds / max(total, 1) * 100)) %",
             rules.category(for: app.bundleID).label]
        }
        log.record(ChartSpec(title: "Nutzung \(periodLabel(request.days))",
                             subtitle: "\(apps.count) Anwendungen",
                             style: .table,
                             unit: "",
                             series: [],
                             table: .init(columns: ["Anwendung", "Zeit", "Anteil", "Einstufung"], rows: rows)))
        return "Die Tabelle listet \(apps.count) Anwendungen für \(periodLabel(request.days)), vorn \(apps[0].name) mit \(Int((apps[0].seconds / 60).rounded())) Minuten."
    }

    // MARK: - Einstufung und Score

    private func distribution(_ request: ChartRequest) -> String {
        let stats = Statistics.series(tracker: tracker, rules: rules, days: request.days)
        let totals = ProductivityCategory.allCases.map { cat in
            (cat, stats.reduce(0.0) { $0 + $1.time(for: cat) })
        }
        let sum = totals.reduce(0) { $0 + $1.1 }
        guard sum > 0 else { return "Für \(periodLabel(request.days)) liegen keine Aufzeichnungen vor." }

        let points = totals.map { ChartPoint(label: $0.0.label, value: ($0.1 / 60).rounded(), color: $0.0.color) }
        let style: ChartSpec.Style = request.shape == .table ? .table
            : (request.shape == .bars ? .horizontalBars : .donut)
        log.record(ChartSpec(title: "Einstufung \(periodLabel(request.days))",
                             subtitle: "produktiv, neutral und unproduktiv",
                             style: style,
                             unit: "Minuten",
                             series: [ChartSeries(name: "Anteile", color: Theme.Palette.accent, points: points)],
                             table: style != .table ? nil : .init(
                                columns: ["Einstufung", "Zeit", "Anteil"],
                                rows: totals.map { [$0.0.label, "\(Int($0.1 / 60)) Min", "\(Int($0.1 / sum * 100)) %"] })))

        let share = totals
            .filter { $0.1 > 0 }
            .map { "\($0.0.label) \(Int($0.1 / 60)) Minuten (\(Int($0.1 / sum * 100)) %)" }
            .joined(separator: ", ")
        return "Die Einstufung \(periodLabel(request.days)) verteilt sich auf \(share)."
    }

    private func score(_ request: ChartRequest) -> String {
        let stats = Statistics.series(tracker: tracker, rules: rules, days: request.days).filter { $0.total > 0 }
        guard !stats.isEmpty else { return "Für \(periodLabel(request.days)) liegen keine Aufzeichnungen vor." }

        let points = stats.map { ChartPoint(label: shortDay($0.day), value: ($0.score * 100).rounded()) }
        // Waagerechte Balken taugen nicht für eine Zeitachse – „Balken“
        // meint hier Säulen.
        let style: ChartSpec.Style = request.shape == .table ? .table
            : (request.shape == .bars ? .groupedBars : .line)
        log.record(ChartSpec(title: "Produktivitäts-Score",
                             subtitle: "\(periodLabel(request.days)), 0 bis 100 Punkte",
                             style: style,
                             unit: "Punkte",
                             series: [ChartSeries(name: "Score", color: Theme.Palette.accent, points: points)],
                             table: style != .table ? nil : .init(
                                columns: ["Tag", "Punkte"],
                                rows: points.map { [$0.label, "\(Int($0.value))"] })))

        let average = Int((stats.reduce(0) { $0 + $1.score } / Double(stats.count) * 100).rounded())
        return "Der Score-Verlauf umfasst \(stats.count == 1 ? "einen Tag" : "\(stats.count) Tage") mit Aufzeichnung, im Durchschnitt \(average) von 100 Punkten."
    }

    // MARK: - Anwendungen auswählen

    struct ResolvedApp {
        let bundleID: String
        let name: String
        let seconds: TimeInterval
    }

    /// Namentlich Genanntes hat Vorrang; sonst entscheidet die Rangliste.
    /// Erfundene Namen kommen hier nicht mehr an – sie werden schon beim
    /// Auswerten der Frage gegen die vorhandenen Anwendungen geprüft.
    private func selectApps(_ request: ChartRequest) -> [ResolvedApp] {
        let available = topApps(days: request.days, count: 50)
        let resolve = { (u: AppUsage) in ResolvedApp(bundleID: u.bundleID, name: u.appName, seconds: u.seconds) }

        if request.allApps { return available.map(resolve) }

        var chosen: [ResolvedApp] = []
        for name in request.namedApps {
            if let hit = available.first(where: { $0.appName == name }),
               !chosen.contains(where: { $0.bundleID == hit.bundleID }) {
                chosen.append(resolve(hit))
            }
        }
        for app in available {
            guard chosen.count < request.count else { break }
            guard !chosen.contains(where: { $0.bundleID == app.bundleID }) else { continue }
            chosen.append(resolve(app))
        }
        return chosen
    }

    /// Für die Prüfung von außen, ob eine Frage überhaupt zeichenbar ist.
    func appNames() -> [String] { knownAppNames() }

    private func knownAppNames() -> [String] {
        var names = Set<String>()
        for seg in tracker.segments { names.insert(seg.appName) }
        for app in tracker.runningApps { if let n = app.localizedName { names.insert(n) } }
        // Längere Namen zuerst, damit „Google Chrome“ vor „Chrome“ greift.
        return names.sorted { $0.count > $1.count }
    }

    private func topApps(days: Int, count: Int) -> [AppUsage] {
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let segments = tracker.segments(from: start, to: Date())
        return Array(tracker.usage(for: segments, rules: rules)
            .filter { $0.seconds >= 30 }
            .prefix(count))
    }

    // MARK: - Kleinkram

    /// Nur Stunden zeigen, in denen überhaupt etwas passiert ist – sonst
    /// besteht das Diagramm aus zwanzig leeren Säulen.
    private func activeHourRange(_ segments: [ActivitySegment]) -> [Int] {
        let hours = segments.flatMap { Statistics.hourSlices(of: $0) }.map(\.hour)
        guard let first = hours.min(), let last = hours.max() else { return Array(8...18) }
        return Array(max(0, first - 1)...min(23, last + 1))
    }

    private func shortDay(_ date: Date) -> String {
        cal.isDateInToday(date) ? "heute" : Format.weekday.string(from: date) + " " + Format.dayMonth.string(from: date)
    }

    private func color(_ index: Int) -> Color {
        Theme.Palette.series[index % Theme.Palette.series.count]
    }

    /// „heute“, „gestern und heute“, „die letzten 7 Tage“ – nie „1 Tage“.
    private func periodLabel(_ days: Int) -> String {
        switch days {
        case 1:  return "heute"
        case 2:  return "gestern und heute"
        default: return "die letzten \(days) Tage"
        }
    }

    private func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " und " + names[names.count - 1]
    }

    private func times(_ apps: [ResolvedApp]) -> String {
        apps.map { "\($0.name) \(Int(($0.seconds / 60).rounded())) Minuten" }.joined(separator: ", ")
    }
}
