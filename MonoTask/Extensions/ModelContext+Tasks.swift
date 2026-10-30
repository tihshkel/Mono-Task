import Foundation
import SwiftData

extension ModelContext {
    @MainActor
    @discardableResult
    func createTask(title: String, folder: CaptureFolderChoice, newFolderName: String, tags: [Tag], highPriority: Bool)
        -> TaskItem?
    {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let tag = folder.resolve(tags: tags, newName: newFolderName, taskTitle: title)
        if let tag, !tags.contains(where: { $0.id == tag.id }) { insert(tag) }
        return createTask(title: title, tag: tag, highPriority: highPriority)
    }

    /// Creates a task from a capture bar and schedules a sync.
    @MainActor
    @discardableResult
    func createTask(title: String, tag: Tag?, highPriority: Bool) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let task = TaskItem(
            title: trimmed,
            bucket: .todo,
            priority: highPriority ? .high : .none,
            isHighPriorityToday: highPriority,
            tags: tag.map { [$0] } ?? []
        )
        insert(task)
        saveAndSync(delaySeconds: 0.3)
        return task
    }

    /// Moves `sourceId` to the position of `targetId` in the global `ordered` list.
    /// Only tasks whose `sortOrder` actually changes are marked for sync.
    @MainActor
    func reorderTask(_ sourceId: UUID, onto targetId: UUID, in ordered: [TaskItem], highPriority: Bool? = nil) {
        guard let fromIndex = ordered.firstIndex(where: { $0.id == sourceId }),
            let toIndex = ordered.firstIndex(where: { $0.id == targetId }),
            fromIndex != toIndex
        else { return }

        var updated = ordered
        let moved = updated.remove(at: fromIndex)
        updated.insert(moved, at: toIndex)

        if let highPriority, moved.isHighPriorityToday != highPriority {
            moved.isHighPriorityToday = highPriority
            moved.touch()
        }

        for (index, task) in updated.enumerated() where task.sortOrder != index {
            task.sortOrder = index
            task.touch()
        }
        saveAndSync(delaySeconds: 0.4)
    }

    /// Moves a task to a single context (or removes its context when `tag` is nil).
    @MainActor
    func assign(_ task: TaskItem, to tag: Tag?) {
        let newTags = tag.map { [$0] } ?? []
        guard task.tags.map(\.id) != newTags.map(\.id) else { return }
        task.tags = newTags
        task.touch()
        saveAndSync(delaySeconds: 0.3)
    }

    @MainActor
    func toggleHighPriority(_ task: TaskItem) {
        task.isHighPriorityToday.toggle()
        task.touch()
        saveAndSync(delaySeconds: 0.3)
    }

    /// Deletes the given completed tasks. Completion history stays for the heatmap.
    @MainActor
    func clearCompleted(_ tasks: [TaskItem]) {
        TaskDeletionManager.shared.requestDelete(tasks.filter(\.isDone), context: self)
    }
}
