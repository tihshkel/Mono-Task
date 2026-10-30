import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class SharedListStore {
    static let shared = SharedListStore()
    private(set) var cache = SharedCache()
    private(set) var accountID: UUID?
    private(set) var isSyncing = false
    private(set) var isMutating = false
    private(set) var isAvailable = false
    private(set) var errorMessage: String?
    var isPresented = false
    var pendingInviteCode: String?
    private(set) var invitations: [UUID: SharedInvite] = [:]
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var requestToken: UUID?
    @ObservationIgnored private var actionToken: UUID?

    static var isPreview: Bool {
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        return ProcessInfo.processInfo.arguments.contains("--screenshots")
            && ProcessInfo.processInfo.arguments.contains("--shared-preview")
        #else
        return false
        #endif
    }

    var lists: [SharedList] { cache.snapshot.lists }
    var pendingCount: Int { cache.pending.count }
    var canManage: Bool { !isMutating && (Self.isPreview || NetworkMonitor.shared.isConnected) && isAvailable }

    func members(in list: UUID) -> [SharedMember] {
        cache.snapshot.members.filter { $0.listID == list }.sorted { $0.displayName < $1.displayName }
    }
    func tasks(in list: UUID) -> [SharedTask] {
        cache.snapshot.tasks.filter { $0.listID == list && $0.deletedAt == nil }.sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            if $0.isHighPriority != $1.isHighPriority { return $0.isHighPriority }
            return $0.createdAt < $1.createdAt
        }
    }
    func conflicts(in list: UUID) -> [PendingSharedTask] {
        cache.pending.filter { $0.task.listID == list && $0.remoteVersion != nil }
    }

    func activateAccount() {
        let owner: UUID?
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        owner = Self.isPreview ? SharedPreviewFixtures.ownerID : AuthManager.shared.userID
        #else
        owner = AuthManager.shared.userID
        #endif
        guard owner != accountID else { return }
        request?.cancel()
        request = nil
        requestToken = nil
        actionToken = nil
        isSyncing = false
        isMutating = false
        isAvailable = false
        errorMessage = nil
        cache = SharedCache()
        invitations = [:]
        accountID = owner
        guard let owner else { return }
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        if Self.isPreview {
            cache.snapshot = SharedPreviewFixtures.snapshot
            isAvailable = true
            return
        }
        #endif
        if let data = try? Data(contentsOf: cacheURL(for: owner)),
            let saved = try? JSONDecoder().decode(SharedCache.self, from: data)
        {
            cache = saved
        }
    }

    func receiveInvitation(_ url: URL) -> Bool {
        guard url.scheme == "com.monotask.ios", url.host == "join" else { return false }
        pendingInviteCode = SharedInvite.parseCode(url.absoluteString)
        isPresented = pendingInviteCode != nil
        return true
    }

    func sync(force: Bool = false) async {
        activateAccount()
        guard let owner = accountID else { return }
        if let request {
            let waitingToken = requestToken
            await request.value
            guard force, owns(owner) else { return }
            if requestToken == waitingToken {
                self.request = nil
                requestToken = nil
            } else if let newer = self.request {
                await newer.value
                return
            }
        }
        let token = UUID()
        requestToken = token
        let task = Task { @MainActor in await self.performSync(owner: owner) }
        request = task
        await task.value
        if requestToken == token { request = nil; requestToken = nil }
    }

    private func performSync(owner: UUID) async {
        guard owns(owner) else { return }
        isSyncing = true
        defer { if owns(owner) { isSyncing = false } }
        if Self.isPreview {
            for entry in cache.pending where entry.remoteVersion == nil {
                var saved = entry.task
                saved.revision += 1
                cache.acknowledge(entry, saved: saved)
                cache.snapshot.tasks.removeAll { $0.id == saved.id }
                cache.snapshot.tasks.append(saved)
            }
            errorMessage = nil
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            errorMessage = "Нет сети. Изменения сохраняются на устройстве и отправятся после подключения."
            return
        }
        do {
            let client = try await client(for: owner)
            // Keep conflicts pending until a person explicitly chooses a version.
            var pendingError: String?
            for edit in cache.pending where edit.remoteVersion == nil {
                do {
                    let saved: SharedTask = try await client.rpc(
                        "monotask_shared_save_task", params: SharedTaskRequest(task: edit.task)
                    ).execute().value
                    guard owns(owner) else { return }
                    cache.acknowledge(edit, saved: saved)
                    persist()
                } catch {
                    let raw = String(describing: error)
                    if !raw.contains("SHARED_CONFLICT") && !raw.contains("SHARED_DELETED") {
                        pendingError = Self.message(for: error)
                    }
                }
            }
            let remote: SharedSnapshot = try await client.rpc("monotask_shared_snapshot").execute().value
            guard owns(owner) else { return }
            cache.reconcile(remote)
            invitations = invitations.filter { id, _ in remote.lists.contains { $0.id == id && $0.ownerID == owner } }
            isAvailable = true
            errorMessage = pendingError
            persist()
        } catch {
            guard owns(owner) else { return }
            errorMessage = Self.message(for: error)
            if String(describing: error).contains("PGRST202") { isAvailable = false }
        }
    }

    func save(_ task: SharedTask) {
        guard let owner = accountID, owns(owner), lists.contains(where: { $0.id == task.listID }) else { return }
        var edited = task
        edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.title.isEmpty else { return }
        edited.updatedAt = .now
        cache.queue(edited)
        persist()
    }

    func resolve(_ id: UUID, keepLocal: Bool) {
        cache.resolve(id, keepLocal: keepLocal)
        persist()
    }

    func createList(title: String) async throws -> UUID {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 100 else { throw SharedError.invalidTitle }
        if Self.isPreview, let owner = accountID {
            let list = SharedList(id: UUID(), title: trimmed, ownerID: owner, createdAt: .now)
            cache.snapshot.lists.append(list)
            cache.snapshot.members.append(SharedMember(listID: list.id, userID: owner, displayName: "Вы"))
            return list.id
        }
        let id: UUID = try await action { client in
            try await client.rpc("monotask_shared_create_list", params: ["p_title": trimmed]).execute().value
        }
        await sync(force: true)
        return id
    }

    func join(code: String) async throws -> UUID {
        guard let code = SharedInvite.parseCode(code) else { throw SharedError.invalidInvite }
        if Self.isPreview, let first = lists.first { pendingInviteCode = nil; return first.id }
        let id: UUID = try await action { client in
            try await client.rpc("monotask_shared_join", params: ["p_code": code]).execute().value
        }
        pendingInviteCode = nil
        await sync(force: true)
        return id
    }

    func createInvite(listID: UUID) async throws -> SharedInvite {
        if Self.isPreview {
            let invite = SharedInvite(
                code: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                expiresAt: .now.addingTimeInterval(72 * 3600))
            invitations[listID] = invite
            return invite
        }
        let invite: SharedInvite = try await action { client in
            try await client.rpc("monotask_shared_create_invite", params: ["p_list_id": listID.uuidString]).execute()
                .value
        }
        invitations[listID] = invite
        return invite
    }

    func removeMember(_ member: SharedMember) async throws {
        if Self.isPreview {
            cache.snapshot.members.removeAll { $0.listID == member.listID && $0.userID == member.userID }
            for index in cache.snapshot.tasks.indices
            where cache.snapshot.tasks[index].listID == member.listID
                && cache.snapshot.tasks[index].assigneeID == member.userID
            {
                cache.snapshot.tasks[index].assigneeID = nil
            }
            return
        }
        try await action { client in
            _ = try await client.rpc(
                "monotask_shared_remove_member",
                params: ["p_list_id": member.listID.uuidString, "p_user_id": member.userID.uuidString]
            ).execute()
        }
        await sync(force: true)
    }

    func updateList(_ list: SharedList, title: String, delete: Bool = false) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 100 else { throw SharedError.invalidTitle }
        if Self.isPreview {
            if delete {
                cache.snapshot.lists.removeAll { $0.id == list.id }
            } else if let index = cache.snapshot.lists.firstIndex(where: { $0.id == list.id }) {
                cache.snapshot.lists[index].title = trimmed
            }
            return
        }
        try await action { client in
            _ = try await client.rpc(
                "monotask_shared_update_list",
                params: SharedListRequest(p_list_id: list.id, p_title: trimmed, p_deleted: delete)
            ).execute()
        }
        await sync(force: true)
    }

    private func action<T>(_ operation: (SupabaseClient) async throws -> T) async throws -> T {
        guard let owner = accountID, owns(owner) else { throw SharedError.auth }
        guard !isMutating else { throw SharedError.busy }
        guard NetworkMonitor.shared.isConnected else { throw SharedError.offline }
        let token = UUID()
        actionToken = token
        isMutating = true
        defer { if actionToken == token { isMutating = false } }
        do {
            let scopedClient = try await client(for: owner)
            let value = try await operation(scopedClient)
            guard owns(owner) else { throw SharedError.auth }
            return value
        } catch { throw SharedError.server(Self.message(for: error)) }
    }

    private func client(for owner: UUID) async throws -> SupabaseClient {
        guard let authClient = SupabaseService.shared.client, let url = SupabaseConfig.shared.cleanUrl else {
            throw SharedError.unavailable
        }
        let session = try await authClient.auth.session
        guard session.user.id == owner, owns(owner) else { throw SharedError.auth }
        let token = session.accessToken
        return SupabaseClient(
            supabaseURL: url, supabaseKey: SupabaseConfig.shared.anonKey,
            options: .init(auth: .init(accessToken: { token })))
    }
    private func owns(_ id: UUID) -> Bool { accountID == id && (Self.isPreview || AuthManager.shared.userID == id) }
    private func cacheURL(for id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "MonoTask/SharedLists/\(id.uuidString).json")
    }
    private func persist() {
        guard !Self.isPreview, let owner = accountID, owns(owner) else { return }
        do {
            let url = cacheURL(for: owner)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        } catch {
            errorMessage =
                "Не удалось сохранить общие задачи на устройстве. Оставьте приложение открытым и повторите синхронизацию."
        }
    }

    static func message(for error: Error) -> String {
        if let shared = error as? SharedError { return shared.localizedDescription }
        let raw = String(describing: error)
        if raw.contains("PGRST202") {
            return "Общие списки ещё не подключены на сервере. Личные задачи работают как прежде."
        }
        if raw.contains("SHARED_INVALID_INVITE") {
            return "Приглашение недействительно, уже использовано или срок его действия истёк."
        }
        if raw.contains("SHARED_OWNER_CANNOT_LEAVE") {
            return "Владелец не может покинуть свой список. Можно удалить список целиком."
        }
        if raw.contains("SHARED_OWNER_REQUIRED") { return "Это действие доступно только владельцу списка." }
        if raw.contains("SHARED_FORBIDDEN") { return "Доступ к списку закрыт. Обновите списки." }
        if raw.contains("SHARED_INVALID_ASSIGNEE") {
            return "Этот пользователь больше не участвует в списке. Выберите другого ответственного."
        }
        return
            "Не удалось связаться с сервером общих списков. Проверьте подключение и повторите действие."
    }
}

enum SharedError: LocalizedError {
    case auth, invalidTitle, invalidInvite, offline, unavailable, busy
    case server(String)
    var errorDescription: String? {
        switch self {
        case .auth: "Войдите в аккаунт для совместной работы."
        case .invalidTitle: "Введите название от 1 до 100 символов."
        case .invalidInvite: "Вставьте код приглашения или ссылку MonoTask."
        case .offline: "Для этого действия нужно подключение к сети."
        case .unavailable: "Совместная работа пока недоступна."
        case .busy: "Дождитесь завершения текущего действия."
        case .server(let message): message
        }
    }
}

private struct SharedListRequest: Encodable {
    let p_list_id: UUID
    let p_title: String
    let p_deleted: Bool
}

private struct SharedTaskRequest: Encodable {
    let task: SharedTask
    enum CodingKeys: String, CodingKey {
        case p_list_id, p_task_id, p_expected_revision, p_title, p_notes, p_is_done, p_is_high_priority, p_assignee_id,
            p_subtasks, p_deleted
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(task.listID, forKey: .p_list_id)
        try c.encode(task.id, forKey: .p_task_id)
        try c.encode(task.revision, forKey: .p_expected_revision)
        try c.encode(task.title, forKey: .p_title)
        try c.encode(task.notes, forKey: .p_notes)
        try c.encode(task.isDone, forKey: .p_is_done)
        try c.encode(task.isHighPriority, forKey: .p_is_high_priority)
        try c.encode(task.assigneeID, forKey: .p_assignee_id)
        try c.encode(task.subtasks, forKey: .p_subtasks)
        try c.encode(task.deletedAt != nil, forKey: .p_deleted)
    }
}
