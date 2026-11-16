import Combine
import EventKit
import SwiftUI

/// Wochenplan: ein Stundenplanraster aus eigenen Einträgen – wiederkehrend
/// oder einmalig – und den Terminen der Systemkalender daneben.
struct WeekPlanView: View {
    @EnvironmentObject private var plan: PlanStore
    @EnvironmentObject private var service: CalendarService

    @State private var weekStart = PlanStore.startOfWeek(Date())
    @State private var events: [EKEvent] = []
    @State private var now = Date()
    @State private var editorTarget: PlanEditorTarget?
    @State private var eventTarget: EventEditorTarget?

    /// Höhe einer Stunde im Raster.
    private let hourHeight: CGFloat = 46
    private let gutter: CGFloat = 46

    private var pointsPerMinute: CGFloat { hourHeight / 60 }
    private var days: [Date] { PlanStore.days(inWeekOf: weekStart) }

    private let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Page(title: "Wochenplan", subtitle: weekSubtitle) {
            Card {
                VStack(spacing: 0) {
                    headerRow
                    if !allDayItems.isEmpty { allDayRow }
                    Divider().padding(.bottom, Theme.Spacing.xs)
                    grid
                }
            }

            if plan.entries.isEmpty {
                Card {
                    EmptyStateView(symbol: "calendar.day.timeline.left",
                                   message: "Noch keine Einträge.\nEin Klick ins Raster legt einen an – wöchentlich wiederkehrend für den Stundenplan oder einmalig.",
                                   actionTitle: "Eintrag anlegen",
                                   action: { newEntry(on: days.first ?? Date(), minute: 9 * 60) })
                }
            }

            if !plan.pausedEntries.isEmpty { pausedCard }
            if service.access != .granted { calendarHintCard }
        }
        actions: {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Vorige Woche")
                    Button("Heute") { weekStart = PlanStore.startOfWeek(Date()) }
                    Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                        .help("Nächste Woche")
                }
                Button {
                    newEntry(on: days.first ?? Date(), minute: 9 * 60)
                } label: {
                    Label("Eintrag", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("Neuen Eintrag anlegen (⌘N)")
            }
            .controlSize(.small)
        }
        .onAppear(perform: loadEvents)
        .onChange(of: weekStart) { _, _ in loadEvents() }
        .onReceive(minute) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in loadEvents() }
        .background {
            Button("") { newEntry(on: days.first ?? Date(), minute: 9 * 60) }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .sheet(item: $editorTarget) { target in
            PlanEntryEditor(target: target) { editorTarget = nil }
                .environmentObject(plan)
        }
        .sheet(item: $eventTarget) { target in
            EventEditor(target: target) {
                eventTarget = nil
                loadEvents()
            }
            .environmentObject(service)
        }
    }

    private var weekSubtitle: String {
        let cal = Calendar.german
        let week = cal.component(.weekOfYear, from: weekStart)
        let last = days.last ?? weekStart
        return "KW \(week) · \(Format.dayMonth.string(from: weekStart)) – \(Format.dayMonth.string(from: last))"
    }

    private func shiftWeek(_ delta: Int) {
        if let next = Calendar.german.date(byAdding: .weekOfYear, value: delta, to: weekStart) {
            weekStart = next
        }
    }

    // MARK: - Kopfzeile

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let today = Calendar.german.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(Weekday(date: day).short)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text("\(Calendar.german.component(.day, from: day))")
                        .font(.system(size: 14, weight: today ? .semibold : .regular))
                        .foregroundStyle(today ? Theme.Palette.accent : Theme.Palette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xs)
                .background(today ? Theme.Palette.accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
        }
    }

    /// Ganztägige Kalendertermine stehen über dem Raster – sie haben dort
    /// keine sinnvolle Höhe.
    private var allDayRow: some View {
        HStack(spacing: 0) {
            Text("ganztägig")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: gutter, alignment: .trailing)
                .padding(.trailing, Theme.Spacing.xxs)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDayItems.filter { covers($0, day) }) { item in
                        Text(item.title)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(item.tint.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .help(item.tooltip)
                            .onTapGesture { open(item) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 1)
            }
        }
        .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Raster

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            hourColumn
            ForEach(days, id: \.self) { day in
                dayColumn(day)
            }
        }
    }

    private var hourColumn: some View {
        VStack(spacing: 0) {
            ForEach(hourRange, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(height: hourHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Theme.Spacing.xxs)
                    .offset(y: -5)
            }
        }
        .frame(width: gutter, height: gridHeight, alignment: .top)
    }

    private func dayColumn(_ day: Date) -> some View {
        let laid = Layout.arrange(items(on: day))
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Stundenlinien und Klickfläche für neue Einträge.
                VStack(spacing: 0) {
                    ForEach(hourRange, id: \.self) { _ in
                        Rectangle()
                            .fill(Theme.Palette.hairline)
                            .frame(height: 1)
                            .frame(height: hourHeight, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    newEntry(on: day, minute: minuteAt(y: point.y))
                }

                if Calendar.german.isDateInToday(day), let y = currentTimeOffset {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.Palette.unproductive)
                            .frame(height: 1.5)
                        Circle()
                            .fill(Theme.Palette.unproductive)
                            .frame(width: 5, height: 5)
                            .offset(x: -2)
                    }
                    .offset(y: y)
                    .allowsHitTesting(false)
                }

                ForEach(laid) { placed in
                    BlockView(item: placed.item)
                        .frame(width: max(18, (geo.size.width - 2) / CGFloat(placed.lanes)) - 2,
                               height: height(of: placed.item))
                        .offset(x: 1 + (geo.size.width - 2) / CGFloat(placed.lanes) * CGFloat(placed.lane),
                                y: offset(of: placed.item))
                        .onTapGesture { open(placed.item) }
                        .contextMenu { menu(for: placed.item) }
                }
            }
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            // Feine Spaltentrennung – hilft, leere Tage auseinanderzuhalten.
            if Weekday(date: day) != .monday {
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Zeitraum des Rasters

    /// Der sichtbare Stundenbereich richtet sich nach dem Inhalt der Woche –
    /// mindestens 8 bis 18 Uhr, damit das Raster nicht von Woche zu Woche
    /// seine Höhe wechselt.
    private var hourRange: [Int] {
        var first = 8
        var last = 18
        for item in timedItems {
            first = min(first, item.startMinute / 60)
            last = max(last, Int(ceil(Double(item.endMinute) / 60)))
        }
        return Array(max(0, first)..<min(24, max(last, first + 1)))
    }

    private var gridHeight: CGFloat { CGFloat(hourRange.count) * hourHeight }

    private var rangeStartMinute: Int { (hourRange.first ?? 8) * 60 }

    private func offset(of item: WeekItem) -> CGFloat {
        CGFloat(item.startMinute - rangeStartMinute) * pointsPerMinute
    }

    private func height(of item: WeekItem) -> CGFloat {
        max(20, CGFloat(item.endMinute - item.startMinute) * pointsPerMinute - 2)
    }

    private func minuteAt(y: CGFloat) -> Int {
        let raw = rangeStartMinute + Int(y / pointsPerMinute)
        // Auf die nächste Viertelstunde runden – so trifft ein Klick
        // verlässlich eine glatte Zeit.
        let snapped = (raw / 15) * 15
        return min(23 * 60, max(0, snapped))
    }

    private var currentTimeOffset: CGFloat? {
        let cal = Calendar.german
        let c = cal.dateComponents([.hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        guard let first = hourRange.first, let lastHour = hourRange.last else { return nil }
        guard m >= first * 60, m <= (lastHour + 1) * 60 else { return nil }
        return CGFloat(m - rangeStartMinute) * pointsPerMinute
    }

    // MARK: - Inhalte zusammenführen

    /// Einträge des Wochenplans und Kalendertermine eines Tages als ein Typ.
    private func items(on day: Date) -> [WeekItem] {
        let cal = Calendar.german
        var result = plan.occurrences(on: day).map { WeekItem(occurrence: $0) }
        result += events
            .filter { !$0.isAllDay && covers($0, day, calendar: cal) }
            .map { WeekItem(event: $0, on: day) }
        return result
    }

    private var timedItems: [WeekItem] { days.flatMap { items(on: $0) } }

    private var allDayItems: [WeekItem] {
        events.filter(\.isAllDay).map { WeekItem(event: $0, on: $0.startDate ?? Date()) }
    }

    private func covers(_ event: EKEvent, _ day: Date, calendar cal: Calendar) -> Bool {
        guard let s = event.startDate, let e = event.endDate else { return false }
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return s < dayEnd && e > dayStart
    }

    private func covers(_ item: WeekItem, _ day: Date) -> Bool {
        let cal = Calendar.german
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) else { return false }
        return item.start < dayEnd && item.end > cal.startOfDay(for: day)
    }

    private func loadEvents() {
        guard service.access == .granted else { events = []; return }
        guard let end = Calendar.german.date(byAdding: .day, value: 7, to: weekStart) else { return }
        events = service.fetchEvents(from: weekStart, to: end)
    }

    // MARK: - Aktionen

    private func newEntry(on day: Date, minute: Int) {
        editorTarget = PlanEditorTarget(entry: nil,
                                        weekday: Weekday(date: day),
                                        day: day,
                                        startMinute: minute)
    }

    private func open(_ item: WeekItem) {
        switch item.source {
        case let .plan(occurrence):
            editorTarget = PlanEditorTarget(entry: occurrence.entry,
                                            weekday: occurrence.entry.weekday,
                                            day: occurrence.day,
                                            startMinute: occurrence.entry.startMinute)
        case let .event(event):
            eventTarget = EventEditorTarget(event: event, day: event.startDate ?? Date())
        }
    }

    @ViewBuilder
    private func menu(for item: WeekItem) -> some View {
        switch item.source {
        case let .plan(occurrence):
            Button("Bearbeiten …") { open(item) }
            Divider()
            if occurrence.isSkipped {
                Button("Diesen Termin wieder aufnehmen") {
                    plan.setSkipped(occurrence.entry, on: occurrence.day, false)
                }
            } else {
                Button("Diesen Termin aussetzen") {
                    plan.setSkipped(occurrence.entry, on: occurrence.day, true)
                }
            }
            if occurrence.entry.rhythm == .weekly {
                Button("Ganze Reihe ruhen lassen") {
                    plan.setPaused(occurrence.entry, true)
                }
            }
            Divider()
            Button("Löschen", role: .destructive) { plan.delete(occurrence.entry) }
        case .event:
            Button("Im Kalender bearbeiten …") { open(item) }
        }
    }

    // MARK: - Nachgeordnete Karten

    private var pausedCard: some View {
        Card(title: "Ruhende Reihen",
             subtitle: "Erscheinen nicht im Raster, bleiben aber erhalten.") {
            VStack(spacing: Theme.Spacing.xxs) {
                ForEach(plan.pausedEntries) { entry in
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(Theme.Palette.series[entry.color % Theme.Palette.series.count])
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(Theme.Font.body)
                            Text("\(entry.rhythmText), \(entry.timeText)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        Button("Fortsetzen") { plan.setPaused(entry, false) }
                            .buttonStyle(.link)
                    }
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .hoverRow()
                }
            }
        }
    }

    private var calendarHintCard: some View {
        Card {
            EmptyStateView(symbol: "calendar.badge.exclamationmark",
                           message: service.access == .denied
                               ? "Kalendertermine fehlen im Plan, weil der Zugriff abgelehnt wurde."
                               : "Termine aus deinen Systemkalendern lassen sich hier mit anzeigen.",
                           actionTitle: service.access == .denied ? "Systemeinstellungen öffnen" : "Zugriff erlauben",
                           action: service.access == .denied ? service.openSystemSettings : service.requestAccess)
        }
    }
}

// MARK: - Ein Block im Raster

/// Vereinheitlicht Wochenplan-Eintrag und Kalendertermin, damit beide im
/// selben Raster liegen können.
struct WeekItem: Identifiable {
    enum Source {
        case plan(PlanOccurrence)
        case event(EKEvent)
    }

    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let tint: Color
    let start: Date
    let end: Date
    /// Minuten seit Mitternacht des dargestellten Tages, auf den Tag begrenzt.
    let startMinute: Int
    let endMinute: Int
    let isSkipped: Bool
    let isFromCalendar: Bool
    let tooltip: String

    init(occurrence: PlanOccurrence) {
        let entry = occurrence.entry
        id = occurrence.id
        source = .plan(occurrence)
        title = entry.title
        subtitle = entry.subtitle
        tint = Theme.Palette.series[entry.color % Theme.Palette.series.count]
        start = occurrence.start
        end = occurrence.end
        startMinute = entry.startMinute
        endMinute = max(entry.endMinute, entry.startMinute + 5)
        isSkipped = occurrence.isSkipped
        isFromCalendar = false
        var lines = [entry.title, entry.timeText, entry.rhythmText]
        if !entry.subtitle.isEmpty { lines.insert(entry.subtitle, at: 1) }
        if !entry.notes.isEmpty { lines.append(entry.notes) }
        if occurrence.isSkipped { lines.append("Ausgesetzt") }
        tooltip = lines.joined(separator: "\n")
    }

    init(event: EKEvent, on day: Date) {
        let cal = Calendar.german
        let dayStart = cal.startOfDay(for: day)
        let s = event.startDate ?? dayStart
        let e = event.endDate ?? s.addingTimeInterval(3600)
        id = "ek-\(event.eventIdentifier ?? UUID().uuidString)-\(DayKey.of(day))"
        source = .event(event)
        title = event.title ?? "Ohne Titel"
        subtitle = event.location ?? ""
        tint = event.calendar?.cgColor.map { Color(cgColor: $0) } ?? Theme.Palette.accent
        start = s
        end = e
        // Über Mitternacht laufende Termine werden auf den Tag beschnitten.
        startMinute = max(0, min(23 * 60 + 55, Int(s.timeIntervalSince(dayStart) / 60)))
        endMinute = max(startMinute + 15, min(24 * 60, Int(e.timeIntervalSince(dayStart) / 60)))
        isSkipped = false
        isFromCalendar = true
        var lines = [title]
        if let loc = event.location, !loc.isEmpty { lines.append(loc) }
        lines.append(event.isAllDay
                     ? "Ganztägig"
                     : "\(Format.time.string(from: s)) – \(Format.time.string(from: e))")
        if let cal = event.calendar { lines.append("Kalender: \(cal.title)") }
        tooltip = lines.joined(separator: "\n")
    }
}

private struct BlockView: View {
    let item: WeekItem
    @State private var hovering = false

    private var compact: Bool { item.endMinute - item.startMinute < 45 }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if item.isFromCalendar {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .strikethrough(item.isSkipped)
                        .lineLimit(compact ? 1 : 2)
                        // Lieber eine Spur kleiner als ein Umbruch mitten
                        // im Wort – in schmalen Spalten passiert das sonst.
                        .minimumScaleFactor(0.8)
                }
                if !compact {
                    Text(PlanEntry.clockText(item.startMinute))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(item.tint.opacity(item.isSkipped ? 0.07 : (hovering ? 0.28 : 0.18)),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(item.tint.opacity(hovering ? 0.75 : 0.30),
                              style: StrokeStyle(lineWidth: 1, dash: item.isSkipped ? [3, 2] : []))
        )
        .opacity(item.isSkipped ? 0.55 : 1)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 5 : 0, y: hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.tooltip)
    }
}

// MARK: - Überlappungen

/// Verteilt einander überlappende Blöcke nebeneinander auf Spuren.
enum Layout {
    struct Placed: Identifiable {
        let item: WeekItem
        let lane: Int
        let lanes: Int
        var id: String { item.id }
    }

    static func arrange(_ items: [WeekItem]) -> [Placed] {
        let sorted = items.sorted { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }
        var result: [Placed] = []
        var cluster: [WeekItem] = []
        var clusterEnd = Int.min

        func flush() {
            guard !cluster.isEmpty else { return }
            // Erste freie Spur je Block; die Breite richtet sich danach,
            // wie viele Spuren die ganze Gruppe braucht.
            var laneEnds: [Int] = []
            var assigned: [(WeekItem, Int)] = []
            for item in cluster {
                if let lane = laneEnds.firstIndex(where: { $0 <= item.startMinute }) {
                    laneEnds[lane] = item.endMinute
                    assigned.append((item, lane))
                } else {
                    laneEnds.append(item.endMinute)
                    assigned.append((item, laneEnds.count - 1))
                }
            }
            result += assigned.map { Placed(item: $0.0, lane: $0.1, lanes: laneEnds.count) }
            cluster = []
            clusterEnd = Int.min
        }

        for item in sorted {
            if !cluster.isEmpty && item.startMinute >= clusterEnd { flush() }
            cluster.append(item)
            clusterEnd = max(clusterEnd, item.endMinute)
        }
        flush()
        return result
    }
}
