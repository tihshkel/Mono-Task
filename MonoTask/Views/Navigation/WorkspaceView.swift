import SwiftUI
import SwiftData

private enum WorkspaceWidget: String, CaseIterable, Identifiable {
    case focus, progress, calendar, timer, note, clock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focus: "Фокус дня"
        case .progress: "Прогресс дня"
        case .calendar: "Календарь"
        case .timer: "Концентрация"
        case .note: "Заметка"
        case .clock: "Часы"
        }
    }
    var icon: String {
        switch self {
        case .focus: "sun.max"
        case .progress: "chart.bar.xaxis"
        case .calendar: "calendar"
        case .timer: "timer"
        case .note: "note.text"
        case .clock: "clock"
        }
    }
}

struct WorkspaceTaskCapture: Identifiable {
    let id = UUID()
    let tag: Tag?
    var highPriority = false
}

struct WorkspaceView: View {
    var onOpenScope: ((TaskScope) -> Void)?
    var onRequestCapture: ((Tag?) -> Void)?
    @Binding var captureTag: Tag?
    @Binding var isCaptureActive: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt)]) private var tasks:
        [TaskItem]
    @Query private var history: [CompletedHistoryEntry]
    @AppStorage("monotask_workspace_widgets") private var widgetOrder = "focus,progress"
    @AppStorage("monotask_workspace_wide") private var wideWidgets = "focus"
    @AppStorage("monotask_workspace_note") private var note = ""
    @AppStorage("monotask_workspace_folder_list") private var folderList = false
    @State private var path = NavigationPath()
    @State private var sharedStore = SharedListStore.shared
    @State private var managingSharedFolder: SharedList?
    @State private var search = ""
    @State private var addingFolder = false
    @State private var editingFolder: Tag?
    @State private var deletingFolder: Tag?
    @State private var taskToEdit: TaskItem?
    @State private var taskCapture: WorkspaceTaskCapture?
    @State private var collapsedFolders: Set<UUID> = []
    @State private var sharedTaskToEdit: SharedTask?
    @State private var sharedTaskToDelete: SharedTask?
    @State private var customizing = false
    @State private var targetFolder: UUID?
    @State private var selectedDate: Date?
    @State private var calendarTaskToEdit: TaskItem?
    @State private var now = Date.now

    init(
        onOpenScope: ((TaskScope) -> Void)? = nil,
        onRequestCapture: ((Tag?) -> Void)? = nil,
        captureTag: Binding<Tag?> = .constant(nil), isCaptureActive: Binding<Bool> = .constant(false)
    ) {
        self.onOpenScope = onOpenScope
        self.onRequestCapture = onRequestCapture
        self._captureTag = captureTag
        self._isCaptureActive = isCaptureActive
    }

    private var widgets: [WorkspaceWidget] {
        widgetOrder.split(separator: ",").compactMap { WorkspaceWidget(rawValue: String($0)) }
    }
    private var openTasks: [TaskItem] { tasks.filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) } }
    private var focusTasks: [TaskItem] {
        let scheduled = FocusService.shared.currentFocusTags(allTags: tags, override: nil)
        return TaskScope.focus.filter(openTasks, scheduledTags: scheduled).sorted {
            if $0.isHighPriorityToday != $1.isHighPriorityToday { return $0.isHighPriorityToday }
            return $0.sortOrder < $1.sortOrder
        }
    }
    private var doneToday: Int {
        let recorded = Set(history.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: now) }.map(\.taskId))
        return recorded.union(
            tasks.filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } == true }.map(\.id)
        ).count
    }
    private var visibleTags: [Tag] {
        search.isEmpty
            ? tags
            : tags.filter { tag in
                tag.name.localizedCaseInsensitiveContains(search)
                    || (folderList && folderTasks(tag).contains { $0.title.localizedCaseInsensitiveContains(search) })
            }
    }
    private var matchingTasks: [TaskItem] { openTasks.filter { $0.title.localizedCaseInsensitiveContains(search) } }
    private var searchResultTasks: [TaskItem] {
        folderList ? matchingTasks.filter { $0.tags.isEmpty } : matchingTasks
    }
    private var visibleSharedFolders: [SharedList] {
        sharedStore.lists.filter { list in
            search.isEmpty || list.title.localizedCaseInsensitiveContains(search)
                || (folderList
                    && sharedStore.tasks(in: list.id).contains {
                        $0.title.localizedCaseInsensitiveContains(search)
                    })
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    #if os(iOS)
                    if search.isEmpty || folderList || !visibleTags.isEmpty || !visibleSharedFolders.isEmpty { folders }
                    #endif
                    if !search.isEmpty {
                        if !folderList || !searchResultTasks.isEmpty { searchResults }
                    } else if !widgets.isEmpty {
                        widgetSection
                    }
                    #if os(macOS)
                    folders
                    #endif
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .scrollIndicators(.hidden)
            .refreshable { await sharedStore.sync() }
            .navigationTitle("Пространство")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if os(macOS)
                    widgetMenu
                    Button {
                        presentTaskCapture()
                    } label: {
                        Label("Новая задача", systemImage: "plus")
                    }
                    .help("Новая задача (⌘N)")
                    #endif
                }
            }
            .navigationDestination(for: TaskScope.self) { scope in
                TodayView(initialScope: scope, isCaptureActive: $isCaptureActive, captureTag: $captureTag)
                    #if os(iOS)
                .navigationTitle("")
                .toolbar(.visible, for: .navigationBar)
                    #else
                .navigationTitle(scope.title(tags: tags))
                    #endif
            }
            .navigationDestination(for: UUID.self) { id in
                SharedListDetailView(listID: id)
                    #if os(iOS)
                .toolbar(.visible, for: .navigationBar)
                    #endif
            }
        }
        .sheet(isPresented: $addingFolder) { TagEditSheet(tagToEdit: nil) }
        .sheet(item: $editingFolder) { TagEditSheet(tagToEdit: $0) }
        .sheet(item: $managingSharedFolder) { SharedMembersView(listID: $0.id) }
        .sheet(item: $taskToEdit) { TaskEditSheet(task: $0) }
        .sheet(item: $taskCapture) { WorkspaceCaptureSheet(tags: tags, initialTag: $0.tag) }
        .sheet(item: $sharedTaskToEdit) { SharedTaskEditor(task: $0) }
        .sheet(isPresented: Binding(get: { selectedDate != nil }, set: { if !$0 { selectedDate = nil } })) {
            if let selectedDate { dateTasks(selectedDate) }
        }
        .confirmationDialog(
            "Удалить папку «\(deletingFolder?.name ?? "")»?",
            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })
        ) {
            Button("Удалить папку", role: .destructive) {
                if let tag = deletingFolder { context.deleteWithSync(tag); context.saveAndSync() }
                deletingFolder = nil
            }
        } message: {
            Text("Задачи сохранятся без категории.")
        }
        .confirmationDialog(
            "Удалить задачу для всех участников?",
            isPresented: Binding(get: { sharedTaskToDelete != nil }, set: { if !$0 { sharedTaskToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if var task = sharedTaskToDelete {
                    task.deletedAt = .now
                    sharedStore.save(task)
                    Task { await sharedStore.sync() }
                }
                sharedTaskToDelete = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macFocusNewTask)) { _ in
            presentTaskCapture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        .onAppear { captureTag = nil }
        .task(id: scenePhase) {
            sharedStore.activateAccount()
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await sharedStore.sync()
                do { try await Task.sleep(for: .seconds(6)) } catch { break }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: widgetOrder)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: wideWidgets)
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        38
        #else
        22
        #endif
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        10
        #else
        28
        #endif
    }

    @ViewBuilder private var heading: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Моё пространство").font(.system(size: 28, weight: .semibold)).tracking(-0.9)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(workspaceDate)
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                widgetMenu
            }
            searchField
        }
        #else
        desktopHeading
        #endif
    }

    private var workspaceDate: String {
        let date = now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
        return date.prefix(1).uppercased() + date.dropFirst()
    }

    private var widgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            Text("Ваш день").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            #endif
            WorkspaceWidgetGrid {
                ForEach(widgets) { widget in
                    widgetTile(widget)
                        .layoutValue(key: WorkspaceWidgetSpan.self, value: widgetSpan(widget))
                        .layoutValue(key: WorkspaceWidgetHeight.self, value: widgetHeight(widget))
                }
            }
        }
    }

    private func widgetSpan(_ widget: WorkspaceWidget) -> Int {
        #if os(iOS)
        if [.focus, .calendar, .note].contains(widget) { return 2 }
        #endif
        return wideWidgets.contains(widget.rawValue) ? 2 : 1
    }
    private func widgetHeight(_ widget: WorkspaceWidget) -> CGFloat {
        #if os(iOS)
        switch widget {
        case .focus: return 178
        case .calendar: return 150
        case .note: return 180
        default: return 160
        }
        #else
        return 190
        #endif
    }

    private var desktopHeading: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(
                    now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
                        .capitalized
                )
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Image(systemName: "circle.dotted").font(.system(size: 16)).foregroundStyle(Theme.Colors.textMuted)
            }
            Text("Ваше пространство")
                .font(.system(size: 35, weight: .semibold)).tracking(-1.4)
                .foregroundStyle(Theme.Colors.textPrimary)
                .minimumScaleFactor(0.75).lineLimit(1)
            HStack(spacing: 12) {
                Text("Всё важное — на своих местах.")
                    .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                #if os(macOS)
                searchField.frame(width: 190)
                #endif
            }
            #if os(iOS)
            searchField
            #endif
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.Colors.textMuted)
            TextField("Поиск задач и папок", text: $search)
                .font(.system(size: 13)).textFieldStyle(.plain)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textMuted)
                }
                .buttonStyle(.plain).accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 13).frame(height: 42)
        .background(Theme.Colors.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Text("Папки").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text("\(tags.count + sharedStore.lists.count)").font(.system(size: 11)).foregroundStyle(
                    Theme.Colors.textMuted)
                Spacer()
                Button {
                    folderList.toggle()
                } label: {
                    Image(systemName: folderList ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).help(folderList ? "Показать сетку папок" : "Показать папки с задачами")
                    .accessibilityLabel(folderList ? "Показать сетку папок" : "Показать папки с задачами")
                    .accessibilityIdentifier("workspace-folder-layout")
                Button {
                    addingFolder = true
                } label: {
                    #if os(iOS)
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent).frame(width: 32, height: 32)
                        .background(Theme.Colors.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    #else
                    Label("Новая папка", systemImage: "plus").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    #endif
                }.buttonStyle(.plain).accessibilityLabel("Новая папка")
            }
            if visibleTags.isEmpty && visibleSharedFolders.isEmpty {
                Button {
                    addingFolder = true
                } label: {
                    VStack(spacing: 10) {
                        Image("BrandMascot").resizable().scaledToFit().frame(width: 90, height: 90)
                        Text(search.isEmpty ? "Создайте первую папку" : "Папки не найдены").font(.system(size: 14))
                        Text("Работа, личное или новая большая идея").font(.system(size: 11)).foregroundStyle(
                            Theme.Colors.textMuted)
                    }.foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 180)
                }.buttonStyle(SoftPressStyle())
            } else if folderList {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(visibleTags) { tag in folderSection(tag) }
                    ForEach(visibleSharedFolders) { list in sharedFolderSection(list) }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145, maximum: 250), spacing: 18)],
                    spacing: 20
                ) {
                    ForEach(visibleTags) { tag in folderTile(tag) }
                    ForEach(visibleSharedFolders) { list in sharedFolderTile(list) }
                }
            }
            Button {
                sharedStore.isPresented = true
            } label: {
                Label("Создать общую папку или присоединиться", systemImage: "person.2.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("workspace-shared-folders")
        }
    }

    private func folderTasks(_ tag: Tag) -> [TaskItem] {
        let contents = tasks.filter {
            $0.tags.contains { $0.id == tag.id } && !TaskDeletionManager.shared.isPending($0)
        }
        return contents.filter { !$0.isDone } + contents.filter(\.isDone)
    }

    private func folderDisclosure(id: UUID, title: String, tint: Color, icon: String, detail: String) -> some View {
        let collapsed = collapsedFolders.contains(id)
        return Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                if collapsed { collapsedFolders.remove(id) } else { collapsedFolders.insert(id) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .foregroundStyle(Theme.Colors.textMuted)
                FolderArtwork(tint: tint, icon: icon).frame(width: 42, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary).lineLimit(2)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Папка \(title), \(detail)")
        .accessibilityValue(collapsed ? "Свёрнута" : "Развёрнута")
        .accessibilityHint(collapsed ? "Развернуть задачи" : "Свернуть задачи")
        .accessibilityIdentifier("workspace-folder-toggle-\(id)")
    }

    private func folderSection(_ tag: Tag) -> some View {
        let contents = folderTasks(tag)
        let matching =
            search.isEmpty || tag.name.localizedCaseInsensitiveContains(search)
            ? contents : contents.filter { $0.title.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                folderDisclosure(
                    id: tag.id, title: tag.name, tint: tag.color, icon: tag.folderIconName,
                    detail: "\(contents.filter { !$0.isDone }.count) открыто")
                Menu {
                    Button("Новая задача", systemImage: "plus") {
                        presentTaskCapture(in: tag)
                    }
                    Button("Открыть папку", systemImage: "arrow.up.right") { open(.tag(tag.id)) }
                    Button("Изменить оформление", systemImage: "pencil") { editingFolder = tag }
                    Button("Удалить папку", systemImage: "trash", role: .destructive) { deletingFolder = tag }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        .foregroundStyle(Theme.Colors.textMuted).contentShape(Rectangle())
                }
                #if os(macOS)
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                #endif
                .accessibilityLabel("Действия с папкой \(tag.name)")
            }
            .draggable("folder:\(tag.id.uuidString)")
            .dropDestination(for: String.self) { items, _ in
                drop(items, onto: tag)
            } isTargeted: {
                targetFolder = $0 ? tag.id : nil
            }
            .background(targetFolder == tag.id ? tag.color.opacity(0.09) : .clear)

            if !collapsedFolders.contains(tag.id) {
                if matching.isEmpty { emptyFolderLabel }
                ForEach(matching) { task in
                    HStack(spacing: 0) {
                        #if os(macOS)
                        MacTaskRowItem(
                            task: task, isTargeted: false, allTags: tags, showsTag: false,
                            onEdit: { taskToEdit = $0 }, onToggleDone: { toggleFolderTask(task) })
                        #else
                        TaskRowView(task: task, allTags: tags, showsTag: false, onEdit: { taskToEdit = $0 })
                        #endif
                        Menu {
                            TaskContextMenu(
                                task: task, allTags: tags, onEdit: { taskToEdit = $0 },
                                onToggleDone: { toggleFolderTask(task) })
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                .foregroundStyle(Theme.Colors.textMuted).contentShape(Rectangle())
                        }
                        #if os(macOS)
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        #endif
                        .accessibilityLabel("Действия с задачей \(task.title)")
                    }
                    .accessibilityIdentifier("workspace-task-\(task.id)")
                }
                .padding(.leading, 24)
            }
        }
    }

    private var emptyFolderLabel: some View {
        Text("В папке пока нет задач")
            .font(.system(size: 12)).foregroundStyle(Theme.Colors.textMuted)
            .padding(.leading, 24).padding(.vertical, 12)
    }

    private func toggleFolderTask(_ task: TaskItem) {
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { context.setCompleted(task, !task.isDone) }
    }

    private func presentTaskCapture(in tag: Tag? = nil) {
        #if os(macOS)
        if let onRequestCapture {
            onRequestCapture(tag)
            return
        }
        #endif
        guard taskCapture == nil else { return }
        taskCapture = WorkspaceTaskCapture(tag: tag)
    }

    private func sharedFolderSection(_ list: SharedList) -> some View {
        let contents = sharedStore.tasks(in: list.id)
        let matching =
            search.isEmpty || list.title.localizedCaseInsensitiveContains(search)
            ? contents : contents.filter { $0.title.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                folderDisclosure(
                    id: list.id, title: list.title, tint: Theme.Colors.blueViolet, icon: "person.2.fill",
                    detail: "Общая · \(contents.filter { !$0.isDone }.count) открыто")
                Menu {
                    Button("Новая задача", systemImage: "plus") {
                        sharedTaskToEdit = SharedTask(listID: list.id, title: "")
                    }
                    Button("Открыть общую папку", systemImage: "arrow.up.right") { path.append(list.id) }
                    Button("Участники и доступ", systemImage: "person.2") { managingSharedFolder = list }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        .foregroundStyle(Theme.Colors.textMuted).contentShape(Rectangle())
                }
                #if os(macOS)
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                #endif
                .accessibilityLabel("Действия с папкой \(list.title)")
            }
            if !collapsedFolders.contains(list.id) {
                if !sharedStore.conflicts(in: list.id).isEmpty {
                    Button("Есть изменения участников — проверить") { path.append(list.id) }
                        .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Theme.Colors.priority)
                        .padding(.leading, 24).frame(minHeight: 44)
                }
                if matching.isEmpty { emptyFolderLabel }
                ForEach(matching) { task in sharedFolderTaskRow(task) }.padding(.leading, 24)
            }
        }
    }

    private func sharedFolderTaskRow(_ task: SharedTask) -> some View {
        HStack(spacing: 4) {
            Button {
                toggleSharedFolderTask(task)
            } label: {
                TaskCheckbox(isDone: task.isDone, isPriority: task.isHighPriority).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Вернуть общую задачу" : "Выполнить общую задачу")
            Button {
                sharedTaskToEdit = task
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.system(size: 15)).strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let member = sharedStore.members(in: task.listID).first(where: {
                            $0.userID == task.assigneeID
                        }) {
                            Text(member.userID == sharedStore.accountID ? "Вы" : member.displayName)
                        }
                        if !task.subtasks.isEmpty {
                            Text("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count) подзадач")
                        }
                    }.font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button("Редактировать", systemImage: "square.and.pencil") { sharedTaskToEdit = task }
                Button(task.isDone ? "Вернуть в работу" : "Выполнено", systemImage: "checkmark.circle") {
                    toggleSharedFolderTask(task)
                }
                Button(task.isHighPriority ? "Снять приоритет" : "Высокий приоритет", systemImage: "flame") {
                    var edited = task
                    edited.isHighPriority.toggle()
                    sharedStore.save(edited)
                    Task { await sharedStore.sync() }
                }
                Button("Удалить", systemImage: "trash", role: .destructive) { sharedTaskToDelete = task }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    .foregroundStyle(Theme.Colors.textMuted).contentShape(Rectangle())
            }
            #if os(macOS)
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            #endif
            .accessibilityLabel("Действия с задачей \(task.title)")
        }
        .padding(.leading, -11).frame(minHeight: 56)
        .accessibilityIdentifier("workspace-shared-task-\(task.id)")
    }

    private func toggleSharedFolderTask(_ task: SharedTask) {
        var edited = task
        edited.isDone.toggle()
        sharedStore.save(edited)
        Haptics.selection()
        Task { await sharedStore.sync() }
    }

    private func sharedFolderTile(_ list: SharedList) -> some View {
        let contents = sharedStore.tasks(in: list.id)
        let activeCount = contents.filter { !$0.isDone }.count
        let progress = contents.isEmpty ? 0 : Double(contents.filter(\.isDone).count) / Double(contents.count)
        let members = sharedStore.members(in: list.id)
        return Button {
            captureTag = nil
            path.append(list.id)
        } label: {
            VStack(spacing: 9) {
                FolderArtwork(
                    tint: Theme.Colors.blueViolet, icon: "person.2.fill", count: activeCount,
                    progress: progress, members: members
                )
                .frame(maxWidth: 188).frame(height: folderArtworkHeight)
                Text(list.title).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                Label("Общая · \(activeCount) открыто", systemImage: "person.2")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.textSecondary)
            }.padding(.vertical, 7).frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(SoftPressStyle())
        .contextMenu {
            Button("Открыть общую папку") { path.append(list.id) }
            Button("Участники и доступ") { managingSharedFolder = list }
        }
        .accessibilityLabel(
            "Общая папка \(list.title), \(activeCount) открыто. Участники: "
                + members.map(\.displayName).joined(separator: ", ")
        )
        .accessibilityIdentifier("workspace-shared-folder-\(list.id)")
    }

    private func folderTile(_ tag: Tag) -> some View {
        let contents = folderTasks(tag)
        let activeCount = contents.filter { !$0.isDone }.count
        let progress = contents.isEmpty ? 0 : Double(contents.filter(\.isDone).count) / Double(contents.count)
        let nextDeadline = contents.filter { !$0.isDone }.compactMap(\.dueDate).min()
        return Button {
            open(.tag(tag.id))
        } label: {
            VStack(spacing: 9) {
                FolderArtwork(tint: tag.color, icon: tag.folderIconName, count: activeCount, progress: progress)
                    .frame(maxWidth: 188).frame(height: folderArtworkHeight)
                Text(tag.name).font(.system(size: 14, weight: .medium)).foregroundStyle(
                    Theme.Colors.textPrimary
                ).lineLimit(1)
                Group {
                    if let nextDeadline {
                        if nextDeadline < now {
                            Text("Есть просроченные задачи")
                        } else {
                            Text(
                                "Ближайшее · \(nextDeadline.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))))"
                            )
                        }
                    } else {
                        Text(contents.isEmpty ? "Пока пусто" : activeCount == 0 ? "Всё готово" : "Всё по плану")
                    }
                }.font(.system(size: 10)).foregroundStyle(Theme.Colors.textSecondary)
            }.padding(.vertical, 7).frame(maxWidth: .infinity)
                .background(
                    targetFolder == tag.id ? tag.color.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 22)
                )
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(SoftPressStyle())
        .draggable("folder:\(tag.id.uuidString)")
        .dropDestination(for: String.self) { items, _ in
            drop(items, onto: tag)
        } isTargeted: {
            targetFolder = $0 ? tag.id : nil
        }
        .contextMenu {
            Button("Открыть папку") { open(.tag(tag.id)) }
            Button("Изменить оформление") { editingFolder = tag }
            Button("Удалить папку", role: .destructive) { deletingFolder = tag }
        }
        .accessibilityLabel("Папка \(tag.name), \(activeCount) открыто")
    }

    private var widgetMenu: some View {
        Menu {
            Button(customizing ? "Готово" : "Настроить пространство") { customizing.toggle() }
            Divider()
            ForEach(WorkspaceWidget.allCases) { widget in
                Button {
                    toggleWidget(widget)
                } label: {
                    Label(widget.title, systemImage: widgets.contains(widget) ? "checkmark" : "plus")
                }
            }
            Divider()
            Button("Вернуть исходную композицию") {
                widgetOrder = "focus,progress"; wideWidgets = "focus"
            }
        } label: {
            #if os(iOS)
            Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 40, height: 40).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 13))
            #else
            Label("Виджеты", systemImage: "square.grid.2x2")
            #endif
        }.accessibilityLabel("Виджеты и пространство")
    }

    private var folderArtworkHeight: CGFloat {
        #if os(iOS)
        124
        #else
        145
        #endif
    }

    private func widgetTile(_ widget: WorkspaceWidget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: widget.icon).font(.system(size: 11))
                Text(widget.title).font(.system(size: 11, weight: .medium))
                Spacer()
                if customizing {
                    Image(systemName: "line.3.horizontal").font(.system(size: 10))
                        .draggable("widget:\(widget.rawValue)")
                } else {
                    Menu {
                        widgetActions(widget)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.Colors.textMuted)
                            .frame(width: 26, height: 24).contentShape(Rectangle())
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    #endif
                    .accessibilityLabel("Настроить: \(widget.title)")
                }
            }.foregroundStyle(Theme.Colors.textSecondary)
            Group {
                switch widget {
                case .focus: focusWidget
                case .progress: progressWidget
                case .calendar: calendarWidget
                case .timer: WorkspaceTimerWidget()
                case .note:
                    TextEditor(text: $note).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("Оставьте место для мысли…").font(.system(size: 13)).foregroundStyle(
                                    Theme.Colors.textMuted
                                ).padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                            }
                        }
                case .clock: clockWidget
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            widget == .progress ? Theme.Colors.sunGlare.opacity(scheme == .dark ? 0.09 : 0.18) : Theme.Colors.surface,
            in: RoundedRectangle(cornerRadius: 23)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 23).strokeBorder(
                customizing ? Theme.Colors.accent.opacity(0.35) : Theme.Colors.borderSubtle, lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.018), radius: 15, y: 5)
        .contextMenu { widgetActions(widget) }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, value.hasPrefix("widget:"),
                let source = WorkspaceWidget(rawValue: String(value.dropFirst(7))),
                let from = widgets.firstIndex(of: source), let to = widgets.firstIndex(of: widget), from != to
            else { return false }
            var ordered = widgets
            ordered.insert(ordered.remove(at: from), at: to)
            widgetOrder = ordered.map(\.rawValue).joined(separator: ",")
            return true
        }
    }

    @ViewBuilder private func widgetActions(_ widget: WorkspaceWidget) -> some View {
        #if os(macOS)
        Button(wideWidgets.contains(widget.rawValue) ? "Обычный размер" : "Широкий виджет") { toggleSize(widget) }
        #else
        if ![.focus, .calendar, .note].contains(widget) {
            Button(wideWidgets.contains(widget.rawValue) ? "Обычный размер" : "Широкий виджет") { toggleSize(widget) }
        }
        #endif
        Button("Переместить в начало") {
            widgetOrder = ([widget] + widgets.filter { $0 != widget }).map(\.rawValue).joined(separator: ",")
        }
        Button("Убрать виджет", role: .destructive) { toggleWidget(widget) }
    }

    private var focusWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            if focusTasks.isEmpty {
                Text("Можно выдохнуть.").font(.system(size: 21, weight: .medium)).foregroundStyle(
                    Theme.Colors.textPrimary)
                Text("Добавьте задачу или оставьте немного свободного времени.")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(Array(focusTasks.prefix(2))) { task in
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { context.setCompleted(task, true) }
                        } label: {
                            Circle().strokeBorder(
                                task.isHighPriorityToday ? Theme.Colors.priority : Theme.Colors.ruleStrong,
                                lineWidth: 1.2
                            )
                            .frame(width: 18, height: 18).frame(width: 24, height: 24)
                        }.buttonStyle(.plain).accessibilityLabel("Завершить \(task.title)")
                        Button {
                            taskToEdit = task
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.system(size: 12, weight: .medium)).foregroundStyle(
                                    Theme.Colors.textPrimary
                                ).lineLimit(1)
                                Text(task.tags.first?.name ?? "Без категории").font(.system(size: 10)).foregroundStyle(
                                    Theme.Colors.textMuted)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.draggable(task.id.uuidString)
                }
            }
            Spacer(minLength: 0)
            Button {
                open(.focus)
            } label: {
                HStack(spacing: 5) {
                    Text("Все задачи дня")
                    Image(systemName: "arrow.right")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
            }.buttonStyle(.plain)
        }
    }

    private var progressWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(doneToday)").font(.system(size: 43, weight: .medium, design: .rounded)).tracking(-2)
                Text("/ \(doneToday + focusTasks.count)").font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.Colors.textMuted)
            }.foregroundStyle(Theme.Colors.textPrimary)
            GeometryReader { geometry in
                Capsule().fill(Theme.Colors.accent.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.Colors.accent.opacity(0.65))
                            .frame(
                                width: geometry.size.width * CGFloat(doneToday)
                                    / CGFloat(max(1, doneToday + focusTasks.count)))
                    }
            }.frame(height: 4)
            Text(doneToday == 0 ? "У каждого дела — своё время." : "Маленькие шаги. Хороший день.")
                .font(.system(size: 10)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var calendarWidget: some View {
        let calendar = Calendar.current
        let week = now.startOfWeek
        return VStack(alignment: .leading, spacing: 15) {
            Text(now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU"))).capitalized)
                .font(.system(size: 21, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: week)!
                    let isToday = calendar.isDate(date, inSameDayAs: now)
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 7) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))))
                                .font(.system(size: 9)).foregroundStyle(Theme.Colors.textMuted)
                            Text("\(calendar.component(.day, from: date))").font(
                                .system(size: 12, weight: isToday ? .semibold : .regular)
                            )
                            .foregroundStyle(isToday ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                            .frame(width: 24, height: 27).background(
                                isToday ? Theme.Colors.accent : .clear, in: Capsule())
                            Circle().fill(
                                openTasks.contains { $0.dueDate.map { calendar.isDate($0, inSameDayAs: date) } == true }
                                    ? Theme.Colors.accent : .clear
                            )
                            .frame(width: 3, height: 3)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var clockWidget: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 9) {
                Text(timeline.date, format: .dateTime.hour().minute()).font(
                    .system(size: 40, weight: .light, design: .rounded))
                Text(timeline.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary)
            }.foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(folderList ? "Без папки" : "Задачи") · \(searchResultTasks.count)").font(
                .system(size: 13, weight: .medium)
            ).foregroundStyle(
                Theme.Colors.textSecondary)
            ForEach(searchResultTasks) { task in
                Button {
                    taskToEdit = task
                } label: {
                    HStack {
                        Image(systemName: "circle").foregroundStyle(Theme.Colors.textMuted)
                        Text(task.title).font(.system(size: 13)).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text(task.tags.first?.name ?? "").font(.system(size: 10)).foregroundStyle(
                            Theme.Colors.textSecondary)
                    }.padding(14).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).draggable(task.id.uuidString)
            }
        }
    }

    private func dateTasks(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                .font(.system(size: 24, weight: .semibold))
            let due = openTasks.filter { $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            if due.isEmpty { Text("На этот день пока нет дедлайнов.").foregroundStyle(Theme.Colors.textSecondary) }
            ForEach(due) { task in
                HStack {
                    Button {
                        context.setCompleted(task, true)
                    } label: {
                        Image(systemName: "circle")
                    }.buttonStyle(.plain)
                    Button {
                        calendarTaskToEdit = task
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(.system(size: 14, weight: .medium))
                                if let deadline = task.dueDate {
                                    Text(
                                        deadline.formatted(
                                            .dateTime.hour().minute().locale(Locale(identifier: "ru_RU")))
                                    )
                                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(
                                Theme.Colors.textMuted)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Button("Готово") { selectedDate = nil }.buttonStyle(.bordered)
        }.padding(28).frame(minWidth: 280, minHeight: 200).background(Theme.Colors.background)
            .sheet(item: $calendarTaskToEdit) { TaskEditSheet(task: $0) }
    }

    private func open(_ scope: TaskScope) {
        if let onOpenScope { onOpenScope(scope) } else { path.append(scope) }
    }
    private func toggleWidget(_ widget: WorkspaceWidget) {
        widgetOrder = (widgets.contains(widget) ? widgets.filter { $0 != widget } : widgets + [widget]).map(\.rawValue)
            .joined(separator: ",")
    }
    private func toggleSize(_ widget: WorkspaceWidget) {
        var wide = Set(wideWidgets.split(separator: ",").map(String.init))
        if wide.contains(widget.rawValue) { wide.remove(widget.rawValue) } else { wide.insert(widget.rawValue) }
        wideWidgets = wide.sorted().joined(separator: ",")
    }
    private func drop(_ items: [String], onto tag: Tag) -> Bool {
        guard let value = items.first else { return false }
        if value.hasPrefix("folder:"), let id = UUID(uuidString: String(value.dropFirst(7))),
            let from = tags.firstIndex(where: { $0.id == id }), let to = tags.firstIndex(where: { $0.id == tag.id }),
            from != to
        {
            var ordered = tags
            ordered.insert(ordered.remove(at: from), at: to)
            for (index, folder) in ordered.enumerated() { folder.sortOrder = index; folder.touch() }
            context.saveAndSync()
            return true
        }
        guard let id = UUID(uuidString: value), let task = openTasks.first(where: { $0.id == id }) else { return false }
        context.assign(task, to: tag)
        return true
    }
}

private struct WorkspaceTimerWidget: View {
    #if os(macOS)
    @State private var island = IslandController.shared
    #else
    @State private var clock = IslandFocusClock()
    #endif
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            #if os(macOS)
            let remaining = island.remaining
            let running = island.clock.isRunning
            #else
            let remaining = clock.remaining(at: timeline.date)
            let running = clock.isRunning
            #endif
            VStack(alignment: .leading, spacing: 14) {
                Text(String(format: "%02d:%02d", Int(ceil(remaining)) / 60, Int(ceil(remaining)) % 60))
                    .font(.system(size: 37, weight: .light, design: .rounded)).monospacedDigit()
                HStack {
                    Text("Одно дело за раз").font(.system(size: 10)).foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Button {
                        #if os(macOS)
                        island.toggleTimer()
                        #else
                        if running {
                            clock.pause(at: .now)
                        } else if clock.hasStarted && remaining > 0 {
                            clock.resume(at: .now)
                        } else {
                            clock.start(minutes: 25, taskID: nil, at: .now)
                        }
                        #endif
                    } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill").font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.onAccent).frame(width: 30, height: 30)
                            .background(Theme.Colors.accent, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(running ? "Пауза" : "Начать фокус")
                }
            }.foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

struct WorkspaceCaptureSheet: View {
    let tags: [Tag]
    var onClose: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var folderChoice: CaptureFolderChoice = .unassigned
    @State private var newFolderName = ""
    @State private var highPriority = false
    @State private var revealed = false
    @FocusState private var focused: Bool

    init(tags: [Tag], initialTag: Tag? = nil, highPriority: Bool = false, onClose: (() -> Void)? = nil) {
        self.tags = tags
        self.onClose = onClose
        _folderChoice = State(initialValue: initialTag.map { .existing($0.id) } ?? .unassigned)
        _highPriority = State(initialValue: highPriority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Новое дело").font(.system(size: 25, weight: .semibold)).tracking(-0.6)
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.Colors.textMuted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Закрыть новое дело")
            }
            .modifier(CaptureContentEntrance(revealed: revealed, delay: 0))
            TextField("Что нужно сделать?", text: $title).font(.system(size: 17)).textFieldStyle(.plain).focused(
                $focused
            ).onSubmit(submit).accessibilityIdentifier("task-capture-title")
                .modifier(CaptureContentEntrance(revealed: revealed, delay: 0.035))
            CaptureFolderPicker(tags: tags, choice: $folderChoice, newName: $newFolderName) { focused = true }
                .modifier(CaptureContentEntrance(revealed: revealed, delay: 0.07))
            HStack {
                Text("Детали можно добавить позже").font(.system(size: 11)).foregroundStyle(Theme.Colors.textMuted)
                Spacer()
                Button("Добавить", action: submit).buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("task-capture-submit")
            }
            .modifier(CaptureContentEntrance(revealed: revealed, delay: 0.105))
        }
        .padding(28).frame(minWidth: 340).background(Theme.Colors.background)
        .tint(Theme.Colors.accent)
        .defaultFocus($focused, true, priority: .userInitiated)
        .onAppear {
            focused = true
            revealed = true
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            focused = true
        }
        .onDisappear { focused = false }
    }
    private func submit() {
        if context.createTask(
            title: title, folder: folderChoice, newFolderName: newFolderName, tags: tags, highPriority: highPriority)
            != nil
        {
            close()
        }
    }

    private func close() {
        focused = false
        if let onClose { onClose() } else { dismiss() }
    }
}

private struct CaptureContentEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let revealed: Bool
    let delay: Double

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 8)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28).delay(delay), value: revealed)
        #else
        content
        #endif
    }
}
