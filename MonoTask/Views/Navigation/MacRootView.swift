import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case workspace
    case list(TaskScope)
    case activity
    case settings
    case shared
    case islandSettings
}

#if os(macOS)
struct MacRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt, order: .reverse)]) private
        var allTasks: [TaskItem]

    @State private var selection: SidebarSelection? = .workspace
    @State private var showingAddTagSheet: Bool = false
    @State private var editingTag: Tag? = nil
    @State private var tagToDelete: Tag? = nil
    @State private var dropTargetTagId: UUID? = nil
    @State private var today: Date = Date.now.startOfDay

    init(initialTab: AppTab = .today) {
        let initial: SidebarSelection =
            switch initialTab {
            case .today: .workspace
            case .activity: .activity
            case .settings: .settings
            }
        _selection = State(initialValue: initial)
    }

    private var scheduledTags: [Tag] {
        _ = today
        return FocusService.shared.currentFocusTags(allTags: tags, override: nil)
    }

    private func openCount(_ scope: TaskScope) -> Int {
        scope.filter(allTasks, scheduledTags: scheduledTags)
            .filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) }.count
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            switch NotificationService.shared.preferences.morningScope {
            case "all": selection = .list(.all)
            case "priority": selection = .list(.highPriority)
            default: selection = .list(.focus)
            }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        .sheet(item: $editingTag) { tag in
            TagEditSheet(tagToEdit: tag)
        }
        .sheet(isPresented: $showingAddTagSheet) {
            TagEditSheet(tagToEdit: nil)
        }
        .confirmationDialog(
            "Удалить категорию «\(tagToDelete?.name ?? "")»?",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } })
        ) {
            Button("Удалить", role: .destructive) {
                if let tag = tagToDelete {
                    deleteTag(tag)
                }
                tagToDelete = nil
            }
            Button("Отмена", role: .cancel) {
                tagToDelete = nil
            }
        } message: {
            Text("Задачи останутся, но потеряют эту категорию.")
        }
        .onChange(of: tags.map(\.id)) { _, ids in
            // Leave a context that was deleted here or on another device
            if case .list(.tag(let id)) = selection, !ids.contains(id) {
                selection = .list(.focus)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            today = Date.now.startOfDay
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenWorkspace)) { _ in selection = .workspace }
        .onChange(of: IslandController.shared.settingsRequested, initial: true) { _, requested in
            if requested {
                selection = .islandSettings
                IslandController.shared.settingsRequested = false
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section {
                sidebarRow(
                    .workspace, title: "Пространство", icon: "square.grid.2x2", tint: Theme.Colors.textPrimary,
                    count: nil)
                sidebarRow(
                    .list(.focus), title: "Фокус дня", icon: "sun.max", tint: Theme.Colors.accent,
                    count: openCount(.focus))
                sidebarRow(
                    .list(.all), title: "Все задачи", icon: "tray", tint: Theme.Colors.textSecondary,
                    count: openCount(.all))
                sidebarRow(
                    .list(.highPriority), title: "Приоритет", icon: "flame", tint: Theme.Colors.priority,
                    count: openCount(.highPriority))
            } header: {
                EyebrowLabel(text: "Обзор")
            }

            Section {
                ForEach(tags) { tag in
                    tagRow(tag)
                }
            } header: {
                HStack {
                    EyebrowLabel(text: "Мои папки")
                    Spacer()
                    Button {
                        showingAddTagSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Новая категория")
                }
            }

            Section {
                sidebarRow(
                    .shared, title: "Общие списки", icon: "person.2", tint: Theme.Colors.textSecondary, count: nil)
                sidebarRow(
                    .activity, title: "Аналитика", icon: "square.grid.3x3", tint: Theme.Colors.textSecondary, count: nil
                )
                sidebarRow(
                    .settings, title: "Настройки", icon: "slider.horizontal.3", tint: Theme.Colors.textSecondary,
                    count: nil)
            } header: {
                EyebrowLabel(text: "Инструменты")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image("BrandLogo").resizable().frame(width: 29, height: 29)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text("MonoTask").font(.system(size: 18, weight: .semibold)).tracking(-0.6)
                Spacer()
            }.foregroundStyle(Theme.Colors.textPrimary).padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Text(today.formattedEyebrowDate)
                    .font(Theme.Typography.eyebrow)
                    .tracking(Theme.Typography.eyebrowTracking)
                    .foregroundColor(Theme.Colors.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.Colors.sidebar)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    private func sidebarRow(_ item: SidebarSelection, title: String, icon: String, tint: Color, count: Int?)
        -> some View
    {
        Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.numeric(11))
                        .foregroundColor(Theme.Colors.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(selectionOutline(for: item))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
    }

    private func tagRow(_ tag: Tag) -> some View {
        let count = openCount(.tag(tag.id))
        let isScheduledToday = scheduledTags.contains { $0.id == tag.id }

        let item = SidebarSelection.list(.tag(tag.id))
        return Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(tag.color)
                    .frame(width: 18)
                Text(tag.name)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if isScheduledToday {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.Colors.accent)
                        .help("В фокусе сегодня")
                }
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.numeric(11))
                        .foregroundColor(Theme.Colors.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(dropTargetTagId == tag.id ? Theme.Colors.fillStrong : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(selectionOutline(for: item))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
        .dropDestination(for: String.self) { items, _ in
            dropTargetTagId = nil
            return moveDroppedTask(items, to: tag)
        } isTargeted: { targeted in
            dropTargetTagId = targeted ? tag.id : (dropTargetTagId == tag.id ? nil : dropTargetTagId)
        }
        .contextMenu {
            Button {
                editingTag = tag
            } label: {
                Label("Изменить…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Удалить категорию", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail

    private func selectionOutline(for item: SidebarSelection) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selection == item ? Theme.Colors.surface : Color.clear)
            .shadow(color: .black.opacity(selection == item ? 0.035 : 0), radius: 4, y: 2)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .workspace {
        case .workspace:
            WorkspaceView(onOpenScope: { selection = .list($0) })
        case .list(let scope):
            MacTaskListView(scope: scope.validated(tags: tags), today: today)
        case .activity:
            HeatmapView()
                .padding(.top, 12)
        case .shared:
            SharedListsView(isEmbedded: true)
        case .settings:
            SettingsView()
                .padding(.top, 12)
        case .islandSettings:
            SettingsView(opensIsland: true)
                .padding(.top, 12)
        }
    }

    // MARK: - Actions

    /// Dropping a task on a context moves it there (tasks have one context).
    private func moveDroppedTask(_ items: [String], to tag: Tag) -> Bool {
        guard let rawId = items.first,
            let taskId = UUID(uuidString: rawId),
            let task = allTasks.first(where: { $0.id == taskId }),
            task.tags.first?.id != tag.id
        else {
            return false
        }
        withAnimation {
            modelContext.assign(task, to: tag)
        }
        return true
    }

    private func deleteTag(_ tag: Tag) {
        if case .list(.tag(let id)) = selection, id == tag.id {
            selection = .list(.focus)
        }
        modelContext.deleteWithSync(tag)
        modelContext.saveAndSync(delaySeconds: 0.1)
    }
}
#endif
