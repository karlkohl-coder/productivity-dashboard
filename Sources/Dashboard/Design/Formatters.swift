import Foundation

enum Format {

    /// Wandelt sicher in eine ganze Zahl. `Int(.nan)` und `Int(.infinity)`
    /// lösen in Swift einen Absturz aus – eine Division durch Null an
    /// irgendeiner Stelle brächte sonst die ganze App zu Fall.
    static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded())
    }

    /// „2 Std 14 Min“ – kompakt und ohne Sekunden, sobald es länger wird.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, whole(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return m > 0 ? "\(h) Std \(m) Min" : "\(h) Std" }
        if m > 0 { return "\(m) Min" }
        return "\(s) Sek"
    }

    /// Kurzform für enge Stellen: „2:14“ bzw. „14 m“.
    static func durationShort(_ seconds: TimeInterval) -> String {
        let total = max(0, whole(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%d:%02d h", h, m) }
        return "\(m) m"
    }

    static func percent(_ value: Double) -> String {
        "\(whole(value * 100))\u{00A0}%"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE"
        return f
    }()

    /// Ausgeschriebener Wochentag. Für die Assistenz wichtig: aus „Mi.“
    /// macht ein Sprachmodell schnell den falschen Tag.
    static let weekdayFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f
    }()

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM"
        return f
    }()

    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM yyyy"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return dayMonth.string(from: date)
    }
}

extension Calendar {
    /// Montag als erster Wochentag – deutschsprachige Konvention.
    static var german: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }
}
