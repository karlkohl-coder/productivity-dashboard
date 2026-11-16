import Foundation

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case low = 0, normal = 1, high = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: return "Niedrig"
        case .normal: return "Normal"
        case .high: return "Hoch"
        }
    }

    static func < (a: TaskPriority, b: TaskPriority) -> Bool { a.rawValue < b.rawValue }
}

struct TaskItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var isDone: Bool = false
    var priority: TaskPriority = .normal
    var dueDate: Date?
    var createdAt: Date = Date()
    var completedAt: Date?

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}
