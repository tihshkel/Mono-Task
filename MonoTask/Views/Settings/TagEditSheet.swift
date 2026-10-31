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

    private static let folderIcons: [(symbol: String, name: String)] = [
        ("square.stack.3d.up.fill", "Проекты"),
        ("briefcase.fill", "Работа"),
        ("graduationcap.fill", "Учёба"),
        ("house.fill", "Дом"),
        ("heart.fill", "Личное"),
        ("paintpalette.fill", "Творчество"),
        ("airplane", "Путешествия"),
        ("book.closed.fill", "Книги"),
        ("leaf.fill", "Природа"),
        ("sparkles", "Вдохновение"),
        ("laptopcomputer", "Компьютер"),
        ("camera.fill", "Фото"),
        ("folder.fill", "Папка"),
        ("tray.fill", "Входящие"),
        ("checklist", "Список дел"),
        ("calendar", "Календарь"),
        ("target", "Цели"),
        ("star.fill", "Избранное"),
        ("flag.fill", "Важное"),
        ("bolt.fill", "Энергия"),
        ("lightbulb.fill", "Идеи"),
        ("pencil.and.ruler.fill", "Дизайн"),
        ("doc.text.fill", "Документы"),
        ("bookmark.fill", "Закладки"),
        ("globe", "Мир"),
        ("map.fill", "Карты"),
        ("location.fill", "Места"),
        ("car.fill", "Автомобиль"),
        ("bicycle", "Велосипед"),
        ("tram.fill", "Транспорт"),
        ("cup.and.saucer.fill", "Отдых"),
        ("fork.knife", "Еда"),
        ("cart.fill", "Покупки"),
        ("gift.fill", "Подарки"),
        ("creditcard.fill", "Финансы"),
        ("chart.bar.fill", "Аналитика"),
        ("banknote.fill", "Бюджет"),
        ("dumbbell.fill", "Спорт"),
        ("figure.run", "Бег"),
        ("cross.case.fill", "Здоровье"),
        ("pawprint.fill", "Питомцы"),
        ("music.note", "Музыка"),
        ("headphones", "Аудио"),
        ("gamecontroller.fill", "Игры"),
        ("film.fill", "Кино"),
        ("hammer.fill", "Ремонт"),
        ("wrench.and.screwdriver.fill", "Инструменты"),
        ("lock.fill", "Приватное"),
    ]

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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                            ForEach(Theme.Colors.tagColorOptions, id: \.hex) { option in
                                let hex = option.hex
                                let isSelected = selectedColorHex == hex
                                Button {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : Theme.Motion.quick) { selectedColorHex = hex }
                                } label: {
                                    Circle()
                                        .fill(Theme.Colors.tagColor(hex))
                                        .frame(width: 30, height: 30)
                                        .padding(4)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isSelected ? Theme.Colors.textPrimary : Color.clear, lineWidth: 2)
                                        )
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.name)
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                                .accessibilityIdentifier("folder-color-\(hex)")
                                .help(option.name)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        EyebrowLabel(text: "Значок папки")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                            ForEach(Self.folderIcons, id: \.symbol) { option in
                                let icon = option.symbol
                                Button {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : Theme.Motion.quick) { selectedIcon = icon }
                                } label: {
                                    Image(systemName: icon).font(.system(size: 19))
                                        .foregroundStyle(
                                            selectedIcon == icon ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                                        )
                                        .frame(width: 44, height: 44)
                                        .background(
                                            selectedIcon == icon
                                                ? Theme.Colors.tagColor(selectedColorHex).opacity(0.18)
                                                : Theme.Colors.fill,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12).strokeBorder(
                                                selectedIcon == icon ? Theme.Colors.tagColor(selectedColorHex) : .clear,
                                                lineWidth: 1.5)
                                        }
                                }
                                .buttonStyle(.plain).accessibilityLabel(option.name)
                                .accessibilityAddTraits(selectedIcon == icon ? [.isSelected] : [])
                                .accessibilityIdentifier("folder-icon-\(icon)")
                                .help(option.name)
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
