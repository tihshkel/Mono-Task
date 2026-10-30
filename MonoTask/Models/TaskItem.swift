import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var bucketRaw: String = Bucket.inbox.rawValue
    var priorityRaw: String = Priority.none.rawValue
    var isHighPriorityToday: Bool = false
    var createdAt: Date = Date.now
    var completedAt: Date?
    var dueDate: Date?
    /// nil disables the reminder without removing the deadline; zero preserves legacy reminders at the deadline.
    var reminderMinutesBefore: Int? = 0
    var reminderSyncPending: Bool = false
    var sortOrder: Int = 0
    var updatedAt: Date = Date.now

    // Cloud storage & offline sync tracking
    var serverUpdatedAt: Date? = nil
    var isPendingOfflineSync: Bool = false

    @Relationship
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade)
    var subtasks: [SubtaskItem] = []

    init(
        title: String,
        notes: String = "",
        bucket: Bucket = .inbox,
        priority: Priority = .none,
        isHighPriorityToday: Bool = false,
        dueDate: Date? = nil,
        reminderMinutesBefore: Int? = 0,
        tags: [Tag] = [],
        subtasks: [SubtaskItem] = []
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.bucketRaw = bucket.rawValue
        self.priorityRaw = priority.rawValue
        self.isHighPriorityToday = isHighPriorityToday
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.serverUpdatedAt = nil
        self.isPendingOfflineSync = true
        self.completedAt = nil
        self.dueDate = dueDate
        self.reminderMinutesBefore = reminderMinutesBefore
        self.sortOrder = 0
        self.tags = tags
        self.subtasks = subtasks
    }

    func touch() {
        updatedAt = Date.now
        isPendingOfflineSync = true
    }

    var scheduledReminderDate: Date? {
        guard let dueDate, let minutes = reminderMinutesBefore, (0...525_600).contains(minutes) else { return nil }
        return dueDate.addingTimeInterval(-Double(minutes) * 60)
    }

    var bucket: Bucket {
        get { Bucket(rawValue: bucketRaw) ?? .inbox }
        set {
            bucketRaw = newValue.rawValue
            updatedAt = Date.now
            isPendingOfflineSync = true
            if newValue == .done && completedAt == nil {
                completedAt = Date.now
            } else if newValue != .done {
                completedAt = nil
            }
        }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set {
            priorityRaw = newValue.rawValue
            updatedAt = Date.now
            isPendingOfflineSync = true
        }
    }

    var isDone: Bool {
        bucket == .done
    }

    var subtasksCount: Int {
        subtasks.count
    }

    var completedSubtasksCount: Int {
        subtasks.filter(\.isCompleted).count
    }

    var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    var subtasksProgress: Double {
        hasSubtasks ? Double(completedSubtasksCount) / Double(subtasksCount) : 0
    }

    var sortedSubtasks: [SubtaskItem] {
        subtasks.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}
