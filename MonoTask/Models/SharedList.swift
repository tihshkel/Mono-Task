import Foundation

struct SharedList: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var ownerID: UUID
    var createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title
        case ownerID = "owner_id"
        case createdAt = "created_at"
    }
}

struct SharedMember: Codable, Hashable, Identifiable, Sendable {
    var listID: UUID
    var userID: UUID
    var displayName: String
    var id: UUID { userID }
    var initials: String {
        Self.initials(for: displayName)
    }
    static func initials(for displayName: String) -> String {
        let name = displayName.split(separator: "@").first.map(String.init) ?? ""
        let parts = name.split { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" }
        let letters = parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }
    var avatarColorIndex: Int {
        userID.uuidString.utf8.reduce(0) { ($0 + Int($1)) % 3 }
    }
    enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case userID = "user_id"
        case displayName = "display_name"
    }
}

struct SharedSubtask: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var isDone = false
    enum CodingKeys: String, CodingKey {
        case id, title
        case isDone = "is_done"
    }
}

struct SharedTask: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var listID: UUID
    var title: String
    var notes = ""
    var isDone = false
    var isHighPriority = false
    var assigneeID: UUID?
    var subtasks: [SharedSubtask] = []
    var revision = 0
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?
    func hasSameContent(as other: SharedTask) -> Bool {
        id == other.id && listID == other.listID && title == other.title && notes == other.notes
            && isDone == other.isDone && isHighPriority == other.isHighPriority
            && assigneeID == other.assigneeID && subtasks == other.subtasks
            && (deletedAt != nil) == (other.deletedAt != nil)
    }
    enum CodingKeys: String, CodingKey {
        case id, title, notes, subtasks, revision
        case listID = "list_id"
        case isDone = "is_done"
        case isHighPriority = "is_high_priority"
        case assigneeID = "assignee_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct SharedSnapshot: Codable, Sendable {
    var lists: [SharedList] = []
    var members: [SharedMember] = []
    var tasks: [SharedTask] = []
}

struct SharedInvite: Codable, Sendable {
    var code: String
    var expiresAt: Date
    var url: URL { URL(string: "https://egoar777.github.io/MonoTask/join/#\(code)")! }
    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
    static func parseCode(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if let parts = URLComponents(string: trimmed), parts.scheme == "com.monotask.ios", parts.host == "join" {
            value = parts.queryItems?.first { $0.name == "code" }?.value ?? ""
        } else if let parts = URLComponents(string: trimmed), parts.scheme == "https",
            parts.host == "egoar777.github.io", parts.port == nil,
            parts.user == nil, parts.password == nil, parts.path == "/MonoTask/join/", parts.query == nil
        {
            value = parts.fragment ?? ""
        } else {
            value = trimmed
        }
        let lower = value.lowercased()
        guard lower.count == 32, lower.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return lower
    }
}

struct PendingSharedTask: Codable, Sendable {
    var mutationID = UUID()
    var task: SharedTask
    var remoteVersion: SharedTask?
}

/// Per-account offline cache; personal SwiftData models never enter this payload.
struct SharedCache: Codable, Sendable {
    var snapshot = SharedSnapshot()
    var pending: [PendingSharedTask] = []

    mutating func queue(_ task: SharedTask) {
        let remote = pending.first { $0.task.id == task.id }?.remoteVersion
        pending.removeAll { $0.task.id == task.id }
        pending.append(PendingSharedTask(task: task, remoteVersion: remote))
        snapshot.tasks.removeAll { $0.id == task.id }
        snapshot.tasks.append(task)
    }

    mutating func acknowledge(_ sent: PendingSharedTask, saved: SharedTask) {
        if let index = pending.firstIndex(where: { $0.task.id == sent.task.id }) {
            if pending[index].mutationID == sent.mutationID {
                pending.remove(at: index)
            } else {
                // An edit made while this RPC was in flight must be sent against its new revision.
                pending[index].task.revision = saved.revision
            }
        }
        snapshot.tasks.removeAll { $0.id == saved.id }
        snapshot.tasks.append(pending.first { $0.task.id == saved.id }?.task ?? saved)
    }

    mutating func reconcile(_ remote: SharedSnapshot) {
        let allowed = Set(remote.lists.map(\.id))
        pending.removeAll { !allowed.contains($0.task.listID) }
        // A lost HTTP response can replay an already committed edit. Identical content is an acknowledgement.
        pending.removeAll { edit in
            remote.tasks.contains { $0.hasSameContent(as: edit.task) }
        }
        for index in pending.indices {
            if let assignee = pending[index].task.assigneeID,
                !remote.members.contains(where: { $0.listID == pending[index].task.listID && $0.userID == assignee })
            {
                pending[index].task.assigneeID = nil
            }
            if let task = remote.tasks.first(where: { $0.id == pending[index].task.id }),
                task.revision != pending[index].task.revision
            {
                pending[index].remoteVersion = task
            }
        }
        snapshot = remote
        for entry in pending {
            snapshot.tasks.removeAll { $0.id == entry.task.id }
            snapshot.tasks.append(entry.task)
        }
    }

    mutating func resolve(_ id: UUID, keepLocal: Bool) {
        guard let edit = pending.first(where: { $0.task.id == id }), let remote = edit.remoteVersion else { return }
        pending.removeAll { $0.task.id == id }
        snapshot.tasks.removeAll { $0.id == id }
        if keepLocal {
            var task = edit.task
            if remote.deletedAt != nil {
                task.id = UUID()
                task.revision = 0
                task.deletedAt = nil
            } else {
                task.revision = remote.revision
            }
            queue(task)
        } else {
            snapshot.tasks.append(remote)
        }
    }
}
