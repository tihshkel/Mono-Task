import SwiftUI
import SwiftData

struct AuthenticatedRootView: View {
    @Environment(AuthManager.self) private var auth
    @State private var container: ModelContainer?
    @State private var containerUserID: UUID?
    @State private var storeError: String?

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView("Восстанавливаем вход…")
            } else if let userID = auth.userID {
                if containerUserID == userID, let container {
                    NotificationHostView().modelContainer(container).id(userID)
                } else if let storeError {
                    ContentUnavailableView(
                        "Не удалось открыть данные",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(storeError))
                } else {
                    ProgressView("Открываем задачи…")
                }
            } else {
                AuthView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .task { await auth.start() }
        .task(id: auth.userID) { await openStoreForCurrentUser() }
    }

    private func openStoreForCurrentUser() async {
        if let userID = auth.userID, let existing = auth.activeContainer {
            container = existing
            containerUserID = userID
            storeError = nil
            return
        }
        container = nil
        containerUserID = nil
        auth.activeContainer = nil
        storeError = nil
        guard let userID = auth.userID else { return }

        let schema = Schema([
            TaskItem.self, SubtaskItem.self, Tag.self, DailyNote.self,
            WeeklyReview.self, FocusSchedule.self, ActivityEntry.self,
            CompletedHistoryEntry.self, SyncTombstone.self,
        ])
        do {
            let directory = URL.applicationSupportDirectory
                .appending(path: "users/\(userID.uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appending(path: "MonoTask.store"),
                cloudKitDatabase: .none
            )
            let opened = try ModelContainer(for: schema, configurations: [configuration])
            guard auth.userID == userID else { return }
            container = opened
            containerUserID = userID
            auth.activeContainer = opened
            NotificationService.shared.refresh(context: opened.mainContext)
            try? await SupabaseSyncService.shared.sync(context: opened.mainContext)
        } catch {
            storeError = error.localizedDescription
        }
    }
}

private struct NotificationHostView: View {
    @Environment(\.modelContext) private var context
    @State private var notifications = NotificationService.shared
    @State private var openedTask: TaskItem?
    @State private var missingTask = false

    var body: some View {
        ContentView()
            .sheet(item: $openedTask) { task in TaskEditSheet(task: task) }
            .alert("Задача недоступна", isPresented: $missingTask) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Возможно, задача удалена или уведомление относится к другому аккаунту.")
            }
            .task(id: notifications.route) {
                guard let route = notifications.route else { return }
                guard route.userID == AuthManager.shared.userID else {
                    missingTask = true
                    notifications.route = nil
                    return
                }
                NotificationCenter.default.post(name: .dismissTaskEditor, object: nil)
                openedTask = nil
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if let id = route.taskID {
                    var tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
                    if !tasks.contains(where: { $0.id == id }) {
                        try? await SupabaseSyncService.shared.sync(context: context)
                        tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
                    }
                    guard !Task.isCancelled else { return }
                    openedTask = tasks.first { $0.id == id }
                    missingTask = openedTask == nil
                } else {
                    notifications.morningNavigationToken = UUID()
                }
                notifications.route = nil
            }
    }
}
