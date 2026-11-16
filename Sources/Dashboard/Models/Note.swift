import Foundation

/// Ein Ordner in der Notizenablage. Ordner dürfen ineinander liegen –
/// `parentID == nil` bedeutet: direkt auf der obersten Ebene.
struct NoteFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var parentID: UUID?
    var createdAt = Date()
}

/// Eine Notizseite.
struct Note: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var body: String = ""
    /// `nil` = liegt in keinem Ordner.
    var folderID: UUID?
    var createdAt = Date()
    var updatedAt = Date()

    /// Überschrift für die Liste. Ist kein Titel gesetzt, dient die erste
    /// Textzeile als Ersatz – so muss niemand erst einen Titel tippen,
    /// bevor eine Notiz wiederzufinden ist.
    var displayTitle: String {
        let own = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? "Ohne Titel" : String(firstLine.prefix(60))
    }

    /// Zweite Zeile in der Liste: Textanfang ohne den Teil, der schon als
    /// Überschrift dient.
    var preview: String {
        var text = body
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Die erste Zeile steht bereits oben – sie hier zu wiederholen
            // sähe nach einem Fehler aus.
            text = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst().first.map(String.init) ?? ""
        }
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(120))
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var wordCount: Int { Note.wordCount(of: body) }

    static func wordCount(of text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || body.localizedCaseInsensitiveContains(query)
    }
}

/// Ein Knoten der Ablage – Ordner oder Notiz. Daraus baut die Liste ihre
/// aufklappbare Struktur.
struct NoteTreeItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(NoteFolder)
        case note(Note)
    }

    let kind: Kind
    /// `nil` bei Notizen – nur dann zeigt die Liste kein Aufklapp-Dreieck.
    var children: [NoteTreeItem]?

    /// Zusammengesetzt, weil Ordner und Notizen in derselben Auswahl liegen.
    var id: String {
        switch kind {
        case .folder(let f): return "f-\(f.id.uuidString)"
        case .note(let n):   return "n-\(n.id.uuidString)"
        }
    }

    var folder: NoteFolder? {
        if case .folder(let f) = kind { return f }
        return nil
    }

    var note: Note? {
        if case .note(let n) = kind { return n }
        return nil
    }

    // MARK: - Auswahlschlüssel

    static func key(for note: Note) -> String { "n-\(note.id.uuidString)" }
    static func key(for folder: NoteFolder) -> String { "f-\(folder.id.uuidString)" }

    static func noteID(from key: String?) -> UUID? {
        guard let key, key.hasPrefix("n-") else { return nil }
        return UUID(uuidString: String(key.dropFirst(2)))
    }

    static func folderID(from key: String?) -> UUID? {
        guard let key, key.hasPrefix("f-") else { return nil }
        return UUID(uuidString: String(key.dropFirst(2)))
    }
}
