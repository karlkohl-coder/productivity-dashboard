import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var draftTitle = ""
    @State private var draftPriority: TaskPriority = .normal
    @State private var draftDue: Date = Date()
    @State private var draftHasDue = false
    @State private var showCompleted = false
    @State private var editing: TaskItem?

    var body: some View {
        Page(title: "Aufgaben",
             subtitle: "\(store.open.count) offen · \(store.completed.count) erledigt") {
            composer
            openList
            completedList
        } actions: {
            Toggle("Erledigte zeigen", isOn: $showCompleted)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(Theme.Font.caption)
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task) { updated in
                store.update(updated)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    // MARK: - Neue Aufgabe

    private var composer: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Theme.Palette.textTertiary)
                    TextField("Neue Aufgabe …", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .onSubmit(commit)
                    Picker("", selection: $draftPriority) {
                        ForEach(TaskPriority.allCases) { p in Text(p.label).tag(p) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .controlSize(.small)
                    Toggle(isOn: $draftHasDue) {
                        Image(systemName: "calendar")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Fälligkeitsdatum setzen")
                    Button("Hinzufügen", action: commit)
                        .controlSize(.small)
                        .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if draftHasDue {
                    HStack {
                        DatePicker("Fällig am", selection: $draftDue, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .controlSize(.small)
                            .font(Theme.Font.caption)
                        Spacer()
                    }
                }
            }
        }
    }

    private func commit() {
        store.add(title: draftTitle, priority: draftPriority, dueDate: draftHasDue ? draftDue : nil)
        draftTitle = ""
        draftPriority = .normal
        draftHasDue = false
    }

    // MARK: - Listen

    private var openList: some View {
        Card(title: "Offen") {
            if store.open.isEmpty {
                EmptyStateView(symbol: "tray", message: "Alles abgearbeitet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.open) { task in
                        TaskRow(task: task) { editing = task }
                        if task.id != store.open.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var completedList: some View {
        if showCompleted && !store.completed.isEmpty {
            Card(title: "Erledigt") {
                VStack(spacing: 0) {
                    ForEach(store.completed) { task in
                        TaskRow(task: task)
                        if task.id != store.completed.last?.id { Divider().opacity(0.4) }
                    }
                }
            } trailing: {
                Button("Aufräumen") { store.clearCompleted() }
                    .buttonStyle(.link)
                    .font(Theme.Font.caption)
            }
        }
    }
}

/// Einzelne Aufgabenzeile – wird auch in der Übersicht verwendet.
struct TaskRow: View {
    let task: TaskItem
    var compact: Bool = false
    var onEdit: (() -> Void)?

    @EnvironmentObject private var store: TaskStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { store.toggle(task) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(task.isDone ? Theme.Palette.accent : Theme.Palette.textTertiary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(Theme.Font.body)
                    .strikethrough(task.isDone, color: Theme.Palette.textTertiary)
                    .foregroundStyle(task.isDone ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                    .lineLimit(1)
                if !compact, !task.notes.isEmpty {
                    Text(task.notes)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.xs)

            if task.priority == .high && !task.isDone {
                Text("Hoch")
                    .font(Theme.Font.caption)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.Palette.unproductive.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.Palette.unproductive)
            }

            if let due = task.dueDate {
                Text(Format.relativeDay(due))
                    .font(Theme.Font.caption)
                    .foregroundStyle(task.isOverdue ? Theme.Palette.unproductive : Theme.Palette.textTertiary)
            }

            if hovering && !compact {
                HStack(spacing: 2) {
                    if onEdit != nil {
                        Button { onEdit?() } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                    }
                    Button { store.delete(task) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, compact ? 3 : 6)
        .background(hovering ? Theme.Palette.hairline.opacity(0.7) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Detailbearbeitung als Blatt.
struct TaskEditor: View {
    @State var task: TaskItem
    var onSave: (TaskItem) -> Void
    var onCancel: () -> Void

    @State private var hasDue: Bool
    @State private var due: Date

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onCancel: @escaping () -> Void) {
        _task = State(initialValue: task)
        self.onSave = onSave
        self.onCancel = onCancel
        _hasDue = State(initialValue: task.dueDate != nil)
        _due = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Aufgabe bearbeiten").font(Theme.Font.sectionTitle)

            TextField("Titel", text: $task.title)
            TextEditor(text: $task.notes)
                .font(Theme.Font.body)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Palette.hairline))

            Picker("Priorität", selection: $task.priority) {
                ForEach(TaskPriority.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.segmented)

            Toggle("Fälligkeitsdatum", isOn: $hasDue)
            if hasDue {
                DatePicker("Fällig am", selection: $due, displayedComponents: .date)
            }

            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                Button("Sichern") {
                    task.dueDate = hasDue ? due : nil
                    onSave(task)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
    }
}
