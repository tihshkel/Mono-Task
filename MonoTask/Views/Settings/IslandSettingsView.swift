#if os(macOS)
import SwiftUI

struct IslandSettingsView: View {
    @State private var island = IslandController.shared
    @State private var section = 0
    private var accent: Color { IslandPalette.accent(island.preferences) }

    var body: some View {
        @Bindable var island = island
        VStack(alignment: .leading, spacing: 22) {
            preview
            GroupCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Включить MonoTask Island", isOn: $island.preferences.enabled)
                        .font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("island-enabled")
                    Text("Задачи и фокус рядом с камерой MacBook. На экране без выреза — отдельная капсула.")
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Picker("Раздел настроек", selection: $section) {
                Text("Оформление").tag(0)
                Text("Поведение").tag(1)
                Text("Фокус").tag(2)
            }.pickerStyle(.segmented).accessibilityIdentifier("island-settings-sections")

            if section == 0 {
                appearanceSettings
                GroupCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 17) {
                        SharedSectionTitle(title: "Движение")
                        Toggle("Плавные анимации", isOn: $island.preferences.animations)
                            .accessibilityIdentifier("island-animations")
                        Picker("Характер", selection: $island.preferences.motion) {
                            ForEach(IslandMotion.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).disabled(!island.preferences.animations)
                        Toggle("Цветной отклик при выполнении", isOn: $island.preferences.celebrateCompletion)
                            .disabled(!island.preferences.animations)
                        Text("Системная настройка «Уменьшение движения» имеет приоритет.")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            } else if section == 1 {
                behaviorSettings
            } else {
                focusSettings
            }
            Button("Вернуть стандартные настройки") {
                let enabled = island.preferences.enabled
                island.preferences = IslandPreferences()
                island.preferences.enabled = enabled
            }
            .font(.system(size: 12, weight: .medium)).buttonStyle(.plain).foregroundStyle(Theme.Colors.textSecondary)
            Text("Настройки сохраняются на этом Mac отдельно для каждого аккаунта.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textMuted)
        }
        .toggleStyle(.switch).controlSize(.small).foregroundStyle(Theme.Colors.textPrimary)
    }

    private var preview: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ВАШ РИТМ. ВАШ ISLAND.").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Маленький центр внимания.").font(.system(size: 24, weight: .semibold)).tracking(-0.7)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                island.preview()
            } label: {
                VStack(spacing: 18) {
                    HStack {
                        Text("MONO").font(.system(size: 8, weight: .semibold)).tracking(2)
                        Spacer()
                        Capsule().fill(.black).frame(width: 115, height: 19)
                        Spacer()
                        HStack(spacing: 3) {
                            Circle().fill(accent)
                            Circle().fill(Theme.Colors.exuberantOrange)
                            Circle().fill(Theme.Colors.blueViolet)
                        }.frame(width: 17, height: 3)
                    }.foregroundStyle(.white.opacity(0.45))
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(accent, lineWidth: 1.4).frame(
                            width: 23, height: 23)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(island.activeTask?.title ?? "Одно дело за раз").font(
                                .system(size: 15, weight: .medium)
                            )
                            .foregroundStyle(Theme.Colors.cloudDancer).lineLimit(1)
                            Text(island.activeTask?.tags.first?.name ?? "Место для главного")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer(minLength: 0)
                    }
                    if island.preferences.showTimer {
                        HStack(spacing: 11) {
                            Image(systemName: "timer").font(.system(size: 18)).foregroundStyle(accent)
                            Text("Фокус").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(island.timerText).font(.system(size: 25, weight: .medium, design: .rounded))
                                .monospacedDigit().foregroundStyle(accent)
                            Image(systemName: island.clock.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 11)).foregroundStyle(accent)
                                .frame(width: 28, height: 28).background(accent.opacity(0.12), in: Circle())
                        }
                        .padding(13).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                    }
                    HStack {
                        Text(island.preferences.showProgress ? "\(island.completedToday) готово сегодня" : "mono")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.48))
                        Spacer()
                        Image(systemName: "pin.fill")
                        Image(systemName: "slider.horizontal.3")
                        Image(systemName: "plus")
                    }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(21).frame(maxWidth: island.preferences.panelSize == .compact ? 340 : 385)
                .background(IslandBackdrop(preferences: island.preferences, running: island.clock.isRunning))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 27, bottomTrailingRadius: 27))
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 27, bottomTrailingRadius: 27)
                        .strokeBorder(
                            accent.opacity(island.preferences.surfaceStyle == .quiet ? 0.08 : 0.22), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.2), radius: 14, y: 10)
            }
            .buttonStyle(.plain).accessibilityLabel("Показать островок с выбранным оформлением")
            .accessibilityIdentifier("island-settings-preview")
            .animation(island.animation, value: island.preferences)
            Button {
                island.preview()
            } label: {
                Label("Показать на экране", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.accent)
            }.buttonStyle(.plain).disabled(!island.preferences.enabled)
        }.padding(22).frame(maxWidth: .infinity)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 25))
    }

    private var appearanceSettings: some View {
        @Bindable var island = island
        return GroupCard(padding: 18) {
            VStack(alignment: .leading, spacing: 20) {
                SharedSectionTitle(title: "Начните с настроения")
                HStack(spacing: 9) {
                    preset("Фокус", symbol: "scope", color: Theme.Colors.sunGlare, index: 0)
                    preset("Тише", symbol: "moon", color: Theme.Colors.blueViolet, index: 1)
                    preset("Ярче", symbol: "sparkles", color: Theme.Colors.exuberantOrange, index: 2)
                }
                Hairline()
                Text("Акцент").font(.system(size: 12, weight: .medium))
                HStack(spacing: 12) {
                    ForEach(IslandAccent.allCases, id: \.self) { value in
                        Button {
                            island.preferences.accent = value
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(swatch(value)).frame(width: 20, height: 20)
                                    .overlay {
                                        if island.preferences.accent == value {
                                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(value == .violet ? .white : Theme.Colors.darkestHour)
                                        }
                                    }
                                Text(value.title).font(.system(size: 11))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(
                                island.preferences.accent == value ? Theme.Colors.fillStrong : Theme.Colors.fill,
                                in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(
                            island.preferences.accent == value ? .isSelected : [])
                    }
                }
                Picker("Поверхность", selection: $island.preferences.surfaceStyle) {
                    ForEach(IslandSurfaceStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("island-style")
                Picker("Ширина", selection: $island.preferences.panelSize) {
                    ForEach(IslandPanelSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("В свёрнутом виде", selection: $island.preferences.compactContent) {
                    ForEach(IslandCompactContent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private var behaviorSettings: some View {
        @Bindable var island = island
        return GroupCard(padding: 18) {
            VStack(alignment: .leading, spacing: 20) {
                SharedSectionTitle(title: "Пусть ведёт себя по-вашему")
                Toggle("Раскрывать при наведении", isOn: $island.preferences.expandOnHover)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Задержка сворачивания").font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.2f с", island.preferences.collapseDelay))
                            .font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(
                                Theme.Colors.accent)
                    }
                    Slider(value: $island.preferences.collapseDelay, in: 0.1...1.5, step: 0.05)
                        .accessibilityLabel("Задержка сворачивания")
                }
                Hairline()
                Picker("При нажатии на капсулу", selection: $island.preferences.clickAction) {
                    Text("Раскрыть панель").tag(IslandClickAction.expand)
                    Text("Запустить / приостановить таймер").tag(IslandClickAction.timer)
                    Text("Открыть MonoTask").tag(IslandClickAction.openApp)
                }
                Picker("При перетаскивании задачи", selection: $island.preferences.dropAction) {
                    Text("Сделать текущей").tag(IslandDropAction.focus)
                    Text("Добавить в очередь").tag(IslandDropAction.enqueue)
                }
                Label("Булавка в островке оставляет панель раскрытой. Escape сворачивает её.", systemImage: "pin")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var focusSettings: some View {
        @Bindable var island = island
        return GroupCard(padding: 18) {
            VStack(alignment: .leading, spacing: 20) {
                SharedSectionTitle(title: "Всё для вашего фокуса")
                Toggle("Показывать таймер", isOn: $island.preferences.showTimer)
                Stepper(
                    "Сессия: \(island.preferences.focusMinutes) мин", value: $island.preferences.focusMinutes,
                    in: 1...120)
                HStack(spacing: 8) {
                    ForEach([15, 25, 45, 60], id: \.self) { value in
                        Button("\(value) мин") { island.preferences.focusMinutes = value }
                            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .foregroundStyle(
                                island.preferences.focusMinutes == value
                                    ? Theme.Colors.darkestHour : Theme.Colors.textSecondary
                            )
                            .background(
                                island.preferences.focusMinutes == value ? Theme.Colors.sunGlare : Theme.Colors.fill,
                                in: Capsule())
                    }
                }
                Text("Новая длительность применяется к следующей сессии.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                Hairline()
                Toggle("Срок текущей задачи", isOn: $island.preferences.showDeadline)
                Toggle("Прогресс дня", isOn: $island.preferences.showProgress)
                Toggle("Раскрывать в срок напоминания", isOn: $island.preferences.reminders)
                Text(
                    "Напоминания островка работают, пока MonoTask запущен. Системные уведомления настраиваются отдельно."
                )
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func swatch(_ value: IslandAccent) -> Color {
        switch value {
        case .lime: Theme.Colors.sunGlare;
        case .orange: Theme.Colors.exuberantOrange;
        case .violet: Theme.Colors.blueViolet
        }
    }

    private func preset(_ title: String, symbol: String, color: Color, index: Int) -> some View {
        Button {
            switch index {
            case 1:
                island.preferences.accent = .violet
                island.preferences.surfaceStyle = .quiet
                island.preferences.motion = .calm
            case 2:
                island.preferences.accent = .orange
                island.preferences.surfaceStyle = .spectrum
                island.preferences.motion = .playful
            default:
                island.preferences.accent = .lime
                island.preferences.surfaceStyle = .glow
                island.preferences.motion = .fluid
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .medium))
            }.frame(maxWidth: .infinity, minHeight: 38).background(
                Theme.Colors.fill, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
#endif
