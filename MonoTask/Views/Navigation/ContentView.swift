import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sharedLists = SharedListStore.shared
    @State private var selectedTab: AppTab = .today
    @State private var isCaptureActive: Bool = false
    @State private var captureDraft = ""
    @State private var capturePriority = false
    @Namespace private var navigationSelection
    @State private var isCapturePresented = false
    @State private var captureTag: Tag?

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        #if os(macOS)
        MacRootView(initialTab: selectedTab)
            .sheet(isPresented: $sharedLists.isPresented) { SharedListsView() }
            .overlay(alignment: .bottom) {
                UndoDeletionToast().padding(.bottom, 20)
            }
        #else
        ZStack(alignment: .bottom) {
            WorkspaceView(
                captureTag: $captureTag,
                isCaptureActive: $isCaptureActive
            )
            .opacity(selectedTab == .today ? 1 : 0)
            .allowsHitTesting(selectedTab == .today)
            .accessibilityHidden(selectedTab != .today)

            if selectedTab == .activity {
                HeatmapView()
                    .transition(.opacity)
            } else if selectedTab == .settings {
                SettingsView()
                    .transition(.opacity)
            }

            UndoDeletionToast().padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }

        .sheet(isPresented: $sharedLists.isPresented) { SharedListsView() }
        .onChange(of: selectedTab) { _, _ in
            isCaptureActive = false
            hideKeyboard()
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            selectedTab = .today
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        #endif
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 10) {
            if !isCapturePresented {
                HStack(spacing: 2) {
                    ForEach(AppTab.allCases) { tab in tabButton(tab) }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.Colors.surfaceElevated.opacity(0.97), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.045), radius: 14, y: 4)
                Button(action: beginCapture) {
                    Image(systemName: "plus").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Theme.Colors.darkestHour)
                        .frame(width: 54, height: 54).background(
                            Theme.Colors.sunGlare, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(SoftPressStyle()).accessibilityLabel("Новая задача")
                .accessibilityIdentifier("navigation-add-task")
            } else {
                FloatingTaskCapture(
                    isPresented: $isCapturePresented, isFocused: $isCaptureActive,
                    title: $captureDraft, highPriority: $capturePriority, activeTag: captureTag
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: 460).frame(height: isCapturePresented ? nil : 56)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            Theme.Colors.background.ignoresSafeArea(edges: .bottom)
        }
    }

    private func beginCapture() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
            selectedTab = .today
            isCapturePresented = true
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            hideKeyboard()
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.activeSystemImage : tab.systemImage)
                    .font(.system(size: 19, weight: isSelected ? .medium : .regular))
                    .frame(height: 23)
                Text(tab == .today ? "Главная" : tab.title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.accent.opacity(0.075))
                        .matchedGeometryEffect(id: "selection", in: navigationSelection)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("navigation-\(tab.rawValue)")

    }
}

#Preview {
    ContentView()
}

private struct FloatingTaskCapture: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    @Binding var title: String
    @Binding var highPriority: Bool
    let activeTag: Tag?
    @FocusState private var fieldFocused: Bool
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @State private var folderChoice: CaptureFolderChoice = .unassigned
    @State private var newFolderName = ""

    private var canSubmit: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 9) {
            CaptureFolderPicker(tags: tags, choice: $folderChoice, newName: $newFolderName) { fieldFocused = true }
            HStack(spacing: 8) {
                PriorityToggleButton(isOn: $highPriority, size: 36)
                TextField("Новая задача", text: $title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                SubmitCircleButton(isEnabled: canSubmit, size: 36, action: submit)
                Button {
                    fieldFocused = false
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть ввод")
            }
            .padding(.horizontal, 8).frame(height: 56)
            .background(Theme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5))
        }
        .onAppear { folderChoice = activeTag.map { .existing($0.id) } ?? .unassigned }
        .foregroundStyle(Theme.Colors.textPrimary)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            fieldFocused = true
        }
        .onChange(of: fieldFocused) { _, focused in isFocused = focused }
        .onChange(of: isFocused) { _, focused in
            if !focused { fieldFocused = false }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { fieldFocused = false }
        }
    }

    private func submit() {
        guard canSubmit else { fieldFocused = false; return }
        guard
            let created = context.createTask(
                title: title, folder: folderChoice, newFolderName: newFolderName, tags: tags, highPriority: highPriority
            )
        else { return }
        folderChoice = created.tags.first.map { .existing($0.id) } ?? .unassigned
        newFolderName = ""
        Haptics.light()
        title = ""
        highPriority = false
    }
}
