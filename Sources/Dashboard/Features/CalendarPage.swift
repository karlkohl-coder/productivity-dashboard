import EventKit
import SwiftUI

struct CalendarPage: View {
    @EnvironmentObject private var service: CalendarService

    @State private var month: Date = Calendar.german.startOfMonth(for: Date())
    @State private var selectedDay: Date = Calendar.german.startOfDay(for: Date())
    @State private var editorTarget: EventEditorTarget?

    var body: some View {
        Page(title: "Kalender", subtitle: Format.monthYear.string(from: month)) {
            switch service.access {
            case .granted:
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    monthCard.frame(maxWidth: .infinity)
                    dayCard.frame(width: 320)
                }
            case .unknown:
                Card {
                    EmptyStateView(symbol: "calendar.badge.plus",
                                   message: "Das Dashboard kann deine Systemkalender lesen.\nDafür wird einmalig Zugriff benötigt.",
                                   actionTitle: "Zugriff erlauben",
                                   action: service.requestAccess)
                }
            case .denied:
                Card {
                    EmptyStateView(symbol: "lock",
                                   message: "Der Kalenderzugriff wurde abgelehnt.\nEr lässt sich in den Systemeinstellungen wieder erlauben.",
                                   actionTitle: "Systemeinstellungen öffnen",
                                   action: service.openSystemSettings)
                }
            }
        } actions: {
            if service.access == .granted {
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        Button("Heute") { jumpToToday() }
                        Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    }
                    Button {
                        editorTarget = EventEditorTarget(event: nil, day: selectedDay)
                    } label: {
                        Label("Termin", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.writableCalendars.isEmpty)
                    .help("Neuen Termin am ausgewählten Tag anlegen (⌘N)")
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: loadMonth)
        .onChange(of: month) { _, _ in loadMonth() }
        .background {
            // Unsichtbare Schaltfläche nur für das Tastaturkürzel.
            Button("") { editorTarget = EventEditorTarget(event: nil, day: selectedDay) }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .sheet(item: $editorTarget) { target in
            EventEditor(target: target) { editorTarget = nil }
                .environmentObject(service)
        }
    }

    // MARK: - Monatsraster

    private var monthCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 0) {
                    ForEach(Calendar.german.shortWeekdaySymbolsStartingMonday, id: \.self) { symbol in
                        Text(symbol)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(daysInGrid, id: \.self) { day in
                        DayCell(day: day,
                                isCurrentMonth: Calendar.german.isDate(day, equalTo: month, toGranularity: .month),
                                isSelected: Calendar.german.isDate(day, inSameDayAs: selectedDay),
                                eventCount: service.events(on: day).count)
                            .onTapGesture { selectedDay = day }
                            .onTapGesture(count: 2) {
                                selectedDay = day
                                editorTarget = EventEditorTarget(event: nil, day: day)
                            }
                            .contextMenu {
                                Button("Termin an diesem Tag anlegen …") {
                                    selectedDay = day
                                    editorTarget = EventEditorTarget(event: nil, day: day)
                                }
                            }
                    }
                }
            }
        }
    }

    /// Immer volle Wochen, damit das Raster nicht springt.
    private var daysInGrid: [Date] {
        let cal = Calendar.german
        let start = cal.startOfMonth(for: month)
        let leading = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: start) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    // MARK: - Tagesdetail

    private var dayCard: some View {
        Card(title: Format.relativeDay(selectedDay),
             subtitle: Format.fullDate.string(from: selectedDay)) {
            let events = service.events(on: selectedDay)
            if events.isEmpty {
                EmptyStateView(symbol: "calendar",
                               message: "Keine Termine.",
                               actionTitle: service.writableCalendars.isEmpty ? nil : "Termin anlegen",
                               action: service.writableCalendars.isEmpty ? nil : {
                                   editorTarget = EventEditorTarget(event: nil, day: selectedDay)
                               })
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(events, id: \.self) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorTarget = EventEditorTarget(event: event, day: selectedDay)
                            }
                    }
                }
            }
        } trailing: {
            Button {
                editorTarget = EventEditorTarget(event: nil, day: selectedDay)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.Palette.accent)
            .disabled(service.writableCalendars.isEmpty)
            .help("Termin an diesem Tag anlegen")
        }
    }

    // MARK: - Navigation

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.german.date(byAdding: .month, value: delta, to: month) {
            month = next
        }
    }

    private func jumpToToday() {
        month = Calendar.german.startOfMonth(for: Date())
        selectedDay = Calendar.german.startOfDay(for: Date())
    }

    private func loadMonth() {
        let cal = Calendar.german
        guard let start = daysInGrid.first,
              let end = cal.date(byAdding: .day, value: 43, to: start) else { return }
        service.load(from: start, to: end)
    }
}

private struct DayCell: View {
    @State private var hovering = false
    let day: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let eventCount: Int

    private var isToday: Bool { Calendar.german.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.german.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                .foregroundStyle(foreground)
            HStack(spacing: 2) {
                ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.8) : Theme.Palette.accent)
                        .frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(hovering && !isSelected ? Theme.Palette.hairlineStrong : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if isSelected { return .white }
        if !isCurrentMonth { return Theme.Palette.textTertiary.opacity(0.5) }
        if isToday { return Theme.Palette.accent }
        return Theme.Palette.textPrimary
    }

    private var background: Color {
        if isSelected { return Theme.Palette.accent }
        if isToday { return Theme.Palette.accent.opacity(0.10) }
        return .clear
    }
}

struct EventRow: View {
    let event: EKEvent

    private var tint: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return Theme.Palette.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Ohne Titel")
                    .font(Theme.Font.body)
                    .lineLimit(1)
                Text(timeText)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 2)
        .frame(height: 38)
        .hoverRow()
    }

    private var timeText: String {
        if event.isAllDay { return "Ganztägig" }
        guard let s = event.startDate, let e = event.endDate else { return "" }
        return "\(Format.time.string(from: s)) – \(Format.time.string(from: e))"
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }

    /// Wochentagskürzel beginnend mit Montag.
    var shortWeekdaySymbolsStartingMonday: [String] {
        let symbols = shortWeekdaySymbols
        let offset = firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
