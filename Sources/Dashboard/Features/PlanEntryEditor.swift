import SwiftUI

/// Ziel des Editors: ein bestehender Eintrag oder ein neuer, vorbelegt mit
/// Tag und Uhrzeit der Stelle, auf die geklickt wurde.
struct PlanEditorTarget: Identifiable {
    let id = UUID()
    var entry: PlanEntry?
    var weekday: Weekday = .monday
    var day: Date = Date()
    var startMinute: Int = 8 * 60

    var isNew: Bool { entry == nil }
}

/// Anlegen und Bearbeiten eines Wochenplan-Eintrags.
struct PlanEntryEditor: View {
    let target: PlanEditorTarget
    var onFinished: () -> Void

    @EnvironmentObject private var plan: PlanStore

    @State private var draft = PlanEntry(title: "")
    @State private var limitStart = false
    @State private var limitEnd = false
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var isValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.endMinute > draft.startMinute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(target.isNew ? "Neuer Eintrag" : "Eintrag bearbeiten")
                .font(Theme.Font.sectionTitle)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                PlanRow("Titel") {
                    TextField("z. B. Analysis I", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }
                PlanRow("Ort") {
                    TextField("optional – Raum, Gebäude, Person", text: $draft.subtitle)
                        .textFieldStyle(.roundedBorder)
                }
                PlanRow("Farbe") {
                    ColorSwatches(selection: $draft.colorIndex)
                    Spacer()
                }

                Divider().padding(.vertical, 2)

                PlanRow("Art") {
                    Picker("", selection: $draft.rhythm) {
                        ForEach(PlanEntry.Rhythm.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    Spacer()
                }

                if draft.rhythm == .weekly {
                    PlanRow("Tag") {
                        Picker("", selection: $draft.weekday) {
                            ForEach(Weekday.allCases) { d in
                                Text(d.short).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    PlanRow("Rhythmus") {
                        Picker("", selection: $draft.interval) {
                            Text("Jede Woche").tag(1)
                            Text("Jede 2. Woche").tag(2)
                            Text("Jede 3. Woche").tag(3)
                            Text("Jede 4. Woche").tag(4)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        Spacer()
                    }
                } else {
                    PlanRow("Datum") {
                        DatePicker("", selection: Binding(
                            get: { draft.date ?? target.day },
                            set: { draft.date = $0 }
                        ), displayedComponents: [.date])
                            .labelsHidden()
                        Spacer()
                    }
                }

                PlanRow("Zeit") {
                    HStack(spacing: Theme.Spacing.xs) {
                        DatePicker("", selection: minuteBinding(\.startMinute),
                                   displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                        Text("bis").foregroundStyle(Theme.Palette.textSecondary)
                        DatePicker("", selection: minuteBinding(\.endMinute),
                                   displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }
                    Spacer()
                }

                if draft.rhythm == .weekly {
                    Divider().padding(.vertical, 2)

                    PlanRow("Zeitraum") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Toggle("ab", isOn: $limitStart)
                                DatePicker("", selection: Binding(
                                    get: { draft.startsOn ?? Date() },
                                    set: { draft.startsOn = $0 }
                                ), displayedComponents: [.date])
                                    .labelsHidden()
                                    .disabled(!limitStart)
                            }
                            HStack(spacing: Theme.Spacing.xs) {
                                Toggle("bis", isOn: $limitEnd)
                                DatePicker("", selection: Binding(
                                    get: { draft.endsOn ?? Date() },
                                    set: { draft.endsOn = $0 }
                                ), displayedComponents: [.date])
                                    .labelsHidden()
                                    .disabled(!limitEnd)
                            }
                        }
                        Spacer()
                    }

                    PlanRow("Aussetzen") {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Ganze Reihe ruhen lassen", isOn: $draft.isPaused)
                            if !draft.skippedDays.isEmpty {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("\(draft.skippedDays.count) einzelne\(draft.skippedDays.count == 1 ? "r Termin" : " Termine") ausgesetzt")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                    Button("Alle wieder aufnehmen") { draft.skippedDays = [] }
                                        .buttonStyle(.link)
                                        .font(Theme.Font.caption)
                                }
                            }
                        }
                        Spacer()
                    }
                }

                Divider().padding(.vertical, 2)

                PlanRow("Notiz", alignment: .top) {
                    TextEditor(text: $draft.notes)
                        .font(Theme.Font.body)
                        .frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .strokeBorder(Theme.Palette.hairline))
                }
            }

            if draft.endMinute <= draft.startMinute {
                Text("Das Ende muss nach dem Beginn liegen.")
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
                    .disabled(!isValid)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 470)
        .onAppear(perform: load)
        .onChange(of: draft.startMinute) { old, new in
            // Dauer beim Verschieben des Beginns beibehalten.
            let length = max(15, draft.endMinute - old)
            draft.endMinute = min(24 * 60, new + length)
        }
        .onChange(of: limitStart) { _, on in if !on { draft.startsOn = nil } else if draft.startsOn == nil { draft.startsOn = Date() } }
        .onChange(of: limitEnd) { _, on in if !on { draft.endsOn = nil } else if draft.endsOn == nil { draft.endsOn = Date() } }
        .alert("Eintrag löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let entry = target.entry { plan.delete(entry) }
                onFinished()
            }
        } message: {
            Text("Die ganze Reihe wird entfernt. Einzelne Termine lassen sich stattdessen aussetzen.")
        }
    }

    // MARK: - Laden und Sichern

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        if let entry = target.entry {
            draft = entry
            limitStart = entry.startsOn != nil
            limitEnd = entry.endsOn != nil
        } else {
            var new = PlanEntry(title: "")
            new.weekday = target.weekday
            new.date = target.day
            new.startMinute = target.startMinute
            new.endMinute = min(24 * 60, target.startMinute + 90)
            new.colorIndex = plan.entries.count % Theme.Palette.series.count
            draft = new
        }
    }

    private func commit() {
        guard isValid else { return }
        var entry = draft
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.subtitle = entry.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.endMinute = max(entry.endMinute, entry.startMinute + 5)
        if entry.rhythm == .once {
            if entry.date == nil { entry.date = target.day }
        } else {
            entry.date = nil
        }

        if target.isNew {
            plan.add(entry)
        } else {
            plan.update(entry)
        }
        onFinished()
    }

    /// Verbindet eine Minutenangabe mit einem `DatePicker`. Das Datum ist
    /// dabei belanglos – gespeichert wird nur die Uhrzeit.
    private func minuteBinding(_ key: WritableKeyPath<PlanEntry, Int>) -> Binding<Date> {
        Binding(
            get: { PlanEntry.time(min(draft[keyPath: key], 23 * 60 + 59), on: Date()) },
            set: { newValue in
                let cal = Calendar.german
                let c = cal.dateComponents([.hour, .minute], from: newValue)
                draft[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// Sechs Farbfelder aus der Diagrammreihe – hält den Plan farblich im
/// selben System wie die Statistiken.
private struct ColorSwatches: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(Theme.Palette.series.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().strokeBorder(Theme.Palette.textPrimary.opacity(selection == index ? 0.9 : 0),
                                              lineWidth: 2)
                            .padding(-3)
                    )
                    .contentShape(Circle())
                    .onTapGesture { selection = index }
            }
        }
    }
}

/// Formularzeile mit fester Beschriftungsspalte.
private struct PlanRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    init(_ label: String, alignment: VerticalAlignment = .center,
         @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 76, alignment: .trailing)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
