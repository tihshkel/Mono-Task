#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

enum IslandPalette {
    static func accent(_ preferences: IslandPreferences) -> Color {
        switch preferences.accent {
        case .lime: Theme.Colors.sunGlare
        case .orange: Theme.Colors.exuberantOrange
        case .violet: Color(hex: "#B8A4FF")
        }
    }
}

struct IslandBackdrop: View {
    let preferences: IslandPreferences
    var running = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color.black
            if !reduceTransparency && preferences.surfaceStyle != .quiet {
                LinearGradient(colors: [.black, Color(hex: "#19151E")], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [IslandPalette.accent(preferences).opacity(running ? 0.20 : 0.10), .clear],
                    center: .bottomTrailing, startRadius: 0, endRadius: 260)
                RadialGradient(
                    colors: [Theme.Colors.blueViolet.opacity(0.22), .clear],
                    center: .topLeading, startRadius: 0, endRadius: 230)
                if preferences.surfaceStyle == .spectrum {
                    RadialGradient(
                        colors: [Theme.Colors.exuberantOrange.opacity(0.22), .clear],
                        center: .bottomLeading, startRadius: 0, endRadius: 190)
                }
            }
        }
    }
}

struct IslandView: View {
    @Bindable var controller: IslandController
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt)]) private var tasks:
        [TaskItem]
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]
    @State private var draft = ""
    @FocusState private var captureFocused: Bool
    @Namespace private var focusMorph

    private var accent: Color { IslandPalette.accent(controller.preferences) }
    private let secondary = Color.white.opacity(0.52)
    private var expanded: Bool { controller.presentation == .expanded }
    private var radius: CGFloat { expanded ? 30 : controller.presentation == .compact ? 14 : 27 }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: controller.hasNotch ? 0 : radius, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: controller.hasNotch ? 0 : radius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            surface
            Spacer(minLength: 0)
        }
        .frame(width: 560, height: 460, alignment: .top).ignoresSafeArea().preferredColorScheme(.dark)
        .onChange(of: tasks.map { "\($0.id)-\($0.updatedAt.timeIntervalSince1970)-\($0.bucketRaw)" }, initial: true) {
            _, _ in
            controller.update(tasks: tasks, tags: tags)
        }
        .onChange(of: tags.map { "\($0.id)-\($0.updatedAt.timeIntervalSince1970)" }) { _, _ in
            controller.update(tasks: tasks, tags: tags)
        }
        .onChange(of: controller.capturing) { _, capturing in captureFocused = capturing }
        .task(id: controller.capturing) {
            guard controller.capturing else { return }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            captureFocused = true
        }
        .onExitCommand { controller.collapse() }
    }

    private var surface: some View {
        VStack(spacing: 0) {
            cameraHeader
            switch controller.presentation {
            case .compact: EmptyView()
            case .expanded: expandedContent.transition(.opacity.combined(with: .offset(y: -8)))
            case .drop: dropContent.transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .message: messageContent.transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: controller.surfaceSize.width, height: controller.surfaceSize.height, alignment: .top)
        .background {
            if controller.presentation == .compact {
                Color.black
            } else {
                IslandBackdrop(preferences: controller.preferences, running: controller.clock.isRunning)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: controller.preferences.surfaceStyle == .quiet
                        ? [.white.opacity(0.08), .white.opacity(0.04)]
                        : [
                            accent.opacity(0.12), .white.opacity(0.06), Theme.Colors.blueViolet.opacity(0.35),
                            accent.opacity(0.32),
                        ],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: controller.presentation == .compact ? 0 : 0.8
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(controller.presentation == .compact ? 0 : 0.38), radius: 22, y: 10)
        .animation(controller.animation, value: controller.surfaceSize)
        .animation(controller.animation, value: controller.preferences)
        .contentShape(shape)
        .dropDestination(for: String.self) { values, _ in
            controller.accept(values)
        } isTargeted: {
            controller.dropTargeted = $0
        }
        .accessibilityElement(children: .contain).accessibilityLabel("MonoTask Island")
        .accessibilityIdentifier("monotask-island")
    }

    private var cameraHeader: some View {
        ZStack {
            if controller.presentation == .compact {
                Button(action: compactAction) {
                    HStack(spacing: 0) {
                        if controller.preferences.compactContent == .timer && controller.clock.isRunning {
                            IslandWaveform(color: accent, animated: controller.animation != nil)
                                .frame(width: 22, height: 15)
                                .matchedGeometryEffect(id: "focus-indicator", in: focusMorph)
                                .frame(width: controller.hasNotch ? 58 : 36)
                            if controller.hasNotch { Spacer(minLength: controller.notchWidth) }
                            Text(controller.timerText).font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit().foregroundStyle(accent).frame(width: 68)
                                .contentTransition(.numericText(countsDown: true))
                        } else if controller.preferences.compactContent == .task, let task = controller.activeTask {
                            Image(systemName: task.tags.first?.folderIconName ?? "circle.dotted")
                                .font(.system(size: 12)).foregroundStyle(accent)
                                .frame(width: controller.hasNotch ? 58 : 32)
                            if controller.hasNotch { Spacer(minLength: controller.notchWidth) }
                            Text(task.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                .foregroundStyle(Theme.Colors.cloudDancer)
                                .frame(width: controller.hasNotch ? 100 : 165, alignment: .leading)
                        } else if !controller.hasNotch {
                            MonoIslandMark().stroke(accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                                .frame(width: 20, height: 12)
                            Text("mono").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                                .padding(.leading, 7)
                            Circle().fill(Theme.Colors.exuberantOrange).frame(width: 3, height: 3).padding(.leading, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).help("MonoTask · наведите курсор или нажмите")
                    .accessibilityLabel("Открыть островок MonoTask")
            } else {
                HStack {
                    Text("MONO").font(.system(size: 8, weight: .semibold)).tracking(2.5)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: controller.hasNotch ? controller.notchWidth : 0)
                    HStack(spacing: 4) {
                        Circle().fill(accent)
                        Circle().fill(Theme.Colors.exuberantOrange)
                        Circle().fill(Theme.Colors.blueViolet)
                    }.frame(width: 20, height: 4)
                }.padding(.horizontal, 23).allowsHitTesting(false)
            }
        }
        .frame(height: controller.headerHeight).contentShape(Rectangle())
        .onTapGesture { if expanded { controller.collapse() } }
    }

    private var expandedContent: some View {
        VStack(spacing: 16) {
            taskContent.frame(height: 90)
            if controller.preferences.showTimer { timerControl }
            if controller.capturing { captureField.transition(.opacity.combined(with: .move(edge: .top))) }
            footer
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
    }

    private var taskContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 4, height: 4)
                    Text("СЕЙЧАС В ФОКУСЕ").font(.system(size: 9, weight: .medium)).tracking(1.3)
                }.foregroundStyle(secondary)
                Spacer()
                queueMenu
            }
            if let task = controller.activeTask {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: controller.completeActive) {
                        RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.8), lineWidth: 1.4)
                            )
                            .frame(width: 26, height: 26)
                    }.buttonStyle(.plain).help("Отметить выполненной")
                        .accessibilityLabel("Завершить \(task.title)").accessibilityIdentifier("island-complete")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.system(size: 17, weight: .medium)).tracking(-0.2)
                            .foregroundStyle(Theme.Colors.cloudDancer).lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: task.tags.first?.folderIconName ?? "tray")
                                .foregroundStyle(task.tags.first?.color ?? secondary)
                            Text(task.tags.first?.name ?? "Без папки").lineLimit(1)
                            if controller.preferences.showDeadline, let due = task.dueDate {
                                Text("·")
                                Image(systemName: "clock")
                                Text(due, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    .foregroundStyle(due < controller.now ? Theme.Colors.exuberantOrange : secondary)
                                    .lineLimit(1)
                            }
                        }.font(.system(size: 10)).foregroundStyle(secondary)
                    }
                    Spacer(minLength: 0)
                    if controller.queuedTasks.count > 1 {
                        iconButton("Следующая задача", symbol: "forward.end", action: controller.nextTask)
                    }
                }
                .id(task.id).transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 12)),
                        removal: .opacity.combined(with: .offset(x: -12))))
            } else {
                HStack(spacing: 13) {
                    Image(systemName: "sparkles").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                        .frame(width: 29)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Место для главного").font(.system(size: 17, weight: .medium))
                        Text("Перетащите задачу или выберите из очереди").font(.system(size: 11)).foregroundStyle(
                            secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).animation(
            controller.animation, value: controller.activeTask?.id)
    }

    private var queueMenu: some View {
        Menu {
            if !controller.queuedTasks.isEmpty {
                Section("Быстрый доступ") {
                    ForEach(controller.queuedTasks) { task in
                        Button {
                            controller.focusTask(task)
                        } label: {
                            if task.id == controller.activeTask?.id {
                                Label(task.title, systemImage: "checkmark")
                            } else {
                                Text(task.title)
                            }
                        }
                    }
                }
                Button("Убрать текущую из островка", action: controller.unpinActive)
                Divider()
            }
            Menu("Выбрать из задач") {
                ForEach(controller.openTasks) { task in Button(task.title) { controller.focusTask(task) } }
                if controller.openTasks.isEmpty { Text("Открытых задач пока нет") }
            }
        } label: {
            HStack(spacing: 5) {
                Text(controller.queuedTasks.isEmpty ? "Выбрать" : "\(controller.queuedTasks.count) в очереди")
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }.font(.system(size: 10)).foregroundStyle(secondary)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Задачи быстрого доступа")
    }

    private var timerControl: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 3)
                Circle().trim(
                    from: 0,
                    to: controller.clock.hasStarted
                        ? max(0, min(1, controller.remaining / controller.clock.duration)) : 1
                )
                .stroke(
                    AngularGradient(
                        colors: controller.preferences.surfaceStyle == .spectrum
                            ? [accent, Theme.Colors.blueViolet, Theme.Colors.exuberantOrange, accent]
                            : [accent, accent],
                        center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                if controller.clock.isRunning {
                    IslandWaveform(color: accent, animated: controller.animation != nil).frame(width: 16, height: 15)
                } else {
                    Image(systemName: "timer").font(.system(size: 13)).foregroundStyle(accent)
                }
            }.frame(width: 37, height: 37).matchedGeometryEffect(id: "focus-indicator", in: focusMorph)
            VStack(alignment: .leading, spacing: 5) {
                Text(controller.clock.isRunning ? "В потоке" : "Фокус").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.cloudDancer)
                Text(controller.clock.hasStarted && !controller.clock.isRunning ? "На паузе" : "Одно дело за раз")
                    .font(.system(size: 9)).foregroundStyle(secondary)
            }.lineLimit(1)
            Spacer(minLength: 0)
            Text(controller.timerText).font(.system(size: 23, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(accent).contentTransition(.numericText(countsDown: true))
                .animation(controller.animation, value: controller.timerText)
            iconButton(
                controller.clock.isRunning ? "Приостановить" : "Начать фокус",
                symbol: controller.clock.isRunning ? "pause.fill" : "play.fill", active: true,
                action: controller.toggleTimer
            ).accessibilityIdentifier("island-timer")
            if controller.clock.hasStarted {
                iconButton("Сбросить таймер", symbol: "arrow.counterclockwise", action: controller.resetTimer)
            }
        }
        .padding(.horizontal, 14).frame(height: 70)
        .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(accent.opacity(0.1), lineWidth: 0.7))
    }

    private var captureField: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").foregroundStyle(accent)
            TextField("Что нужно сделать?", text: $draft).textFieldStyle(.plain).font(.system(size: 12))
                .focused($captureFocused).onSubmit(submitTask).accessibilityIdentifier("island-capture")
            Button(action: submitTask) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 23)).foregroundStyle(accent)
            }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Добавить задачу")
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.24), lineWidth: 0.7))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if controller.preferences.showProgress {
                ZStack {
                    Circle().stroke(.white.opacity(0.10), lineWidth: 2)
                    Circle().trim(from: 0, to: controller.dayProgress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 16, height: 16)
                Text("\(controller.completedToday) готово сегодня").font(.system(size: 10)).foregroundStyle(secondary)
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                MonoIslandMark().stroke(accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 19, height: 13)
            }
            Spacer(minLength: 0)
            iconButton(
                controller.pinnedOpen ? "Открепить панель" : "Оставить раскрытым", symbol: "pin.fill",
                active: controller.pinnedOpen, action: controller.togglePinned
            )
            .accessibilityIdentifier("island-pin")
            iconButton("Настроить островок", symbol: "slider.horizontal.3", action: controller.showSettings)
                .accessibilityIdentifier("island-settings")
            iconButton("Добавить задачу", symbol: "plus", action: controller.beginCapture).accessibilityIdentifier(
                "island-add")
            iconButton("Открыть MonoTask", symbol: "arrow.up.right", action: openWorkspace)
        }.frame(height: 30)
    }

    private var dropContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                .symbolEffect(.bounce, options: .nonRepeating, isActive: controller.animation != nil)
            Text(controller.preferences.dropAction == .focus ? "Отпустите. Это главное." : "Добавить в очередь")
                .font(.system(size: 15, weight: .medium))
            Text("Задача останется в своей папке").font(.system(size: 10)).foregroundStyle(secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Отпустите задачу здесь")
    }

    private var messageContent: some View {
        let color =
            controller.message?.symbol == "bell"
            ? Theme.Colors.exuberantOrange
            : controller.message?.symbol == "moon.stars" ? Color(hex: "#B8A4FF") : accent
        return VStack(spacing: 9) {
            IslandMessageGlyph(
                symbol: controller.message?.symbol ?? "checkmark", color: color,
                animated: controller.animation != nil,
                celebrate: controller.preferences.celebrateCompletion && controller.message?.symbol == "checkmark"
            ).id(controller.message)
            Text(controller.message?.title ?? "MonoTask").font(.system(size: 16, weight: .medium))
            Text(controller.message?.subtitle ?? "").font(.system(size: 11)).foregroundStyle(secondary)
                .lineLimit(1).padding(.horizontal, 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconButton(_ title: String, symbol: String, active: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        IslandRoundButton(
            title: title, symbol: symbol, accent: accent, active: active, animated: controller.animation != nil,
            action: action)
    }
    private func compactAction() {
        switch controller.preferences.clickAction {
        case .expand: controller.expand()
        case .timer: controller.toggleTimer()
        case .openApp: openWorkspace()
        }
    }
    private func openWorkspace() { controller.openWorkspace?(); controller.collapse() }
    private func submitTask() { if controller.createTask(title: draft) { draft = "" } }
}

private struct IslandRoundButton: View {
    let title: String
    let symbol: String
    let accent: Color
    var active: Bool
    var animated: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? accent : .white.opacity(hovered ? 1 : 0.65))
                .frame(width: 28, height: 28)
                .background(
                    active ? accent.opacity(hovered ? 0.22 : 0.14) : .white.opacity(hovered ? 0.12 : 0.055),
                    in: Circle()
                )
                .scaleEffect(hovered ? 1.07 : 1).contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .animation(animated ? .easeOut(duration: 0.16) : nil, value: hovered)
        .help(title).accessibilityLabel(title)
    }
}

private struct IslandWaveform: View {
    let color: Color
    var animated: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Capsule().fill(color.opacity(index == 2 ? 1 : 0.7))
                        .frame(width: 2.5, height: 4 + 10 * (0.5 + 0.5 * sin(time * 4 + Double(index) * 1.25)))
                }
            }
        }.accessibilityHidden(true)
    }
}

private struct IslandMessageGlyph: View {
    let symbol: String
    let color: Color
    let animated: Bool
    let celebrate: Bool
    @State private var revealed = false
    var body: some View {
        ZStack {
            if celebrate && animated {
                ForEach(0..<8) { index in
                    let angle = Double(index) * .pi / 4
                    Circle().fill([color, Theme.Colors.exuberantOrange, Theme.Colors.blueViolet][index % 3])
                        .frame(width: 3, height: 3)
                        .offset(x: cos(angle) * (revealed ? 35 : 8), y: sin(angle) * (revealed ? 35 : 8))
                        .opacity(revealed ? 0 : 1).scaleEffect(revealed ? 0.5 : 1)
                }
            }
            Circle().fill(color.opacity(0.09)).scaleEffect(revealed ? 1 : 0.7)
            if symbol == "checkmark" {
                IslandCheckmark().trim(from: 0, to: revealed ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)).padding(12)
            } else {
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(color)
                    .scaleEffect(revealed ? 1 : 0.8).opacity(revealed ? 1 : 0)
            }
        }
        .frame(width: 44, height: 44)
        .onAppear { withAnimation(animated ? .easeOut(duration: 0.38) : nil) { revealed = true } }
    }
}

private struct IslandCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY * 0.84))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

struct MonoIslandMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.35))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.height * 0.35),
            control1: CGPoint(x: rect.minX, y: -rect.height * 0.1),
            control2: CGPoint(x: rect.midX, y: -rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.35))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.35),
            control1: CGPoint(x: rect.midX, y: -rect.height * 0.1),
            control2: CGPoint(x: rect.maxX, y: -rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
#endif
