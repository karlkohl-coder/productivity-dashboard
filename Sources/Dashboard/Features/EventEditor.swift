import EventKit
import SwiftUI

/// Ziel des Editors: entweder ein bestehender Termin oder ein neuer an einem Tag.
struct EventEditorTarget: Identifiable {
    let id = UUID()
    var event: EKEvent?
    var day: Date

    var isNew: Bool { event == nil }
}

/// Anlegen und Bearbeiten von Terminen. Schreibt direkt in den gewählten
/// Systemkalender – dieselben Termine erscheinen danach auch in Kalender.app.
struct EventEditor: View {
    let target: EventEditorTarget
    var onFinished: () -> Void

    @EnvironmentObject private var service: CalendarService

    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var calendar: EKCalendar?
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(target.isNew ? "Neuer Termin" : "Termin bearbeiten")
                .font(Theme.Font.sectionTitle)

            VStack(spacing: Theme.Spacing.sm) {
                LabeledRow("Titel") {
                    TextField("z. B. Team-Meeting", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledRow("Ort") {
                    TextField("optional", text: $location)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledRow("Kalender") {
                    Picker("", selection: $calendar) {
                        ForEach(service.writableCalendars, id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle().fill(color(of: cal)).frame(width: 8, height: 8)
                                Text(cal.title)
                            }
                            .tag(cal as EKCalendar?)
                        }
                    }
                    .labelsHidden()
                }

                Divider().padding(.vertical, 2)

                LabeledRow("Ganztägig") {
                    Toggle("", isOn: $isAllDay).labelsHidden()
                    Spacer()
                }
                LabeledRow("Beginn") {
                    DatePicker("", selection: $start,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                    Spacer()
                }
                LabeledRow("Ende") {
                    DatePicker("", selection: $end,
                               in: start...,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                    Spacer()
                }

                Divider().padding(.vertical, 2)

                LabeledRow("Notiz", alignment: .top) {
                    TextEditor(text: $notes)
                        .font(Theme.Font.body)
                        .frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .strokeBorder(Theme.Palette.hairline))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.unproductive)
            }

            HStack {
                if !target.isNew {
                    Button("Löschen", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Abbrechen", action: onFinished)
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || calendar == nil)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 460)
        .onAppear(perform: load)
        .onChange(of: start) { old, new in
            // Dauer beim Verschieben des Beginns beibehalten.
            if end > old { end = new.addingTimeInterval(end.timeIntervalSince(old)) }
        }
        .alert("Termin löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive, action: remove)
        }
    }

    // MARK: - Laden und Sichern

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        if let event = target.event {
            title = event.title ?? ""
            location = event.location ?? ""
            notes = event.notes ?? ""
            isAllDay = event.isAllDay
            start = event.startDate ?? target.day
            end = event.endDate ?? start.addingTimeInterval(3600)
            calendar = event.calendar
        } else {
            let draft = service.makeDraft(on: target.day)
            start = draft.startDate
            end = draft.endDate
            calendar = draft.calendar
        }
        if calendar == nil { calendar = service.defaultCalendar }
    }

    private func commit() {
        guard let calendar else { return }
        let event = target.event ?? service.makeDraft(on: target.day)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = location.isEmpty ? nil : location
        event.notes = notes.isEmpty ? nil : notes
        event.calendar = calendar
        event.isAllDay = isAllDay
        if isAllDay {
            let cal = Calendar.german
            event.startDate = cal.startOfDay(for: start)
            event.endDate = cal.startOfDay(for: max(end, start))
        } else {
            event.startDate = start
            event.endDate = max(end, start.addingTimeInterval(300))
        }

        do {
            try service.save(event)
            onFinished()
        } catch {
            errorMessage = "Konnte nicht gesichert werden: \(error.localizedDescription)"
        }
    }

    private func remove() {
        guard let event = target.event else { return }
        do {
            try service.delete(event)
            onFinished()
        } catch {
            errorMessage = "Konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    private func color(of cal: EKCalendar) -> Color {
        cal.cgColor.map { Color(cgColor: $0) } ?? Theme.Palette.accent
    }
}

/// Formularzeile mit fester Beschriftungsspalte – hält die Felder in einer Flucht.
private struct LabeledRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    init(_ label: String, alignment: VerticalAlignment = .center, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 72, alignment: .trailing)
            content()
        }
    }
}
