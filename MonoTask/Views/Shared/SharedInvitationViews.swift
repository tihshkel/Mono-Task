import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SharedPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.Colors.darkestHour)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.sunGlare, in: RoundedRectangle(cornerRadius: 17))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}

struct SharedSectionTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if let detail { Text(detail).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary) }
        }
    }
}

@MainActor
enum SharedClipboard {
    static func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}

struct SharedInviteSheet: View {
    let listID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                SharedInvitationContent(listID: listID)
                    .padding(24).frame(maxWidth: 510).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Пригласить в папку")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } } }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 720)
        #endif
    }
}

struct SharedInvitationContent: View {
    let listID: UUID
    var created = false
    @State private var store = SharedListStore.shared
    @State private var invite: SharedInvite?
    @State private var image: CGImage?
    @State private var loading = false
    @State private var copied = false
    @State private var replacing = false
    @State private var error: String?
    private var list: SharedList? { store.lists.first { $0.id == listID } }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(created ? "Папка готова." : "Ближе на один скан.")
                    .font(.system(size: 29, weight: .semibold)).tracking(-0.9)
                Text(
                    created
                        ? "Пригласите первого участника — и начинайте вместе."
                        : "Покажите этот код тому, с кем хотите разделить планы."
                )
                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let valid = invite.map { $0.expiresAt > timeline.date } ?? false
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.Colors.sunGlare)
                        Text(list?.title ?? "Общая папка").font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Spacer()
                        Image(systemName: "person.2.fill").foregroundStyle(Theme.Colors.cloudDancer.opacity(0.65))
                    }.foregroundStyle(Theme.Colors.cloudDancer).padding(20)
                    VStack(spacing: 17) {
                        if let image, valid {
                            Image(image, scale: 1, label: Text("QR-код приглашения в папку \(list?.title ?? "")"))
                                .interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 250).padding(8).background(
                                    .white, in: RoundedRectangle(cornerRadius: 18)
                                )
                                .accessibilityLabel("QR-код приглашения в папку \(list?.title ?? "")")
                                .accessibilityIdentifier("shared-invite-qr")
                        } else {
                            VStack(spacing: 14) {
                                if loading {
                                    ProgressView().tint(Theme.Colors.darkestHour)
                                    Text("Готовим приглашение…")
                                } else {
                                    Image(systemName: "qrcode").font(.system(size: 58, weight: .light))
                                    Text(invite == nil ? "Ваш код появится здесь" : "Срок действия истёк")
                                }
                            }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.Colors.darkestHour)
                            .frame(maxWidth: 250).frame(height: 250).padding(8)
                            .background(Theme.Colors.cloudDancer, in: RoundedRectangle(cornerRadius: 18))
                        }
                        HStack(spacing: 7) {
                            Circle().fill(valid ? Theme.Colors.sunGlare : Theme.Colors.cloudDancer.opacity(0.5))
                                .frame(width: 5, height: 5)
                            Text(valid ? "ОДНО ПРИГЛАШЕНИЕ · ОДИН УЧАСТНИК" : "ПРИГЛАШЕНИЕ В MONOTASK")
                                .font(.system(size: 9, weight: .medium)).tracking(0.7)
                                .foregroundStyle(Theme.Colors.cloudDancer.opacity(0.85))
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 22)
                    Line().stroke(
                        Theme.Colors.cloudDancer.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                    .frame(height: 1).padding(.horizontal, 20)
                    HStack {
                        Image(systemName: "clock").foregroundStyle(Theme.Colors.sunGlare)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Действует 72 часа").font(.system(size: 12, weight: .medium))
                            if let invite {
                                Text("До \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.cloudDancer.opacity(0.7))
                            }
                        }
                        Spacer()
                        Text("m.").font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.sunGlare)
                    }.foregroundStyle(Theme.Colors.cloudDancer).padding(20)
                }
                .background(Theme.Colors.blueViolet, in: RoundedRectangle(cornerRadius: 28))
                .overlay(alignment: .bottomLeading) {
                    Circle().fill(Theme.Colors.background).frame(width: 14, height: 14).offset(x: -7, y: -67)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(Theme.Colors.background).frame(width: 14, height: 14).offset(x: 7, y: -67)
                }
                if let invite, valid {
                    ShareLink(item: invite.url, subject: Text("Приглашение в \(list?.title ?? "MonoTask")")) {
                        Label("Поделиться приглашением", systemImage: "square.and.arrow.up")
                    }.buttonStyle(SharedPrimaryStyle()).disabled(loading)
                    Button {
                        SharedClipboard.copy(invite.url.absoluteString)
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(
                            copied ? "Ссылка скопирована" : "Скопировать ссылку",
                            systemImage: copied ? "checkmark" : "link"
                        )
                        .font(.system(size: 13, weight: .medium)).frame(minHeight: 38)
                    }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent)
                    DisclosureGroup("Код для ручного ввода") {
                        Text(invite.code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .padding(.vertical, 10).accessibilityIdentifier("shared-generated-code")
                    }.font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.danger).fixedSize(horizontal: false, vertical: true)
            }
            Button(invite == nil ? "Получить QR-код" : "Создать новый QR-код") {
                if invite == nil { generate() } else { replacing = true }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
            .disabled(loading || !store.canManage).accessibilityIdentifier("shared-create-invite")
            Text("Код одноразовый. Новый QR-код заменяет предыдущее неиспользованное приглашение.")
                .font(.system(size: 11)).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .task {
            if let cached = store.invitations[listID], cached.expiresAt > .now {
                invite = cached
                image = SharedQRCode.image(for: cached.url.absoluteString)
            } else {
                generate()
            }
        }
        .confirmationDialog("Заменить приглашение?", isPresented: $replacing, titleVisibility: .visible) {
            Button("Создать новый код") { generate() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Предыдущий неиспользованный QR-код и ссылка перестанут действовать.")
        }
    }

    private func generate() {
        guard !loading else { return }
        loading = true
        error = nil
        Task { @MainActor in
            defer { loading = false }
            do {
                let received = try await store.createInvite(listID: listID)
                invite = received
                image = SharedQRCode.image(for: received.url.absoluteString)
                copied = false
                if image == nil { error = "Не удалось нарисовать QR-код. Пригласите участника по ссылке." }
            } catch { self.error = SharedListStore.message(for: error) }
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path(); path.move(to: .zero); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); return path
        }
    }
}

struct SharedCreateFolderSheet: View {
    var onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var title = ""
    @State private var createdID: UUID?
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private var valid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let createdID {
                        SharedInvitationContent(listID: createdID, created: true)
                    } else {
                        FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill")
                            .frame(width: 164, height: 132).padding(.top, 12)
                        VStack(spacing: 9) {
                            Text("Общим планам —\nсвою папку.")
                                .font(.system(size: 30, weight: .semibold)).tracking(-0.9).multilineTextAlignment(
                                    .center)
                            Text("Задачи, идеи и маленькие победы. Теперь вместе.")
                                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        GroupCard(padding: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Название папки").font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text("\(title.count)/100").font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(
                                            title.count > 100 ? Theme.Colors.danger : Theme.Colors.textMuted)
                                }
                                TextField("Например, наш большой проект", text: $title)
                                    .font(.system(size: 19, weight: .medium)).textFieldStyle(.plain)
                                    .focused($focused).submitLabel(.done).onSubmit { if valid { create() } }
                                    .accessibilityIdentifier("shared-folder-name")
                            }
                        }
                        if let error { Text(error).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.danger) }
                        Button(action: create) {
                            HStack(spacing: 8) {
                                if saving { ProgressView().tint(Theme.Colors.darkestHour) }
                                Text(saving ? "Создаём папку…" : "Создать папку")
                                if !saving { Image(systemName: "arrow.right") }
                            }
                        }.buttonStyle(SharedPrimaryStyle()).disabled(!valid || saving || !store.canManage)
                            .accessibilityIdentifier("shared-confirm-create")
                        Label("После создания вы получите QR-код для приглашения.", systemImage: "qrcode")
                            .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }.padding(24).frame(maxWidth: 510).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if let createdID {
                    Button {
                        onOpen(createdID); dismiss()
                    } label: {
                        Label("Открыть папку", systemImage: "arrow.right")
                    }.buttonStyle(SharedPrimaryStyle()).padding(20).background(Theme.Colors.background)
                        .accessibilityIdentifier("shared-open-created-folder")
                }
            }
            .navigationTitle(createdID == nil ? "Новая папка" : "Готово")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdID == nil ? "Отмена" : "Закрыть") { dismiss() }.disabled(saving)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .foregroundStyle(Theme.Colors.textPrimary).tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 650)
        #endif
    }
    private func create() {
        guard valid, !saving else { return }
        saving = true; error = nil; focused = false
        Task { @MainActor in
            defer { saving = false }
            do { createdID = try await store.createList(title: title); Haptics.success() } catch {
                self.error = SharedListStore.message(for: error)
            }
        }
    }
}

struct SharedJoinFolderSheet: View {
    var onJoined: (UUID) -> Void
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = SharedListStore.shared
    @State private var code: String
    @State private var connectionCode: String?
    @State private var attemptID = UUID()
    @State private var joinedListID: UUID?
    @State private var scanning = false
    @State private var scannedCode: String?
    @State private var importing = false
    @State private var joining = false
    @State private var error: String?
    @State private var appeared = false
    @FocusState private var focused: Bool
    private var validCode: String? { SharedInvite.parseCode(code) }

    init(initialCode: String = "", onClose: (() -> Void)? = nil, onJoined: @escaping (UUID) -> Void) {
        self.onJoined = onJoined
        self.onClose = onClose
        _code = State(initialValue: initialCode)
        _connectionCode = State(initialValue: SharedInvite.parseCode(initialCode))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image("BrandLogo").resizable().scaledToFit().frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                Text("MonoTask").font(.system(size: 17, weight: .semibold)).tracking(-0.5)
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Theme.Colors.fill, in: Circle())
                }
                .buttonStyle(.plain).disabled(joining).keyboardShortcut(.cancelAction)
                .accessibilityLabel("Отмена").accessibilityIdentifier("shared-close-join")
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 24) {
                    if let connectionCode {
                        connectionContent(connectionCode)
                    } else {
                        manualContent
                    }
                    Label("Личные папки остаются только вашими.", systemImage: "lock")
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: 510).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.Colors.background)
        .tint(Theme.Colors.accent).foregroundStyle(Theme.Colors.textPrimary).preferredColorScheme(Theme.colorScheme)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: connectionCode != nil)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: error != nil)
        .interactiveDismissDisabled(joining)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
        .task(id: attemptID) {
            if let connectionCode { await join(code: connectionCode) }
        }
        .sheet(
            isPresented: $scanning,
            onDismiss: {
                if let scannedCode {
                    self.scannedCode = nil
                    requestJoin(scannedCode)
                }
            }
        ) {
            SharedQRScannerView { scannedCode = $0 }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { @MainActor in
                    let allowed = url.startAccessingSecurityScopedResource()
                    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20 * 1024 * 1024 else {
                            error = "Выберите изображение меньше 20 МБ."; return
                        }
                        let data = try Data(contentsOf: url)
                        let found = await Task.detached(priority: .userInitiated) { SharedQRCode.invitation(in: data) }
                            .value
                        guard let found else { error = "На изображении не найден QR-код приглашения MonoTask."; return }
                        Haptics.success()
                        requestJoin(found)
                    } catch { self.error = "Не удалось открыть изображение. Попробуйте другое или вставьте ссылку." }
                }
            case .failure: break
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 650)
        #endif
    }

    private func connectionContent(_ invitation: String) -> some View {
        VStack(spacing: 24) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Theme.Colors.accent.opacity(0.06)).frame(width: 216, height: 216)
                    .overlay {
                        Circle().strokeBorder(Theme.Colors.accent.opacity(0.1), lineWidth: 1)
                    }
                FolderArtwork(tint: Theme.Colors.blueViolet, icon: "person.2.fill")
                    .frame(width: 200, height: 172).rotationEffect(.degrees(reduceMotion ? 0 : -6))
                    .offset(x: -8, y: reduceMotion || appeared ? -16 : -4)
                Image(systemName: error == nil ? "link" : "exclamationmark")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(error == nil ? Theme.Colors.accent : Theme.Colors.priority)
                    .symbolEffect(.pulse, isActive: joining && !reduceMotion)
                    .frame(width: 54, height: 54)
                    .background(Theme.Colors.surfaceElevated, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.borderSubtle, lineWidth: 1))
                    .offset(x: -14, y: -12)
            }.padding(.top, 10).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(error == nil ? "Открываем\nобщую папку." : "Пока не получилось.")
                    .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("shared-join-heading")
                Text(
                    error == nil
                        ? "Приглашение уже с вами. Подключим папку и сразу покажем задачи — без лишних нажатий."
                        : joinedListID == nil
                            ? "Папка ещё не подключена. Можно попробовать снова или открыть другое приглашение."
                            : "Вы уже присоединились. Осталось загрузить папку — повторно принимать приглашение не нужно."
                )
                .font(.system(size: 14)).lineSpacing(4).foregroundStyle(Theme.Colors.textSecondary)
            }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.dangerMuted, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("shared-join-error")
                Button {
                    requestJoin(invitation)
                } label: {
                    Label("Попробовать снова", systemImage: "arrow.clockwise")
                }.buttonStyle(SharedPrimaryStyle()).disabled(joining || store.isMutating)
                    .accessibilityIdentifier("shared-retry-join")
                Button("Другое приглашение") {
                    connectionCode = nil; joinedListID = nil; code = ""; self.error = nil
                }
                .font(.system(size: 13, weight: .medium)).buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent).accessibilityIdentifier("shared-change-invite")
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.Colors.accent)
                    Text("Подключаем папку…").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.Colors.accent).padding(.horizontal, 18).padding(.vertical, 13)
                .background(Theme.Colors.primaryMuted, in: Capsule())
                .accessibilityElement(children: .combine)
            }
            DisclosureGroup("Подробности приглашения") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(invitation).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("shared-received-code")
                    Text("Код одноразовый и действует 72 часа с момента создания.")
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
            .padding(16).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Вместе —\nв одной папке.").font(.system(size: 32, weight: .semibold)).tracking(-1)
                Text("Отсканируйте QR-код — сразу откроем папку. Или вставьте приглашение вручную.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
            }
            Button {
                focused = false; scanning = true
            } label: {
                HStack(spacing: 18) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 39, weight: .light))
                        .foregroundStyle(Theme.Colors.sunGlare)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Сканировать QR-код").font(.system(size: 17, weight: .semibold))
                        Text("Камера, код, готово.").font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.cloudDancer.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 15))
                }.foregroundStyle(Theme.Colors.cloudDancer).padding(22)
                    .frame(maxWidth: .infinity, minHeight: 122)
                    .background(Theme.Colors.blueViolet, in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(SoftPressStyle()).accessibilityIdentifier("shared-scan-qr")
            GroupCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ссылка или код").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Вставить") {
                            if let value = SharedClipboard.string { code = value; error = nil }
                        }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
                            .foregroundStyle(Theme.Colors.accent).accessibilityIdentifier("shared-paste-invite")
                    }
                    TextField("Код или ссылка MonoTask", text: $code, axis: .vertical)
                        .font(.system(size: 13, design: .monospaced)).textFieldStyle(.plain)
                        .autocorrectionDisabled().lineLimit(2...4).focused($focused)
                        .accessibilityIdentifier("shared-invite-code")
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                        #endif
                    if validCode != nil {
                        Label(
                            "Приглашение готово к открытию",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            Button {
                importing = true
            } label: {
                Label("Выбрать изображение с QR-кодом", systemImage: "photo")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.plain).foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("shared-import-qr")
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.danger).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let validCode { requestJoin(validCode) }
            } label: {
                Label("Открыть папку", systemImage: "arrow.right")
            }.buttonStyle(SharedPrimaryStyle()).disabled(validCode == nil || joining || store.isMutating)
                .accessibilityIdentifier("shared-confirm-join")
        }
    }

    private func requestJoin(_ value: String) {
        guard !joining, let invitation = SharedInvite.parseCode(value) else { return }
        code = invitation; connectionCode = invitation; error = nil; focused = false
        attemptID = UUID()
    }

    private func join(code: String) async {
        store.activateAccount()
        let owner = store.accountID
        joining = true; error = nil; focused = false
        defer { joining = false }
        do {
            let listID: UUID
            if let joinedListID {
                listID = joinedListID
                await store.sync(force: true)
            } else {
                listID = try await store.join(code: code)
            }
            guard !Task.isCancelled, owner == store.accountID else { return }
            joinedListID = listID
            guard store.lists.contains(where: { $0.id == listID }) else {
                error = store.errorMessage ?? "Не удалось загрузить задачи. Проверьте подключение и попробуйте снова."
                return
            }
            Haptics.success()
            onJoined(listID)
            if onClose == nil { dismiss() }
        } catch {
            guard !Task.isCancelled, owner == store.accountID else { return }
            self.error = SharedListStore.message(for: error)
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
