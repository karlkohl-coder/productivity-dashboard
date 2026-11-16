import AppKit
import Combine
import SwiftUI

/// Zeichnet auf, welche Anwendung im Vordergrund ist, und schneidet daraus
/// zusammenhängende Segmente. Bei Inaktivität (keine Maus-/Tastatureingabe)
/// wird die Aufzeichnung pausiert, damit Leerlauf nicht als Arbeitszeit zählt.
///
/// Es werden ausschließlich App-Name und Bundle-ID erfasst – keine
/// Fenstertitel, keine Inhalte. Dafür sind keine Sonderrechte nötig.
@MainActor
final class ActivityTracker: ObservableObject {

    private static let file = "activity.json"

    // MARK: - Veröffentlichter Zustand

    @Published private(set) var segments: [ActivitySegment] = [] {
        didSet {
            dayIndex = nil
            revision &+= 1
        }
    }

    /// Zählt jede Änderung an den Segmenten. Zwischenspeicher erkennen daran,
    /// ob ihr Ergebnis noch gilt. Bewusst nicht `@Published` – `segments`
    /// meldet sich bereits, ein zweites Signal wäre nur zusätzliche Arbeit.
    private(set) var revision = 0

    /// Segmente nach Tagesbeginn vorsortiert, träge aufgebaut.
    ///
    /// Ohne diesen Index filtert `segments(on:)` bei jedem Aufruf die ganze
    /// Historie – und die Statistik ruft ihn einmal pro Tag im Zeitraum auf.
    /// Bei 90 Tagen ist das die Historie 90-mal, jedes Mal mit teurer
    /// Kalenderrechnung je Segment.
    private var dayIndex: [Date: [ActivitySegment]]?
    @Published private(set) var currentApp: (name: String, bundleID: String)?
    @Published private(set) var currentSince: Date?
    @Published private(set) var isIdle = false
    @Published private(set) var runningApps: [NSRunningApplication] = []

    @Published var isTracking = true {
        didSet {
            UserDefaults.standard.set(isTracking, forKey: "tracking.enabled")
            if isTracking { start() } else { stop() }
        }
    }

    /// Ab wie vielen Sekunden ohne Eingabe gilt die Sitzung als Leerlauf.
    @Published var idleThreshold: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(idleThreshold, forKey: "tracking.idleThreshold") }
    }

    /// Segmente, die kürzer sind, werden verworfen (Fensterwechsel-Rauschen).
    private let minimumSegmentDuration: TimeInterval = 3
    /// Wie viele Tage Historie behalten werden.
    private let retentionDays = 120
    private let tickInterval: TimeInterval = 2

    /// Systemprozesse, die zwar im Vordergrund erscheinen können, aber keine
    /// Anwendung im Sinne der Auswertung sind. Sie tauchten sonst als
    /// eigenständige Einträge in Diagrammen auf.
    static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.ScreenSaver.Engine",
        "com.apple.screencaptureui"
    ]

    private var timer: Timer?
    private var openStart: Date?
    private var openApp: (name: String, bundleID: String)?
    private var lastPersist = Date.distantPast

    /// Bundle-IDs der zuletzt gemeldeten laufenden Apps. Dient nur dem
    /// Vergleich – ohne ihn meldete der Tracker alle zwei Sekunden eine
    /// Änderung, auch wenn sich nichts geändert hat.
    private var lastRunningIDs: [String] = []

    /// Zeitpunkt des letzten Ticks. Alles, was danach liegt, ist unbelegt –
    /// der Timer könnte stillgestanden haben.
    private var lastTick = Date()

    /// Ab dieser Lücke zwischen zwei Ticks gilt die Zwischenzeit als nicht
    /// erfasst: der Timer stand still – Ruhezustand, geschlossener Deckel
    /// oder eine vom System ausgelagerte App.
    ///
    /// Vier ausgefallene Ticks. Kürzer wäre heikel, weil ein ausgelasteter
    /// Rechner den Timer auch einmal verzögert und Segmente dann unnötig
    /// zerfielen; länger schriebe mehr Phantomzeit gut. So bleibt der Fehler
    /// je Ruhepause auf wenige Sekunden begrenzt, gleich wie lange sie war.
    private var maxTickGap: TimeInterval { tickInterval * 4 }

    // MARK: - Lebenszyklus

    init() {
        if let stored = JSONStore.load([ActivitySegment].self, from: Self.file) {
            segments = stored
        }
        if UserDefaults.standard.object(forKey: "tracking.enabled") != nil {
            isTracking = UserDefaults.standard.bool(forKey: "tracking.enabled")
        }
        if let t = UserDefaults.standard.object(forKey: "tracking.idleThreshold") as? Double {
            idleThreshold = t
        }
        prune()
        refreshRunningApps()
        observeSystemEvents()
        if isTracking { start() }
    }

    /// Ruhezustand, Bildschirmsperre und Benutzerwechsel melden sich beim
    /// System an. Das ist genauer als die Lückenerkennung, weil der Zeitpunkt
    /// bekannt ist, statt erst beim Aufwachen bemerkt zu werden.
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pausiert: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        let fortgesetzt: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        for name in pausiert {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            }
        }
        for name in fortgesetzt {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            }
        }

        // Beim Beenden das laufende Segment sichern – sonst geht die Zeit
        // seit der letzten Sicherung verloren.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeOpenSegment()
                self?.save()
            }
        }
    }

    /// Der Rechner geht schlafen oder der Bildschirm wird gesperrt: das
    /// laufende Segment endet hier und jetzt.
    private func suspend() {
        closeOpenSegment()
        setCurrent(nil, since: nil)
        save()
    }

    /// Zurück aus dem Ruhezustand. Der letzte Tick wird auf jetzt gesetzt,
    /// damit die Lückenerkennung nicht noch einmal dasselbe behandelt.
    private func resume() {
        lastTick = Date()
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closeOpenSegment()
        setCurrent(nil, since: nil)
        save()
    }

    // MARK: - Aufzeichnung

    private func tick() {
        let now = Date()
        // Stand der Timer still, ist die Zwischenzeit keine Nutzung. Ohne
        // diese Prüfung wüchse das offene Segment über den gesamten
        // Ruhezustand weiter und schriebe der zuletzt aktiven App Stunden gut.
        if now.timeIntervalSince(lastTick) > maxTickGap {
            closeOpenSegment(until: lastTick)
            save()
        }
        lastTick = now

        refreshRunningApps()

        let idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
        let idleNow = idleSeconds >= idleThreshold
        if idleNow != isIdle { isIdle = idleNow }

        guard !idleNow else {
            closeOpenSegment()
            setCurrent(nil, since: nil)
            return
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              !Self.ignoredBundleIDs.contains(bundleID) else { return }
        let name = front.localizedName ?? bundleID

        if openApp?.bundleID != bundleID {
            closeOpenSegment()
            openApp = (name, bundleID)
            openStart = now
        }

        setCurrent(openApp, since: openStart)

        // Regelmäßig sichern, damit ein Absturz höchstens eine Minute kostet.
        if now.timeIntervalSince(lastPersist) > 60 {
            flushOpenSegment()
            save()
        }
    }

    /// Schreibt das laufende Segment bis `end` fort, ohne es zu beenden.
    private func flushOpenSegment(until end: Date = Date()) {
        guard let app = openApp, let start = openStart else { return }
        guard end.timeIntervalSince(start) >= minimumSegmentDuration else { return }
        if let last = segments.last, last.bundleID == app.bundleID, last.start == start {
            segments[segments.count - 1].end = max(segments[segments.count - 1].end, end)
        } else {
            segments.append(ActivitySegment(bundleID: app.bundleID, appName: app.name, start: start, end: end))
        }
        lastPersist = Date()
    }

    private func closeOpenSegment(until end: Date = Date()) {
        flushOpenSegment(until: end)
        openApp = nil
        openStart = nil
    }

    private func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return !Self.ignoredBundleIDs.contains(id)
            }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }

        // `@Published` meldet jede Zuweisung, auch eine unveränderte. Da der
        // Tick alle zwei Sekunden läuft, rechneten Übersicht und Statistik
        // sonst dauerhaft im Leerlauf neu – und das wird mit wachsender
        // Historie teurer.
        let ids = apps.compactMap(\.bundleIdentifier)
        guard ids != lastRunningIDs else { return }
        lastRunningIDs = ids
        runningApps = apps
    }

    /// Meldet die laufende Sitzung – aber nur, wenn sie sich geändert hat.
    /// Die mitlaufende Dauer zeichnen die Ansichten mit eigener Uhr; die
    /// Übersicht zeigt Minuten und kommt mit dem 60-Sekunden-Takt aus.
    private func setCurrent(_ app: (name: String, bundleID: String)?, since: Date?) {
        if currentApp?.bundleID != app?.bundleID || currentApp?.name != app?.name {
            currentApp = app
        }
        if currentSince != since { currentSince = since }
    }

    // MARK: - Abfragen

    private func indexedByDay() -> [Date: [ActivitySegment]] {
        if let dayIndex { return dayIndex }
        let cal = Calendar.current
        var built: [Date: [ActivitySegment]] = [:]
        // Der Filter gilt auch rückwirkend, damit früher aufgezeichnete
        // Systemprozesse nicht in Auswertungen auftauchen.
        for seg in segments where !Self.ignoredBundleIDs.contains(seg.bundleID) {
            built[cal.startOfDay(for: seg.start), default: []].append(seg)
        }
        dayIndex = built
        return built
    }

    /// Alle Segmente eines Tages, inkl. des noch laufenden.
    func segments(on day: Date) -> [ActivitySegment] {
        let cal = Calendar.current
        var result = indexedByDay()[cal.startOfDay(for: day)] ?? []
        if cal.isDateInToday(day), let app = openApp, let start = openStart {
            // Auch die Anzeige darf nicht über den letzten Tick hinausrechnen:
            // sonst zeigt sie nach dem Aufwachen kurz die ganze Schlafenszeit.
            let liveEnd = min(Date(), lastTick.addingTimeInterval(maxTickGap))
            let live = ActivitySegment(bundleID: app.bundleID, appName: app.name, start: start, end: liveEnd)
            if let idx = result.firstIndex(where: { $0.start == start && $0.bundleID == app.bundleID }) {
                result[idx] = live
            } else if live.duration >= 1 {
                result.append(live)
            }
        }
        return result
    }

    func segments(from: Date, to: Date) -> [ActivitySegment] {
        let cal = Calendar.current
        var day = cal.startOfDay(for: from)
        var result: [ActivitySegment] = []
        while day <= to {
            result += segments(on: day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Aggregiert Segmente zu App-Nutzung, absteigend nach Dauer.
    func usage(for segments: [ActivitySegment], rules: CategoryRules) -> [AppUsage] {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for seg in segments {
            let entry = totals[seg.bundleID] ?? (seg.appName, 0)
            totals[seg.bundleID] = (entry.name, entry.seconds + seg.duration)
        }
        return totals
            .map { AppUsage(bundleID: $0.key, appName: $0.value.name, seconds: $0.value.seconds,
                            category: rules.category(for: $0.key)) }
            .sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Verwaltung

    func clearHistory() {
        segments.removeAll()
        closeOpenSegment()
        save()
    }

    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        segments.removeAll { $0.end < cutoff }
    }

    func save() {
        JSONStore.save(segments, to: Self.file)
    }
}
