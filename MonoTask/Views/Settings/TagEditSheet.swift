import SwiftUI
import SwiftData

struct TagEditSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    var tagToEdit: Tag?

    @State private var name: String = ""
    @State private var selectedIcon = "square.stack.3d.up.fill"
    @State private var selectedColorHex: String = Theme.Colors.tagColors[0]
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var confirmingDelete = false

    private var isEditing: Bool {
        tagToEdit != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.callout)
                .foregroundColor(Theme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                EyebrowLabel(text: isEditing ? "Категория" : "Новая категория")

                Spacer()

                Button {
                    save()
                    dismiss()
                } label: {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canSave ? Theme.Colors.onInverse : Theme.Colors.textMuted)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(canSave ? Theme.Colors.inverse : Theme.Colors.fillStrong)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {

                    FolderArtwork(tint: Theme.Colors.tagColor(selectedColorHex), icon: selectedIcon)
                        .frame(width: 160, height: 125).frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.Colors.tagColor(selectedColorHex))
                            .frame(width: 12, height: 12)
                        TextField("Название", text: $name)
                            .textFieldStyle(.plain)
                            .font(Theme.Typography.heading(24))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel(text: "Цвет")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 12)], spacing: 12) {
                            ForEach(Theme.Colors.tagColors, id: \.self) { hex in
                                let isSelected = selectedColorHex == hex
                                Button {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : Theme.Motion.quick) { selectedColorHex = hex }
                                } label: {
                                    Circle()
                                        .fill(Theme.Colors.tagColor(hex))
                                        .frame(width: 26, height: 26)
                                        .padding(3)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isSelected ? Theme.Colors.textPrimary : Color.clear, lineWidth: 2)
                                        )
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        EyebrowLabel(text: "Значок папки")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 10) {
                            ForEach(
                                [
                                    "square.stack.3d.up.fill", "briefcase.fill", "graduationcap.fill", "house.fill",
                                    "heart.fill", "paintpalette.fill", "airplane", "book.closed.fill", "leaf.fill",
                                    "sparkles", "laptopcomputer", "camera.fill",
                                ], id: \.self
                            ) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon).font(.system(size: 19))
                                        .foregroundStyle(
                                            selectedIcon == icon ? Theme.Colors.accent : Theme.Colors.textSecondary
                                        )
                                        .frame(width: 40, height: 40)
                                        .background(
                                            selectedIcon == icon
                                                ? Theme.Colors.accent.opacity(0.12) : Theme.Colors.fill,
                                            in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel(icon)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel(text: "Дни фокуса")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                            ForEach(Weekday.orderedFromMonday) { day in
                                let isActive = selectedWeekdays.contains(day)
                                Button {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : Theme.Motion.quick) { toggleWeekday(day) }
                                } label: {
                                    Text(day.shortName.uppercased())
                                        .font(Theme.Typography.numeric(12, weight: isActive ? .bold : .regular))
                                        .foregroundColor(isActive ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(
                                            isActive ? Theme.Colors.tagColor(selectedColorHex) : Theme.Colors.surface
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(
                                                    isActive ? Color.clear : Theme.Colors.hairline, lineWidth: 1)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("В эти дни задачи категории попадают в «Фокус дня».")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textMuted)
                    }
                    if tagToEdit != nil {
                        Button("Удалить категорию", role: .destructive) { confirmingDelete = true }
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .monoScrollEdge()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .tint(Theme.Colors.accent)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.background)
        .presentationCornerRadius(Theme.Radius.sheet)
        #else
        .frame(minWidth: 440, idealWidth: 480, minHeight: 600, idealHeight: 690)
        #endif
        .preferredColorScheme(Theme.colorScheme)
        .confirmationDialog("Удалить категорию?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let tag = tagToEdit { modelContext.deleteWithSync(tag); modelContext.saveAndSync(); dismiss() }
            }
        } message: {
            Text("Задачи останутся без этой категории.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTaskEditor)) { _ in dismiss() }
        .onAppear {
            if let tag = tagToEdit {
                name = tag.name
                selectedIcon = tag.folderIconName

                selectedColorHex = Theme.Colors.normalizedTagHex(tag.colorHex)
                selectedWeekdays = Set(tag.scheduledDays)
            }
        }
    }

    private func toggleWeekday(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Keep a stable Monday-first order instead of Set iteration order
        let orderedDays = Weekday.orderedFromMonday.filter { selectedWeekdays.contains($0) }

        if let tag = tagToEdit {
            tag.name = trimmedName
            tag.colorHex = selectedColorHex
            tag.iconName = selectedIcon
            tag.scheduledDays = orderedDays
            tag.touch()
        } else {
            let newTag = Tag(
                name: trimmedName,
                colorHex: selectedColorHex,
                iconName: selectedIcon,
                scheduledDays: orderedDays,
                // New contexts go to the end instead of colliding with the first one at 0
                sortOrder: (tags.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(newTag)
        }

        modelContext.saveAndSync(delaySeconds: 0.3)
    }
}
