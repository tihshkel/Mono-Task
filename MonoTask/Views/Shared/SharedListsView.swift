import SwiftUI

struct SharedListsView: View {
    var isEmbedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = SharedListStore.shared
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var joining: JoinRequest?
    @State private var destination: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heading
                    if store.accountID == nil {
                        ContentUnavailableView(
                            "Войдите в аккаунт", systemImage: "person.crop.circle",
                            description: Text("Общие папки доступны после входа в MonoTask."))
                    } else {
                        actions
                        if store.errorMessage != nil || store.pendingCount > 0
                            || (store.isSyncing && store.lists.isEmpty)
                        {
                            status
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            SharedSectionTitle(title: "Ваши общие папки", detail: "\(store.lists.count)")
                            if store.lists.isEmpty && !store.isSyncing {
                                emptyState
                            } else {
                                ForEach(store.lists) { list in folderRow(list) }
                            }
                        }
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "lock").font(.system(size: 12))
                            Text("Задачи общей папки видны её участникам. Ваши личные папки остаются личными.")
                                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }.foregroundStyle(Theme.Colors.textSecondary).padding(.horizontal, 3)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 28)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background).scrollIndicators(.hidden)
            .refreshable { await store.sync() }
            .navigationTitle("Общие папки")
            .navigationDestination(for: UUID.self) { SharedListDetailView(listID: $0) }
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(Theme.Colors.accent).foregroundStyle(Theme.Colors.textPrimary).preferredColorScheme(Theme.colorScheme)
        .sheet(isPresented: $creating, onDismiss: openDestination) {
            SharedCreateFolderSheet { destination = $0 }
        }
        .sheet(
            item: $joining,
            onDismiss: {
                store.pendingInviteCode = nil
                openDestination()
            }
        ) { request in
            SharedJoinFolderSheet(initialCode: request.code) { destination = $0 }
        }
        .task(id: scenePhase) {
            store.activateAccount()
            if let pending = store.pendingInviteCode { joining = JoinRequest(code: pending) }
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.sync()
                do { try await Task.sleep(for: .seconds(6)) } catch { break }
            }
        }
        .onChange(of: store.pendingInviteCode) { _, value in
            if let value { joining = JoinRequest(code: value) }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 740, minHeight: 660)
        #endif
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ВМЕСТЕ ПРОЩЕ").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Общие дела.\nОбщие папки.").font(.system(size: 30, weight: .semibold)).tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Планы, к которым хочется присоединиться.")
                    .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill")
                .frame(width: 110, height: 92).accessibilityHidden(true)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                creating = true
            } label: {
                actionCard(title: "Новая папка", detail: "Начать вместе", symbol: "folder.badge.plus", primary: true)
            }.accessibilityIdentifier("shared-create-list")
            Button {
                joining = JoinRequest(code: "")
            } label: {
                actionCard(
                    title: "Присоединиться", detail: "QR-код или ссылка", symbol: "qrcode.viewfinder", primary: false)
            }.accessibilityIdentifier("shared-join-list")
        }
        .buttonStyle(SoftPressStyle()).disabled(store.isMutating)
    }

    private func actionCard(title: String, detail: String, symbol: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: symbol).font(.system(size: 25, weight: .regular))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(.system(size: 11)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(primary ? Theme.Colors.darkestHour : Theme.Colors.cloudDancer)
        .padding(18).frame(maxWidth: .infinity, minHeight: 135, alignment: .leading)
        .background(primary ? Theme.Colors.sunGlare : Theme.Colors.blueViolet, in: RoundedRectangle(cornerRadius: 23))
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isSyncing && store.lists.isEmpty {
                ProgressView("Обновляем папки…").font(Theme.Typography.caption)
            }
            if store.pendingCount > 0 {
                Label("Изменений на устройстве: \(store.pendingCount)", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            if let message = store.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark").font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Повторить") { Task { await store.sync() } }.disabled(store.isSyncing)
                        .font(.system(size: 12, weight: .medium))
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 29, weight: .light)).foregroundStyle(Theme.Colors.accent)
            Text("Здесь начинается «мы»").font(.system(size: 17, weight: .medium))
            Text("Создайте папку для общих планов\nили примите приглашение.")
                .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func folderRow(_ list: SharedList) -> some View {
        let tasks = store.tasks(in: list.id)
        let done = tasks.filter(\.isDone).count
        return NavigationLink(value: list.id) {
            HStack(spacing: 14) {
                FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill").frame(width: 74, height: 64)
                VStack(alignment: .leading, spacing: 7) {
                    Text(list.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(
                        Theme.Colors.textPrimary
                    )
                    .lineLimit(2)
                    Text("\(tasks.count - done) открыто · \(store.members(in: list.id).count) участников")
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary)
                    SharedMemberAvatars(members: store.members(in: list.id), size: 23)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.6))
        }.buttonStyle(.plain).accessibilityIdentifier("shared-list-\(list.id)")
    }

    private struct JoinRequest: Identifiable { let id = UUID(); let code: String }

    private func openDestination() {
        if let destination { path.append(destination); self.destination = nil }
    }
}

extension View {
    func sharedErrorAlert(_ error: Binding<String?>) -> some View {
        alert(
            "Не удалось завершить действие",
            isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })
        ) {
            Button("Понятно", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}
