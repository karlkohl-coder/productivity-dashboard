import AppKit
import Foundation
import SwiftUI

/// Hält Notizen und Ordner und bringt sie in die Baumform, die die Liste
/// anzeigt.
@MainActor
final class NotesStore: ObservableObject {

    private static let file = "notes.json"
    /// Schutz vor einer in sich verketteten Ablage: eine beschädigte Datei
    /// soll die Ansicht nicht in eine Endlosschleife schicken.
    private static let maxDepth = 12

    @Published private(set) var notes: [Note] = []
    @Published private(set) var folders: [NoteFolder] = []

    private struct Stored: Codable {
        var notes: [Note]
        var folders: [NoteFolder]
    }

    private var saveTimer: Timer?

    init() {
        if let stored = JSONStore.load(Stored.self, from: Self.file) {
            notes = stored.notes
            folders = stored.folders
        }
        // Beim Beenden sofort schreiben – sonst ginge verloren, was im
        // Sammelfenster noch aussteht.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: - Sichern

    /// Tippen erzeugt sehr viele Änderungen. Die Datei wird deshalb gebündelt
    /// geschrieben: der Stand im Speicher ist sofort aktuell, die Platte folgt
    /// eine Sekunde später. Bei jedem Tastendruck zu schreiben wäre spürbar.
    private func scheduleSave() {
        saveTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
        RunLoop.main.add(t, forMode: .common)
        saveTimer = t
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        JSONStore.save(Stored(notes: notes, folders: folders), to: Self.file)
    }

    // MARK: - Notizen

    @discardableResult
    func addNote(in folderID: UUID? = nil) -> Note {
        let note = Note(folderID: folderID)
        notes.append(note)
        flush()
        return note
    }

    /// Schreibt Titel und Text zurück. Ohne echte Änderung passiert nichts –
    /// sonst setzte schon das bloße Öffnen einer Notiz ihr Änderungsdatum neu.
    func setContent(title: String, body: String, of id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[idx].title != title || notes[idx].body != body else { return }
        notes[idx].title = title
        notes[idx].body = body
        notes[idx].updatedAt = Date()
        scheduleSave()
    }

    func move(noteID: UUID, to folderID: UUID?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard notes[idx].folderID != folderID else { return }
        notes[idx].folderID = folderID
        notes[idx].updatedAt = Date()
        flush()
    }

    func delete(noteID: UUID) {
        notes.removeAll { $0.id == noteID }
        flush()
    }

    func note(id: UUID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Ordner

    @discardableResult
    func addFolder(name: String, parent: UUID? = nil) -> NoteFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = NoteFolder(name: trimmed, parentID: parent)
        folders.append(folder)
        flush()
        return folder
    }

    func rename(folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].name = trimmed
        flush()
    }

    /// Verschiebt einen Ordner. Ein Ordner darf nicht in sich selbst oder in
    /// einen seiner eigenen Unterordner wandern – das zerrisse den Baum und
    /// die betroffenen Notizen wären nicht mehr erreichbar.
    func move(folderID: UUID, to parent: UUID?) {
        guard folderID != parent else { return }
        guard !isDescendant(parent, of: folderID) else { return }
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].parentID = parent
        flush()
    }

    func canMove(folderID: UUID, to parent: UUID?) -> Bool {
        folderID != parent && !isDescendant(parent, of: folderID)
    }

    private func isDescendant(_ candidate: UUID?, of folderID: UUID) -> Bool {
        var cursor = candidate
        var steps = 0
        while let current = cursor, steps < Self.maxDepth {
            if current == folderID { return true }
            cursor = folders.first { $0.id == current }?.parentID
            steps += 1
        }
        return false
    }

    /// Löscht einen Ordner und hängt seinen Inhalt eine Ebene höher.
    /// Bewusst nicht mitlöschen: eine Notiz soll nie verschwinden, weil
    /// jemand ihren Ordner aufgeräumt hat.
    func deleteFolder(id folderID: UUID) {
        let parent = folders.first { $0.id == folderID }?.parentID
        for i in notes.indices where notes[i].folderID == folderID {
            notes[i].folderID = parent
        }
        for i in folders.indices where folders[i].parentID == folderID {
            folders[i].parentID = parent
        }
        folders.removeAll { $0.id == folderID }
        flush()
    }

    func folder(id: UUID?) -> NoteFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    /// „Uni / Semester 3“ – für Menüs und die Zeile über dem Editor.
    func path(of folderID: UUID?) -> String {
        guard let folderID else { return "Keine Ablage" }
        var parts: [String] = []
        var cursor: UUID? = folderID
        var steps = 0
        while let current = cursor, steps < Self.maxDepth {
            guard let f = folders.first(where: { $0.id == current }) else { break }
            parts.insert(f.name, at: 0)
            cursor = f.parentID
            steps += 1
        }
        return parts.isEmpty ? "Keine Ablage" : parts.joined(separator: " / ")
    }

    /// Alle Ordner als flache, eingerückte Liste – für Auswahlmenüs.
    func allFoldersSorted() -> [(folder: NoteFolder, depth: Int)] {
        var result: [(NoteFolder, Int)] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            guard depth < Self.maxDepth else { return }
            for f in childFolders(of: parent) {
                result.append((f, depth))
                walk(f.id, depth + 1)
            }
        }
        walk(nil, 0)
        return result
    }

    func noteCount(in folderID: UUID, recursive: Bool = true) -> Int {
        var count = notes.filter { $0.folderID == folderID }.count
        if recursive {
            for sub in childFolders(of: folderID) {
                count += noteCount(in: sub.id, recursive: true)
            }
        }
        return count
    }

    // MARK: - Baum

    private func childFolders(of parent: UUID?) -> [NoteFolder] {
        folders.filter { $0.parentID == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Die Ablage als Baum. Bei einer Suche entfällt die Struktur und es
    /// erscheinen nur die Treffer – flach, dafür vollständig.
    func tree(search: String = "") -> [NoteTreeItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty else {
            return notes.filter { $0.matches(query) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { NoteTreeItem(kind: .note($0), children: nil) }
        }
        return items(in: nil, depth: 0)
    }

    private func items(in parent: UUID?, depth: Int) -> [NoteTreeItem] {
        guard depth < Self.maxDepth else { return [] }
        let subfolders = childFolders(of: parent).map {
            NoteTreeItem(kind: .folder($0), children: items(in: $0.id, depth: depth + 1))
        }
        let ownNotes = notes.filter { $0.folderID == parent }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { NoteTreeItem(kind: .note($0), children: nil) }
        return subfolders + ownNotes
    }

    var isEmpty: Bool { notes.isEmpty && folders.isEmpty }
}
