import Foundation
import SwiftData

var checks = 0
@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

@MainActor
func run() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let schema = Schema([TaskItem.self, Tag.self, SubtaskItem.self])
    let config = ModelConfiguration(
        schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
    func seed() throws {
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let tag = Tag(name: "Work", scheduledDays: [Weekday.current])
        let otherTag = Tag(name: "Personal")
        context.insert(tag)
        context.insert(otherTag)
        let task = TaskItem(title: "Persisted", notes: "Notes", isHighPriorityToday: true, tags: [tag])
        task.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        task.reminderMinutesBefore = 120
        task.reminderSyncPending = true
        context.insert(task)
        let first = SubtaskItem(title: "First", isCompleted: true, sortOrder: 0)
        let second = SubtaskItem(title: "Second", sortOrder: 1)
        context.insert(first)
        context.insert(second)
        task.subtasks = [first, second]
        try context.save()
    }
    try seed()
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let task = try context.fetch(FetchDescriptor<TaskItem>()).first!
    check(
        task.reminderMinutesBefore == 120 && task.reminderSyncPending,
        "Reminder timing and pending sync survive reopening the store")
    check(
        task.scheduledReminderDate == task.dueDate?.addingTimeInterval(-7_200),
        "Compute the early reminder separately from its deadline")
    let preservedDeadline = task.dueDate
    task.reminderMinutesBefore = nil
    try context.save()
    check(
        task.scheduledReminderDate == nil && task.dueDate == preservedDeadline,
        "Turning reminders off preserves the calendar deadline")
    let tags = try context.fetch(FetchDescriptor<Tag>())
    let work = tags.first { $0.name == "Work" }!
    let personal = tags.first { $0.name == "Personal" }!
    check(
        CaptureFolderChoice.existing(work.id).resolve(tags: tags, newName: "", taskTitle: "Task") === work,
        "Capture assigns the selected folder")
    check(
        CaptureFolderChoice.unassigned.resolve(tags: tags, newName: "", taskTitle: "Task") == nil,
        "Capture can leave a task unassigned")
    let automatic = CaptureFolderChoice.newFolder.resolve(tags: tags, newName: "", taskTitle: "  New task  ")!
    check(
        automatic.name == "New task" && automatic.modelContext == nil,
        "Automatic folders use the title and remain unsaved until submission")
    check(
        CaptureFolderChoice.newFolder.resolve(tags: tags, newName: " work ", taskTitle: "Task") === work,
        "Reuse a matching folder instead of duplicating it")
    check(
        CaptureFolderChoice.newFolder.resolve(tags: tags, newName: "", taskTitle: "   ") == nil,
        "Empty capture does not create a folder")
    check(task.title == "Persisted" && task.notes == "Notes", "Title and notes survive reopening a disk store")
    check(
        task.tags.first?.id == work.id && work.tasks.contains { $0.id == task.id },
        "Category inverse relationship survives reopening")
    check(task.sortedSubtasks.map(\.title) == ["First", "Second"], "Subtask order survives reopening")
    check(task.subtasksProgress == 0.5, "Subtask completion survives reopening")
    check(work.scheduledDays == [Weekday.current], "Category schedule survives reopening")
    task.bucket = .done
    check(task.isDone && task.completedAt != nil, "Completing a task records its completion date")
    try context.save()
    let reloaded = ModelContext(container)
    let completed = try reloaded.fetch(FetchDescriptor<TaskItem>()).first!
    check(completed.isDone && completed.completedAt != nil, "Completion is persisted")
    task.bucket = .inbox
    check(
        !task.isDone && task.completedAt == nil && task.isPendingOfflineSync,
        "Undoing completion clears the date and queues synchronization")
    let untagged = TaskItem(title: "Untagged")
    let other = TaskItem(title: "Other", tags: [personal])
    context.insert(untagged)
    context.insert(other)
    let all = [task, untagged, other]
    check(
        Set(TaskScope.focus.filter(all, scheduledTags: [work]).map(\.id)) == Set([task.id, untagged.id]),
        "Focus includes scheduled and untagged tasks")
    check(TaskScope.focus.filter(all, scheduledTags: []).count == 3, "Focus without a schedule falls back to all tasks")
    check(
        TaskScope.highPriority.filter(all, scheduledTags: []).map(\.id) == [task.id],
        "Priority filter preserves only flagged tasks")
    check(
        TaskScope.tag(personal.id).filter(all, scheduledTags: []).map(\.id) == [other.id],
        "Category filter excludes unrelated tasks")
    check(TaskScope.tag(UUID()).validated(tags: tags) == .focus, "Missing category falls back to focus")
    check(
        TaskScope.all.defaultTag(tags: tags, scheduledTags: [work]) == nil,
        "Adding to all tasks does not silently assign a category")
    check(
        FocusService.shared.currentFocusTags(allTags: tags, override: personal).first?.id == personal.id,
        "Manual focus override takes precedence")
    context.delete(task)
    try context.save()
    let subtasks = try context.fetch(FetchDescriptor<SubtaskItem>())
    check(subtasks.isEmpty, "Deleting a task cascades to its subtasks")
    let categoryCount = try context.fetchCount(FetchDescriptor<Tag>())
    check(categoryCount == 2, "Deleting a task keeps its categories")
    context.delete(personal)
    try context.save()
    check(other.tags.isEmpty, "Deleting a category unlinks tasks without deleting them")
    let taskCount = try context.fetchCount(FetchDescriptor<TaskItem>())
    check(taskCount == 2, "Tasks survive category deletion")
    print("Passed \(checks) model and disk persistence checks")
}
try run()
