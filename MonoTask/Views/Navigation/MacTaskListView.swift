import SwiftUI
import SwiftData

#if os(macOS)
struct MacTaskListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt, order: .reverse)]) private
        var allTasks: [TaskItem]
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    let scope: TaskScope
    let today: Date

    @AppStorage("monotask_task_layout") private var taskLayout = "list"
    @State private var search = ""
    @State private var taskTitle: String = ""
    @State private var isHighPriority: Bool = false
    @State private var taskToEdit: TaskItem? = nil
    @State private var showCompleted: Bool = false
    @State private var showingClearCompleted: Bool = false
    @State private var targetedTaskId: UUID? = nil
    @FocusState private var isCaptureFocused: Bool

    private var scheduledTags: [Tag] {
        _ = today
        return FocusService.shared.currentFocusTags(allTags: tags, override: nil)
    }

    private var activeTag: Tag? {
        scope.defaultTag(tags: tags, scheduledTags: scheduledTags)
    }

    private var scopeColor: Color {
        switch scope {
        case .focus, .highPriority: return Theme.Colors.accent
        case .tag(let id): return tags.first { $0.id == id }?.color ?? Theme.Colors.textSecondary
        case .all: return Theme.Colors.textSecondary
        }
    }

    private var filteredTasks: [TaskItem] {
        scope.filter(allTasks, scheduledTags: scheduledTags)
            .filter { !TaskDeletionManager.shared.isPending($0) }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var highPriorityTasks: [TaskItem] {
        filteredTasks.filter { $0.isHighPriorityToday && !$0.isDone }
    }

    private var regularTasks: [TaskItem] {
        filteredTasks.filter { !$0.isHighPriorityToday && !$0.isDone }
    }

    private var completedTasks: [TaskItem] {
        filteredTasks.filter(\.isDone)
    }

    private var progress: Double {
        filteredTasks.isEmpty ? 0 : Double(completedTasks.count) / Double(filteredTasks.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                captureBar

                if !highPriorityTasks.isEmpty {
                    section(
                        title: "Приоритет", tasks: highPriorityTasks, color: Theme.Colors.priority, highPriority: true)
                }

                if !regularTasks.isEmpty {
                    section(
                        title: "Задачи",
                        tasks: regularTasks,
                        color: Theme.Colors.textMuted,
                        highPriority: scope == .highPriority ? nil : false
                    )
                } else if highPriorityTasks.isEmpty {
                    emptyState
                }

                if !completedTasks.isEmpty {
                    completedSection
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 48)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: filteredTasks.map(\.id))
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: highPriorityTasks.map(\.id))
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: completedTasks.map(\.id))
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle(scope.title(tags: tags))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NotificationCenter.default.post(name: .macOpenWorkspace, object: nil)
                } label: {
                    Label("Пространство", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Вид задач", selection: $taskLayout) {
                    Image(systemName: "list.bullet").tag("list")
                    Image(systemName: "square.grid.2x2").tag("cards")
                }.pickerStyle(.segmented).frame(width: 86)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .macTriggerSync, object: nil)
                } label: {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Синхронизировать (⌘R)")
                .disabled(SupabaseService.shared.syncStatus.isSyncing)
            }
        }
        .sheet(item: $taskToEdit) { task in
            TaskEditSheet(task: task)
        }
        .clearCompletedAlert(isPresented: $showingClearCompleted, tasks: completedTasks)
        .onReceive(NotificationCenter.default.publisher(for: .macFocusNewTask)) { _ in
            isCaptureFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 22) {
                if let tag = activeTag, isTagScope {
                    FolderArtwork(tint: tag.color, icon: tag.folderIconName)
                        .frame(width: 115, height: 90)
                } else {
                    Image(systemName: scope == .focus ? "sun.max" : "tray")
                        .font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Theme.Colors.accent)
                        .frame(width: 70, height: 70)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(headerTitle).font(.system(size: 32, weight: .semibold)).tracking(-1)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(headerSubtitle ?? "Всё, что важно, в одном месте.")
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(completedTasks.count) из \(filteredTasks.count) выполнено")
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted)
                }
                Spacer()
            }
            HStack {
                TextField("Найти задачу в папке", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.Colors.textMuted)
            }.padding(12).background(Theme.Colors.fill, in: RoundedRectangle(cornerRadius: 12))
            ProgressLine(progress: progress, height: 3)
        }
    }

    private var headerTitle: String {
        scope == .focus ? "Сегодня" : scope.title(tags: tags)
    }

    private var headerSubtitle: String? {
        switch scope {
        case .focus:
            if scheduledTags.isEmpty { return nil }
            return scheduledTags.map(\.name).joined(separator: " · ")
        case .all: return "Все категории"
        case .highPriority: return "Только срочное"
        case .tag: return "Отдельное место для ваших дел."
        }
    }

    // MARK: - Capture

    private var captureBar: some View {
        let canSubmit = !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            PriorityToggleButton(isOn: $isHighPriority, size: 30)

            TextField(
                "",
                text: $taskTitle,
                prompt: Text("Новая задача  ⌘N").foregroundColor(Theme.Colors.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(Theme.Colors.textPrimary)
            .focused($isCaptureFocused)
            .onSubmit {
                handleCreateTask()
            }

            if let activeTag {
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeTag.color)
                        .frame(width: 6, height: 6)
                    Text(activeTag.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Theme.Colors.fill)
                .clipShape(Capsule())
            }

            SubmitCircleButton(isEnabled: canSubmit, size: 26) {
                handleCreateTask()
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 46)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isCaptureFocused ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.ruleStrong, lineWidth: 1)
        )
    }

    // MARK: - Sections

    private func section(title: String, tasks: [TaskItem], color: Color, highPriority: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: title, count: tasks.count, color: color)
            if taskLayout == "cards" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(tasks) { task in
                        MacWorkspaceTaskCard(
                            task: task, allTags: tags, onEdit: { taskToEdit = task },
                            onComplete: { toggleTaskDone(task) }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let value = items.first, let id = UUID(uuidString: value) else { return false }
                            modelContext.reorderTask(id, onto: task.id, in: allTasks, highPriority: highPriority)
                            return true
                        }
                    }
                }
            } else {
                ForEach(tasks) { task in
                    row(task, highPriority: highPriority)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    showCompleted.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionTitle(text: "Выполнено", count: completedTasks.count)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showCompleted ? 0 : -90))
                        .foregroundColor(Theme.Colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)

            if showCompleted {
                Hairline()
                ForEach(completedTasks) { task in
                    row(task, highPriority: nil)
                    Hairline()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет открытых задач")
                .font(Theme.Typography.heading(24))
                .textCase(.uppercase)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(
                completedTasks.isEmpty
                    ? "В этом списке нет задач. Нажмите ⌘N, чтобы добавить."
                    : "Открытых задач в этом списке не осталось."
            )
            .font(Theme.Typography.callout)
            .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 24)
    }

    private func row(_ task: TaskItem, highPriority: Bool?) -> some View {
        MacTaskRowItem(
            task: task,
            isTargeted: targetedTaskId == task.id,
            allTags: tags,
            showsTag: !isTagScope,
            onEdit: { taskToEdit = $0 },
            onToggleDone: { toggleTaskDone(task) }
        )
        .dropDestination(for: String.self) { items, _ in
            targetedTaskId = nil
            guard let rawId = items.first,
                let sourceId = UUID(uuidString: rawId),
                sourceId != task.id
            else { return false }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                modelContext.reorderTask(sourceId, onto: task.id, in: allTasks, highPriority: highPriority)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                targetedTaskId = targeted ? task.id : (targetedTaskId == task.id ? nil : targetedTaskId)
            }
        }
    }

    private var isTagScope: Bool {
        if case .tag = scope { return true }
        return false
    }

    // MARK: - Actions

    private func handleCreateTask() {
        let created = modelContext.createTask(
            title: taskTitle,
            tag: activeTag,
            highPriority: isHighPriority || scope == .highPriority
        )
        guard created != nil else { return }
        taskTitle = ""
        isHighPriority = false
        isCaptureFocused = true
    }

    private func toggleTaskDone(_ task: TaskItem) {
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
            modelContext.setCompleted(task, !task.isDone)
        }
    }
}

// MARK: - Mac Task Row

struct MacTaskRowItem: View {
    @Bindable var task: TaskItem
    let isTargeted: Bool
    let allTags: [Tag]
    var showsTag: Bool = true
    let onEdit: (TaskItem) -> Void
    let onToggleDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var completing = false
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                guard !completing else { return }
                if task.isDone || reduceMotion {
                    onToggleDone()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { completing = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        guard task.modelContext != nil else { return }
                        onToggleDone()
                        completing = false
                    }
                }
            } label: {
                TaskCheckbox(isDone: task.isDone || completing, isPriority: task.isHighPriorityToday, size: 19)
                    .scaleEffect(completing ? 1.14 : 1)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Вернуть в работу" : "Отметить выполненной")

            Button {
                onEdit(task)
            } label: {
                HStack(spacing: 12) {
                    Text(task.title)
                        .font(.system(size: 15))
                        .tracking(-0.2)
                        .strikethrough(task.isDone, color: Theme.Colors.textMuted)
                        .foregroundColor(task.isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 12)

                    if showNotes && !task.notes.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Colors.textMuted)
                    }

                    if task.hasSubtasks {
                        let allDone = task.completedSubtasksCount == task.subtasksCount
                        Text("\(task.completedSubtasksCount)/\(task.subtasksCount)")
                            .font(Theme.Typography.numeric(11))
                            .foregroundColor(allDone && !task.isDone ? Theme.Colors.accent : Theme.Colors.textMuted)
                    }

                    if showsTag, let tag = task.tags.first {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(task.isDone ? Theme.Colors.textMuted : tag.color)
                                .frame(width: 6, height: 6)
                            Text(tag.name)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, compactRows ? 3 : 6)
        .background(
            Rectangle()
                .fill(isTargeted ? Theme.Colors.fillStrong : (isHovered ? Theme.Colors.fill : Color.clear))
                .padding(.horizontal, -10)
        )
        .onHover { isHovered = $0 }
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .contextMenu {
            if !task.isDone {
                Button {
                    IslandController.shared.pin(task)
                } label: {
                    Label("В MonoTask Island", systemImage: "capsule")
                }
                .disabled(!IslandController.shared.preferences.enabled)
                Divider()
            }
            TaskContextMenu(task: task, allTags: allTags, onEdit: onEdit, onToggleDone: onToggleDone)
        }
    }
}
private struct MacWorkspaceTaskCard: View {
    @Bindable var task: TaskItem
    let allTags: [Tag]
    let onEdit: () -> Void
    let onComplete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onComplete) {
                    TaskCheckbox(isDone: task.isDone, isPriority: task.isHighPriorityToday, size: 19)
                }
                .buttonStyle(.plain).accessibilityLabel("Завершить \(task.title)")
                Spacer()
                if task.isHighPriorityToday {
                    Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(Theme.Colors.priority)
                }
                Menu {
                    TaskContextMenu(task: task, allTags: allTags, onEdit: { _ in onEdit() }, onToggleDone: onComplete)
                    Button("В MonoTask Island") { IslandController.shared.pin(task) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.Colors.textMuted)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    if !task.notes.isEmpty {
                        Text(task.notes).font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(
                            2)
                    }
                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(spacing: 5) {
                if let tag = task.tags.first {
                    Image(systemName: "folder.fill").foregroundStyle(tag.color)
                    Text(tag.name)
                }
                Spacer()
                if task.hasSubtasks { Text("\(task.completedSubtasksCount)/\(task.subtasksCount)") }
                if let due = task.dueDate { Text(due, format: .dateTime.day().month(.abbreviated)) }
            }.font(.system(size: 10)).foregroundStyle(Theme.Colors.textMuted)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.7))
            .draggable(task.id.uuidString)
    }
}
#endif
