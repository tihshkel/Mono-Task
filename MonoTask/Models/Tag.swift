import Foundation
import SwiftData
import SwiftUI

enum CaptureFolderChoice: Equatable {
    case unassigned
    case existing(UUID)
    case newFolder

    func resolve(tags: [Tag], newName: String, taskTitle: String) -> Tag? {
        switch self {
        case .unassigned: return nil
        case .existing(let id): return tags.first { $0.id == id }
        case .newFolder:
            let entered = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name =
                entered.isEmpty ? String(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) : entered
            guard !name.isEmpty else { return nil }
            if let existing = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            }
            return Tag(
                name: name, colorHex: "#6B57C8", iconName: "folder.fill",
                sortOrder: (tags.map(\.sortOrder).max() ?? -1) + 1)
        }
    }
}

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#6B57C8"
    var iconName: String = "tag.fill"
    var scheduledDaysRaw: [Int] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(inverse: \TaskItem.tags)
    var tasks: [TaskItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#6B57C8",
        iconName: String = "tag.fill",
        scheduledDays: [Weekday] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.scheduledDaysRaw = scheduledDays.map(\.rawValue)
        self.sortOrder = sortOrder
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.tasks = []
    }

    func touch() {
        updatedAt = Date.now
    }

    var color: Color {
        Theme.Colors.tagColor(colorHex)
    }

    /// Give existing categories a useful sticker until the user picks their own symbol.
    var folderIconName: String {
        guard iconName == "tag.fill" else { return iconName }
        let title = name.lowercased()
        if ["учё", "уче", "study", "learn"].contains(where: title.contains) { return "graduationcap.fill" }
        if ["проект", "project"].contains(where: title.contains) { return "square.stack.3d.up.fill" }
        if ["работ", "work"].contains(where: title.contains) { return "briefcase.fill" }
        if ["личн", "personal", "дом", "home"].contains(where: title.contains) { return "heart.fill" }
        if ["дизайн", "design", "творч"].contains(where: title.contains) { return "paintpalette.fill" }
        return "square.stack.3d.up.fill"
    }

    var scheduledDays: [Weekday] {
        get {
            scheduledDaysRaw.compactMap { Weekday(rawValue: $0) }
        }
        set {
            scheduledDaysRaw = newValue.map(\.rawValue)
            updatedAt = Date.now
        }
    }
}
