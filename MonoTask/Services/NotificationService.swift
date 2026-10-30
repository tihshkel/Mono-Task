import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var taskReminders = true
    var morningPlan = false
    var sound = true
    var showPreview = true
    var morningHour = 9
    var morningMinute = 0
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var morningScope = "focus"
    var taskCount = 3
}

struct ReminderTask: Sendable {
    let id: UUID
    let title: String
    let date: Date?
    let done: Bool
    let priority: Bool
    let tagIDs: [UUID]
    let order: Int
    var minutesBefore: Int? = 0

    var fireDate: Date? {
        guard let date, let minutesBefore, (0...525_600).contains(minutesBefore) else { return nil }
        return date.addingTimeInterval(-Double(minutesBefore) * 60)
    }
}

enum ReminderLeadTime {
    static let presets = [0, 5, 15, 30, 60, 120, 1_440, 2_880, 10_080]
    static func duration(_ minutes: Int) -> String {
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) дн." }
        if minutes % 60 == 0 { return "\(minutes / 60) ч." }
        return "\(minutes) мин."
    }
    static func label(_ minutes: Int?) -> String {
        guard let minutes else { return "Без уведомления" }
        return minutes == 0 ? "В момент срока" : "За " + duration(minutes)
    }
}

struct ReminderTag: Sendable {
    let id: UUID
    let name: String
    let weekdays: [Int]
}

struct PlannedNotification: Sendable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
    let taskID: UUID?
}

// Pure planning logic is shared by the app and the executable regression tests.
enum NotificationPlanner {
    static func plans(
        tasks: [ReminderTask], tags: [ReminderTag], preferences p: NotificationPreferences,
        now: Date, calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard p.enabled else { return [] }
        var result: [PlannedNotification] = []
        let open = tasks.filter { !$0.done }
        if p.taskReminders {
            for task in open {
                guard let date = task.fireDate, date > now else { continue }
                let early = (task.minutesBefore ?? 0) > 0
                let detail =
                    early ? "До срока: \(ReminderLeadTime.duration(task.minutesBefore!))." : "Крайний срок наступил."
                result.append(
                    PlannedNotification(
                        identifier: "monotask.task.\(task.id.uuidString)",
                        title: early ? "Срок задачи приближается" : "Крайний срок задачи",
                        body: p.showPreview ? "\(task.title)\n\(detail)" : "Пора вернуться к задаче в MonoTask.",
                        date: date, taskID: task.id))
            }
        }
        if p.morningPlan {
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                    let date = calendar.date(bySettingHour: p.morningHour, minute: p.morningMinute, second: 0, of: day),
                    date > now, p.weekdays.contains(calendar.component(.weekday, from: day))
                else { continue }
                let focus = tags.filter { $0.weekdays.contains(calendar.component(.weekday, from: day)) }
                let focusIDs = Set(focus.map(\.id))
                let candidates = open.filter { task in
                    switch p.morningScope {
                    case "priority": return task.priority
                    case "all": return true
                    default:
                        return focusIDs.isEmpty || task.tagIDs.isEmpty || task.tagIDs.contains { focusIDs.contains($0) }
                    }
                }.sorted {
                    if $0.priority != $1.priority { return $0.priority }
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.id.uuidString < $1.id.uuidString
                }
                let focusText =
                    focus.isEmpty ? "Без заданного фокуса." : "Фокус: \(focus.map(\.name).joined(separator: ", "))."
                let names = candidates.prefix(max(1, min(p.taskCount, 8))).map(\.title).joined(separator: "; ")
                let body: String
                if p.showPreview {
                    body =
                        "\(focusText) \(candidates.isEmpty ? "Задач пока нет." : "Задач: \(candidates.count). \(names)")"
                } else {
                    body = "Откройте MonoTask, чтобы посмотреть задачи и фокус дня."
                }
                let stamp = calendar.dateComponents([.year, .month, .day], from: day)
                result.append(
                    PlannedNotification(
                        identifier: "monotask.morning.\(stamp.year!)-\(stamp.month!)-\(stamp.day!)",
                        title: "Утренний план", body: body, date: date, taskID: nil))
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.identifier < $1.identifier
        }
    }
}

#if !PLANNER_TEST
import SwiftData
import Observation
import UserNotifications

struct NotificationRoute: Equatable {
    let token = UUID()
    let userID: UUID
    let taskID: UUID?
}

@Observable
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    var preferences = NotificationPreferences() {
        didSet {
            guard !loadingPreferences, let accountID else { return }
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: preferencesKey(accountID))
            }
            refresh(context: AuthManager.shared.activeContainer?.mainContext)
        }
    }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pendingCount = 0
    private(set) var overflowCount = 0
    private(set) var errorMessage: String?
    var route: NotificationRoute?
    var morningNavigationToken: UUID?
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var loadingPreferences = false
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private override init() { super.init() }

    func install() { UNUserNotificationCenter.current().delegate = self }

    private func preferencesKey(_ id: UUID) -> String { "monotask.notifications.\(id.uuidString)" }

    func checkAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await checkAuthorization()
            refresh(context: AuthManager.shared.activeContainer?.mainContext)
            return allowed
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func enableTaskReminders() async {
        preferences.enabled = true
        preferences.taskReminders = true
        await checkAuthorization()
        if authorization == .notDetermined { _ = await requestAuthorization() }
    }

    /// Serialize replacements so a cancelled in-flight add cannot resurrect a completed task's reminder.
    func refresh(context: ModelContext?) {
        let userID = AuthManager.shared.userID
        if let context, context !== AuthManager.shared.activeContainer?.mainContext { return }
        if accountID != userID {
            loadingPreferences = true
            accountID = userID
            preferences =
                userID.flatMap { id in
                    UserDefaults.standard.data(forKey: preferencesKey(id)).flatMap {
                        try? JSONDecoder().decode(NotificationPreferences.self, from: $0)
                    }
                } ?? NotificationPreferences()
            loadingPreferences = false
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        // Failed fetches must not replace a valid schedule with an empty one.
        let tasks: [TaskItem]
        let tags: [Tag]
        do {
            tasks = try context?.fetch(FetchDescriptor<TaskItem>()) ?? []
            tags = try context?.fetch(FetchDescriptor<Tag>()) ?? []
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let snapshots = tasks.filter { !TaskDeletionManager.shared.isPending($0) }.map {
            ReminderTask(
                id: $0.id, title: $0.title, date: $0.dueDate,
                done: $0.isDone, priority: $0.isHighPriorityToday, tagIDs: $0.tags.map(\.id), order: $0.sortOrder,
                minutesBefore: $0.reminderMinutesBefore)
        }
        let tagSnapshots = tags.map {
            ReminderTag(id: $0.id, name: $0.name, weekdays: $0.scheduledDays.map(\.rawValue))
        }
        let p = preferences
        let previous = updateTask
        previous?.cancel()
        updateTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            await checkAuthorization()
            guard !Task.isCancelled else { return }
            let plans = NotificationPlanner.plans(tasks: snapshots, tags: tagSnapshots, preferences: p, now: .now)
            // Reserve four slots for previews and OS bookkeeping; retain the nearest events first.
            let selected = Array(plans.prefix(60))
            let oldPending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            let oldIDs = oldPending.filter { $0.identifier.hasPrefix("monotask.") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
            let delivered = await center.deliveredNotifications()
            guard !Task.isCancelled else { return }
            center.removeDeliveredNotifications(
                withIdentifiers: delivered.filter {
                    // Remove completed/deleted task alerts as well as alerts from another account.
                    let info = $0.request.content.userInfo
                    let belongs = info["user_id"] as? String == userID?.uuidString
                    let activeTask = info["task_id"] as? String
                    return !belongs || !p.enabled || !p.showPreview || (activeTask != nil && !p.taskReminders)
                        || (activeTask == nil && !p.morningPlan)
                        || (activeTask != nil
                            && !snapshots.contains {
                                $0.id.uuidString == activeTask && !$0.done
                            })
                }.map { $0.request.identifier })
            pendingCount = 0
            overflowCount = max(0, plans.count - selected.count)
            errorMessage = nil
            guard let userID, context != nil, p.enabled,
                authorization == .authorized || authorization == .provisional
            else { return }
            for plan in selected {
                guard !Task.isCancelled, userID == AuthManager.shared.userID,
                    context === AuthManager.shared.activeContainer?.mainContext
                else { return }
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = p.sound ? .default : nil
                content.threadIdentifier = "monotask.\(userID.uuidString)"
                content.userInfo = ["user_id": userID.uuidString, "kind": plan.taskID == nil ? "morning" : "task"]
                if let id = plan.taskID { content.userInfo["task_id"] = id.uuidString }
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: plan.date)
                components.timeZone = .current
                let request = UNNotificationRequest(
                    identifier: plan.identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                do {
                    try await center.add(request)
                    pendingCount += 1
                } catch {
                    errorMessage = "Не удалось запланировать уведомления: \(error.localizedDescription)"
                }
            }
        }
    }

    func sendTest() async -> Bool {
        guard let userID = AuthManager.shared.userID else { return false }
        guard await requestAuthorization() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "MonoTask: проверка"
        content.body = "Уведомления работают."
        content.sound = preferences.sound ? .default : nil
        content.userInfo = ["user_id": userID.uuidString, "kind": "morning"]
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "notification-preview",
                    content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearForSignOut() {
        refresh(context: nil)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        route = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let user = (info["user_id"] as? String).flatMap(UUID.init(uuidString:))
        let task = (info["task_id"] as? String).flatMap(UUID.init(uuidString:))
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let user {
            Task { @MainActor in self.route = NotificationRoute(userID: user, taskID: task) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let owner = notification.request.content.userInfo["user_id"] as? String
        let hasSound = notification.request.content.sound != nil
        Task { @MainActor in
            guard owner == AuthManager.shared.userID?.uuidString else { completionHandler([]); return }
            completionHandler(hasSound ? [.banner, .list, .sound] : [.banner, .list])
        }
    }
}
#endif
