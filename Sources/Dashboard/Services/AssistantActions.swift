import Foundation
import SwiftUI

/// Eine Änderung, die die Assistenz am Dashboard vorgenommen hat.
///
/// Jede Änderung wird protokolliert und unter der Antwort angezeigt. Damit
/// hängt nichts an der Behauptung des Modells: sichtbar ist, was tatsächlich
/// passiert ist – und das meiste lässt sich zurücknehmen.
struct AssistantAction: Identifiable {
    enum Kind {
        case created, deleted, changed

        var symbol: String {
            switch self {
            case .created: return "plus.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .changed: return "pencil.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .created: return Theme.Palette.productive
            case .deleted: return Theme.Palette.unproductive
            case .changed: return Theme.Palette.accent
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let text: String
    /// Nimmt die Änderung zurück. Nil, wenn das nicht möglich ist.
    let undo: (() -> Void)?
    var undone = false
}

/// Sammelt die Änderungen eines Gesprächszugs.
@MainActor
final class ActionLog {
    private(set) var actions: [AssistantAction] = []

    func record(_ kind: AssistantAction.Kind, _ text: String, undo: (() -> Void)? = nil) {
        actions.append(AssistantAction(kind: kind, text: text, undo: undo))
    }

    /// Gibt die seither gesammelten Änderungen zurück und leert das Protokoll.
    func drain() -> [AssistantAction] {
        defer { actions.removeAll() }
        return actions
    }
}
