#if os(macOS)
import AppKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IslandController {
    static let shared = IslandController()

    enum Presentation: Equatable { case compact, expanded, drop, message }
    struct Message: Equatable, Hashable {
        var symbol: String
        var title: String
        var subtitle: String
    }

    var preferences = IslandPreferences() {
        didSet {
            guard !loading else { return }
            persist()
            if !preferences.enabled { collapse() }
            updateVisibility()
        }
    }
    private(set) var queue = IslandQueue()
    private(set) var clock = IslandFocusClock()
    private(set) var tasks: [TaskItem] = []
    private(set) var tags: [Tag] = []
    private(set) var presentation: Presentation = .compact
    private(set) var message: Message?
    private(set) var now = Date.now
    private(set) var notchWidth: CGFloat = 180
    private(set) var notchHeight: CGFloat = 32
    private(set) var hasNotch = false
    private(set) var capturing = false
    private(set) var pinnedOpen = false
    var settingsRequested = false
    var dropTargeted = false
    @ObservationIgnored var openWorkspace: (() -> Void)?

    @ObservationIgnored private var panel: IslandPanel?
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var accountKey: String?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var messageUntil: Date?
    @ObservationIgnored private var globalMouseMonitor: Any?
    @ObservationIgnored private var localMouseMonitor: Any?
    @ObservationIgnored private var leaveTask: Task<Void, Never>?
    @ObservationIgnored private var menuObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var menuTracking = false
    @ObservationIgnored private var reminderDates: [UUID: Date] = [:]
    @ObservationIgnored private var lastTick = Date.now
    @ObservationIgnored private var dragNearby = false
    @ObservationIgnored private var preferredScreen: NSScreen?

    var animation: Animation? {
        guard preferences.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        switch preferences.motion {
        case .calm: return .spring(response: 0.38, dampingFraction: 0.96)
        case .fluid: return .spring(response: 0.32, dampingFraction: 0.86)
        case .playful: return .spring(response: 0.38, dampingFraction: 0.74)
        }
    }

    var openTasks: [TaskItem] {
        tasks.filter {
            $0.modelContext != nil && !$0.isDeleted && !$0.isDone && !TaskDeletionManager.shared.isPending($0)
        }
    }

    var queuedTasks: [TaskItem] {
        let available = Dictionary(uniqueKeysWithValues: openTasks.map { ($0.id, $0) })
        return queue.ids.compactMap { available[$0] }
    }

    var activeTask: TaskItem? {
        queuedTasks.first { $0.id == queue.activeID }
    }

    var completedToday: Int {
        tasks.filter {
            $0.modelContext != nil && !$0.isDeleted && $0.isDone
                && $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } == true
        }.count
    }

    var dayProgress: Double {
        let scheduled = FocusService.shared.currentFocusTags(allTags: tags, override: nil)
        let remaining = TaskScope.focus.filter(openTasks, scheduledTags: scheduled).count
        let total = completedToday + remaining
        return total == 0 ? 0 : Double(completedToday) / Double(total)
    }

    var headerHeight: CGFloat { hasNotch ? notchHeight + 5 : 30 }
    var remaining: TimeInterval { clock.hasStarted ? clock.remaining(at: now) : Double(preferences.focusMinutes * 60) }
    var timerText: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var surfaceSize: CGSize {
        switch presentation {
        case .compact:
            let taskPreview = preferences.compactContent == .task && activeTask != nil
            let timerPreview = preferences.compactContent == .timer && clock.isRunning
            return CGSize(
                width: hasNotch
                    ? notchWidth + (taskPreview ? 166 : timerPreview ? 134 : 8)
                    : (taskPreview ? 222 : timerPreview ? 154 : 104),
                height: headerHeight)
        case .expanded:
            return CGSize(
                width: max(preferences.panelSize.width, notchWidth + 144),
                height: headerHeight + 256
                    - (preferences.showTimer ? 0 : 86) + (capturing ? 56 : 0))
        case .drop: return CGSize(width: max(350, notchWidth + 90), height: headerHeight + 120)
        case .message: return CGSize(width: max(380, notchWidth + 110), height: headerHeight + 124)
        }
    }

    func attach(container: ModelContainer?, accountID: UUID?) {
        guard self.container !== container else { return }
        detach()
        guard let container else { return }
        self.container = container
        #if DEBUG
        let preview =
            ProcessInfo.processInfo.arguments.contains("--screenshots")
            || ProcessInfo.processInfo.arguments.contains("--scroll-gesture-test")
        #else
        let preview = false
        #endif
        guard accountID != nil || preview else { self.container = nil; return }
        accountKey = accountID.map { "monotask.island.\($0.uuidString)" }
        loading = true
        now = .now
        preferences = IslandPreferences()
        if let accountKey {
            let defaults = UserDefaults.standard
            preferences =
                defaults.data(forKey: accountKey + ".preferences")
                .flatMap { try? JSONDecoder().decode(IslandPreferences.self, from: $0) } ?? IslandPreferences()
            queue =
                defaults.data(forKey: accountKey + ".queue")
                .flatMap { try? JSONDecoder().decode(IslandQueue.self, from: $0) } ?? IslandQueue()
            clock =
                defaults.data(forKey: accountKey + ".clock")
                .flatMap { try? JSONDecoder().decode(IslandFocusClock.self, from: $0) } ?? IslandFocusClock()
        }
        loading = false
        tasks = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        tags = (try? container.mainContext.fetch(FetchDescriptor<Tag>())) ?? []
        queue.reconcile(availableIDs: Set(openTasks.map(\.id)))
        lastTick = .now
        reminderDates = Dictionary(
            uniqueKeysWithValues: openTasks.compactMap { task in
                task.scheduledReminderDate.map { (task.id, $0) }
            })

        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "MonoTask Island"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: IslandView(controller: self).modelContainer(container))
        self.panel = panel
        positionPanel()
        updateVisibility()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.positionPanel() } }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.collapse() } }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }
        for (name, tracking) in [
            (NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false),
        ] {
            menuObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.menuTracking = tracking
                        if !tracking { self?.updatePointer() }
                    }
                })
        }
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        #if DEBUG
        if preview && ProcessInfo.processInfo.arguments.contains("--island-expanded") {
            if let task = openTasks.first { queue.add(task.id, makeActive: true) }
            expand()
            messageUntil = Date.now.addingTimeInterval(30)
        }
        #endif
    }

    func detach() {
        persist()
        leaveTask?.cancel()
        leaveTask = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers = []
        menuTracking = false
        ticker?.invalidate()
        ticker = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        screenObserver = nil
        resignObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel?.contentView = nil
        panel = nil
        container = nil
        accountKey = nil
        tasks = []
        tags = []
        queue = IslandQueue()
        clock = IslandFocusClock()
        message = nil
        messageUntil = nil
        presentation = .compact
        capturing = false
        pinnedOpen = false
        dropTargeted = false
        dragNearby = false
        preferredScreen = nil
    }

    func update(tasks: [TaskItem], tags: [Tag]) {
        self.tasks = tasks
        self.tags = tags
        let oldQueue = queue
        queue.reconcile(availableIDs: Set(openTasks.map(\.id)))
        if oldQueue != queue { persist() }
        if let id = clock.taskID, !openTasks.contains(where: { $0.id == id }) { resetTimer() }
    }

    @discardableResult
    func accept(_ values: [String]) -> Bool {
        let available = Set(openTasks.map(\.id))
        let ids = values.compactMap(UUID.init(uuidString:)).filter { available.contains($0) }
        guard !ids.isEmpty else { return false }
        for (index, id) in ids.enumerated() {
            queue.add(id, makeActive: preferences.dropAction == .focus && index == 0)
        }
        persist()
        dropTargeted = false
        dragNearby = false
        let title = openTasks.first { $0.id == ids[0] }?.title ?? "Задача"
        showMessage(symbol: "checkmark", title: "Задача рядом", subtitle: title, seconds: 1.8)
        return true
    }

    func pin(_ task: TaskItem) {
        _ = accept([task.id.uuidString])
    }

    func focusTask(_ task: TaskItem) {
        guard openTasks.contains(where: { $0.id == task.id }) else { return }
        queue.add(task.id, makeActive: true)
        persist()
    }

    func completeActive() {
        guard let task = activeTask, let context = container?.mainContext else { return }
        let title = task.title
        if clock.taskID == task.id { resetTimer() }
        queue.remove(task.id)
        context.setCompleted(task, true)
        persist()
        showMessage(symbol: "checkmark", title: "Ещё одно дело позади", subtitle: title, seconds: 2)
    }

    func nextTask() {
        queue.next()
        persist()
    }

    func unpinActive() {
        guard let id = activeTask?.id else { return }
        queue.remove(id)
        persist()
    }

    func expand() {
        messageUntil = nil
        message = nil
        transition(to: .expanded)
    }

    func collapse() {
        leaveTask?.cancel()
        leaveTask = nil
        capturing = false
        pinnedOpen = false
        messageUntil = nil
        message = nil
        transition(to: .compact)
        if panel?.isKeyWindow == true { panel?.resignKey() }
    }

    func beginCapture() {
        expand()
        capturing = true
        panel?.makeKey()
    }

    func togglePinned() {
        pinnedOpen.toggle()
        if pinnedOpen { expand() }
    }

    func showSettings() {
        settingsRequested = true
        openWorkspace?()
        collapse()
    }

    @discardableResult
    func createTask(title: String) -> Bool {
        guard let task = container?.mainContext.createTask(title: title, tag: nil, highPriority: false) else {
            return false
        }
        if !tasks.contains(where: { $0.id == task.id }) { tasks.append(task) }
        queue.add(task.id, makeActive: queue.activeID == nil)
        persist()
        capturing = false
        panel?.resignKey()
        return true
    }

    func toggleTimer() {
        now = .now
        if clock.isRunning {
            clock.pause(at: now)
        } else if clock.hasStarted && clock.remaining(at: now) > 0 {
            clock.resume(at: now)
        } else {
            clock.start(minutes: preferences.focusMinutes, taskID: activeTask?.id, at: now)
        }
        persist()
    }

    func resetTimer() {
        clock.reset(minutes: preferences.focusMinutes)
        persist()
    }

    func preview() {
        guard preferences.enabled else { return }
        expand()
        messageUntil = .now.addingTimeInterval(5)
    }

    private func showMessage(symbol: String, title: String, subtitle: String, seconds: TimeInterval) {
        guard preferences.enabled else { return }
        capturing = false
        message = Message(symbol: symbol, title: title, subtitle: subtitle)
        messageUntil = Date.now.addingTimeInterval(seconds)
        transition(to: .message)
    }

    private func transition(to value: Presentation) {
        guard presentation != value else { return }
        withAnimation(animation) { presentation = value }
    }

    private func positionPanel() {
        guard let panel else { return }
        // Prefer the physical camera, even when an external display owns the menu bar.
        guard
            let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        preferredScreen = screen
        hasNotch = screen.safeAreaInsets.top > 0
        notchHeight = hasNotch ? screen.safeAreaInsets.top : 30
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(100, right.minX - left.maxX)
        } else {
            notchWidth = 180
        }
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - 280,
                y: screen.frame.maxY - 460 - (hasNotch ? 0 : 6),
                width: 560, height: 460), display: true)
    }

    private func updateVisibility() {
        if preferences.enabled { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
    }

    private func tick() {
        let date = Date.now
        // A suspended Mac may skip arbitrarily many ticks; elapsed time still comes from the deadline.
        if date.timeIntervalSince(now) >= 1 {
            now = date
            let oldQueue = queue
            queue.reconcile(availableIDs: Set(openTasks.map(\.id)))
            if queue != oldQueue { persist() }
            if clock.finishIfNeeded(at: date) {
                persist()
                showMessage(
                    symbol: "moon.stars", title: "Время сделать паузу", subtitle: "Фокус завершён. Выдохните.",
                    seconds: 5)
            }
            checkReminders(from: lastTick, to: date)
            lastTick = date
        }
        if let until = messageUntil, date >= until {
            messageUntil = nil
            message = nil
            transition(to: .compact)
        }
        updatePointer()
    }

    /// Pointer events start expansion in the same run-loop turn; the timer is only a fallback.
    private func updatePointer() {
        guard preferences.enabled, let panel, preferredScreen != nil else { return }
        let size = surfaceSize
        let rect = NSRect(
            x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height,
            width: size.width, height: size.height)
        let pointer = NSEvent.mouseLocation
        let inside = (presentation == .compact ? rect.insetBy(dx: -10, dy: -6) : rect).contains(pointer)
        var validDrag = false
        if NSEvent.pressedMouseButtons & 1 != 0,
            let raw = NSPasteboard(name: .drag).string(forType: .string), let id = UUID(uuidString: raw)
        {
            validDrag = openTasks.contains { $0.id == id }
        }
        dragNearby = validDrag && rect.insetBy(dx: -65, dy: -55).contains(pointer)
        panel.ignoresMouseEvents = !inside && !dragNearby
        if dragNearby || dropTargeted {
            leaveTask?.cancel()
            leaveTask = nil
            transition(to: .drop)
            return
        }
        if presentation == .drop { transition(to: .compact) }
        if inside {
            leaveTask?.cancel()
            leaveTask = nil
            if (presentation == .compact && preferences.expandOnHover) || presentation == .message { expand() }
        } else if !capturing && !pinnedOpen && !menuTracking && messageUntil == nil && presentation != .compact
            && leaveTask == nil
        {
            leaveTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.preferences.collapseDelay))
                guard !Task.isCancelled, !self.capturing, !self.pinnedOpen, !self.menuTracking else { return }
                self.collapse()
            }
        }
    }

    private func checkReminders(from previous: Date, to date: Date) {
        var due: TaskItem?
        var earliest: Date?
        for task in openTasks {
            guard let deadline = task.scheduledReminderDate else { reminderDates[task.id] = nil; continue }
            // New or rescheduled deadlines get one chance; old overdue tasks never flood the island.
            let changed = reminderDates[task.id] != deadline
            if deadline <= date && (deadline > previous || (changed && date.timeIntervalSince(deadline) < 60)) {
                if earliest == nil || deadline < earliest! { due = task; earliest = deadline }
            }
            reminderDates[task.id] = deadline
        }
        guard preferences.reminders, let due, !capturing, presentation != .drop else { return }
        showMessage(symbol: "bell", title: "Пора вернуться к задаче", subtitle: due.title, seconds: 6)
    }

    private func persist() {
        guard let accountKey, !loading else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(preferences) {
            UserDefaults.standard.set(data, forKey: accountKey + ".preferences")
        }
        if let data = try? encoder.encode(queue) { UserDefaults.standard.set(data, forKey: accountKey + ".queue") }
        if let data = try? encoder.encode(clock) { UserDefaults.standard.set(data, forKey: accountKey + ".clock") }
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Capture the scene's OpenWindowAction so the independent panel can reopen a closed workspace.
struct MacIslandLifecycle: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                IslandController.shared.openWorkspace = {
                    if let window = NSApp.windows.first(where: {
                        !($0 is NSPanel) && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
                    }) {
                        window.deminiaturize(nil)
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "workspace")
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
#endif
