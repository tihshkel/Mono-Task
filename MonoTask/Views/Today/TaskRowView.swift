import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TaskItem
    var allTags: [Tag] = []
    var isTargeted: Bool = false
    let onEdit: (TaskItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var completing = false
    @State private var checkboxScale: CGFloat = 1.0
    @State private var lastToggleTime: Date = .distantPast
    @State private var settledSwipeOffset: CGFloat = 0
    @State private var liveSwipeOffset: CGFloat?
    @State private var isFullSwipeArmed = false
    @State private var rowSize = CGSize(width: 340, height: 56)
    @State private var isDeleting = false

    private let deleteButtonWidth: CGFloat = 88

    private var swipeOffset: CGFloat { liveSwipeOffset ?? settledSwipeOffset }
    private var deleteWidth: CGFloat { max(0, -swipeOffset) }
    private var fullSwipeThreshold: CGFloat { rowSize.width * 0.72 }

    private var isDone: Bool {
        task.isDone
    }

    private var primaryTag: Tag? {
        task.tags.first
    }

    private var allSubtasksDone: Bool {
        task.hasSubtasks && task.completedSubtasksCount == task.subtasksCount
    }

    private var hasMeta: Bool {
        primaryTag != nil || task.hasSubtasks || !task.notes.isEmpty || (task.dueDate != nil && !isDone)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .opacity(swipeOffset < -0.5 ? 1 : 0)
                .allowsHitTesting(swipeOffset < -0.5)
            taskRow
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { _, size in
                    rowSize = size
                }
                .offset(x: swipeOffset)
        }
        .frame(minHeight: 56)
        .clipped()
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--screenshots"),
                ProcessInfo.processInfo.arguments.contains("--animate-completion"), task.sortOrder == 0
            {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toggleDone()
            }
            #endif
        }
        #if os(iOS)
        .gesture(swipeGesture)
        #endif
    }

    #if os(iOS)
    private var swipeGesture: some UIGestureRecognizerRepresentable {
        HorizontalTaskSwipe(
            onChanged: { translation in
                let nextOffset = min(0, max(-rowSize.width, settledSwipeOffset + translation))
                liveSwipeOffset = nextOffset
                let armed = shouldCompleteSwipe(translation: translation, offset: nextOffset)
                if armed && !isFullSwipeArmed { Haptics.impact() }
                isFullSwipeArmed = armed
            },
            onEnded: { translation in
                let finalOffset = min(0, max(-rowSize.width, settledSwipeOffset + translation))
                if shouldCompleteSwipe(translation: translation, offset: finalOffset) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        settledSwipeOffset = -rowSize.width
                        liveSwipeOffset = nil
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        deleteTask()
                    }
                } else {
                    let shouldReveal = -finalOffset > deleteButtonWidth / 2
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        settledSwipeOffset = shouldReveal ? -deleteButtonWidth : 0
                        liveSwipeOffset = nil
                    }
                    isFullSwipeArmed = false
                }
            },
            onCancelled: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    liveSwipeOffset = nil
                    isFullSwipeArmed = false
                }
            }
        )
    }
    private func shouldCompleteSwipe(translation: CGFloat, offset: CGFloat) -> Bool {
        // Once the action is open, a second deliberate left swipe commits it.
        // Moving right still closes the action, and a small wobble does not delete.
        let secondSwipe = settledSwipeOffset <= -deleteButtonWidth && translation <= -44
        return -offset >= fullSwipeThreshold || secondSwipe
    }
    #endif

    private var taskRow: some View {
        HStack(alignment: .center, spacing: 4) {

            Button {
                toggleDone()
            } label: {
                TaskCheckbox(isDone: isDone || completing, isPriority: task.isHighPriorityToday)
                    .scaleEffect(checkboxScale)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Вернуть в работу" : "Отметить выполненной")
            .padding(.leading, -11)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(Theme.Typography.body)
                    .tracking(Theme.Typography.bodyTracking)
                    .strikethrough(isDone || completing, color: Theme.Colors.textMuted)
                    .foregroundColor(isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasMeta {
                    metaRow
                }
            }
            .padding(.vertical, compactRows ? 8 : 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit(task)
            }
        }
        .frame(minHeight: 56)
        .background(
            Rectangle()
                .fill(isTargeted ? Theme.Colors.fillStrong : Theme.Colors.background)
        )
        .contentShape(Rectangle())
        .draggable(task.id.uuidString) {
            dragPreview
        }
        .contextMenu {
            TaskContextMenu(task: task, allTags: allTags, onEdit: onEdit, onToggleDone: toggleDone)
        }
    }

    private var deleteAction: some View {
        Button(action: deleteTask) {
            VStack(spacing: 4) {
                Image(systemName: isFullSwipeArmed ? "trash.fill" : "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(isFullSwipeArmed ? 1.12 : 1)
                Text("УДАЛИТЬ")
                    .font(Theme.Typography.numeric(9, weight: .medium))
            }
            .foregroundColor(Theme.Colors.textPrimary)
            .fixedSize()
            .frame(width: deleteWidth, height: rowSize.height, alignment: .center)
            .background(Theme.Colors.danger)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(swipeOffset == 0)
    }

    private func deleteTask() {
        guard !isDeleting, !completing else { return }
        isDeleting = true
        Haptics.warning()
        withAnimation(.easeInOut(duration: 0.2)) {
            TaskDeletionManager.shared.requestDelete(task, context: modelContext)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            if let date = task.dueDate, !isDone {
                Label(date.formattedDateTime, systemImage: "calendar")
                    .lineLimit(1)
                    .font(Theme.Typography.caption)
                    .foregroundColor(date > .now ? Theme.Colors.accent : Theme.Colors.textMuted)
            }
            if let tag = primaryTag {
                HStack(spacing: 5) {
                    Circle()
                        .fill(isDone ? Theme.Colors.textMuted : tag.color)
                        .frame(width: 6, height: 6)
                    Text(tag.name)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            if task.hasSubtasks {
                HStack(spacing: 4) {
                    Image(systemName: allSubtasksDone ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 11))
                    Text("\(task.completedSubtasksCount)/\(task.subtasksCount)")
                        .font(Theme.Typography.numeric(11))
                }
                .foregroundColor(allSubtasksDone && !isDone ? Theme.Colors.success : Theme.Colors.textMuted)
            }

            if showNotes && !task.notes.isEmpty {
                Text(task.notes)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private func toggleDone() {
        guard !completing, !isDeleting else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastToggleTime) >= 0.4 else { return }
        lastToggleTime = now
        let next = !task.isDone
        next ? Haptics.success() : Haptics.selection()
        if reduceMotion || KeyboardObserver.shared.isKeyboardVisible || !next {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                modelContext.setCompleted(task, next)
            }
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            completing = true
            checkboxScale = 1.14
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard task.modelContext != nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                checkboxScale = 1
                modelContext.setCompleted(task, true)
                completing = false
            }
        }
    }

    // MARK: - Drag Preview

    private var dragPreview: some View {
        HStack(spacing: 8) {
            if let tag = task.tags.first {
                Circle()
                    .fill(tag.color)
                    .frame(width: 6, height: 6)
            }
            Text(task.title.isEmpty ? "Задача" : task.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Colors.hairline, lineWidth: 1)
        )
    }
}

/// Context menu shared by the iPhone and Mac task rows.
struct TaskContextMenu: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    let allTags: [Tag]
    let onEdit: (TaskItem) -> Void
    let onToggleDone: () -> Void

    var body: some View {
        Button {
            onEdit(task)
        } label: {
            Label("Открыть", systemImage: "square.and.pencil")
        }

        Button {
            onToggleDone()
        } label: {
            Label(
                task.isDone ? "Вернуть в работу" : "Выполнено",
                systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark.circle"
            )
        }

        Button {
            Haptics.selection()
            modelContext.toggleHighPriority(task)
        } label: {
            Label(
                task.isHighPriorityToday ? "Снять приоритет" : "Высокий приоритет",
                systemImage: task.isHighPriorityToday ? "flame.fill" : "flame"
            )
        }

        if !allTags.isEmpty {
            Menu {
                ForEach(allTags) { tag in
                    let isAssigned = task.tags.contains { $0.id == tag.id }
                    Button {
                        Haptics.selection()
                        modelContext.assign(task, to: isAssigned ? nil : tag)
                    } label: {
                        if isAssigned {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                Label("Категория", systemImage: "circle.grid.2x2")
            }
        }

        Divider()

        Button(role: .destructive) {
            Haptics.warning()
            withAnimation {
                TaskDeletionManager.shared.requestDelete(task, context: modelContext)
            }
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

#if os(iOS)
/// Rejects vertical drags before recognition, so the parent list keeps scrolling.
private struct HorizontalTaskSwipe: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> TaskSwipePanRecognizer {
        let pan = TaskSwipePanRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: TaskSwipePanRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.horizontalTranslation)
        case .ended:
            onEnded(recognizer.horizontalTranslation)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view?.window)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer
        }
    }
}
/// Keeps the full touch displacement, including the movement that first starts recognition.
private final class TaskSwipePanRecognizer: UIPanGestureRecognizer {
    private var initialPoint = CGPoint.zero
    private var currentPoint = CGPoint.zero
    var horizontalTranslation: CGFloat { currentPoint.x - initialPoint.x }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            initialPoint = touch.location(in: nil)
            currentPoint = initialPoint
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { currentPoint = touch.location(in: nil) }
        super.touchesMoved(touches, with: event)
    }

}
#endif
