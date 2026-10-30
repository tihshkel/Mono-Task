import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = false
    @State private var showsPassword = false
    @State private var appeared = false
    @Namespace private var modeSelection
    @FocusState private var focusedField: Field?
    private enum Field { case email, password }
    private var compact: Bool { focusedField != nil }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !auth.isBusy
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: compact ? 20 : 26) {
                    brand
                    if !compact { illustration.transition(.opacity.combined(with: .scale(scale: 0.94))) }
                    introduction
                    modePicker
                    form
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.vertical, compact ? 20 : 28)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.background)
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: compact)
        .onAppear {
            #if DEBUG
            creatingAccount = ProcessInfo.processInfo.arguments.contains("--auth-register")
            #endif
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) { appeared = true }
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 16, weight: .light))
            Text("MonoTask").font(.system(size: 17, weight: .semibold)).tracking(-0.5)
            Spacer()
            Image(systemName: "checkmark.seal").font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.Colors.accent.opacity(0.65))
        }.foregroundStyle(Theme.Colors.textPrimary)
    }

    private var illustration: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("BrandMascot").resizable().interpolation(.high).scaledToFit()
                .frame(width: 138, height: 138)
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                Text("Одно дело за раз").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.Colors.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            .offset(x: 49, y: 7)
        }
        .frame(height: 138)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(spacing: 9) {
            Text(creatingAccount ? "Начнём с главного." : "С возвращением.")
                .font(.system(size: compact ? 27 : 30, weight: .semibold)).tracking(-0.9)
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.opacity)
                .accessibilityIdentifier("auth-heading")
            Text(
                creatingAccount
                    ? "Создайте место для своих планов.\nОстальное сложится по порядку."
                    : "Ваши планы, идеи и маленькие победы.\nВсё на своих местах."
            )
            .font(.system(size: 13)).foregroundStyle(Theme.Colors.textSecondary)
            .lineSpacing(4).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("Вход", creating: false)
            modeButton("Регистрация", creating: true)
        }
        .padding(4).background(Theme.Colors.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
    }

    private func modeButton(_ title: String, creating: Bool) -> some View {
        Button {
            guard creatingAccount != creating else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88)) {
                creatingAccount = creating
                auth.errorMessage = nil
                auth.infoMessage = nil
            }
        } label: {
            Text(title).font(.system(size: 13, weight: creatingAccount == creating ? .semibold : .medium))
                .foregroundStyle(creatingAccount == creating ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background {
                    if creatingAccount == creating {
                        RoundedRectangle(cornerRadius: 11).fill(Theme.Colors.surfaceElevated)
                            .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "auth-mode", in: modeSelection)
                    }
                }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(auth.isBusy)
        .accessibilityAddTraits(creatingAccount == creating ? .isSelected : [])
        .accessibilityIdentifier(creating ? "auth-register-mode" : "auth-login-mode")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("Электронная почта")
                HStack(spacing: 11) {
                    Image(systemName: "envelope").font(.system(size: 15)).foregroundStyle(Theme.Colors.textMuted)
                    TextField(
                        "", text: $email,
                        prompt: Text(verbatim: "name@example.com").foregroundStyle(Theme.Colors.textMuted)
                    )
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled().focused($focusedField, equals: .email)
                    .submitLabel(.next).onSubmit { focusedField = .password }
                    .accessibilityLabel("Электронная почта").accessibilityIdentifier("auth-email")
                }.modifier(AuthFieldStyle(focused: focusedField == .email))
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    fieldLabel("Пароль")
                    Spacer()
                    if creatingAccount {
                        Text("Не менее 6 символов").font(.system(size: 10)).foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                HStack(spacing: 11) {
                    Image(systemName: "lock").font(.system(size: 15)).foregroundStyle(Theme.Colors.textMuted)
                    Group {
                        if showsPassword {
                            TextField("Ваш пароль", text: $password)
                        } else {
                            SecureField("Ваш пароль", text: $password)
                        }
                    }
                    .textContentType(creatingAccount ? .newPassword : .password)
                    .focused($focusedField, equals: .password).submitLabel(.go).onSubmit(submit)
                    .accessibilityLabel("Пароль").accessibilityIdentifier("auth-password")
                    Button {
                        showsPassword.toggle(); focusedField = .password
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye").font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary).frame(width: 30, height: 40)
                    }.buttonStyle(.plain).accessibilityLabel(showsPassword ? "Скрыть пароль" : "Показать пароль")
                }.modifier(AuthFieldStyle(focused: focusedField == .password))
            }
            if let error = auth.errorMessage { message(error, error: true) }
            if let info = auth.infoMessage { message(info, error: false) }
            Button(action: submit) {
                HStack(spacing: 9) {
                    Spacer()
                    if auth.isBusy { ProgressView().controlSize(.small).tint(Theme.Colors.onAccent) }
                    Text(creatingAccount ? "Создать пространство" : "Войти в пространство").font(
                        .system(size: 14, weight: .semibold))
                    if !auth.isBusy { Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
                    Spacer()
                }
                .frame(height: 52)
                .foregroundStyle(canSubmit || auth.isBusy ? Theme.Colors.onAccent : Theme.Colors.textMuted)
                .background(
                    canSubmit || auth.isBusy ? Theme.Colors.accent : Theme.Colors.fillStrong.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(SoftPressStyle()).disabled(!canSubmit).accessibilityIdentifier("auth-submit")
                .padding(.top, 4)
        }
        .disabled(auth.isBusy)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: auth.errorMessage)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: auth.infoMessage)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "icloud").font(.system(size: 12)).padding(.top, 1)
            Text("Ваше пространство синхронизируется\nмежду iPhone и Mac.")
                .font(.system(size: 11)).lineSpacing(3).multilineTextAlignment(.center)
        }.foregroundStyle(Theme.Colors.textMuted).frame(maxWidth: .infinity)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
    }
    private func message(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: error ? "exclamationmark.circle" : "envelope.badge").font(.system(size: 13))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(error ? Theme.Colors.danger : Theme.Colors.accent)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (error ? Theme.Colors.danger : Theme.Colors.accent).opacity(0.07), in: RoundedRectangle(cornerRadius: 12)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(error ? "Ошибка: \(text)" : text)
    }

    private func submit() {
        guard canSubmit else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), let domain = trimmed.split(separator: "@").last, domain.contains(".") else {
            auth.errorMessage = "Проверьте адрес электронной почты."
            focusedField = .email
            return
        }
        if creatingAccount && password.count < 6 {
            auth.errorMessage = "Для пароля нужно не менее 6 символов."
            focusedField = .password
            return
        }
        focusedField = nil
        Task {
            if creatingAccount {
                await auth.signUp(email: trimmed, password: password)
            } else {
                await auth.signIn(email: trimmed, password: password)
            }
        }
    }
}

private struct AuthFieldStyle: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.Colors.textPrimary)
            .padding(.leading, 15).padding(.trailing, 10).frame(height: 53)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    focused ? Theme.Colors.accent.opacity(0.65) : Theme.Colors.borderSubtle,
                    lineWidth: focused ? 1 : 0.6))
    }
}
