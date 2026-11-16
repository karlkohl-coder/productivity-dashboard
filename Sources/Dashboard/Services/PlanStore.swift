import Foundation
import SwiftUI

/// Hält die Einträge des Wochenplans und rechnet sie auf konkrete Tage um.
@MainActor
final class PlanStore: ObservableObject {

    private static let file = "weekplan.json"

    @Published private(set) var entries: [PlanEntry] = [] {
        didSet { JSONStore.save(entries, to: Self.file) }
    }

    init() {
        entries = JSONStore.load([PlanEntry].self, from: Self.file) ?? []
    }

    // MARK: - Mutationen

    func add(_ entry: PlanEntry) {
        entries.append(entry)
    }

    func update(_ entry: PlanEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
    }

    func delete(_ entry: PlanEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    /// Setzt ein einzelnes Vorkommen aus – der Rest der Reihe bleibt stehen.
    func setSkipped(_ entry: PlanEntry, on day: Date, _ skipped: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let key = DayKey.of(day)
        if skipped {
            entries[idx].skippedDays.insert(key)
        } else {
            entries[idx].skippedDays.remove(key)
        }
    }

    /// Lässt die ganze Reihe ruhen (oder weiterlaufen).
    func setPaused(_ entry: PlanEntry, _ paused: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].isPaused = paused
    }

    // MARK: - Vorkommen

    /// Alle Vorkommen eines Tages, nach Beginn sortiert.
    /// Ausgesetzte Einzeltermine sind enthalten und als solche markiert –
    /// sie bleiben im Raster sichtbar, damit sie sich zurückholen lassen.
    /// Ruhende Reihen erscheinen nicht.
    func occurrences(on day: Date) -> [PlanOccurrence] {
        let cal = Calendar.german
        let dayStart = cal.startOfDay(for: day)
        return entries
            .filter { occurs($0, on: dayStart, calendar: cal) }
            .map { PlanOccurrence(entry: $0, day: dayStart) }
            .sorted { ($0.start, $0.entry.title) < ($1.start, $1.entry.title) }
    }

    /// Die sieben Tage der Woche zu einem Datum, jeweils mit ihren Vorkommen.
    func week(of date: Date) -> [(day: Date, items: [PlanOccurrence])] {
        Self.days(inWeekOf: date).map { ($0, occurrences(on: $0)) }
    }

    /// Reihen, die gerade ruhen – für den Hinweis unter dem Raster.
    var pausedEntries: [PlanEntry] {
        entries.filter { $0.isPaused && $0.rhythm == .weekly }
            .sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
    }

    private func occurs(_ entry: PlanEntry, on dayStart: Date, calendar cal: Calendar) -> Bool {
        switch entry.rhythm {
        case .once:
            guard let date = entry.date else { return false }
            return cal.isDate(date, inSameDayAs: dayStart)

        case .weekly:
            guard !entry.isPaused else { return false }
            guard Weekday(date: dayStart) == entry.weekday else { return false }
            if let from = entry.startsOn, dayStart < cal.startOfDay(for: from) { return false }
            if let to = entry.endsOn, dayStart > cal.startOfDay(for: to) { return false }
            guard entry.interval > 1 else { return true }

            // Bezugswoche für „jede n-te Woche“: der Beginn der Gültigkeit,
            // ersatzweise die Woche, in der der Eintrag angelegt wurde.
            let anchor = Self.startOfWeek(entry.startsOn ?? entry.createdAt)
            let weeks = cal.dateComponents([.weekOfYear],
                                           from: anchor,
                                           to: Self.startOfWeek(dayStart)).weekOfYear ?? 0
            return weeks % entry.interval == 0
        }
    }

    // MARK: - Wochenhilfen

    static func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar.german
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func days(inWeekOf date: Date) -> [Date] {
        let cal = Calendar.german
        let start = startOfWeek(date)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
}
