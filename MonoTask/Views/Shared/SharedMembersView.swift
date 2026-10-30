import SwiftUI

struct SharedMembersView: View {
    let listID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var inviting = false
    @State private var error: String?
    @State private var removing: SharedMember?
    @State private var deleting = false
    @State private var renaming = false
    @State private var title = ""
    private var list: SharedList? { store.lists.first { $0.id == listID } }
    private var isOwner: Bool { list?.ownerID == store.accountID }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let list {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 18) {
                            FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill")
                                .frame(width: 100, height: 85)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(list.title).font(.system(size: 25, weight: .semibold)).tracking(-0.6)
                                Label(isOwner ? "Ваша общая папка" : "Общая папка", systemImage: "person.2")
                                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        if isOwner {
                            Button {
                                inviting = true
                            } label: {
                                Label("Пригласить по QR-коду", systemImage: "qrcode")
                            }.buttonStyle(SharedPrimaryStyle()).accessibilityIdentifier("shared-open-invite")
                        }
                        VStack(alignment: .leading, spacing: 13) {
                            SharedSectionTitle(title: "Участники", detail: "\(store.members(in: listID).count)")
                            GroupCard {
                                ForEach(store.members(in: listID)) { member in
                                    HStack(spacing: 12) {
                                        SharedMemberAvatar(member: member, size: 42)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(
                                                member.userID == store.accountID
                                                    ? "\(member.displayName) (вы)" : member.displayName
                                            )
                                            .font(.system(size: 14, weight: .medium))
                                            Text(member.userID == list.ownerID ? "Владелец папки" : "Участник")
                                                .font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        Spacer(minLength: 0)
                                        if isOwner && member.userID != list.ownerID {
                                            Button("Удалить", role: .destructive) { removing = member }
                                                .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                                                .foregroundStyle(Theme.Colors.danger).disabled(!store.canManage)
                                        }
                                    }.padding(16)
                                        .accessibilityElement(children: .contain)
                                        .accessibilityIdentifier("shared-member-\(member.id)")
                                    if member.id != store.members(in: listID).last?.id { Hairline(leading: 70) }
                                }
                            }
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.2.badge.key").foregroundStyle(Theme.Colors.accent)
                            Text(
                                "Участники видят общие задачи и могут редактировать их. Приглашениями и доступом управляет владелец."
                            )
                            .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 13) {
                            SharedSectionTitle(title: "Управление папкой")
                            GroupCard {
                                if isOwner {
                                    managementRow("Переименовать", icon: "pencil") {
                                        title = list.title; renaming = true
                                    }
                                    Hairline(leading: 52)
                                    managementRow("Удалить общую папку", icon: "trash", destructive: true) {
                                        deleting = true
                                    }
                                } else if let own = store.members(in: listID).first(where: {
                                    $0.userID == store.accountID
                                }) {
                                    managementRow(
                                        "Покинуть папку", icon: "rectangle.portrait.and.arrow.right", destructive: true
                                    ) {
                                        removing = own
                                    }
                                }
                            }
                        }
                    }
                    .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Папка недоступна", systemImage: "person.2.slash").padding(30)
                }
            }
            .background(Theme.Colors.background).scrollIndicators(.hidden)
            .navigationTitle("Участники и доступ")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } } }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .foregroundStyle(Theme.Colors.textPrimary).tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        .sheet(isPresented: $inviting) { SharedInviteSheet(listID: listID) }
        .sharedErrorAlert($error)
        .alert("Переименовать папку", isPresented: $renaming) {
            TextField("Название", text: $title)
            Button("Сохранить") {
                guard let list else { return }
                Task {
                    do { try await store.updateList(list, title: title) } catch {
                        self.error = SharedListStore.message(for: error)
                    }
                }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100)
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Закрыть доступ к папке?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Подтвердить", role: .destructive) {
                guard let member = removing else { return }
                Task {
                    do {
                        try await store.removeMember(member)
                        if member.userID == store.accountID { dismiss() }
                    } catch { self.error = SharedListStore.message(for: error) }
                    removing = nil
                }
            }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: {
            Text("Участник потеряет доступ к общей папке. Его личные задачи сохранятся.")
        }
        .confirmationDialog(
            "Удалить папку для всех участников?", isPresented: $deleting, titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                guard let list else { return }
                Task {
                    do { try await store.updateList(list, title: list.title, delete: true); dismiss() } catch {
                        self.error = SharedListStore.message(for: error)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Общая папка и её задачи станут недоступны всем участникам.")
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 660)
        #endif
    }

    private func managementRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .foregroundStyle(destructive ? Theme.Colors.danger : Theme.Colors.textPrimary)
            .padding(18).frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!store.canManage)
    }
}
