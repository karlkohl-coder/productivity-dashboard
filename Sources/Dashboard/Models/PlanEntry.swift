import Foundation

/// Wochentag mit Montag = 1.
///
/// Bewusst unabhängig von `Calendar.weekday` (dort ist Sonntag = 1):
/// gespeicherte Einträge sollen nicht davon abhängen, wie der Kalender
/// gerade eingestellt ist.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .monday:    return "Montag"
        case .tuesday:   return "Dienstag"
        case .wednesday: return "Mittwoch"
        case .thursday:  return "Donnerstag"
        case .friday:    return "Freitag"
        case .saturday:  return "Samstag"
        case .sunday:    return "Sonntag"
        }
    }

    var short: String { String(label.prefix(2)) }

    /// Wochentag eines Datums.
    init(date: Date) {
        // Calendar: Sonntag = 1 … Samstag = 7. Umrechnung auf Montag = 1.
        let raw = Calendar.german.component(.weekday, from: date)
        self = Weekday(rawValue: ((raw + 5) % 7) + 1) ?? .monday
    }

    static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

/// Tagesschlüssel „2026-09-21“ – stabil über JSON hinweg. Ein `Set<Date>`
/// wäre hier untauglich: nach dem Laden stimmen die Werte nicht mehr exakt
/// überein, und der Vergleich schlüge fehl.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
}

/// Ein Eintrag im Wochenplan: entweder wöchentlich wiederkehrend
/// (Stundenplan) oder ein einzelner Termin an einem Datum.
///
/// Der Wochenplan liegt bewusst neben dem Systemkalender und nicht darin.
/// Ein Stundenplan gehört nicht in jeden geteilten Kalender, und wiederkehrende
/// EventKit-Serien lassen sich nur umständlich einzeln aussetzen.
struct PlanEntry: Codable, Identifiable, Hashable {

    enum Rhythm: String, Codable, CaseIterable, Identifiable {
        case weekly, once

        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekly: return "Wöchentlich"
            case .once:   return "Einmalig"
            }
        }
    }

    var id = UUID()
    var title: String
    /// Zweite Zeile im Block – Raum, Dozent, Ort.
    var subtitle: String = ""
    var notes: String = ""
    /// Zeigt in `Theme.Palette.series`.
    var colorIndex: Int = 0

    var rhythm: Rhythm = .weekly

    // Wiederkehrend
    var weekday: Weekday = .monday
    /// Jede n-te Woche. 1 = jede Woche.
    var interval: Int = 1
    var startsOn: Date?
    var endsOn: Date?
    /// Die ganze Reihe ruht (Ferien, Kurs pausiert).
    var isPaused: Bool = false
    /// Einzeln ausgesetzte Termine als Tagesschlüssel.
    var skippedDays: Set<String> = []

    // Einmalig
    var date: Date?

    // Uhrzeit als Minuten seit Mitternacht – unabhängig vom Datum.
    var startMinute: Int = 8 * 60
    var endMinute: Int = 9 * 60 + 30

    var createdAt: Date = Date()

    // MARK: - Abgeleitetes

    var color: Int { max(0, colorIndex) }

    var timeText: String {
        "\(Self.clockText(startMinute)) – \(Self.clockText(endMinute))"
    }

    /// Beschreibt die Wiederholung in einem Satzteil.
    var rhythmText: String {
        switch rhythm {
        case .once:
            guard let date else { return "Einmalig" }
            return Format.fullDate.string(from: date)
        case .weekly:
            let base = interval <= 1 ? "Jeden \(weekday.label)" : "Jeden \(interval). \(weekday.label)"
            switch (startsOn, endsOn) {
            case let (s?, e?):
                return "\(base), \(Format.dayMonth.string(from: s)) – \(Format.dayMonth.string(from: e))"
            case let (s?, nil): return "\(base), ab \(Format.dayMonth.string(from: s))"
            case let (nil, e?): return "\(base), bis \(Format.dayMonth.string(from: e))"
            case (nil, nil):    return base
            }
        }
    }

    static func clockText(_ minute: Int) -> String {
        String(format: "%02d:%02d", (minute / 60) % 24, minute % 60)
    }

    /// Uhrzeit an einem konkreten Tag. Über `Calendar` statt über Sekunden
    /// gerechnet, damit die Zeitumstellung den Block nicht verschiebt.
    static func time(_ minute: Int, on day: Date) -> Date {
        let cal = Calendar.german
        let dayStart = cal.startOfDay(for: day)
        guard minute < 24 * 60 else {
            return cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        }
        return cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? dayStart
    }

    func start(on day: Date) -> Date { Self.time(startMinute, on: day) }
    func end(on day: Date) -> Date { Self.time(max(endMinute, startMinute + 5), on: day) }

    func isSkipped(on day: Date) -> Bool { skippedDays.contains(DayKey.of(day)) }
}

/// Ein konkretes Vorkommen eines Eintrags an einem Datum.
struct PlanOccurrence: Identifiable, Hashable {
    let entry: PlanEntry
    /// Tagesbeginn des Vorkommens.
    let day: Date

    var id: String { "\(entry.id.uuidString)@\(DayKey.of(day))" }
    var start: Date { entry.start(on: day) }
    var end: Date { entry.end(on: day) }
    var isSkipped: Bool { entry.isSkipped(on: day) }
}
