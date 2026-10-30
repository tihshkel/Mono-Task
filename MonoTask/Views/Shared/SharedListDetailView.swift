import SwiftUI

struct SharedListDetailView: View {
    let listID: UUID
    @State private var store = SharedListStore.shared
    @State private var editingTask: SharedTask?
    @State private var managing = false
    @State private var inviting = false
    private var list: SharedList? { store.lists.first { $0.id == listID } }

    var body: some View {
        Group {
            if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        let tasks = store.tasks(in: listID)
                        folderHeader(list, tasks: tasks)
                        if let message = store.errorMessage {
                            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if store.pendingCount > 0 {
                            Text("Есть изменения, ожидающие синхронизации").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        ForEach(store.conflicts(in: listID), id: \.task.id) { edit in conflictCard(edit) }
                        if tasks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checklist").font(.system(size: 30, weight: .light))
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("Начните с одной задачи").font(.system(size: 18, weight: .medium))
                                Text("Её увидят все участники папки.").font(Theme.Typography.callout)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(tasks) { task in taskRow(task) }
                        Button {
                            editingTask = SharedTask(listID: listID, title: "")
                        } label: {
                            Label("Новая задача", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(SharedPrimaryStyle())
                        .accessibilityIdentifier("shared-add-task")
                    }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .refreshable { await store.sync() }
                .background(Theme.Colors.background)
                .navigationTitle(list.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            managing = true
                        } label: {
                            Label("Участники", systemImage: "person.2")
                        }
                        .accessibilityIdentifier("shared-manage-members")
                    }
                }
                .sheet(isPresented: $managing) { SharedMembersView(listID: listID) }
                .sheet(isPresented: $inviting) { SharedInviteSheet(listID: listID) }
                .sheet(item: $editingTask) { task in SharedTaskEditor(task: task) }
            } else {
                ContentUnavailableView(
                    "Список недоступен", systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Список удалён или доступ к нему закрыт."))
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func folderHeader(_ list: SharedList, tasks: [SharedTask]) -> some View {
        let done = tasks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("ОБЩАЯ ПАПКА").font(.system(size: 9, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(list.title).font(.system(size: 27, weight: .semibold)).tracking(-0.8)
                    Text("Планы складываются, когда вы вместе.")
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill")
                    .frame(width: 100, height: 90)
            }
            HStack(spacing: 12) {
                Button {
                    managing = true
                } label: {
                    HStack(spacing: 9) {
                        SharedMemberAvatars(members: store.members(in: listID), size: 30)
                        Text("Участников: \(store.members(in: listID).count)").font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("shared-folder-members")
                Spacer()
                if list.ownerID == store.accountID {
                    Button {
                        inviting = true
                    } label: {
                        Image(systemName: "qrcode").font(.system(size: 17)).foregroundStyle(Theme.Colors.accent)
                            .frame(width: 42, height: 42)
                            .background(Theme.Colors.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityLabel("Пригласить по QR-коду")
                        .accessibilityIdentifier("shared-quick-invite")
                }
            }
            Hairline()
            HStack {
                Text("\(done) / \(tasks.count) выполнено").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(tasks.isEmpty ? "Начало истории" : done == tasks.count ? "Всё готово" : "Двигаемся вместе")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.textMuted)
            }
            ProgressLine(progress: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count), height: 3)
        }
        .padding(20).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.6))
    }

    private func taskRow(_ task: SharedTask) -> some View {
        GroupCard(padding: 14) {
            HStack(spacing: 10) {
                Button {
                    var edited = task
                    edited.isDone.toggle()
                    store.save(edited)
                    Haptics.selection()
                    Task { await store.sync() }
                } label: {
                    TaskCheckbox(isDone: task.isDone).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(
                    task.isDone ? "Вернуть общую задачу" : "Выполнить общую задачу")
                Button {
                    editingTask = task
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if task.isHighPriority {
                                Image(systemName: "flame.fill").foregroundStyle(Theme.Colors.priority)
                            }
                            Text(task.title).font(Theme.Typography.body).strikethrough(task.isDone)
                        }
                        if !task.notes.isEmpty {
                            Text(task.notes).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                        HStack(spacing: 10) {
                            if let member = store.members(in: listID).first(where: { $0.userID == task.assigneeID }) {
                                Label(
                                    member.userID == store.accountID ? "Вы" : member.displayName, systemImage: "person")
                            } else {
                                Text("Без ответственного")
                            }
                            if !task.subtasks.isEmpty {
                                Text("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count) подзадач")
                            }
                        }.font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("shared-task-\(task.id)")
            }
        }
    }

    private func conflictCard(_ edit: PendingSharedTask) -> some View {
        GroupCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Задача изменена другим участником", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.priority)
                Text("На устройстве: \(edit.task.deletedAt != nil ? "удалена — " : "")\(edit.task.title)").font(
                    Theme.Typography.body)
                if let remote = edit.remoteVersion {
                    Text(
                        remote.deletedAt != nil
                            ? "Общая задача удалена." : "Общая версия: \(remote.title)\n\(remote.notes)"
                    )
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    Button(remote.deletedAt != nil ? "Принять удаление" : "Использовать общую версию") {
                        store.resolve(edit.task.id, keepLocal: false)
                    }
                    Button(
                        remote.deletedAt != nil
                            ? "Сохранить мои правки копией"
                            : edit.task.deletedAt != nil ? "Удалить обновлённую задачу" : "Сохранить мои изменения"
                    ) {
                        store.resolve(edit.task.id, keepLocal: true)
                        Task { await store.sync() }
                    }
                }
            }
        }
    }
}

struct SharedTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var draft: SharedTask
    @State private var subtaskTitle = ""
    @State private var deleting = false

    init(task: SharedTask) { _draft = State(initialValue: task) }
    private var valid: Bool {
        store.lists.contains(where: { $0.id == draft.listID })
            && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.title.count <= 500
            && draft.notes.count <= 20000
            && draft.subtasks.allSatisfy {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 500
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    GroupCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 16) {
                            EyebrowLabel(text: "Общая задача")
                            TextField("Что нужно сделать?", text: $draft.title, axis: .vertical)
                                .font(.system(size: 24, weight: .semibold)).textFieldStyle(.plain)
                                .accessibilityIdentifier("shared-task-title")
                            TextField("Заметки", text: $draft.notes, axis: .vertical).lineLimit(3...10)
                                .font(.system(size: 14)).textFieldStyle(.plain)
                                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Colors.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
                                .accessibilityIdentifier("shared-task-notes")
                        }
                    }
                    GroupCard(padding: 18) {
                        VStack(spacing: 16) {
                            Toggle("Выполнено", isOn: $draft.isDone)
                            Hairline()
                            Toggle(isOn: $draft.isHighPriority) {
                                Label("Высокий приоритет", systemImage: "flame")
                            }
                        }.font(.system(size: 14))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SharedSectionTitle(title: "Ответственный")
                        GroupCard(padding: 18) {
                            Picker("Участник", selection: $draft.assigneeID) {
                                Text("Без ответственного").tag(UUID?.none)
                                ForEach(store.members(in: draft.listID)) { member in
                                    Text(member.userID == store.accountID ? "Вы" : member.displayName)
                                        .tag(Optional(member.userID))
                                }
                            }.font(.system(size: 14))
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SharedSectionTitle(
                            title: "Подзадачи",
                            detail: "\(draft.subtasks.filter(\.isDone).count)/\(draft.subtasks.count)")
                        GroupCard(padding: 16) {
                            VStack(spacing: 12) {
                                ForEach($draft.subtasks) { $subtask in
                                    HStack(spacing: 10) {
                                        Toggle("Выполнить подзадачу", isOn: $subtask.isDone).labelsHidden().frame(
                                            width: 44)
                                        TextField("Подзадача", text: $subtask.title).textFieldStyle(.plain)
                                            .font(.system(size: 14))
                                        Button {
                                            draft.subtasks.removeAll { $0.id == subtask.id }
                                        } label: {
                                            Image(systemName: "minus.circle").frame(minWidth: 36, minHeight: 44)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }.buttonStyle(.plain).accessibilityLabel("Удалить подзадачу")
                                    }
                                    Hairline()
                                }
                                if draft.subtasks.count < 100 {
                                    HStack(spacing: 10) {
                                        TextField("Новая подзадача", text: $subtaskTitle).textFieldStyle(.plain)
                                            .font(.system(size: 14)).accessibilityIdentifier("shared-subtask-input")
                                        Button("Добавить") {
                                            draft.subtasks.append(
                                                SharedSubtask(
                                                    title: subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                                            )
                                            subtaskTitle = ""
                                        }.font(.system(size: 12, weight: .semibold)).buttonStyle(.plain)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .disabled(
                                                subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                    || subtaskTitle.count > 500)
                                    }.frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    if store.cache.snapshot.tasks.contains(where: { $0.id == draft.id }) {
                        Button("Удалить общую задачу", role: .destructive) { deleting = true }
                            .font(.system(size: 13, weight: .medium)).buttonStyle(.plain)
                            .foregroundStyle(Theme.Colors.danger).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Label("Заметки, подзадачи и статус видны всем участникам папки.", systemImage: "person.2")
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary)
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively).background(Theme.Colors.background)
            .navigationTitle(draft.revision == 0 ? "Новая задача" : "Общая задача")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.save(draft); Task { await store.sync() }; dismiss()
                    }
                    .disabled(!valid).accessibilityIdentifier("shared-save-task")
                }
            }
            .confirmationDialog(
                "Удалить задачу для всех участников?", isPresented: $deleting, titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    draft.deletedAt = .now
                    store.save(draft)
                    Task { await store.sync() }
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 580)
        #endif
    }
}
