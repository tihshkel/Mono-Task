import Foundation

// MARK: - Tag DTO

struct TagDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let iconName: String
    let scheduledDays: [Int]
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case scheduledDays = "scheduled_days"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        name: String,
        colorHex: String = "#6366F1",
        iconName: String = "tag.fill",
        scheduledDays: [Int] = [],
        sortOrder: Int = 0,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.scheduledDays = scheduledDays
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Категория"
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#6366F1"
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "tag.fill"
        self.scheduledDays = try container.decodeIfPresent([Int].self, forKey: .scheduledDays) ?? []
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Task Item DTO

struct TaskItemDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let notes: String
    let bucketRaw: String
    let priorityRaw: String
    let isHighPriorityToday: Bool
    let createdAt: Date
    let completedAt: Date?
    let dueDate: Date?
    let reminderMinutesBefore: Int?
    var includesReminderTiming = true
    let sortOrder: Int
    let tagIds: [UUID]
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case bucketRaw = "bucket_raw"
        case priorityRaw = "priority_raw"
        case isHighPriorityToday = "is_high_priority_today"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case dueDate = "due_date"
        case reminderMinutesBefore = "reminder_minutes_before"
        case sortOrder = "sort_order"
        case tagIds = "tag_ids"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        title: String,
        notes: String = "",
        bucketRaw: String = "todo",
        priorityRaw: String = "none",
        isHighPriorityToday: Bool = false,
        createdAt: Date = Date.now,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        reminderMinutesBefore: Int? = 0,
        sortOrder: Int = 0,
        tagIds: [UUID] = [],
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.bucketRaw = bucketRaw
        self.priorityRaw = priorityRaw
        self.isHighPriorityToday = isHighPriorityToday
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.reminderMinutesBefore = reminderMinutesBefore
        self.sortOrder = sortOrder
        self.tagIds = tagIds
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.bucketRaw = try container.decodeIfPresent(String.self, forKey: .bucketRaw) ?? "todo"
        self.priorityRaw = try container.decodeIfPresent(String.self, forKey: .priorityRaw) ?? "none"
        self.isHighPriorityToday = try container.decodeIfPresent(Bool.self, forKey: .isHighPriorityToday) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        includesReminderTiming = container.contains(.reminderMinutesBefore)
        self.reminderMinutesBefore =
            includesReminderTiming
            ? try container.decodeIfPresent(Int.self, forKey: .reminderMinutesBefore) : 0
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.tagIds = try container.decodeIfPresent([UUID].self, forKey: .tagIds) ?? []
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(bucketRaw, forKey: .bucketRaw)
        try container.encode(priorityRaw, forKey: .priorityRaw)
        try container.encode(isHighPriorityToday, forKey: .isHighPriorityToday)
        try container.encode(createdAt, forKey: .createdAt)
        // Explicit nulls clear removed deadlines/reminders on other devices.
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(dueDate, forKey: .dueDate)
        if includesReminderTiming { try container.encode(reminderMinutesBefore, forKey: .reminderMinutesBefore) }
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(tagIds, forKey: .tagIds)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

}

// MARK: - Subtask Item DTO

struct SubtaskItemDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let taskId: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case title
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        taskId: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int = 0,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.taskId = try container.decode(UUID.self, forKey: .taskId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Daily Note DTO

struct DailyNoteDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let wins: String
    let losses: String
    let reason: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case wins
        case losses
        case reason
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        date: Date,
        wins: String = "",
        losses: String = "",
        reason: String = "",
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.wins = wins
        self.losses = losses
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date.now
        self.wins = try container.decodeIfPresent(String.self, forKey: .wins) ?? ""
        self.losses = try container.decodeIfPresent(String.self, forKey: .losses) ?? ""
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Weekly Review DTO

struct WeeklyReviewDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let weekStartDate: Date
    let summary: String
    let improvements: String
    let completedTasksCount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case weekStartDate = "week_start_date"
        case summary
        case improvements
        case completedTasksCount = "completed_tasks_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        weekStartDate: Date,
        summary: String = "",
        improvements: String = "",
        completedTasksCount: Int = 0,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.summary = summary
        self.improvements = improvements
        self.completedTasksCount = completedTasksCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.weekStartDate = try container.decodeIfPresent(Date.self, forKey: .weekStartDate) ?? Date.now
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.improvements = try container.decodeIfPresent(String.self, forKey: .improvements) ?? ""
        self.completedTasksCount = try container.decodeIfPresent(Int.self, forKey: .completedTasksCount) ?? 0
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Focus Schedule DTO

struct FocusScheduleDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let weekdayRaw: Int
    let tagId: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case weekdayRaw = "weekday_raw"
        case tagId = "tag_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        weekdayRaw: Int,
        tagId: UUID? = nil,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.weekdayRaw = weekdayRaw
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.weekdayRaw = try container.decodeIfPresent(Int.self, forKey: .weekdayRaw) ?? 1
        self.tagId = try container.decodeIfPresent(UUID.self, forKey: .tagId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Activity Entry DTO

struct ActivityEntryDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let tagId: UUID?
    let count: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case tagId = "tag_id"
        case count
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        date: Date,
        tagId: UUID? = nil,
        count: Int = 1,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.tagId = tagId
        self.count = count
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date.now
        self.tagId = try container.decodeIfPresent(UUID.self, forKey: .tagId)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Completed History Entry DTO

struct CompletedHistoryEntryDTO: Codable, Identifiable, Sendable {
    let id: UUID
    let taskId: UUID
    let tagId: UUID?
    let completedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case tagId = "tag_id"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        taskId: UUID,
        tagId: UUID? = nil,
        completedAt: Date = Date.now,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.tagId = tagId
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.taskId = try container.decode(UUID.self, forKey: .taskId)
        self.tagId = try container.decodeIfPresent(UUID.self, forKey: .tagId)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date.now
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.now
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
