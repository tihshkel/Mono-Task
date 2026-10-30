import SwiftUI
import SwiftData

private enum SettingsPage: String, Hashable {
    case categories = "Категории и расписание"
    case notifications = "Уведомления"
    case appearance = "Оформление"
    case account = "Аккаунт и синхронизация"
    #if os(macOS)
    case island = "MonoTask Island"
    #endif
}

struct SettingsView: View {
    var opensIsland = false
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var tasks: [TaskItem]
    @Environment(\.modelContext) private var context
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notifications = NotificationService.shared
    @State private var sharedStore = SharedListStore.shared
    @State private var editingTag: Tag?
    @State private var addingTag = false
    @State private var deletingTag: Tag?
    @State private var confirmingSignOut = false
    @AppStorage("monotask_appearance") private var appearanceMode = "light"
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var path: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageIntro(title: "Настройки", subtitle: "Ваш профиль и привычный ритм.")
                    accountPreview
                    GroupCard {
                        Button {
                            SharedListStore.shared.isPresented = true
                        } label: {
                            HStack(spacing: 12) {
                                settingsIcon("person.2", color: Theme.Colors.priority)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Общие папки").font(.system(size: 15, weight: .medium)).foregroundStyle(
                                        Theme.Colors.textPrimary)
                                    Text("Участники, приглашения и совместные задачи").font(.system(size: 11))
                                        .foregroundStyle(
                                            Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }.padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("settings-shared-lists")
                    }
                    schedulePreview
                    VStack(alignment: .leading, spacing: 10) {
                        GroupCard {
                            destination(
                                .notifications, icon: "bell", subtitle: morningSummary,
                                badge: notificationStatus)
                            Hairline(leading: 58)
                            destination(.appearance, icon: "list.bullet.rectangle", subtitle: appearanceSummary)
                            #if os(macOS)
                            Hairline(leading: 58)
                            destination(.island, icon: "capsule", subtitle: "Задачи рядом с камерой MacBook")
                            #endif
                        }
                    }
                    HStack {
                        Text("MONOTASK").font(Theme.Typography.heading(12))
                        Spacer()
                        Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(Theme.Typography.eyebrow)
                    }
                    .foregroundStyle(Theme.Colors.textMuted)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .scrollIndicators(.hidden)
            .navigationDestination(for: SettingsPage.self) { page in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .categories: categories
                        case .notifications: NotificationPreferencesView()
                        case .appearance: appearance
                        case .account: account
                        #if os(macOS)
                        case .island: IslandSettingsView()
                        #endif
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .background(Theme.Colors.background)
                .navigationTitle(page.rawValue)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        .task { await notifications.checkAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.checkAuthorization() } }
        }
        .sheet(item: $editingTag) { TagEditSheet(tagToEdit: $0) }
        .sheet(isPresented: $addingTag) { TagEditSheet(tagToEdit: nil) }
        .confirmationDialog(
            "Удалить категорию «\(deletingTag?.name ?? "")»?",
            isPresented: Binding(get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let tag = deletingTag { context.deleteWithSync(tag); context.saveAndSync() }
                deletingTag = nil
            }
        } message: {
            Text("Задачи останутся, но потеряют эту категорию.")
        }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                if auth.userID != nil { Task { await auth.signOut() } }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            #if os(macOS)
            if opensIsland { path = [.island] }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-categories") { path = [.categories] }
            if ProcessInfo.processInfo.arguments.contains("--settings-notifications") { path = [.notifications] }
            if ProcessInfo.processInfo.arguments.contains("--settings-sync") { path = [.account] }
            if ProcessInfo.processInfo.arguments.contains("--settings-appearance") { path = [.appearance] }
            #if os(macOS)
            if ProcessInfo.processInfo.arguments.contains("--settings-island") { path = [.island] }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--settings-edit") {
                path = [.categories]; editingTag = tags.first
            }
            #endif
        }
    }

    private func destination(_ page: SettingsPage, icon: String, subtitle: String, badge: String? = nil) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                settingsIcon(icon)
                VStack(alignment: .leading, spacing: 5) {
                    Text(page.rawValue).font(.system(size: 15, weight: .medium)).foregroundStyle(
                        Theme.Colors.textPrimary)
                    Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(Theme.Typography.numeric(10, weight: .medium))
                        .foregroundStyle(badge == "Вкл." ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.Colors.fillStrong, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                    Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("settings-page-" + icon)
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: subtitle)
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: badge)
    }

    private func settingsIcon(_ symbol: String, color: Color = Theme.Colors.accent) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .regular))
            .foregroundStyle(color).frame(width: 34, height: 34)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
    }

    private var profileEmail: String {
        auth.email ?? (SyncPresentation.isPreview ? "Демонстрационный аккаунт" : "Локальное пространство")
    }

    private var profileInitials: String {
        guard let email = auth.email else { return "M" }
        return SharedMember.initials(for: email)
    }

    private var activeTaskCount: Int {
        tasks.filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) }.count
            + sharedStore.lists.reduce(0) { $0 + sharedStore.tasks(in: $1.id).filter { !$0.isDone }.count }
    }

    private var accountPreview: some View {
        NavigationLink(value: SettingsPage.account) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("ВАШЕ ПРОСТРАНСТВО").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.Colors.cloudDancer.opacity(0.75))
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle().fill(
                                [Theme.Colors.sunGlare, Theme.Colors.exuberantOrange, Theme.Colors.cloudDancer][index]
                            ).frame(width: 7, height: 7)
                        }
                    }.accessibilityHidden(true)
                }
                HStack(spacing: 14) {
                    Text(profileInitials)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.darkestHour)
                        .frame(width: 60, height: 60)
                        .background(Theme.Colors.sunGlare, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Мой профиль").font(.system(size: 23, weight: .semibold)).tracking(-0.7)
                        Text(profileEmail).font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.cloudDancer.opacity(0.8))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.12), in: Circle())
                }
                HStack(spacing: 6) {
                    Image(systemName: SyncPresentation.icon)
                    Text(SyncPresentation.title)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.cloudDancer)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.white.opacity(0.12), in: Capsule())
                .contentTransition(.opacity)
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                HStack(spacing: 12) {
                    profileStat(tags.count + sharedStore.lists.count, title: "Папки")
                    profileStat(activeTaskCount, title: "В работе")
                    profileStat(sharedStore.lists.count, title: "Общие")
                }
            }
            .foregroundStyle(Theme.Colors.cloudDancer)
            .padding(22)
            .background(Theme.Colors.blueViolet, in: RoundedRectangle(cornerRadius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }.buttonStyle(.plain).accessibilityIdentifier("settings-account")
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: SyncPresentation.title)
    }

    private func profileStat(_ count: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)").font(.system(size: 23, weight: .medium, design: .rounded))
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.Colors.cloudDancer.opacity(0.75))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var schedulePreview: some View {
        #if os(iOS)
        GroupCard(padding: 16) {
            NavigationLink(value: SettingsPage.categories) {
                HStack(spacing: 12) {
                    settingsIcon("folder")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Папки и расписание").font(.system(size: 15, weight: .medium)).foregroundStyle(
                            Theme.Colors.textPrimary)
                        Text("Выберите свой ритм недели").font(.system(size: 11)).foregroundStyle(
                            Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(
                        Theme.Colors.textMuted)
                }.frame(minHeight: 40).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if tags.isEmpty {
                Button {
                    addingTag = true
                } label: {
                    Label("Создать первую папку", systemImage: "plus").font(.system(size: 12)).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent).padding(.top, 8)
            } else {
                Hairline().padding(.vertical, 13)
                ForEach(tags.prefix(3)) { tag in
                    Button {
                        editingTag = tag
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tag.folderIconName).font(.system(size: 15)).foregroundStyle(tag.color)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tag.name).font(.system(size: 13, weight: .medium)).foregroundStyle(
                                    Theme.Colors.textPrimary)
                                Text(scheduleText(tag)).font(.system(size: 10)).foregroundStyle(
                                    Theme.Colors.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(Weekday.orderedFromMonday) { day in
                                    Circle().fill(tag.scheduledDays.contains(day) ? tag.color : Theme.Colors.fillStrong)
                                        .frame(width: 5, height: 5)
                                }
                            }.accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(tag.name), \(scheduleText(tag))")
                        .accessibilityIdentifier("settings-preview-" + tag.id.uuidString)
                }
                if tags.count > 3 {
                    NavigationLink("Все папки · \(tags.count)", value: SettingsPage.categories)
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.accent).padding(.top, 10)
                }
            }
        }
        #else
        scheduleTablePreview
        #endif
    }

    private var scheduleTablePreview: some View {
        GroupCard(padding: 16) {
            NavigationLink(value: SettingsPage.categories) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Категории и расписание")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Фокус по дням недели")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            if tags.isEmpty {
                Text("Добавьте категорию и выберите дни фокуса.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
                Button {
                    addingTag = true
                } label: {
                    Label("Новая категория", systemImage: "plus")
                        .font(Theme.Typography.callout)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent)
            } else {
                Hairline().padding(.top, 14).padding(.bottom, 10)
                HStack {
                    Text("Категория").font(Theme.Typography.eyebrow).foregroundStyle(Theme.Colors.textMuted)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        ForEach(Weekday.orderedFromMonday) { day in
                            Text(day.shortName.uppercased())
                                .font(Theme.Typography.numeric(9, weight: day == .current ? .bold : .regular))
                                .foregroundStyle(day == .current ? Theme.Colors.accent : Theme.Colors.textMuted)
                                .frame(width: 19)
                        }
                    }
                }.padding(.bottom, 4)
                ForEach(tags.prefix(4)) { tag in
                    Button {
                        editingTag = tag
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(tag.color).frame(width: 7, height: 7)
                            Text(tag.name)
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            HStack(spacing: 4) {
                                ForEach(Weekday.orderedFromMonday) { day in
                                    let active = tag.scheduledDays.contains(day)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(active ? tag.color.opacity(0.85) : Theme.Colors.fillStrong)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4).strokeBorder(
                                                day == .current ? Theme.Colors.textSecondary : .clear, lineWidth: 1)
                                        )
                                        .frame(width: 19, height: 19)
                                }
                            }.accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tag.name), \(scheduleText(tag))")
                    .accessibilityHint("Открыть расписание категории")
                    .accessibilityIdentifier("settings-preview-" + tag.id.uuidString)
                }
                if tags.count > 4 {
                    NavigationLink(value: SettingsPage.categories) {
                        Text("Все категории · \(tags.count)")
                            .font(Theme.Typography.caption)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private var morningSummary: String {
        guard notifications.preferences.morningPlan else { return "Утренний план выключен" }
        let time = String(
            format: "%02d:%02d", notifications.preferences.morningHour, notifications.preferences.morningMinute)
        return notifications.preferences.enabled ? "Утренний план в \(time)" : "План в \(time) · неактивен"
    }

    private var notificationStatus: String {
        guard notifications.preferences.enabled else { return "Выкл." }
        switch notifications.authorization {
        case .denied: return "Нет доступа"
        case .notDetermined: return "Разрешить"
        default: return "Вкл."
        }
    }

    private var appearanceSummary: String {
        (compactRows ? "Компактные строки" : "Обычные строки") + " · " + (showNotes ? "с заметками" : "без заметок")
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выберите категорию, чтобы настроить цвет и дни фокуса. Для изменения порядка перетащите строку.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
            GroupCard {
                ForEach(tags) { tag in
                    Button {
                        editingTag = tag
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.Colors.textSecondary)
                            Circle().fill(tag.color).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tag.name).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary)
                                Text(scheduleText(tag)).font(Theme.Typography.caption).foregroundStyle(
                                    Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Text("\(tasks.filter { !$0.isDone && $0.tags.contains { $0.id == tag.id } }.count)")
                                .font(Theme.Typography.numeric(13)).foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(
                                Theme.Colors.textSecondary)
                        }.padding(16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .draggable(tag.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let from = UUID(uuidString: raw) else { return false }
                        return reorder(from: from, onto: tag.id)
                    }
                    .contextMenu { Button("Удалить категорию", role: .destructive) { deletingTag = tag } }
                    Hairline(leading: 48)
                }
                Button {
                    addingTag = true
                } label: {
                    Label("Новая категория", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupCard(padding: 18) {
                Text("Оформление пространства").font(Theme.Typography.title).padding(.bottom, 14)
                Picker("Тема", selection: $appearanceMode) {
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                    Text("Системная").tag("system")
                }.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    iconPreview(dark: false)
                    iconPreview(dark: true)
                }.padding(.top, 18)
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                [
                                    Theme.Colors.sunGlare, Theme.Colors.exuberantOrange, Theme.Colors.blueViolet,
                                    Theme.Colors.cloudDancer, Theme.Colors.darkestHour,
                                ][index]
                            )
                            .frame(height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Colors.border, lineWidth: 0.5))
                    }
                }.padding(.top, 16).accessibilityLabel("Палитра: лайм, оранжевый, фиолетовый, молочный и графит")
                Text("Иконка MonoTask меняется вместе с темой.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary).padding(.top, 12)
                if let error = AppIconManager.shared.errorMessage {
                    Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.danger).padding(.top, 8)
                }
            }
            Text("Настройте плотность и детали задач. Виджеты и композиция меняются прямо в вашем пространстве.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
            GroupCard(padding: 16) {
                EyebrowLabel(text: "Пример списка")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                HStack(spacing: 10) {
                    TaskCheckbox(isDone: false)
                        .frame(width: 30, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Подготовить план на завтра")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityIdentifier("settings-preview-task")
                        HStack(spacing: 6) {
                            Circle().fill(tags.first?.color ?? Theme.Colors.accent).frame(width: 6, height: 6)
                            Text(tags.first?.name ?? "Категория")
                                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            if showNotes {
                                Text("Выбрать три главные задачи")
                                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textMuted)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("settings-preview-notes")
                                    .transition(.opacity)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, compactRows ? 8 : 12)
                Hairline()
            }
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: showNotes)
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: compactRows)

            GroupCard(padding: 18) {
                Toggle(isOn: $showNotes) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Заметки в списке").font(Theme.Typography.body)
                        Text("Показывать текст заметки, не открывая задачу.")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .accessibilityLabel("Показывать заметки в списке")
                Hairline().padding(.vertical, 16)
                Toggle(isOn: $compactRows) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Компактные строки задач").font(Theme.Typography.body)
                        Text("Меньше отступов — больше задач на экране.")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .accessibilityLabel("Компактные строки задач")
            }
            .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func iconPreview(dark: Bool) -> some View {
        VStack(spacing: 8) {
            Image(dark ? "BrandDockDark" : "BrandDockLight").resizable().scaledToFit().frame(width: 64, height: 64)
            Text(dark ? "Тёмная" : "Светлая").font(.system(size: 11, weight: .medium))
                .foregroundStyle(dark ? Theme.Colors.cloudDancer : Theme.Colors.darkestHour)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(dark ? Theme.Colors.darkestHour : Theme.Colors.cloudDancer, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.Colors.border, lineWidth: 0.5))
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupCard(padding: 18) {
                HStack(spacing: 16) {
                    Image("BrandLogo").resizable().frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Мой профиль").font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
                        Text(profileEmail).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                            .textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GroupCard(padding: 18) { SyncDetailsView() }
            if auth.userID != nil || SyncPresentation.isPreview {
                Button {
                    confirmingSignOut = true
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.danger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.Colors.dangerMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .strokeBorder(Theme.Colors.danger.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-sign-out")
                .disabled(auth.isBusy)
                .padding(.top, 4)
            }
            if let error = auth.errorMessage { Text(error).foregroundStyle(Theme.Colors.danger) }
        }
    }

    private func scheduleText(_ tag: Tag) -> String {
        let days = Weekday.orderedFromMonday.filter { tag.scheduledDays.contains($0) }
        if days.count == 7 { return "Каждый день" }
        if days.isEmpty { return "Дни фокуса не выбраны" }
        if days == Array(Weekday.orderedFromMonday.prefix(5)) { return "Пн–Пт" }
        return days.map(\.shortName).joined(separator: ", ")
    }

    private func reorder(from: UUID, onto: UUID) -> Bool {
        guard let source = tags.firstIndex(where: { $0.id == from }),
            let target = tags.firstIndex(where: { $0.id == onto }), source != target
        else { return false }
        var result = tags
        result.insert(result.remove(at: source), at: target)
        for (index, tag) in result.enumerated() where tag.sortOrder != index { tag.sortOrder = index; tag.touch() }
        context.saveAndSync()
        return true
    }
}
