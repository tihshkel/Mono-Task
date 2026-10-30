import Foundation
import SwiftData
import Supabase

@MainActor
final class SupabaseSyncService {
    static let shared = SupabaseSyncService()

    // A refresh view may be recreated as syncStatus changes. Own the request here
    // so cancellation of the view's task cannot cancel its URLSession requests.
    private var activeRequest: Task<Void, Error>?
    private var activeRequestContext: ObjectIdentifier?
    private var activeRequestToken: UUID?
    private var isSyncInProgress = false
    /// Set when a sync is requested while another one is running; triggers one follow-up sync
    private var needsResync = false
    private var syncDebounceTask: Task<Void, Never>?

    static var usesPreviewTransport: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--screenshots")
            && ProcessInfo.processInfo.arguments.contains("--sync-preview")
        #else
        return false
        #endif
    }

    private init() {}

    enum SyncError: LocalizedError {
        case notConfigured
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Supabase не настроен. Проверьте SupabaseConfig.plist."
            case .notAuthenticated:
                return "Войдите в аккаунт для синхронизации."
            }
        }
    }

    /// Reconcile remote changes before pushing queued local edits.
    func scheduleSync(context: ModelContext, delaySeconds: Double = 0.35) {
        guard SupabaseConfig.shared.isConfigured,
            AuthManager.shared.userID != nil
        else {
            return
        }

        SupabaseService.shared.hasPendingChanges = true
        SupabaseService.shared.localChangeRevision += 1
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }

            guard NetworkMonitor.shared.isConnected else {
                print(
                    "[SupabaseSync] Offline: changes saved locally in SwiftData, will sync when internet is restored.")
                return
            }

            do {
                try await sync(context: context)
            } catch {
                print("[SupabaseSync] Debounced sync error: \(error)")
            }
        }
    }

    /// Remote task and subtask changes take precedence when both sides changed.
    func sync(context: ModelContext) async throws {
        let contextID = ObjectIdentifier(context)
        if let request = activeRequest, activeRequestContext == contextID {
            needsResync = true
            try await request.value
            return
        }
        let token = UUID()
        let request = Task { @MainActor in
            try await self.performSync(context: context)
        }
        activeRequest = request
        activeRequestContext = contextID
        activeRequestToken = token
        defer {
            if activeRequestToken == token {
                activeRequest = nil
                activeRequestContext = nil
                activeRequestToken = nil
            }
        }
        try await request.value
    }

    private func performSync(context: ModelContext) async throws {
        #if DEBUG && targetEnvironment(simulator)
        if Self.usesPreviewTransport {
            SupabaseService.shared.syncStatus = .syncing
            do {
                try await Task.sleep(for: .seconds(1))
                SupabaseService.shared.syncStatus = .success(.now)
            } catch {
                SupabaseService.shared.syncStatus = .error(error.localizedDescription)
                throw error
            }
            return
        }
        #endif
        guard SupabaseConfig.shared.isConfigured else {
            throw SyncError.notConfigured
        }

        guard NetworkMonitor.shared.isConnected else {
            print("[SupabaseSync] Offline: cannot run reconciliation sync without internet.")
            SupabaseService.shared.connectionStatus = .offline
            return
        }

        if SupabaseService.shared.client == nil {
            SupabaseService.shared.configureClient()
        }

        guard let authClient = SupabaseService.shared.client,
            let url = SupabaseConfig.shared.cleanUrl
        else {
            throw SyncError.notConfigured
        }

        guard let ownerContainer = AuthManager.shared.activeContainer,
            context === ownerContainer.mainContext,
            let session = try? await authClient.auth.session,
            session.user.id == AuthManager.shared.userID
        else {
            throw SyncError.notAuthenticated
        }

        // ModelContext does not retain its container. Keep it alive across network awaits;
        // otherwise a cancelled view task can leave a queued sync with an invalid context.
        defer { withExtendedLifetime(ownerContainer) {} }
        guard !isSyncInProgress else {
            print("[SupabaseSync] Sync already in progress, queueing a follow-up sync")
            needsResync = true
            return
        }

        // Bind this reconciliation to its original account even if the user signs out
        // while a request is in flight. A shared client's token can change mid-sync.
        let token = session.accessToken
        let client = SupabaseClient(
            supabaseURL: url, supabaseKey: SupabaseConfig.shared.anonKey,
            options: .init(auth: .init(accessToken: { token })))
        let syncRevision = SupabaseService.shared.localChangeRevision
        isSyncInProgress = true
        SupabaseService.shared.syncStatus = .syncing
        print("[SupabaseSync] Starting bi-directional sync (server changes prioritized)...")

        defer {
            isSyncInProgress = false
            if needsResync {
                needsResync = false
                scheduleSync(context: context, delaySeconds: 0.2)
            }
        }

        do {

            // Pull first to resolve conflicts before uploading local changes.

            try await pullAll(client: client, context: context)

            guard session.user.id == AuthManager.shared.userID,
                context === AuthManager.shared.activeContainer?.mainContext
            else { throw SyncError.notAuthenticated }
            try await pushTombstones(client: client, context: context)

            guard session.user.id == AuthManager.shared.userID,
                context === AuthManager.shared.activeContainer?.mainContext
            else { throw SyncError.notAuthenticated }
            try await pushLocalChanges(client: client, context: context)
            guard session.user.id == AuthManager.shared.userID else { return }

            NotificationService.shared.refresh(context: context)
            let now = Date.now
            SupabaseConfig.shared.lastSyncDate = now
            let pendingReminderSync =
                (try? context.fetch(FetchDescriptor<TaskItem>()))?.contains { $0.reminderSyncPending } ?? false
            SupabaseService.shared.hasPendingChanges =
                SupabaseService.shared.localChangeRevision != syncRevision || pendingReminderSync
            SupabaseService.shared.syncStatus = .success(now)
            SupabaseService.shared.connectionStatus = .connected
            print("[SupabaseSync] Sync completed successfully at \(now.formatted(date: .omitted, time: .standard))")

        } catch {
            let errorMsg = error.localizedDescription
            print("[SupabaseSync] Sync failed: \(errorMsg)")
            if session.user.id == AuthManager.shared.userID {
                SupabaseService.shared.syncStatus = .error(errorMsg)
                SupabaseService.shared.connectionStatus = .error(errorMsg)
            }
            throw error
        }
    }

    // MARK: - Pull

    private func pullAll(client: SupabaseClient, context: ModelContext) async throws {
        // 1. Fetch active tombstones to know what was explicitly deleted locally
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        let localTombstonesById = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.recordId, $0) })

        // Pull Tags
        let remoteTags: [TagDTO]
        do {
            remoteTags =
                try await client
                .from("monotask_tags")
                .select()
                .execute()
                .value
            print("[SupabaseSync] Pulled \(remoteTags.count) remote tags")
        } catch {
            print("[SupabaseSync] Failed to fetch monotask_tags: \(error)")
            throw error
        }

        let localTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var localTagsById = Dictionary(uniqueKeysWithValues: localTags.map { ($0.id, $0) })
        var localTagsByName = Dictionary(
            localTags.map { ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })

        for remoteTag in remoteTags {
            // Deleted on another device: remove it here too. Skipping these rows (the old
            // `deleted_at IS NULL` filter) left the local copy alive, and the next push
            // upserted it with `deleted_at = null`, resurrecting the deletion.
            if remoteTag.deletedAt != nil {
                if let existing = localTagsById.removeValue(forKey: remoteTag.id) {
                    localTagsByName = localTagsByName.filter { $0.value !== existing }
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteTag.id] {
                    context.delete(tombstone)
                }
                continue
            }

            if let tombstone = localTombstonesById[remoteTag.id] {
                if remoteTag.updatedAt > tombstone.deletedAt {
                    context.delete(tombstone)
                } else {
                    continue
                }
            }

            // Match by ID first, or by exact name (case-insensitive) to prevent duplicate default tags
            let normalizedName = remoteTag.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let existing = localTagsById[remoteTag.id] ?? localTagsByName[normalizedName]

            if let existing {
                // Ensure local ID matches Supabase ID
                if existing.id != remoteTag.id {
                    existing.id = remoteTag.id
                    localTagsById[remoteTag.id] = existing
                }
                if remoteTag.updatedAt >= existing.updatedAt {
                    existing.name = remoteTag.name
                    existing.colorHex = remoteTag.colorHex
                    existing.iconName = remoteTag.iconName
                    existing.scheduledDaysRaw = remoteTag.scheduledDays
                    existing.sortOrder = remoteTag.sortOrder
                    existing.updatedAt = remoteTag.updatedAt
                }
            } else {
                let newTag = Tag(
                    id: remoteTag.id,
                    name: remoteTag.name,
                    colorHex: remoteTag.colorHex,
                    iconName: remoteTag.iconName,
                    scheduledDays: remoteTag.scheduledDays.compactMap { Weekday(rawValue: $0) },
                    sortOrder: remoteTag.sortOrder
                )
                newTag.createdAt = remoteTag.createdAt
                newTag.updatedAt = remoteTag.updatedAt
                context.insert(newTag)
                localTagsById[newTag.id] = newTag
                localTagsByName[normalizedName] = newTag
            }
        }

        // Pull Tasks with Server Priority
        // Preserve offline edits unless the server version changed as well.
        let remoteTasks: [TaskItemDTO]
        do {
            remoteTasks =
                try await client
                .from("monotask_tasks")
                .select()
                .execute()
                .value
            print("[SupabaseSync] Pulled \(remoteTasks.count) remote tasks")
        } catch {
            print("[SupabaseSync] Failed to fetch monotask_tasks: \(error)")
            throw error
        }

        let localTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var localTasksById = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })
        let taskTombstones = Dictionary(
            uniqueKeysWithValues: tombstones.filter { $0.recordType == "task" }.map { ($0.recordId, $0) })

        for remoteTask in remoteTasks {
            let tombstone = taskTombstones[remoteTask.id]
            let existing = localTasksById[remoteTask.id]

            // Soft-deleted on server -> delete locally
            if remoteTask.deletedAt != nil {
                if let existing {
                    context.delete(existing)
                    localTasksById.removeValue(forKey: remoteTask.id)
                }
                if let tombstone {
                    context.delete(tombstone)
                }
                continue
            }

            // Deleted locally while offline
            if let tombstone {
                // If server modified this task after local deletion:
                // A newer remote edit cancels the local deletion.
                if remoteTask.updatedAt > tombstone.deletedAt {
                    print(
                        "[SupabaseSync] Task '\(remoteTask.title)' was deleted locally but updated on server. Server wins -> restoring task."
                    )
                    context.delete(tombstone)
                    let matchedTags = remoteTask.tagIds.compactMap { localTagsById[$0] }
                    let newTask = TaskItem(
                        title: remoteTask.title,
                        notes: remoteTask.notes,
                        bucket: Bucket(rawValue: remoteTask.bucketRaw) ?? .todo,
                        priority: Priority(rawValue: remoteTask.priorityRaw) ?? .none,
                        isHighPriorityToday: remoteTask.isHighPriorityToday,
                        dueDate: remoteTask.dueDate,
                        reminderMinutesBefore: remoteTask.reminderMinutesBefore,
                        tags: matchedTags
                    )
                    newTask.id = remoteTask.id
                    newTask.createdAt = remoteTask.createdAt
                    newTask.completedAt = remoteTask.completedAt
                    newTask.sortOrder = remoteTask.sortOrder
                    newTask.updatedAt = remoteTask.updatedAt
                    newTask.serverUpdatedAt = remoteTask.updatedAt
                    newTask.isPendingOfflineSync = false
                    context.insert(newTask)
                    localTasksById[newTask.id] = newTask
                }
                // Otherwise keep tombstone for the deletion push
                continue
            }

            let matchedTags = remoteTask.tagIds.compactMap { localTagsById[$0] }

            // Task exists locally
            if let existing {
                let serverChanged: Bool
                if let lastServerUpdate = existing.serverUpdatedAt {
                    serverChanged = (remoteTask.updatedAt != lastServerUpdate)
                } else {
                    serverChanged =
                        (remoteTask.updatedAt >= existing.updatedAt || remoteTask.title != existing.title
                            || remoteTask.notes != existing.notes || remoteTask.bucketRaw != existing.bucketRaw
                            || remoteTask.priorityRaw != existing.priorityRaw
                            || remoteTask.isHighPriorityToday != existing.isHighPriorityToday
                            || remoteTask.dueDate != existing.dueDate || remoteTask.completedAt != existing.completedAt
                            || (remoteTask.includesReminderTiming
                                && remoteTask.reminderMinutesBefore != existing.reminderMinutesBefore)
                            || remoteTask.sortOrder != existing.sortOrder)
                }

                let localChanged =
                    existing.isPendingOfflineSync || existing.reminderSyncPending
                    || (existing.updatedAt > (existing.serverUpdatedAt ?? .distantPast))

                if serverChanged {
                    if localChanged {
                        print(
                            "[SupabaseSync] Conflict in task '\(existing.title)' (id: \(existing.id)). Server changed AND device changed. Server wins -> cancelling device changes."
                        )
                    } else {
                        print("[SupabaseSync] Updating task '\(remoteTask.title)' from server.")
                    }
                    // Resolve a concurrent edit using the remote version.
                    existing.title = remoteTask.title
                    existing.notes = remoteTask.notes
                    existing.bucketRaw = remoteTask.bucketRaw
                    existing.priorityRaw = remoteTask.priorityRaw
                    existing.isHighPriorityToday = remoteTask.isHighPriorityToday
                    existing.completedAt = remoteTask.completedAt
                    existing.dueDate = remoteTask.dueDate
                    if remoteTask.includesReminderTiming {
                        existing.reminderMinutesBefore = remoteTask.reminderMinutesBefore
                        existing.reminderSyncPending = false
                    }
                    existing.sortOrder = remoteTask.sortOrder
                    existing.tags = matchedTags
                    existing.updatedAt = remoteTask.updatedAt
                    existing.serverUpdatedAt = remoteTask.updatedAt
                    existing.isPendingOfflineSync = false
                } else if localChanged {
                    // Server did not change, device changed while offline -> keep local changes for the next push
                    print(
                        "[SupabaseSync] Task '\(existing.title)' changed locally offline without server conflict. Will push to server."
                    )
                } else {
                    existing.serverUpdatedAt = remoteTask.updatedAt
                    existing.isPendingOfflineSync = false
                }
            } else {
                // New task from server
                let newTask = TaskItem(
                    title: remoteTask.title,
                    notes: remoteTask.notes,
                    bucket: Bucket(rawValue: remoteTask.bucketRaw) ?? .todo,
                    priority: Priority(rawValue: remoteTask.priorityRaw) ?? .none,
                    isHighPriorityToday: remoteTask.isHighPriorityToday,
                    dueDate: remoteTask.dueDate,
                    reminderMinutesBefore: remoteTask.reminderMinutesBefore,
                    tags: matchedTags
                )
                newTask.id = remoteTask.id
                newTask.createdAt = remoteTask.createdAt
                newTask.completedAt = remoteTask.completedAt
                newTask.sortOrder = remoteTask.sortOrder
                newTask.updatedAt = remoteTask.updatedAt
                newTask.serverUpdatedAt = remoteTask.updatedAt
                newTask.isPendingOfflineSync = false
                context.insert(newTask)
                localTasksById[newTask.id] = newTask
            }
        }

        // Pull Subtasks with Server Priority
        let remoteSubtasks: [SubtaskItemDTO]
        do {
            remoteSubtasks =
                try await client
                .from("monotask_subtasks")
                .select()
                .execute()
                .value
            print("[SupabaseSync] Pulled \(remoteSubtasks.count) remote subtasks")
        } catch {
            print("[SupabaseSync] Failed to fetch monotask_subtasks: \(error)")
            throw error
        }

        let localSubtasks = (try? context.fetch(FetchDescriptor<SubtaskItem>())) ?? []
        var localSubtasksById = Dictionary(uniqueKeysWithValues: localSubtasks.map { ($0.id, $0) })
        let subtaskTombstones = Dictionary(
            uniqueKeysWithValues: tombstones.filter { $0.recordType == "subtask" }.map { ($0.recordId, $0) })

        for remoteSubtask in remoteSubtasks {
            let tombstone = subtaskTombstones[remoteSubtask.id]
            let existing = localSubtasksById[remoteSubtask.id]

            // Soft-deleted on server -> delete locally
            if remoteSubtask.deletedAt != nil {
                if let existing {
                    context.delete(existing)
                    localSubtasksById.removeValue(forKey: remoteSubtask.id)
                }
                if let tombstone {
                    context.delete(tombstone)
                }
                continue
            }

            // Deleted locally while offline
            if let tombstone {
                if remoteSubtask.updatedAt > tombstone.deletedAt {
                    context.delete(tombstone)
                    let newSubtask = SubtaskItem(
                        title: remoteSubtask.title,
                        isCompleted: remoteSubtask.isCompleted,
                        sortOrder: remoteSubtask.sortOrder
                    )
                    newSubtask.id = remoteSubtask.id
                    newSubtask.createdAt = remoteSubtask.createdAt
                    newSubtask.updatedAt = remoteSubtask.updatedAt
                    newSubtask.serverUpdatedAt = remoteSubtask.updatedAt
                    newSubtask.isPendingOfflineSync = false
                    newSubtask.task = localTasksById[remoteSubtask.taskId]
                    context.insert(newSubtask)
                    localSubtasksById[newSubtask.id] = newSubtask
                }
                continue
            }

            if let existing {
                let serverChanged: Bool
                if let lastServerUpdate = existing.serverUpdatedAt {
                    serverChanged = (remoteSubtask.updatedAt != lastServerUpdate)
                } else {
                    serverChanged =
                        (remoteSubtask.updatedAt >= existing.updatedAt || remoteSubtask.title != existing.title
                            || remoteSubtask.isCompleted != existing.isCompleted
                            || remoteSubtask.sortOrder != existing.sortOrder)
                }

                let localChanged =
                    existing.isPendingOfflineSync || (existing.updatedAt > (existing.serverUpdatedAt ?? .distantPast))

                if serverChanged {
                    existing.title = remoteSubtask.title
                    existing.isCompleted = remoteSubtask.isCompleted
                    existing.sortOrder = remoteSubtask.sortOrder
                    existing.updatedAt = remoteSubtask.updatedAt
                    existing.serverUpdatedAt = remoteSubtask.updatedAt
                    existing.isPendingOfflineSync = false
                    if existing.task == nil || existing.task?.id != remoteSubtask.taskId {
                        existing.task = localTasksById[remoteSubtask.taskId]
                    }
                } else if localChanged {
                    // Local changed offline without server conflict -> push in Phase 3
                } else {
                    existing.serverUpdatedAt = remoteSubtask.updatedAt
                    existing.isPendingOfflineSync = false
                }
            } else {
                let newSubtask = SubtaskItem(
                    title: remoteSubtask.title,
                    isCompleted: remoteSubtask.isCompleted,
                    sortOrder: remoteSubtask.sortOrder
                )
                newSubtask.id = remoteSubtask.id
                newSubtask.createdAt = remoteSubtask.createdAt
                newSubtask.updatedAt = remoteSubtask.updatedAt
                newSubtask.serverUpdatedAt = remoteSubtask.updatedAt
                newSubtask.isPendingOfflineSync = false
                newSubtask.task = localTasksById[remoteSubtask.taskId]
                context.insert(newSubtask)
                localSubtasksById[newSubtask.id] = newSubtask
            }
        }

        // Pull Daily Notes
        let remoteNotes: [DailyNoteDTO] =
            (try? await client
                .from("monotask_daily_notes")
                .select()
                .execute()
                .value) ?? []

        let localNotes = (try? context.fetch(FetchDescriptor<DailyNote>())) ?? []
        let localNotesById = Dictionary(uniqueKeysWithValues: localNotes.map { ($0.id, $0) })

        for remoteNote in remoteNotes {
            if remoteNote.deletedAt != nil {
                if let existing = localNotesById[remoteNote.id] {
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteNote.id] {
                    context.delete(tombstone)
                }
                continue
            }
            if localTombstonesById[remoteNote.id] != nil { continue }
            if let existing = localNotesById[remoteNote.id] {
                if remoteNote.updatedAt >= existing.updatedAt {
                    existing.date = remoteNote.date
                    existing.wins = remoteNote.wins
                    existing.losses = remoteNote.losses
                    existing.reason = remoteNote.reason
                    existing.updatedAt = remoteNote.updatedAt
                }
            } else {
                let newNote = DailyNote(
                    date: remoteNote.date,
                    wins: remoteNote.wins,
                    losses: remoteNote.losses,
                    reason: remoteNote.reason
                )
                newNote.id = remoteNote.id
                newNote.createdAt = remoteNote.createdAt
                newNote.updatedAt = remoteNote.updatedAt
                context.insert(newNote)
            }
        }

        // Pull Weekly Reviews
        let remoteReviews: [WeeklyReviewDTO] =
            (try? await client
                .from("monotask_weekly_reviews")
                .select()
                .execute()
                .value) ?? []

        let localReviews = (try? context.fetch(FetchDescriptor<WeeklyReview>())) ?? []
        let localReviewsById = Dictionary(uniqueKeysWithValues: localReviews.map { ($0.id, $0) })

        for remoteReview in remoteReviews {
            if remoteReview.deletedAt != nil {
                if let existing = localReviewsById[remoteReview.id] {
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteReview.id] {
                    context.delete(tombstone)
                }
                continue
            }
            if localTombstonesById[remoteReview.id] != nil { continue }
            if let existing = localReviewsById[remoteReview.id] {
                if remoteReview.updatedAt >= existing.updatedAt {
                    existing.weekStartDate = remoteReview.weekStartDate
                    existing.summary = remoteReview.summary
                    existing.improvements = remoteReview.improvements
                    existing.completedTasksCount = remoteReview.completedTasksCount
                    existing.updatedAt = remoteReview.updatedAt
                }
            } else {
                let newReview = WeeklyReview(
                    weekStartDate: remoteReview.weekStartDate,
                    summary: remoteReview.summary,
                    improvements: remoteReview.improvements,
                    completedTasksCount: remoteReview.completedTasksCount
                )
                newReview.id = remoteReview.id
                newReview.createdAt = remoteReview.createdAt
                newReview.updatedAt = remoteReview.updatedAt
                context.insert(newReview)
            }
        }

        // Pull Focus Schedules
        let remoteSchedules: [FocusScheduleDTO] =
            (try? await client
                .from("monotask_focus_schedules")
                .select()
                .execute()
                .value) ?? []

        let localSchedules = (try? context.fetch(FetchDescriptor<FocusSchedule>())) ?? []
        let localSchedulesById = Dictionary(uniqueKeysWithValues: localSchedules.map { ($0.id, $0) })

        for remoteSchedule in remoteSchedules {
            if remoteSchedule.deletedAt != nil {
                if let existing = localSchedulesById[remoteSchedule.id] {
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteSchedule.id] {
                    context.delete(tombstone)
                }
                continue
            }
            if localTombstonesById[remoteSchedule.id] != nil { continue }
            let tag = remoteSchedule.tagId.flatMap { localTagsById[$0] }
            if let existing = localSchedulesById[remoteSchedule.id] {
                if remoteSchedule.updatedAt >= existing.updatedAt {
                    existing.weekdayRaw = remoteSchedule.weekdayRaw
                    existing.tag = tag
                    existing.updatedAt = remoteSchedule.updatedAt
                }
            } else {
                let newSchedule = FocusSchedule(
                    weekday: Weekday(rawValue: remoteSchedule.weekdayRaw) ?? .monday,
                    tag: tag
                )
                newSchedule.id = remoteSchedule.id
                newSchedule.createdAt = remoteSchedule.createdAt
                newSchedule.updatedAt = remoteSchedule.updatedAt
                context.insert(newSchedule)
            }
        }

        // Pull Activity Entries
        let remoteActivities: [ActivityEntryDTO] =
            (try? await client
                .from("monotask_activity_entries")
                .select()
                .execute()
                .value) ?? []

        let localActivities = (try? context.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        let localActivitiesById = Dictionary(uniqueKeysWithValues: localActivities.map { ($0.id, $0) })

        for remoteAct in remoteActivities {
            if remoteAct.deletedAt != nil {
                if let existing = localActivitiesById[remoteAct.id] {
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteAct.id] {
                    context.delete(tombstone)
                }
                continue
            }
            if localTombstonesById[remoteAct.id] != nil { continue }
            if let existing = localActivitiesById[remoteAct.id] {
                if remoteAct.updatedAt >= existing.updatedAt {
                    existing.count = remoteAct.count
                    existing.tagId = remoteAct.tagId
                    existing.date = remoteAct.date
                    existing.updatedAt = remoteAct.updatedAt
                }
            } else {
                let newAct = ActivityEntry(date: remoteAct.date, tagId: remoteAct.tagId, count: remoteAct.count)
                newAct.id = remoteAct.id
                newAct.createdAt = remoteAct.createdAt
                newAct.updatedAt = remoteAct.updatedAt
                context.insert(newAct)
            }
        }

        // Pull Completed History
        let remoteHistory: [CompletedHistoryEntryDTO] =
            (try? await client
                .from("monotask_completed_history")
                .select()
                .execute()
                .value) ?? []

        let localHistories = (try? context.fetch(FetchDescriptor<CompletedHistoryEntry>())) ?? []
        let localHistoriesById = Dictionary(uniqueKeysWithValues: localHistories.map { ($0.id, $0) })

        for remoteH in remoteHistory {
            if remoteH.deletedAt != nil {
                if let existing = localHistoriesById[remoteH.id] {
                    context.delete(existing)
                }
                if let tombstone = localTombstonesById[remoteH.id] {
                    context.delete(tombstone)
                }
                continue
            }
            if localTombstonesById[remoteH.id] != nil { continue }
            if let existing = localHistoriesById[remoteH.id] {
                if remoteH.updatedAt >= existing.updatedAt {
                    existing.taskId = remoteH.taskId
                    existing.tagId = remoteH.tagId
                    existing.completedAt = remoteH.completedAt
                    existing.updatedAt = remoteH.updatedAt
                }
            } else {
                let newH = CompletedHistoryEntry(
                    taskId: remoteH.taskId, tagId: remoteH.tagId, completedAt: remoteH.completedAt)
                newH.id = remoteH.id
                newH.createdAt = remoteH.createdAt
                newH.updatedAt = remoteH.updatedAt
                context.insert(newH)
            }
        }

        try context.save()
    }

    // MARK: - Push deletions

    private func pushTombstones(client: SupabaseClient, context: ModelContext) async throws {
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        guard !tombstones.isEmpty else { return }

        let isoFormatter = ISO8601DateFormatter()
        var pushedCount = 0

        for tombstone in tombstones {
            let tableName: String? = {
                switch tombstone.recordType {
                case "tag": return "monotask_tags"
                case "task": return "monotask_tasks"
                case "subtask": return "monotask_subtasks"
                case "daily_note": return "monotask_daily_notes"
                case "weekly_review": return "monotask_weekly_reviews"
                case "focus_schedule": return "monotask_focus_schedules"
                case "activity_entry": return "monotask_activity_entries"
                case "completed_history": return "monotask_completed_history"
                default: return nil
                }
            }()

            guard let tableName else {
                context.delete(tombstone)
                continue
            }

            do {
                // Soft-delete on remote: set deleted_at = now()
                try await client
                    .from(tableName)
                    .update(["deleted_at": isoFormatter.string(from: tombstone.deletedAt)])
                    .eq("id", value: tombstone.recordId.uuidString)
                    .execute()

                context.delete(tombstone)
                pushedCount += 1
            } catch {
                print("[SupabaseSync] Failed to push tombstone for \(tableName) id \(tombstone.recordId): \(error)")
            }
        }

        if pushedCount > 0 {
            print("[SupabaseSync] Processed and pushed \(pushedCount) local deletions")
            try context.save()
        }
    }

    // MARK: - Push local changes

    private func pushLocalChanges(client: SupabaseClient, context: ModelContext) async throws {
        // Push Tags
        let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        if !tags.isEmpty {
            let tagDTOs = tags.map { tag in
                TagDTO(
                    id: tag.id,
                    name: tag.name,
                    colorHex: tag.colorHex,
                    iconName: tag.iconName,
                    scheduledDays: tag.scheduledDaysRaw,
                    sortOrder: tag.sortOrder,
                    createdAt: tag.createdAt,
                    updatedAt: tag.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_tags").upsert(tagDTOs).execute()
            print("[SupabaseSync] Pushed \(tagDTOs.count) tags")
        }

        // Push Tasks (only offline pending changes or new local records)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let tasksToPush = tasks.filter {
            $0.isPendingOfflineSync || $0.serverUpdatedAt == nil || $0.reminderSyncPending
        }
        if !tasksToPush.isEmpty {
            let taskDTOs = tasksToPush.map { task in
                TaskItemDTO(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    bucketRaw: task.bucketRaw,
                    priorityRaw: task.priorityRaw,
                    isHighPriorityToday: task.isHighPriorityToday,
                    createdAt: task.createdAt,
                    completedAt: task.completedAt,
                    dueDate: task.dueDate,
                    reminderMinutesBefore: task.reminderMinutesBefore,
                    sortOrder: task.sortOrder,
                    tagIds: task.tags.map(\.id),
                    updatedAt: task.updatedAt,
                    deletedAt: nil
                )
            }
            // The BEFORE UPDATE trigger rewrites updated_at on the server, so remember the
            // server's value; otherwise the next pull sees a "server change", declares a
            // conflict and discards any edit made in the meantime.
            let pushedUpdatedAt = Dictionary(uniqueKeysWithValues: taskDTOs.map { ($0.id, $0.updatedAt) })
            let savedTasks: [TaskItemDTO]
            do {
                savedTasks = try await client.from("monotask_tasks").upsert(taskDTOs).select().execute().value
            } catch let error as PostgrestError
                where error.code == "PGRST204" && error.message.contains("reminder_minutes_before")
            {
                // Older databases still sync tasks. Keep local reminder edits queued until the additive migration is applied.
                let legacy = taskDTOs.map { dto in
                    var copy = dto
                    copy.includesReminderTiming = false
                    return copy
                }
                savedTasks = try await client.from("monotask_tasks").upsert(legacy).select().execute().value
            }
            let serverUpdatedAt = Dictionary(uniqueKeysWithValues: savedTasks.map { ($0.id, $0.updatedAt) })
            for task in tasksToPush {
                task.serverUpdatedAt = serverUpdatedAt[task.id] ?? task.updatedAt
                // Edited again while the request was in flight: keep it pending for the next push
                if task.updatedAt == pushedUpdatedAt[task.id] {
                    task.isPendingOfflineSync = false
                    if savedTasks.first(where: { $0.id == task.id })?.includesReminderTiming == true {
                        task.reminderSyncPending = false
                    }
                }
            }
            print("[SupabaseSync] Pushed \(taskDTOs.count) tasks")
        }

        // Push Subtasks (only offline pending changes or new local records)
        let subtasks = (try? context.fetch(FetchDescriptor<SubtaskItem>())) ?? []
        let subtasksToPush = subtasks.filter { $0.isPendingOfflineSync || $0.serverUpdatedAt == nil }
        if !subtasksToPush.isEmpty {
            let subtaskDTOs = subtasksToPush.compactMap { subtask -> SubtaskItemDTO? in
                guard let taskId = subtask.task?.id else { return nil }
                return SubtaskItemDTO(
                    id: subtask.id,
                    taskId: taskId,
                    title: subtask.title,
                    isCompleted: subtask.isCompleted,
                    sortOrder: subtask.sortOrder,
                    createdAt: subtask.createdAt,
                    updatedAt: subtask.updatedAt,
                    deletedAt: nil
                )
            }
            if !subtaskDTOs.isEmpty {
                let pushedUpdatedAt = Dictionary(uniqueKeysWithValues: subtaskDTOs.map { ($0.id, $0.updatedAt) })
                let savedSubtasks: [SubtaskItemDTO] = try await client.from("monotask_subtasks").upsert(subtaskDTOs)
                    .select().execute().value
                let serverUpdatedAt = Dictionary(uniqueKeysWithValues: savedSubtasks.map { ($0.id, $0.updatedAt) })
                for subtask in subtasksToPush where pushedUpdatedAt[subtask.id] != nil {
                    subtask.serverUpdatedAt = serverUpdatedAt[subtask.id] ?? subtask.updatedAt
                    if subtask.updatedAt == pushedUpdatedAt[subtask.id] {
                        subtask.isPendingOfflineSync = false
                    }
                }
                print("[SupabaseSync] Pushed \(subtaskDTOs.count) subtasks")
            }
        }

        // Push Daily Notes
        let notes = (try? context.fetch(FetchDescriptor<DailyNote>())) ?? []
        if !notes.isEmpty {
            let noteDTOs = notes.map { note in
                DailyNoteDTO(
                    id: note.id,
                    date: note.date,
                    wins: note.wins,
                    losses: note.losses,
                    reason: note.reason,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_daily_notes").upsert(noteDTOs).execute()
        }

        // Push Weekly Reviews
        let reviews = (try? context.fetch(FetchDescriptor<WeeklyReview>())) ?? []
        if !reviews.isEmpty {
            let reviewDTOs = reviews.map { review in
                WeeklyReviewDTO(
                    id: review.id,
                    weekStartDate: review.weekStartDate,
                    summary: review.summary,
                    improvements: review.improvements,
                    completedTasksCount: review.completedTasksCount,
                    createdAt: review.createdAt,
                    updatedAt: review.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_weekly_reviews").upsert(reviewDTOs).execute()
        }

        // Push Focus Schedules
        let schedules = (try? context.fetch(FetchDescriptor<FocusSchedule>())) ?? []
        if !schedules.isEmpty {
            let scheduleDTOs = schedules.map { schedule in
                FocusScheduleDTO(
                    id: schedule.id,
                    weekdayRaw: schedule.weekdayRaw,
                    tagId: schedule.tag?.id,
                    createdAt: schedule.createdAt,
                    updatedAt: schedule.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_focus_schedules").upsert(scheduleDTOs).execute()
        }

        // Push Activity Entries
        let activities = (try? context.fetch(FetchDescriptor<ActivityEntry>())) ?? []
        if !activities.isEmpty {
            let actDTOs = activities.map { act in
                ActivityEntryDTO(
                    id: act.id,
                    date: act.date,
                    tagId: act.tagId,
                    count: act.count,
                    createdAt: act.createdAt,
                    updatedAt: act.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_activity_entries").upsert(actDTOs).execute()
        }

        // Push Completed History
        let histories = (try? context.fetch(FetchDescriptor<CompletedHistoryEntry>())) ?? []
        if !histories.isEmpty {
            let historyDTOs = histories.map { h in
                CompletedHistoryEntryDTO(
                    id: h.id,
                    taskId: h.taskId,
                    tagId: h.tagId,
                    completedAt: h.completedAt,
                    createdAt: h.createdAt,
                    updatedAt: h.updatedAt,
                    deletedAt: nil
                )
            }
            try await client.from("monotask_completed_history").upsert(historyDTOs).execute()
        }
    }
}
