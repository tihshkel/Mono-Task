import Foundation

/// Device-local preferences. Missing keys retain the previous user's choices during upgrades.
struct IslandPreferences: Codable, Equatable {
    var enabled = true
    var animations = true
    var reminders = true
    var showTimer = true
    var showDeadline = true
    var showProgress = true
    var focusMinutes = 25
    var dropAction = IslandDropAction.focus
    var clickAction = IslandClickAction.expand
    var accent = IslandAccent.lime
    var surfaceStyle = IslandSurfaceStyle.glow
    var panelSize = IslandPanelSize.balanced
    var motion = IslandMotion.fluid
    var compactContent = IslandCompactContent.timer
    var expandOnHover = true
    var collapseDelay = 0.35
    var celebrateCompletion = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, animations, reminders, showTimer, showDeadline, showProgress, focusMinutes
        case dropAction, clickAction, accent, surfaceStyle, panelSize, motion, compactContent
        case expandOnHover, collapseDelay, celebrateCompletion
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        animations = try values.decodeIfPresent(Bool.self, forKey: .animations) ?? animations
        reminders = try values.decodeIfPresent(Bool.self, forKey: .reminders) ?? reminders
        showTimer = try values.decodeIfPresent(Bool.self, forKey: .showTimer) ?? showTimer
        showDeadline = try values.decodeIfPresent(Bool.self, forKey: .showDeadline) ?? showDeadline
        showProgress = try values.decodeIfPresent(Bool.self, forKey: .showProgress) ?? showProgress
        focusMinutes = max(1, min(120, try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? focusMinutes))
        dropAction = (try? values.decode(IslandDropAction.self, forKey: .dropAction)) ?? dropAction
        clickAction = (try? values.decode(IslandClickAction.self, forKey: .clickAction)) ?? clickAction
        accent = (try? values.decode(IslandAccent.self, forKey: .accent)) ?? accent
        surfaceStyle = (try? values.decode(IslandSurfaceStyle.self, forKey: .surfaceStyle)) ?? surfaceStyle
        panelSize = (try? values.decode(IslandPanelSize.self, forKey: .panelSize)) ?? panelSize
        motion = (try? values.decode(IslandMotion.self, forKey: .motion)) ?? motion
        compactContent = (try? values.decode(IslandCompactContent.self, forKey: .compactContent)) ?? compactContent
        expandOnHover = try values.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? expandOnHover
        let delay = try values.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? collapseDelay
        collapseDelay = delay.isFinite ? max(0.1, min(1.5, delay)) : 0.35
        celebrateCompletion = try values.decodeIfPresent(Bool.self, forKey: .celebrateCompletion) ?? celebrateCompletion
    }
}

enum IslandAccent: String, Codable, CaseIterable {
    case lime, orange, violet
    var title: String {
        switch self {
        case .lime: "Лайм";
        case .orange: "Оранжевый";
        case .violet: "Фиолетовый"
        }
    }
}

enum IslandSurfaceStyle: String, Codable, CaseIterable {
    case quiet, glow, spectrum
    var title: String {
        switch self {
        case .quiet: "Матовый";
        case .glow: "Свечение";
        case .spectrum: "Спектр"
        }
    }
}

enum IslandPanelSize: String, Codable, CaseIterable {
    case compact, balanced, wide
    var title: String {
        switch self {
        case .compact: "Компактный";
        case .balanced: "Обычный";
        case .wide: "Широкий"
        }
    }
    var width: Double {
        switch self {
        case .compact: 380;
        case .balanced: 420;
        case .wide: 470
        }
    }
}

enum IslandMotion: String, Codable, CaseIterable {
    case calm, fluid, playful
    var title: String {
        switch self {
        case .calm: "Спокойно";
        case .fluid: "Плавно";
        case .playful: "Упруго"
        }
    }
}

enum IslandCompactContent: String, Codable, CaseIterable {
    case minimal, timer, task
    var title: String {
        switch self {
        case .minimal: "Минимум";
        case .timer: "Таймер";
        case .task: "Текущая задача"
        }
    }
}

enum IslandDropAction: String, Codable, CaseIterable {
    case focus, enqueue
}

enum IslandClickAction: String, Codable, CaseIterable {
    case expand, timer, openApp
}

/// IDs are scoped to the signed-in account; adding an item never moves it out of its category.
struct IslandQueue: Codable, Equatable {
    private(set) var ids: [UUID] = []
    private(set) var activeID: UUID?

    mutating func add(_ id: UUID, makeActive: Bool) {
        if !ids.contains(id) { ids.append(id) }
        if makeActive || activeID == nil { activeID = id }
    }

    mutating func reconcile(availableIDs: Set<UUID>) {
        ids = ids.filter { availableIDs.contains($0) }
        if let activeID, ids.contains(activeID) { return }
        activeID = ids.first
    }

    mutating func next() {
        guard !ids.isEmpty else { activeID = nil; return }
        let index = activeID.flatMap { ids.firstIndex(of: $0) } ?? -1
        activeID = ids[(index + 1) % ids.count]
    }

    mutating func remove(_ id: UUID) {
        let index = ids.firstIndex(of: id) ?? 0
        ids.removeAll { $0 == id }
        if activeID == id { activeID = ids.isEmpty ? nil : ids[min(index, ids.count - 1)] }
    }
}

/// A deadline, rather than timer ticks, keeps a focus session accurate across sleep and relaunch.
struct IslandFocusClock: Codable, Equatable {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var pausedRemaining: TimeInterval = 25 * 60
    private(set) var endsAt: Date?
    private(set) var hasStarted = false
    private(set) var taskID: UUID?

    var isRunning: Bool { endsAt != nil }

    func remaining(at date: Date) -> TimeInterval {
        max(0, endsAt.map { $0.timeIntervalSince(date) } ?? pausedRemaining)
    }

    mutating func start(minutes: Int, taskID: UUID?, at date: Date) {
        duration = TimeInterval(max(1, min(minutes, 120)) * 60)
        pausedRemaining = duration
        endsAt = date.addingTimeInterval(duration)
        hasStarted = true
        self.taskID = taskID
    }

    mutating func pause(at date: Date) {
        pausedRemaining = remaining(at: date)
        endsAt = nil
    }

    mutating func resume(at date: Date) {
        guard hasStarted, pausedRemaining > 0 else { return }
        endsAt = date.addingTimeInterval(pausedRemaining)
    }

    @discardableResult
    mutating func finishIfNeeded(at date: Date) -> Bool {
        guard isRunning, remaining(at: date) <= 0 else { return false }
        endsAt = nil
        pausedRemaining = 0
        return true
    }

    mutating func reset(minutes: Int) {
        self = IslandFocusClock()
        duration = TimeInterval(max(1, min(minutes, 120)) * 60)
        pausedRemaining = duration
    }
}
