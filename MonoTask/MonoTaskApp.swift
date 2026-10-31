import SwiftUI
import SwiftData

@main
struct MonoTaskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthManager.shared
    @AppStorage("monotask_appearance") private var appearance = "light"

    init() {
        Theme.registerFonts()
        NotificationService.shared.install()
    }

    var body: some Scene {
        WindowGroup("MonoTask", id: "workspace") {
            rootView
                .environment(auth)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .modifier(AppIconAppearance(preference: appearance))
                .onOpenURL { url in
                    if !SharedListStore.shared.receiveInvitation(url) {
                        Task { await auth.handleAuthURL(url) }
                    }
                }
                .task(id: auth.userID) {
                    SharedListStore.shared.activateAccount()
                    await SharedListStore.shared.sync()
                }
                .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in syncActiveStore() }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in syncActiveStore() }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    syncActiveStore()
                }
                .onReceive(NotificationCenter.default.publisher(for: .macTriggerSync)) { _ in syncActiveStore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { syncActiveStore() }
                    if phase == .background { TaskDeletionManager.shared.commitPending() }
                }
                #if os(macOS)
            .modifier(MacIslandLifecycle())
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая задача") {
                    NotificationCenter.default.post(name: .macFocusNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Синхронизировать") {
                    NotificationCenter.default.post(name: .macTriggerSync, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Островок") {
                Button("Раскрыть MonoTask Island") { IslandController.shared.preview() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Добавить задачу в островке") { IslandController.shared.beginCapture() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!IslandController.shared.preferences.enabled)
            }
        }
        #endif
    }

    private func syncActiveStore() {
        Task { await SharedListStore.shared.sync() }
        guard auth.userID != nil, let container = auth.activeContainer,
            NetworkMonitor.shared.isConnected
        else { return }
        NotificationService.shared.refresh(context: container.mainContext)
        Task { @MainActor in
            try? await SupabaseSyncService.shared.sync(context: container.mainContext)
        }
    }

    @ViewBuilder private var rootView: some View {
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        if ProcessInfo.processInfo.arguments.contains("--onboarding-preview") {
            OnboardingPreviewRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--auth-preview") {
            AuthView()
        } else if ProcessInfo.processInfo.arguments.contains("--screenshots") {
            ScreenshotPreviewRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--scroll-gesture-test") {
            ScrollGestureTestRoot()
        } else {
            AuthenticatedRootView()
        }
        #else
        AuthenticatedRootView()
        #endif
    }
}
