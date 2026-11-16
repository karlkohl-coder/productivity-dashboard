import SwiftUI

/// Notizen mit Ordnerablage: links der Baum, rechts die offene Seite.
/// Bewusst nicht im `Page`-Gerüst – der Editor braucht die volle Höhe,
/// und eine Seite, die selbst scrollt, verträgt sich nicht mit einer
/// Liste, die das auch tut.
struct NotesView: View {
    @EnvironmentObject private var store: NotesStore

    @State private var selection: String?
    @State private var search = ""

    /// Der Text wird lokal gehalten und von dort in den Speicher
    /// geschrieben. Direkt an den Speicher gebunden geriete die
    /// Schreibmarke bei jedem Rückschreiben durcheinander.
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var loadedNoteID: UUID?
    /// Während des Umschaltens stehen Titel und Text kurz aus zwei
    /// verschiedenen Notizen nebeneinander. Ohne diese Sperre könnte ein
    /// Rückschreiben dazwischenfunken und den Text der einen Notiz in die
    /// andere tragen.
    @State private var isLoading = false

    /// Aufgeklappte Ordner. `List(children:)` würde alles zugeklappt zeigen –
    /// beim Öffnen sähe man dann nur Ordnernamen und keine einzige Notiz.
    @State private var expanded: Set<String> = []
    @State private var didExpandInitially = false

    @State private var folderSheet: FolderSheet?
    @State private var deletingNote: Note?
    @State private var deletingFolder: NoteFolder?

    private var selectedNote: Note? { store.note(id: NoteTreeItem.noteID(from: selection)) }
    private var selectedFolder: NoteFolder? { store.folder(id: NoteTreeItem.folderID(from: selection)) }

    /// Ordner, in dem eine neue Notiz landen soll: der ausgewählte Ordner,
    /// sonst der Ordner der offenen Notiz.
    private var targetFolder: UUID? {
        selectedFolder?.id ?? selectedNote?.folderID
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 270)
                .background(Theme.Palette.card.opacity(0.4))
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Palette.canvas)
        .onAppear { expandInitially(); restoreSelection() }
        .onChange(of: selection) { _, _ in syncDraft() }
        .onChange(of: draftTitle) { _, _ in pushDraft() }
        .onChange(of: draftBody) { _, _ in pushDraft() }
        .onDisappear { pushDraft(); store.flush() }
        .background {
            Button("") { newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .sheet(item: $folderSheet) { sheet in
            FolderEditor(sheet: sheet) { name in
                if let existing = sheet.existing {
                    store.rename(folderID: existing.id, to: name)
                } else if let created = store.addFolder(name: name, parent: sheet.parent) {
                    reveal(folderID: sheet.parent)
                    expanded.insert(NoteTreeItem.key(for: created))
                    selection = NoteTreeItem.key(for: created)
                }
                folderSheet = nil
            } onCancel: { folderSheet = nil }
        }
        .alert("Notiz löschen?", isPresented: Binding(
            get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingNote = nil }
            Button("Löschen", role: .destructive) {
                if let note = deletingNote {
                    if loadedNoteID == note.id { loadedNoteID = nil; selection = nil }
                    store.delete(noteID: note.id)
                }
                deletingNote = nil
            }
        } message: {
            Text("„\(deletingNote?.displayTitle ?? "")“ wird unwiderruflich entfernt.")
        }
        .alert("Ordner löschen?", isPresented: Binding(
            get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("Abbrechen", role: .cancel) { deletingFolder = nil }
            Button("Löschen", role: .destructive) {
                if let folder = deletingFolder {
                    if selectedFolder?.id == folder.id { selection = nil }
                    store.deleteFolder(id: folder.id)
                }
                deletingFolder = nil
            }
        } message: {
            Text("Der Ordner wird entfernt. Sein Inhalt bleibt erhalten und rückt eine Ebene nach oben.")
        }
    }

    // MARK: - Ablage

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Notizen")
                    .font(Theme.Font.sectionTitle)
                Spacer()
                Button { folderSheet = FolderSheet(existing: nil, parent: targetFolder) } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Palette.textTertiary)
                .help("Neuen Ordner anlegen")

                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Palette.accent)
                .help("Neue Notiz (⌘N)")
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)

            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                TextField("Suchen …", text: $search)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.caption)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .font(.system(size: 10))
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 5)
            .background(Theme.Palette.hairline, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)

            let items = store.tree(search: search)
            if items.isEmpty {
                VStack {
                    EmptyStateView(symbol: search.isEmpty ? "note.text" : "magnifyingglass",
                                   message: search.isEmpty
                                       ? "Noch keine Notizen."
                                       : "Nichts gefunden.",
                                   actionTitle: search.isEmpty ? "Erste Notiz anlegen" : nil,
                                   action: search.isEmpty ? { newNote() } : nil)
                    Spacer()
                }
            } else {
                List(selection: $selection) {
                    outlineRows(items)
                }
                .listStyle(.sidebar)
            }
        }
    }

    /// Baut die Liste selbst auf, statt `List(children:)` zu überlassen –
    /// nur so lässt sich steuern, was offen ist.
    private func outlineRows(_ items: [NoteTreeItem]) -> AnyView {
        AnyView(
            ForEach(items) { item in
                if item.folder != nil, let children = item.children {
                    DisclosureGroup(isExpanded: expansion(of: item.id)) {
                        outlineRows(children)
                    } label: {
                        row(item)
                            .tag(item.id)
                            .contextMenu { menu(for: item) }
                    }
                } else {
                    row(item)
                        .tag(item.id)
                        .contextMenu { menu(for: item) }
                }
            }
        )
    }

    private func expansion(of id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { isOpen in
                    if isOpen { expanded.insert(id) } else { expanded.remove(id) }
                })
    }

    /// Beim ersten Öffnen alles aufklappen. Danach entscheidet der Benutzer.
    private func expandInitially() {
        guard !didExpandInitially else { return }
        didExpandInitially = true
        expanded = Set(store.folders.map { NoteTreeItem.key(for: $0) })
    }

    /// Sorgt dafür, dass ein neu angelegter Eintrag auch zu sehen ist.
    private func reveal(folderID: UUID?) {
        guard let folderID else { return }
        var cursor: UUID? = folderID
        var steps = 0
        while let current = cursor, steps < 12 {
            expanded.insert("f-\(current.uuidString)")
            cursor = store.folder(id: current)?.parentID
            steps += 1
        }
    }

    @ViewBuilder
    private func row(_ item: NoteTreeItem) -> some View {
        switch item.kind {
        case .folder(let folder):
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.accent)
                Text(folder.name)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xxs)
                let count = store.noteCount(in: folder.id)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        case .note(let note):
            VStack(alignment: .leading, spacing: 1) {
                Text(note.displayTitle)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(Format.relativeDay(note.updatedAt))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func menu(for item: NoteTreeItem) -> some View {
        switch item.kind {
        case .folder(let folder):
            Button("Neue Notiz hier") {
                let note = store.addNote(in: folder.id)
                reveal(folderID: folder.id)
                selection = NoteTreeItem.key(for: note)
            }
            Button("Unterordner anlegen …") {
                folderSheet = FolderSheet(existing: nil, parent: folder.id)
            }
            Button("Umbenennen …") {
                folderSheet = FolderSheet(existing: folder, parent: folder.parentID)
            }
            Menu("Verschieben nach") {
                folderTargets(current: folder.parentID) { target in
                    store.move(folderID: folder.id, to: target)
                } isEnabled: { target in
                    store.canMove(folderID: folder.id, to: target)
                }
            }
            Divider()
            Button("Löschen …", role: .destructive) { deletingFolder = folder }
        case .note(let note):
            Menu("Verschieben nach") {
                folderTargets(current: note.folderID) { target in
                    store.move(noteID: note.id, to: target)
                } isEnabled: { _ in true }
            }
            Divider()
            Button("Löschen …", role: .destructive) { deletingNote = note }
        }
    }

    /// Liste aller Ordner als Verschiebeziel, eingerückt nach Ebene.
    @ViewBuilder
    private func folderTargets(current: UUID?,
                               onPick: @escaping (UUID?) -> Void,
                               isEnabled: @escaping (UUID?) -> Bool) -> some View {
        Button("Keine Ablage") { onPick(nil) }
            .disabled(current == nil || !isEnabled(nil))
        Divider()
        ForEach(store.allFoldersSorted(), id: \.folder.id) { entry in
            Button(String(repeating: "   ", count: entry.depth) + entry.folder.name) {
                onPick(entry.folder.id)
            }
            .disabled(current == entry.folder.id || !isEnabled(entry.folder.id))
        }
    }

    // MARK: - Rechte Seite

    @ViewBuilder
    private var detail: some View {
        if let note = selectedNote {
            editor(for: note)
        } else if let folder = selectedFolder {
            folderSummary(folder)
        } else {
            EmptyStateView(symbol: "note.text",
                           message: store.isEmpty
                               ? "Lege deine erste Notiz an.\nOrdner helfen später beim Sortieren."
                               : "Wähle links eine Notiz aus.",
                           actionTitle: "Neue Notiz",
                           action: { newNote() })
                .frame(maxHeight: .infinity)
        }
    }

    private func editor(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Titel", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xs)

            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    folderTargets(current: note.folderID) { target in
                        store.move(noteID: note.id, to: target)
                    } isEnabled: { _ in true }
                } label: {
                    Label(store.path(of: note.folderID), systemImage: "folder")
                        .font(Theme.Font.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Theme.Palette.textSecondary)
                .help("Notiz in einen anderen Ordner verschieben")

                Text("·").foregroundStyle(Theme.Palette.textTertiary)
                Text("Geändert \(Format.relativeDay(note.updatedAt)), \(Format.time.string(from: note.updatedAt))")
                Text("·").foregroundStyle(Theme.Palette.textTertiary)
                Text("\(Note.wordCount(of: draftBody)) Wörter")
                    .monospacedDigit()

                Spacer(minLength: Theme.Spacing.sm)

                Button { deletingNote = note } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Palette.textTertiary)
                .help("Diese Notiz löschen")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            Divider()

            TextEditor(text: $draftBody)
                .font(Theme.Font.body)
                .scrollContentBackground(.hidden)
                .background(Theme.Palette.canvas)
                .padding(.horizontal, Theme.Spacing.lg - 5)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .onAppear(perform: syncDraft)
    }

    private func folderSummary(_ folder: NoteFolder) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.Palette.accent)
            Text(store.path(of: folder.id))
                .font(Theme.Font.sectionTitle)
            Text(countLabel(folder))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.md) {
                Button("Neue Notiz hier") {
                    let note = store.addNote(in: folder.id)
                    reveal(folderID: folder.id)
                    selection = NoteTreeItem.key(for: note)
                }
                Button("Unterordner anlegen") {
                    folderSheet = FolderSheet(existing: nil, parent: folder.id)
                }
            }
            .controlSize(.small)
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countLabel(_ folder: NoteFolder) -> String {
        let direct = store.noteCount(in: folder.id, recursive: false)
        let total = store.noteCount(in: folder.id)
        if total == direct {
            return direct == 1 ? "1 Notiz" : "\(direct) Notizen"
        }
        return "\(direct) direkt, \(total) mit Unterordnern"
    }

    // MARK: - Entwurf und Speicher abgleichen

    /// Beim Öffnen die zuletzt bearbeitete Notiz zeigen – eine leere
    /// rechte Hälfte wäre bei jedem Besuch ein unnötiger Zwischenschritt.
    private func restoreSelection() {
        guard selection == nil,
              let latest = store.notes.max(by: { $0.updatedAt < $1.updatedAt }) else { return }
        selection = NoteTreeItem.key(for: latest)
        syncDraft()
    }

    private func newNote() {
        pushDraft()
        let note = store.addNote(in: targetFolder)
        reveal(folderID: targetFolder)
        selection = NoteTreeItem.key(for: note)
    }

    /// Wechselt die Auswahl: erst den bisherigen Stand sichern, dann den
    /// neuen laden.
    private func syncDraft() {
        let newID = selectedNote?.id
        guard newID != loadedNoteID else { return }
        pushDraft()
        isLoading = true
        loadedNoteID = newID
        draftTitle = selectedNote?.title ?? ""
        draftBody = selectedNote?.body ?? ""
        isLoading = false
    }

    private func pushDraft() {
        guard !isLoading else { return }
        guard let id = loadedNoteID, store.note(id: id) != nil else { return }
        store.setContent(title: draftTitle, body: draftBody, of: id)
    }
}

/// Ziel des Ordner-Dialogs: neu anlegen oder umbenennen.
struct FolderSheet: Identifiable {
    let id = UUID()
    var existing: NoteFolder?
    var parent: UUID?
}

private struct FolderEditor: View {
    let sheet: FolderSheet
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @EnvironmentObject private var store: NotesStore
    @State private var name = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(sheet.existing == nil ? "Neuer Ordner" : "Ordner umbenennen")
                .font(Theme.Font.sectionTitle)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if sheet.existing == nil, sheet.parent != nil {
                Text("Wird angelegt in: \(store.path(of: sheet.parent))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 340)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = sheet.existing?.name ?? ""
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}
