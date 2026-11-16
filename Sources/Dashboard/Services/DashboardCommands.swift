import EventKit
import Foundation

/// Schreibender Gegenpart zu `DashboardQuery`: legt Aufgaben und Termine an,
/// hakt ab, löscht und ändert Einstufungen.
///
/// Jede Methode gibt einen Satz zurück, den das Modell wörtlich weitergeben
/// kann, und trägt die Änderung ins `ActionLog` ein. Was nicht eindeutig ist,
/// wird nicht geraten, sondern zurückgefragt.
@MainActor
struct DashboardCommands {
    let tasks: TaskStore
    let calendar: CalendarService
    let rules: CategoryRules
    let tracker: ActivityTracker
    let log: ActionLog

    private var cal: Calendar { .german }

    // MARK: - Aufgaben

    func addTask(title: String, priority: String, due: String) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Es wurde kein Titel für die Aufgabe genannt." }

        let dueDate = Self.parseDate(due)
        guard let task = tasks.add(title: clean,
                                   priority: Self.parsePriority(priority),
                                   dueDate: dueDate) else {
            return "Die Aufgabe konnte nicht angelegt werden."
        }

        log.record(.created, "Aufgabe angelegt: \(task.title)") {
            tasks.delete(task)
        }

        var answer = "Erledigt: Die Aufgabe „\(task.title)“ wurde angelegt"
        if task.priority != .normal { answer += ", Priorität \(task.priority.label)" }
        if let dueDate { answer += ", fällig am \(Format.fullDate.string(from: dueDate))" }
        return answer + ". Sie steht ab sofort im Bereich Aufgaben."
    }

    func completeTask(title: String) -> String {
        switch find(title, in: tasks.open) {
        case .none:
            return "Es gibt keine offene Aufgabe, die zu „\(title)“ passt. \(openTasksHint())"
        case .ambiguous(let matches):
            return "Mehrere offene Aufgaben passen zu „\(title)“: \(matches.map(\.title).joined(separator: ", ")). Welche ist gemeint?"
        case .one(let task):
            tasks.setDone(task, true)
            log.record(.changed, "Aufgabe abgehakt: \(task.title)") {
                tasks.setDone(task, false)
            }
            return "Erledigt: Die Aufgabe „\(task.title)“ ist jetzt als erledigt markiert."
        }
    }

    func deleteTask(title: String) -> String {
        switch find(title, in: tasks.tasks) {
        case .none:
            return "Es gibt keine Aufgabe, die zu „\(title)“ passt. \(openTasksHint())"
        case .ambiguous(let matches):
            return "Mehrere Aufgaben passen zu „\(title)“: \(matches.map(\.title).joined(separator: ", ")). Welche soll gelöscht werden?"
        case .one(let task):
            tasks.delete(task)
            log.record(.deleted, "Aufgabe gelöscht: \(task.title)") {
                tasks.reinsert(task)
            }
            return "Erledigt: Die Aufgabe „\(task.title)“ wurde gelöscht."
        }
    }

    // MARK: - Termine

    func addEvent(title: String, date: String, time: String, durationMinutes: Int, allDay: Bool) -> String {
        guard calendar.access == .granted else {
            return "Der Termin konnte nicht angelegt werden, weil das Dashboard keinen Kalenderzugriff hat. Der Benutzer kann ihn im Bereich Kalender erteilen."
        }
        guard let target = calendar.defaultCalendar else {
            return "Es steht kein beschreibbarer Kalender zur Verfügung."
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Es wurde kein Titel für den Termin genannt." }
        guard let day = Self.parseDate(date) else {
            return "Das Datum „\(date)“ war nicht eindeutig. Bitte nenne es als Tagesdatum, zum Beispiel 2026-09-15, oder als „heute“ beziehungsweise „morgen“."
        }

        let event = EKEvent(eventStore: calendar.eventStore)
        event.title = clean
        event.calendar = target
        event.isAllDay = allDay

        if allDay {
            event.startDate = cal.startOfDay(for: day)
            event.endDate = cal.startOfDay(for: day)
        } else {
            let clock = Self.parseTime(time) ?? (hour: 9, minute: 0)
            let start = cal.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day) ?? day
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(max(durationMinutes, 5) * 60))
        }

        do {
            try calendar.save(event)
        } catch {
            return "Der Termin konnte nicht gesichert werden: \(error.localizedDescription)"
        }

        log.record(.created, "Termin angelegt: \(clean), \(Format.dayMonth.string(from: event.startDate))") {
            try? calendar.delete(event)
        }

        let when = allDay
            ? "ganztägig am \(Format.fullDate.string(from: event.startDate))"
            : "am \(Format.fullDate.string(from: event.startDate)) um \(Format.time.string(from: event.startDate)) Uhr für \(durationMinutes) Minuten"
        return "Erledigt: Der Termin „\(clean)“ wurde \(when) im Kalender „\(target.title)“ eingetragen."
    }

    func deleteEvent(title: String, date: String) -> String {
        guard calendar.access == .granted else {
            return "Termine können nicht gelöscht werden, weil das Dashboard keinen Kalenderzugriff hat."
        }
        // Suchfenster: ein Monat zurück, ein Jahr voraus – oder der genannte Tag.
        let (from, to): (Date, Date)
        if let day = Self.parseDate(date) {
            from = cal.startOfDay(for: day)
            to = cal.date(byAdding: .day, value: 1, to: from) ?? from
        } else {
            from = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            to = cal.date(byAdding: .day, value: 365, to: Date()) ?? Date()
        }

        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = calendar.fetchEvents(from: from, to: to).filter {
            guard let t = $0.title?.lowercased() else { return false }
            return needle.isEmpty || t.contains(needle) || needle.contains(t)
        }

        guard !matches.isEmpty else {
            return "Es wurde kein Termin gefunden, der zu „\(title)“ passt."
        }
        guard matches.count == 1, let event = matches.first else {
            let list = matches.prefix(6).map { "\($0.title ?? "ohne Titel") am \(Format.dayMonth.string(from: $0.startDate))" }
            return "Mehrere Termine passen zu „\(title)“: \(list.joined(separator: ", ")). Welcher soll gelöscht werden?"
        }
        guard event.calendar.allowsContentModifications else {
            return "Der Termin „\(event.title ?? "")“ liegt in einem Kalender, der nicht verändert werden darf."
        }

        let snapshot = EventSnapshot(event: event)
        let label = "\(event.title ?? "ohne Titel") am \(Format.dayMonth.string(from: event.startDate))"
        do {
            try calendar.delete(event)
        } catch {
            return "Der Termin konnte nicht gelöscht werden: \(error.localizedDescription)"
        }

        log.record(.deleted, "Termin gelöscht: \(label)") {
            let restored = snapshot.makeEvent(in: calendar.eventStore)
            try? calendar.save(restored)
        }
        return "Erledigt: Der Termin „\(label)“ wurde gelöscht."
    }

    // MARK: - Einstufung

    func setCategory(app: String, category: String) -> String {
        guard let target = Self.parseCategory(category) else {
            return "„\(category)“ ist keine gültige Einstufung. Möglich sind produktiv, neutral und unproduktiv."
        }
        var candidates: [String: String] = [:]
        for seg in tracker.segments { candidates[seg.bundleID] = seg.appName }
        for running in tracker.runningApps where running.bundleIdentifier != nil {
            candidates[running.bundleIdentifier!] = running.localizedName ?? running.bundleIdentifier!
        }
        let needle = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let hit = candidates.first(where: { $0.value.lowercased() == needle })
            ?? candidates.first(where: { $0.value.lowercased().contains(needle) })
        else {
            return "Zu „\(app)“ ist keine Anwendung bekannt."
        }

        let previous = rules.choice(for: hit.key)
        rules.apply(.fixed(target), to: hit.key)
        log.record(.changed, "\(hit.value) als \(target.label) eingestuft") {
            rules.apply(previous, to: hit.key)
        }
        return "Erledigt: \(hit.value) gilt ab sofort als \(target.label). Das überschreibt die automatische Einstufung."
    }

    // MARK: - Auswertung von Freitext

    private enum Match<T> { case none, one(T), ambiguous([T]) }

    private func find(_ title: String, in list: [TaskItem]) -> Match<TaskItem> {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return .none }
        if let exact = list.first(where: { $0.title.lowercased() == needle }) { return .one(exact) }
        let partial = list.filter {
            $0.title.lowercased().contains(needle) || needle.contains($0.title.lowercased())
        }
        switch partial.count {
        case 0:  return .none
        case 1:  return .one(partial[0])
        default: return .ambiguous(partial)
        }
    }

    private func openTasksHint() -> String {
        let titles = tasks.open.prefix(8).map(\.title)
        return titles.isEmpty ? "Es sind keine Aufgaben offen." : "Offen sind: \(titles.joined(separator: ", "))."
    }

    static func parsePriority(_ raw: String) -> TaskPriority {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "hoch", "high", "wichtig", "dringend": return .high
        case "niedrig", "low", "gering":            return .low
        default:                                    return .normal
        }
    }

    static func parseCategory(_ raw: String) -> ProductivityCategory? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "produktiv", "productive":       return .productive
        case "neutral":                       return .neutral
        case "unproduktiv", "unproductive":   return .unproductive
        default:                              return nil
        }
    }

    /// Nimmt „heute“, „morgen“, Wochentage und Datumsangaben entgegen.
    static func parseDate(_ raw: String) -> Date? {
        let cal = Calendar.german
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text != "keine", text != "kein datum" else { return nil }

        let today = cal.startOfDay(for: Date())
        switch text {
        case "heute":      return today
        case "morgen":     return cal.date(byAdding: .day, value: 1, to: today)
        case "übermorgen": return cal.date(byAdding: .day, value: 2, to: today)
        case "gestern":    return cal.date(byAdding: .day, value: -1, to: today)
        default: break
        }

        // Nächster genannter Wochentag.
        let weekdays = ["montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5,
                        "freitag": 6, "samstag": 7, "sonntag": 1]
        if let target = weekdays.first(where: { text.contains($0.key) })?.value {
            for offset in 1...7 {
                if let day = cal.date(byAdding: .day, value: offset, to: today),
                   cal.component(.weekday, from: day) == target {
                    return day
                }
            }
        }

        for format in ["yyyy-MM-dd", "dd.MM.yyyy", "d.M.yyyy", "dd.MM.", "d.M.", "dd.MM", "d.M"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.calendar = cal
            f.dateFormat = format
            if let date = f.date(from: text) {
                // Formate ohne Jahr landen im Jahr 2000 – auf dieses Jahr heben.
                if !format.contains("yyyy") {
                    var parts = cal.dateComponents([.day, .month], from: date)
                    parts.year = cal.component(.year, from: today)
                    if let lifted = cal.date(from: parts) {
                        return lifted < today
                            ? cal.date(byAdding: .year, value: 1, to: lifted)
                            : lifted
                    }
                }
                return cal.startOfDay(for: date)
            }
        }
        return nil
    }

    /// „14:30“, „14.30“, „14 Uhr“, „1430“.
    static func parseTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let text = raw.lowercased().replacingOccurrences(of: "uhr", with: "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "." })
        if parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        if let h = Int(text), (0...23).contains(h) { return (h, 0) }
        return nil
    }
}

/// Kopie eines Termins, um ihn nach dem Löschen wiederherstellen zu können.
private struct EventSnapshot {
    let title: String?
    let notes: String?
    let location: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendar: EKCalendar?

    init(event: EKEvent) {
        title = event.title
        notes = event.notes
        location = event.location
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        calendar = event.calendar
    }

    func makeEvent(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.location = location
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.calendar = calendar ?? store.defaultCalendarForNewEvents
        return event
    }
}
