import SwiftUI
import SwiftData

struct FastCaptureBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    let activeTag: Tag?
    @Binding var isCaptureActive: Bool

    @State private var taskTitle: String = ""
    @State private var isHighPriority: Bool = false
    @FocusState private var isFocused: Bool
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @State private var folderChoice: CaptureFolderChoice = .unassigned
    @State private var newFolderName = ""
    @State private var isCaptureExpanded = false

    init(activeTag: Tag?, isCaptureActive: Binding<Bool> = .constant(false)) {
        self.activeTag = activeTag
        self._isCaptureActive = isCaptureActive
    }

    private var canSubmit: Bool {
        !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if isCaptureExpanded || !taskTitle.isEmpty {
                CaptureFolderPicker(tags: tags, choice: $folderChoice, newName: $newFolderName) { isFocused = true }
                    .padding(.horizontal, 12)
            }
            inputBar
        }
        .onAppear { folderChoice = activeTag.map { .existing($0.id) } ?? .unassigned }
        .onChange(of: activeTag?.id) { _, _ in
            if taskTitle.isEmpty { folderChoice = activeTag.map { .existing($0.id) } ?? .unassigned }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            PriorityToggleButton(isOn: $isHighPriority, size: 36)
                .fixedSize()

            TextField(
                "",
                text: $taskTitle,
                prompt: Text("Новая задача").foregroundColor(Theme.Colors.textMuted)
            )
            .font(Theme.Typography.body)
            .tracking(Theme.Typography.bodyTracking)
            .foregroundColor(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit {
                handleSubmit()
            }

            if let activeTag, !isFocused {
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeTag.color)
                        .frame(width: 6, height: 6)
                    Text(shortName(activeTag.name))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Theme.Colors.fill)
                .clipShape(Capsule())
                .fixedSize()
                .transition(.opacity)
            }

            SubmitCircleButton(isEnabled: canSubmit, size: 34) {
                handleSubmit()
            }
            .fixedSize()
            if isFocused {
                Button {
                    isFocused = false
                    isCaptureActive = false
                    isCaptureExpanded = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .transition(.opacity)
                .accessibilityLabel("Скрыть клавиатуру")
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: isFocused)
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .frame(height: 52)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.capturePill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.capturePill, style: .continuous)
                .strokeBorder(
                    isCaptureActive ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.ruleStrong, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(Theme.Colors.background)
        .transaction { $0.animation = nil }
        .onChange(of: isFocused) { _, focused in
            if focused { isCaptureExpanded = true }
            if focused != isCaptureActive {
                isCaptureActive = focused
            }
        }
        .onChange(of: isCaptureActive) { _, active in
            if !active && isFocused {
                isFocused = false
                hideKeyboard()
            } else if active && !isFocused {
                isFocused = true
            }
        }
        .onAppear {
            isFocused = isCaptureActive
            if !isCaptureActive { hideKeyboard() }
        }
        .onDisappear {
            isFocused = false
            isCaptureActive = false
            hideKeyboard()
        }
    }

    /// Keeps the context chip compact so the text field always gets the room
    private func shortName(_ name: String) -> String {
        name.count > 12 ? String(name.prefix(11)) + "…" : name
    }

    private func handleSubmit() {
        guard canSubmit else {
            isFocused = false
            isCaptureActive = false
            hideKeyboard()
            return
        }

        Haptics.light()
        guard
            let created = modelContext.createTask(
                title: taskTitle, folder: folderChoice, newFolderName: newFolderName, tags: tags,
                highPriority: isHighPriority)
        else { return }
        folderChoice = created.tags.first.map { .existing($0.id) } ?? .unassigned
        newFolderName = ""

        taskTitle = ""
        isHighPriority = false

        // Keep the cursor for consecutive entry
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if isCaptureActive {
                isFocused = true
            }
        }
    }
}
