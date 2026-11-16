import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {

    private static let file = "tasks.json"

    @Published private(set) var tasks: [TaskItem] = [] {
        didSet { JSONStore.save(tasks, to: Self.file) }
    }

    init() {
        tasks = JSONStore.load([TaskItem].self, from: Self.file) ?? []
    }

    // MARK: - Mutationen

    @discardableResult
    func add(title: String, notes: String = "", priority: TaskPriority = .normal, dueDate: Date? = nil) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed, notes: notes, priority: priority, dueDate: dueDate)
        tasks.insert(task, at: 0)
        return task
    }

    /// Fügt eine Aufgabe unverändert wieder ein – für „Rückgängig“.
    func reinsert(_ task: TaskItem) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.insert(task, at: 0)
    }

    func setDone(_ task: TaskItem, _ done: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isDone = done
        tasks[idx].completedAt = done ? Date() : nil
    }

    func update(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
    }

    func toggle(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isDone.toggle()
        tasks[idx].completedAt = tasks[idx].isDone ? Date() : nil
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
    }

    func clearCompleted() {
        tasks.removeAll { $0.isDone }
    }

    // MARK: - Abfragen

    var open: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.createdAt > b.createdAt
            }
        }
    }

    var completed: [TaskItem] {
        tasks.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func completedCount(on day: Date) -> Int {
        tasks.filter { $0.isDone && Calendar.current.isDate($0.completedAt ?? .distantPast, inSameDayAs: day) }.count
    }

    var dueToday: [TaskItem] { open.filter { $0.isDueToday || $0.isOverdue } }
}
