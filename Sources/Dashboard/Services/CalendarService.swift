import AppKit
import EventKit
import SwiftUI

/// Liest Termine aus den macOS-Systemkalendern (EventKit).
/// Der Zugriff ist reines Lesen; die Berechtigung wird beim ersten Öffnen
/// des Kalenderbereichs angefragt.
@MainActor
final class CalendarService: ObservableObject {

    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var calendars: [EKCalendar] = []

    private let store = EKEventStore()

    /// Termine müssen aus demselben Store stammen, in den sie gesichert werden.
    var eventStore: EKEventStore { store }
    private var loadedRange: (start: Date, end: Date)?

    init() {
        refreshAccess()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        // Die Berechtigung lässt sich auch außerhalb der App ändern – und
        // nach einer Ablehnung geht es *nur* noch über die Systemeinstellungen,
        // weil macOS den Dialog kein zweites Mal zeigt. Ohne diese Prüfung
        // bliebe die App auf „abgelehnt“ stehen, bis sie neu gestartet wird.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAccess() }
        }
    }

    /// Liest den Berechtigungsstand beim System nach und lädt nach, falls
    /// er sich zum Besseren gewendet hat.
    func refreshAccess() {
        let previous = access
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            access = .unknown
        default:
            // `writeOnly` zählt hier zu „abgelehnt“: das Dashboard muss lesen.
            access = .denied
        }
        if access == .granted, previous != .granted {
            calendars = store.calendars(for: .event)
            reload()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                // Nicht blind auf `granted` verlassen: hat der Benutzer den
                // Dialog schon einmal abgelehnt, erscheint er nicht erneut und
                // `granted` ist false, obwohl in den Systemeinstellungen
                // inzwischen etwas anderes stehen kann.
                self.refreshAccess()
                if granted, self.access != .granted { self.access = .granted }
                if self.access == .granted { self.reload() }
            }
        }
    }

    /// Lädt Termine für einen Zeitraum. Mehrfachaufrufe sind unkritisch.
    func load(from start: Date, to end: Date) {
        loadedRange = (start, end)
        guard access == .granted else { return }
        calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func reload() {
        guard let r = loadedRange else { return }
        load(from: r.start, to: r.end)
    }

    /// Direkte Abfrage am Store, ohne den veröffentlichten Zustand zu ändern.
    /// Wird von der Assistenz für beliebige Zeiträume genutzt.
    func fetchEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on day: Date) -> [EKEvent] {
        let cal = Calendar.current
        return events.filter { ev in
            guard let s = ev.startDate, let e = ev.endDate else { return false }
            let dayStart = cal.startOfDay(for: day)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
            return s < dayEnd && e > dayStart
        }
    }

    // MARK: - Schreiben

    /// Kalender, in die geschrieben werden darf.
    var writableCalendars: [EKCalendar] {
        calendars.filter { $0.allowsContentModifications }
    }

    var defaultCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents ?? writableCalendars.first
    }

    /// Neuer, noch nicht gesicherter Termin – muss aus diesem Store stammen.
    func makeDraft(on day: Date) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = defaultCalendar
        let cal = Calendar.german
        // Vorbelegung: nächste volle Stunde, eine Stunde lang.
        let now = Date()
        let hour = cal.isDateInToday(day) ? cal.component(.hour, from: now) + 1 : 9
        let start = cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: day) ?? day
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        return event
    }

    func save(_ event: EKEvent) throws {
        try store.save(event, span: .thisEvent, commit: true)
        reload()
    }

    func delete(_ event: EKEvent) throws {
        try store.remove(event, span: .thisEvent, commit: true)
        reload()
    }

    /// Öffnet die Systemeinstellungen, falls der Zugriff abgelehnt wurde.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
