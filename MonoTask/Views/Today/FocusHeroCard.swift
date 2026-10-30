import SwiftUI
import SwiftData
struct FocusHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact: Bool = false
    var collapseAnimation: Animation = Theme.Motion.standard
    let tags: [Tag]
    let scheduledTags: [Tag]
    @Binding var scope: TaskScope
    let today: Date
    let doneCount: Int
    let totalCount: Int
    let openCount: (TaskScope) -> Int

    private var progress: Double {
        totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    private var title: String {
        scope == .focus ? "Сегодня" : scope.title(tags: tags)
    }

    private var subtitle: String? {
        guard scope == .focus else { return nil }
        if scheduledTags.isEmpty { return nil }
        return scheduledTags.map(\.name).joined(separator: " · ")
    }

    var body: some View {
        #if os(iOS)
        mobileBody
        #else
        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 8) {
                EyebrowLabel(text: today.formattedEyebrowDate)
                Spacer()
                SyncIndicator()
            }
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

            Text(title)
                .contentTransition(.opacity)
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(compact ? 22.0 / 34.0 : 1, anchor: .leading)
                .frame(height: compact ? 29 : 43, alignment: .leading)
                .padding(.top, compact ? 10 : 18)

            CollapsingSection(progress: compact ? 1 : 0) {
                VStack(alignment: .leading, spacing: 0) {

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(doneCount)")
                            .font(Theme.Typography.figure(46))
                            .foregroundColor(Theme.Colors.accent)
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("focus-completion-count")
                        Text("/ \(totalCount) готово")
                            .font(Theme.Typography.numeric(13))
                            .foregroundColor(Theme.Colors.textMuted)

                        if let subtitle {
                            Spacer(minLength: 8)
                            Text(subtitle.uppercased())
                                .font(Theme.Typography.eyebrow)
                                .tracking(Theme.Typography.eyebrowTracking)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.top, 4)

                    ProgressLine(progress: progress)
                        .padding(.top, 14)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(compact ? 0 : 1)
            .clipped()
            .accessibilityHidden(compact)

            scopePicker
        }
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .background(Theme.Colors.background)
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: doneCount)
        .animation(reduceMotion ? nil : collapseAnimation, value: compact)
        #endif
    }

    #if os(iOS)
    private var mobileBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if !compact {
                    HStack {
                        Text(today.formattedEyebrowDate).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        SyncIndicator()
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: compact ? 22 : 26, weight: .semibold)).tracking(-0.7)
                            .foregroundStyle(Theme.Colors.textPrimary).lineLimit(1).minimumScaleFactor(0.75)
                            .contentTransition(.opacity)
                        if let subtitle, !compact {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if !compact {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(doneCount) / \(totalCount)")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.Colors.accent).contentTransition(.numericText())
                                .accessibilityIdentifier("focus-completion-count")
                            Text("выполнено").font(.system(size: 10)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                if !compact { ProgressLine(progress: progress, height: 3) }
            }
            .padding(18)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5))
            scopePicker
        }
        .padding(.horizontal, Theme.Spacing.screenPadding).padding(.top, 6)
        .background(Theme.Colors.background)
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: doneCount)
        .animation(reduceMotion ? nil : collapseAnimation, value: compact)
    }
    #endif

    private var scopePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill(.focus, title: "Фокус", color: nil)
                    pill(.all, title: "Все", color: nil)
                    ForEach(tags) { tag in
                        pill(.tag(tag.id), title: tag.name, color: tag.color)
                    }
                    Button {
                        SharedListStore.shared.isPresented = true
                    } label: {
                        Label("Общие", systemImage: "person.2")
                            .font(Theme.Typography.numeric(12))
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .background(Theme.Colors.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-shared-lists")
                }
                .padding(.horizontal, Theme.Spacing.screenPadding)
                .padding(.vertical, 16)
            }
            .padding(.horizontal, -Theme.Spacing.screenPadding)
            .onChange(of: scope) { _, newScope in
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    proxy.scrollTo(pillId(newScope), anchor: .center)
                }
            }
        }
    }

    private func pill(_ pillScope: TaskScope, title: String, color: Color?) -> some View {
        ScopeTab(
            title: title,
            color: color,
            count: openCount(pillScope),
            isSelected: scope == pillScope
        ) {
            guard scope != pillScope else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Theme.Motion.standard) { scope = pillScope }
        }
        .id(pillId(pillScope))
        .accessibilityIdentifier("task-scope-" + pillId(pillScope))
    }

    private func pillId(_ scope: TaskScope) -> String {
        switch scope {
        case .focus: return "focus"
        case .all: return "all"
        case .highPriority: return "priority"
        case .tag(let id): return id.uuidString
        }
    }
}
/// Measures the expanded summary directly rather than feeding geometry changes
/// back into state during keyboard animation. Layout and clipping share one value.
private struct CollapsingSection: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: size.width, height: size.height * (1 - min(1, max(0, progress))))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: proposal.width, height: nil))
    }
}

struct SyncIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetails = false
    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    if SupabaseService.shared.syncStatus.isSyncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(SyncPresentation.color).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 12, height: 12)
                Text(SyncPresentation.title.uppercased())
                    .contentTransition(.opacity)
                    .font(Theme.Typography.eyebrow)
                    .tracking(Theme.Typography.eyebrowTracking)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: SyncPresentation.title)
        .accessibilityIdentifier("sync-status")
        .accessibilityHint("Показать подробности синхронизации")
        #if os(iOS)
        .sheet(isPresented: $showingDetails) {
            ScrollView {
                SyncDetailsView(showsCloseButton: true).padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.height(280), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.Colors.surfaceElevated)
        }
        #else
        .popover(isPresented: $showingDetails) {
            ScrollView {
                SyncDetailsView(showsCloseButton: true).padding(24)
            }
            .frame(width: 380, height: 320)
        }
        #endif
    }
}

@MainActor
enum SyncPresentation {
    static var isPreview: Bool {
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        return ProcessInfo.processInfo.arguments.contains("--screenshots")
            && ProcessInfo.processInfo.arguments.contains("--sync-success")
        #else
        return false
        #endif
    }
    static var title: String {
        if isPreview { return "Синхронизировано" }
        let service = SupabaseService.shared
        if AuthManager.shared.userID == nil && !SupabaseSyncService.usesPreviewTransport { return "Локально" }
        if !NetworkMonitor.shared.isConnected { return "Без сети" }
        if service.syncStatus.isSyncing { return "Синхронизация…" }
        if case .error = service.syncStatus { return "Ошибка синхронизации" }
        if case .error = service.connectionStatus { return "Нет соединения" }
        if service.hasPendingChanges { return "Есть изменения" }
        if case .success = service.syncStatus { return "Синхронизировано" }
        return "Ожидает синхронизации"
    }
    static var icon: String {
        if SupabaseService.shared.syncStatus.isSyncing { return "arrow.triangle.2.circlepath" }
        return title == "Синхронизировано" ? "checkmark.icloud" : "icloud"
    }
    static var color: Color {
        if case .error = SupabaseService.shared.syncStatus { return Theme.Colors.danger }
        if !NetworkMonitor.shared.isConnected { return Theme.Colors.warning }
        return title == "Синхронизировано" ? Theme.Colors.accent : Theme.Colors.textSecondary
    }
}

struct SyncDetailsView: View {
    var showsCloseButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var retryError: String?
    private var canSync: Bool {
        !SyncPresentation.isPreview && AuthManager.shared.userID != nil && NetworkMonitor.shared.isConnected
            && !SupabaseService.shared.syncStatus.isSyncing
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Label(SyncPresentation.title, systemImage: SyncPresentation.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SyncPresentation.color)
                Spacer(minLength: 4)
                if showsCloseButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36).background(Theme.Colors.fillStrong, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Закрыть")
                }
            }
            Text(
                SyncPresentation.isPreview
                    ? "Пример успешной синхронизации. Демонстрационные данные."
                    : AuthManager.shared.userID == nil
                        ? "Данные находятся на этом устройстве. Войдите в аккаунт, чтобы синхронизировать их между устройствами."
                        : "Задачи сохранены на устройстве. При подключении к сети изменения обновляются в облаке."
            )
            .font(.system(size: 16))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            if let date = SyncPresentation.isPreview ? Date.now : SupabaseConfig.shared.lastSyncDate,
                SyncPresentation.isPreview || AuthManager.shared.userID != nil
            {
                HStack(alignment: .firstTextBaseline) {
                    Text("Обновлено").foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(
                        date.formatted(
                            .dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "ru_RU"))))
                }
                .font(.system(size: 15))
            }
            if case .error(let message) = SupabaseService.shared.syncStatus {
                Text(message).font(.system(size: 15)).foregroundStyle(Theme.Colors.danger)
            }
            if let retryError { Text(retryError).font(.system(size: 15)).foregroundStyle(Theme.Colors.danger) }
            Button {
                Task { @MainActor in
                    do { try await SupabaseSyncService.shared.sync(context: context); retryError = nil } catch {
                        retryError = error.localizedDescription
                    }
                }
            } label: {
                Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSync ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(canSync ? Theme.Colors.accent : Theme.Colors.surfaceInteractive, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSync)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .preferredColorScheme(Theme.colorScheme)
    }
}
