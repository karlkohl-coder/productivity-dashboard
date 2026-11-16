import AppKit
import Foundation

// Prüft die Rechenlogik gegen den echten Quelltext: Wochenplan, Notizen
// und den Tagesindex des Trackers.

private var bestanden = 0
private var durchgefallen = 0

private func pruefe(_ name: String, _ bedingung: Bool, _ detail: @autoclosure () -> String = "") {
    if bedingung {
        bestanden += 1
        print("  ok   \(name)")
    } else {
        durchgefallen += 1
        print("  FEHLER \(name) \(detail())")
    }
}

private func tag(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "Europe/Berlin")
    return f.date(from: s)!
}

// MARK: - Wochenplan

@MainActor
private func wochenplan() {
    print("\n── Wochenplan")
    let s = PlanStore()
    for e in s.entries { s.delete(e) }

    var mo = PlanEntry(title: "Analysis")
    mo.weekday = .monday
    mo.startMinute = 10 * 60
    mo.endMinute = 11 * 60 + 30
    mo.createdAt = tag("2026-09-07")
    s.add(mo)
    pruefe("wöchentlich: Montag trifft", s.occurrences(on: tag("2026-09-21")).count == 1)
    pruefe("wöchentlich: Dienstag nicht", s.occurrences(on: tag("2026-09-22")).isEmpty)
    let woche = s.week(of: tag("2026-09-23"))
    pruefe("Woche hat 7 Tage", woche.count == 7)
    pruefe("Woche beginnt montags", Weekday(date: woche[0].day) == .monday)

    for e in s.entries { s.delete(e) }
    var zwei = PlanEntry(title: "Labor")
    zwei.weekday = .wednesday
    zwei.interval = 2
    zwei.startsOn = tag("2026-09-23")
    s.add(zwei)
    pruefe("jede 2. Woche: 23.09. ja", s.occurrences(on: tag("2026-09-23")).count == 1)
    pruefe("jede 2. Woche: 30.09. nein", s.occurrences(on: tag("2026-09-30")).isEmpty)
    pruefe("jede 2. Woche: 07.10. ja", s.occurrences(on: tag("2026-10-07")).count == 1)
    pruefe("vor Gültigkeitsbeginn nichts", s.occurrences(on: tag("2026-09-16")).isEmpty)

    for e in s.entries { s.delete(e) }
    var kurs = PlanEntry(title: "Kurs")
    kurs.weekday = .tuesday
    s.add(kurs)
    s.setSkipped(s.entries[0], on: tag("2026-09-22"), true)
    pruefe("ausgesetzter Termin bleibt sichtbar", s.occurrences(on: tag("2026-09-22")).count == 1)
    pruefe("und ist markiert", s.occurrences(on: tag("2026-09-22")).first?.isSkipped == true)
    pruefe("Folgewoche unberührt", s.occurrences(on: tag("2026-09-29")).first?.isSkipped == false)
    s.setPaused(s.entries[0], true)
    pruefe("ruhende Reihe verschwindet", s.occurrences(on: tag("2026-09-22")).isEmpty)
    pruefe("und steht in der Liste", s.pausedEntries.count == 1)
    s.setPaused(s.entries[0], false)
    pruefe("fortgesetzte Reihe kehrt zurück", s.occurrences(on: tag("2026-09-22")).count == 1)

    for e in s.entries { s.delete(e) }
    var so = PlanEntry(title: "Sonntag")
    so.weekday = .sunday
    so.startMinute = 10 * 60
    so.endMinute = 12 * 60
    s.add(so)
    let umstellung = s.occurrences(on: tag("2026-10-25")).first!
    pruefe("Zeitumstellung: Beginn bleibt 10:00",
           Format.time.string(from: umstellung.start) == "10:00",
           Format.time.string(from: umstellung.start))
    pruefe("Zeitumstellung: Ende bleibt 12:00",
           Format.time.string(from: umstellung.end) == "12:00")

    pruefe("Wochentag Mo", Weekday(date: tag("2026-09-21")) == .monday)
    pruefe("Wochentag So", Weekday(date: tag("2026-09-27")) == .sunday)
}

// MARK: - Notizen

@MainActor
private func notizen() {
    print("\n── Notizen")
    let s = NotesStore()
    for n in s.notes { s.delete(noteID: n.id) }
    for f in s.folders { s.deleteFolder(id: f.id) }

    let uni = s.addFolder(name: "Uni")!
    let sem = s.addFolder(name: "Semester 3", parent: uni.id)!
    let la = s.addFolder(name: "Lineare Algebra", parent: sem.id)!
    let privat = s.addFolder(name: "Privat")!
    pruefe("Pfad über drei Ebenen",
           s.path(of: la.id) == "Uni / Semester 3 / Lineare Algebra", s.path(of: la.id))
    pruefe("ohne Ordner", s.path(of: nil) == "Keine Ablage")

    let n1 = s.addNote(in: la.id)
    s.setContent(title: "Eigenwerte", body: "Spur und Determinante", of: n1.id)
    let n2 = s.addNote(in: la.id)
    s.setContent(title: "Basiswechsel", body: "", of: n2.id)
    _ = s.addNote(in: privat.id)
    _ = s.addNote()

    let baum = s.tree()
    pruefe("Wurzel: 2 Ordner + 1 lose Notiz", baum.count == 3, "\(baum.count)")
    pruefe("Ordner vor Notizen", baum[0].folder != nil && baum[2].note != nil)
    pruefe("Ordner alphabetisch", baum[0].folder?.name == "Privat")
    pruefe("Notizen ohne Kinder", baum[2].children == nil)
    pruefe("Uni rekursiv zählt 2", s.noteCount(in: uni.id) == 2)
    pruefe("Uni direkt zählt 0", s.noteCount(in: uni.id, recursive: false) == 0)

    let vorher = s.notes.count
    s.deleteFolder(id: sem.id)
    pruefe("Ordner löschen verliert keine Notiz", s.notes.count == vorher)
    pruefe("Unterordner rückt hoch", s.folder(id: la.id)?.parentID == uni.id)

    pruefe("kein Ordner in sich selbst", !s.canMove(folderID: uni.id, to: uni.id))
    pruefe("kein Ordner in eigenen Unterordner", !s.canMove(folderID: uni.id, to: la.id))
    pruefe("umgekehrt erlaubt", s.canMove(folderID: la.id, to: privat.id))
    s.move(folderID: uni.id, to: la.id)
    pruefe("verbotener Zug wird verworfen", s.folder(id: uni.id)?.parentID == nil)

    pruefe("Suche im Titel", s.tree(search: "Eigenwerte").count == 1)
    pruefe("Suche im Volltext", s.tree(search: "Determinante").count == 1)
    pruefe("Suche ignoriert Groß-/Kleinschreibung", s.tree(search: "eigenWERTE").count == 1)
    pruefe("Suche liefert flach", s.tree(search: "e").allSatisfy { $0.note != nil })

    let ohne = s.addNote()
    s.setContent(title: "", body: "Erste Zeile\nZweite Zeile", of: ohne.id)
    pruefe("erste Zeile wird Überschrift", s.note(id: ohne.id)?.displayTitle == "Erste Zeile")
    pruefe("Vorschau überspringt sie", s.note(id: ohne.id)?.preview == "Zweite Zeile")
    pruefe("leere Notiz heißt „Ohne Titel“", s.addNote().displayTitle == "Ohne Titel")

    let stempel = s.note(id: n1.id)!.updatedAt
    s.setContent(title: "Eigenwerte", body: "Spur und Determinante", of: n1.id)
    pruefe("unverändertes Schreiben lässt das Datum stehen",
           s.note(id: n1.id)?.updatedAt == stempel)
    s.setContent(title: "Eigenwerte", body: "geändert", of: n1.id)
    pruefe("echte Änderung setzt es neu", s.note(id: n1.id)!.updatedAt > stempel)

    s.setContent(title: "Nur im Speicher", body: "x", of: n2.id)
    pruefe("Tippen schreibt nicht sofort",
           NotesStore().note(id: n2.id)?.title != "Nur im Speicher")
    s.flush()
    pruefe("flush schreibt", NotesStore().note(id: n2.id)?.title == "Nur im Speicher")
    pruefe("Struktur überlebt das Neuladen",
           NotesStore().path(of: la.id) == s.path(of: la.id))
}

// MARK: - Tagesindex des Trackers

@MainActor
private func tagesindex() {
    print("\n── Tagesindex (Statistik-Beschleunigung)")
    let tracker = ActivityTracker()
    tracker.isTracking = false

    // Der Index darf exakt dasselbe liefern wie ein unbeschleunigter Filter.
    // Ohne diese Prüfung fiele eine falsche Tageszuordnung erst in den
    // Statistiken auf – und dort nur als unplausible Zahl.
    func naiv(on day: Date) -> [ActivitySegment] {
        let cal = Calendar.current
        return tracker.segments.filter {
            cal.isDate($0.start, inSameDayAs: day)
                && !ActivityTracker.ignoredBundleIDs.contains($0.bundleID)
        }
    }

    let cal = Calendar.german
    var abweichungen = 0
    var geprueft = 0
    // Ein Jahr abdecken – darin liegen beide Zeitumstellungen.
    for offset in 0..<365 {
        guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
        let a = naiv(on: d).map(\.id).sorted { $0.uuidString < $1.uuidString }
        let b = tracker.segments(on: d).map(\.id).sorted { $0.uuidString < $1.uuidString }
        geprueft += 1
        if a != b { abweichungen += 1 }
    }
    pruefe("Index stimmt an \(geprueft) Tagen mit dem Filter überein",
           abweichungen == 0, "\(abweichungen) Abweichungen")

    // Der Index muss veralten, sobald sich die Segmente ändern.
    let vorherRevision = tracker.revision
    tracker.clearHistory()
    pruefe("Änderung erhöht die Revision", tracker.revision > vorherRevision)
    pruefe("Index nach dem Leeren leer", tracker.segments(on: Date()).isEmpty)
}

@main
struct Logik {
    static func main() {
        MainActor.assumeIsolated {
            wochenplan()
            notizen()
            tagesindex()
            print("\n\(bestanden) bestanden, \(durchgefallen) fehlgeschlagen")
        }
        exit(durchgefallen == 0 ? 0 : 1)
    }
}
