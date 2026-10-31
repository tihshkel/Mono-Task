import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @AccessibilityFocusState private var headingFocused: Bool
    @ScaledMetric(relativeTo: .title) private var headingSize = 30.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 15.0

    private let titles = [
        "Всё по своим папкам.", "Поймайте мысль.", "Готово. И стало легче.", "Главное — на первом плане.",
    ]
    private var descriptions: [String] {
        [
            "Нажмите «Новая папка», выберите цвет и значок. Работа, учёба и личное больше не смешиваются.",
            captureDescription,
            "Нажмите кружок слева от задачи, чтобы выполнить её. Нажмите на название, чтобы изменить детали.",
            "В меню задачи выберите «Высокий приоритет». Самые важные дела будут под рукой в разделе «Приоритет».",
        ]
    }
    private var captureDescription: String {
        #if os(macOS)
        "Нажмите + или ⌘N, напишите задачу и нажмите «Добавить». Внутри папки она сразу попадёт куда нужно."
        #else
        "Нажмите +, напишите задачу и нажмите «Добавить». Внутри папки она сразу попадёт куда нужно."
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 24) {
                        OnboardingMotion(page: page)
                            .frame(height: min(340, max(220, geometry.size.height * 0.43)))
                        VStack(spacing: 14) {
                            Text(titles[page])
                                .font(.system(size: headingSize, weight: .semibold)).tracking(-1)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($headingFocused)
                                .accessibilityIdentifier("onboarding-heading")
                            Text(descriptions[page])
                                .font(.system(size: bodySize)).lineSpacing(5)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 400)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 190))
                    .id(page)
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16)))
                }
                .scrollIndicators(.hidden)
                footer
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .tint(Theme.Colors.accent)
        .task(id: page) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            headingFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image("BrandLogo").resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text("MonoTask").font(.system(size: 18, weight: .semibold)).tracking(-0.5)
            Spacer()
            Text("\(page + 1) / 4")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.textMuted)
                .accessibilityLabel("Шаг \(page + 1) из 4")
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 28).padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index == page ? Theme.Colors.accent : Theme.Colors.fillStrong)
                        .frame(width: index == page ? 26 : 6, height: 6)
                }
            }.accessibilityHidden(true)
            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        changePage(to: page - 1)
                    } label: {
                        Image(systemName: "arrow.left").font(.system(size: 16, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .background(Theme.Colors.fill, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(SoftPressStyle()).accessibilityLabel("Назад")
                    .accessibilityIdentifier("onboarding-back")
                }
                Button {
                    if page < 3 {
                        changePage(to: page + 1)
                    } else {
                        Haptics.selection()
                        onFinish()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(page == 3 ? "Начать" : "Далее").font(.system(size: bodySize, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16).frame(minHeight: 52)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(SoftPressStyle()).accessibilityIdentifier("onboarding-next")
            }
        }
        .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 24)
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
    }

    private func changePage(to newPage: Int) {
        Haptics.selection()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.35)) { page = newPage }
    }
}

private struct OnboardingMotion: View {
    let page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle().fill(Theme.Colors.blueViolet.opacity(0.06)).frame(width: 270, height: 270)
                    .scaleEffect(phase > 1 ? 1.08 : 0.94)
                Circle().strokeBorder(Theme.Colors.accent.opacity(0.09), lineWidth: 1)
                    .frame(width: 294, height: 294)
                Group {
                    switch page {
                    case 0: folders
                    case 1: capture
                    case 2: completion
                    default: priority
                    }
                }
            }
            .frame(width: 340, height: 310)
            .scaleEffect(min(geometry.size.width / 340, geometry.size.height / 310))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
        .task(id: "\(page)-\(reduceMotion)-\(scenePhase == .active)") {
            guard !reduceMotion, scenePhase == .active else {
                phase = 3
                return
            }
            do {
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.4)) { phase = 0 }
                    try await Task.sleep(for: .milliseconds(800))
                    for nextPhase in 1...3 {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { phase = nextPhase }
                        try await Task.sleep(for: .milliseconds(1100))
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch {}
        }
    }

    private var folders: some View {
        ZStack {
            folder("Работа", color: Theme.Colors.blueViolet, icon: "briefcase.fill")
                .rotationEffect(.degrees(phase > 0 ? -8 : -16))
                .offset(x: -77, y: phase > 0 ? -45 : 0)
            folder("Личное", color: Theme.Colors.exuberantOrange, icon: "heart.fill")
                .rotationEffect(.degrees(phase > 0 ? 9 : 17))
                .offset(x: 78, y: phase > 0 ? -45 : 10)
            VStack(spacing: 8) {
                demoRow("Подготовить проект", icon: "circle")
                demoRow("Записать идею", icon: "circle")
            }
            .padding(12).background(Theme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 20))
            .frame(width: 270)
            .shadow(color: .black.opacity(0.07), radius: 20, y: 10)
            .opacity(phase >= 2 ? 1 : 0).offset(y: phase >= 2 ? 88 : 106)
            chip("Новая папка", icon: "plus", highlighted: phase == 1)
                .offset(y: -121)
            tapHint.offset(x: 69, y: -102).opacity(phase == 1 ? 1 : 0)
        }
    }

    private var capture: some View {
        ZStack {
            folder("Личное", color: Theme.Colors.exuberantOrange, icon: "heart.fill")
                .scaleEffect(0.8).rotationEffect(.degrees(-12)).offset(x: -92, y: -56)
            Image(systemName: "plus").font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.Colors.onAccent).frame(width: 52, height: 52)
                .background(Theme.Colors.accent, in: Circle())
                .scaleEffect(phase == 1 ? 0.88 : 1).offset(x: 108, y: -100)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(phase == 3 ? "Задача добавлена" : "Новое дело").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: phase == 3 ? "checkmark.circle.fill" : "xmark")
                        .foregroundStyle(Theme.Colors.accent)
                }
                HStack(spacing: 2) {
                    Text(phase >= 2 ? "Записать идею" : "Что нужно сделать?")
                        .foregroundStyle(phase >= 2 ? Theme.Colors.textPrimary : Theme.Colors.textMuted)
                    if phase == 2 { Capsule().fill(Theme.Colors.accent).frame(width: 2, height: 20) }
                    Spacer(minLength: 0)
                }.font(.system(size: 18))
                HStack {
                    chip("Личное", icon: "heart.fill", highlighted: false)
                    Spacer()
                    Text(phase == 3 ? "Готово" : "Добавить").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .background(Theme.Colors.accent, in: Capsule())
                        .scaleEffect(phase == 3 ? 0.95 : 1)
                }
            }
            .padding(22).frame(width: 300)
            .foregroundStyle(Theme.Colors.textPrimary)
            .background(Theme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.08), radius: 22, y: 12)
            .scaleEffect(phase > 0 ? 1 : 0.88).opacity(phase > 0 ? 1 : 0)
            .offset(y: phase > 0 ? 35 : 55)
            tapHint.offset(x: 125, y: -78).opacity(phase == 1 ? 1 : 0)
        }
    }

    private var completion: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle().stroke(Theme.Colors.fillStrong, lineWidth: 8)
                Circle().trim(from: 0, to: phase >= 2 ? 1 : 0.66)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: phase >= 2 ? "checkmark" : "sparkles")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.Colors.accent)
                    Text(phase >= 2 ? "3 из 3" : "2 из 3")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }.frame(width: 108, height: 108).scaleEffect(phase == 2 ? 1.08 : 1)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TaskCheckbox(isDone: phase >= 2, size: 23)
                        .scaleEffect(phase == 2 ? 1.16 : 1)
                    Text("Записать идею").strikethrough(phase >= 2)
                        .foregroundStyle(phase >= 2 ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(Theme.Colors.textMuted)
                }
                .font(.system(size: 15)).padding(18)
                .background(Theme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .leading) {
                    tapHint.offset(x: 13, y: 24).opacity(phase == 1 ? 1 : 0)
                }
                Text(phase >= 2 ? "Ещё одна маленькая победа" : "Одно касание — и готово")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.accent)
            }.frame(width: 284)
        }
    }

    private var priority: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                chip("Все задачи", icon: "tray", highlighted: phase < 2)
                chip("Приоритет", icon: "flame", highlighted: phase >= 2)
            }
            VStack(spacing: 14) {
                demoRow("Подготовить проект", icon: phase >= 2 ? "flame.fill" : "circle")
                if phase < 2 {
                    HStack {
                        Image(systemName: "flame").foregroundStyle(Theme.Colors.priority)
                        Text("Высокий приоритет")
                        Spacer()
                    }
                    .font(.system(size: 13)).padding(12)
                    .background(Theme.Colors.fill, in: RoundedRectangle(cornerRadius: 12))
                    .opacity(phase == 1 ? 1 : 0)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Важное не потеряется")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.accent)
                    .padding(.vertical, 12)
                }
            }
            .padding(18).frame(width: 300)
            .background(Theme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
            .overlay(alignment: .trailing) {
                tapHint.offset(x: -3, y: -17).opacity(phase == 0 ? 1 : 0)
            }
            Image("BrandMascot").resizable().scaledToFit().frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .rotationEffect(.degrees(phase >= 2 ? -8 : 6))
                .offset(y: phase >= 2 ? -2 : 4)
        }
    }

    private func folder(_ title: String, color: Color, icon: String) -> some View {
        VStack(spacing: 5) {
            FolderArtwork(tint: color, icon: icon, count: 2).frame(width: 148, height: 125)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func demoRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(icon == "flame.fill" ? Theme.Colors.priority : Theme.Colors.accent)
            Text(title).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(Theme.Colors.textMuted)
        }.font(.system(size: 13)).padding(.vertical, 7)
    }

    private func chip(_ title: String, icon: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .foregroundStyle(highlighted ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
        .background(highlighted ? Theme.Colors.accent : Theme.Colors.fill, in: Capsule())
    }

    private var tapHint: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Theme.Colors.textPrimary)
            .shadow(color: Theme.Colors.background, radius: 2)
            .scaleEffect(phase == 1 ? 0.92 : 1)
    }
}

#if DEBUG
struct OnboardingPreviewRoot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completed = false

    var body: some View {
        Group {
            if completed {
                AuthView()
            } else {
                OnboardingView { completed = true }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: completed)
    }
}
#endif
