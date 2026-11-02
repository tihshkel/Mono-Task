import MonoInference
import SwiftData
import SwiftUI

struct MonoAIView: View {
    var initialFolderID: UUID?
    var initialText = ""
    var fromIsland = false
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @State private var model = MonoAIModelStore.shared
    @State private var speech = MonoAISpeech()
    @State private var keywords = MonoAIKeywordsStore.shared
    @State private var input = MonoAIInput()
    @State private var recordingStarted = Date.now
    @State private var understanding: MonoAIUnderstanding?
    @State private var selectedFolder: UUID?
    @State private var title = ""
    @State private var priority = false
    @State private var routingExplanation = ""
    @State private var routingNeedsConfirmation = false
    @State private var dueDate: Date?
    @State private var deadlineCandidate = Date.now
    @State private var deadlineCandidateEdited = false
    @State private var deadlineClarification: String?
    @State private var error: String?
    @State private var thinking = false
    @State private var saved = false
    @State private var settings = false
    @State private var generation: Task<Void, Never>?
    @State private var microphoneTask: Task<Void, Never>?
    @State private var inputTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var captureID = UUID()
    @State private var submitting = false
    @State private var appeared = false
    @State private var draftAccountID: UUID?
    @State private var modelNotice: String?
    @State private var replyAttempted = false
    @AppStorage("monotask_ai_voice") private var voice = false
    @FocusState private var inputFocused: Bool

    private var hasProposal: Bool { understanding != nil }

    private var needsClarification: Bool {
        understanding?.clarification != nil || routingNeedsConfirmation || deadlineClarification != nil
    }

    private var folders: [MonoAIFolder] {
        tags.map { MonoAIFolder(id: $0.id, name: $0.name, keywords: keywords.keywords(for: $0)) }
    }

    private var activity: MonoAIActivity {
        if saved { return .done }
        if speech.isListening { return .listening }
        if thinking { return .thinking }
        if speech.isPreparingVoice { return .thinking }
        if speech.isSpeaking { return .speaking }
        return .idle
    }

    private var status: String {
        if saved { return "Задача на своём месте" }
        if speech.isStarting { return "Подключаю микрофон…" }
        if speech.isFinalizing || submitting { return "Сохраняю последние слова…" }
        if speech.isListening { return "Слушаю вас" }
        if thinking { return "Нахожу место для вашей мысли…" }
        if speech.isSpeaking { return "Mono AI говорит" }
        if speech.isPreparingVoice { return "Готовлю голос…" }
        if input.voiceMode { return "Запись остановлена" }
        if needsClarification { return "Уточним одну деталь" }
        if hasProposal { return "Всё верно? Можно добавить" }
        return "Готов к вашим идеям"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    MonoAIOrb(activity: activity, level: speech.level)
                        .frame(width: hasProposal ? 130 : 205, height: hasProposal ? 130 : 205)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: hasProposal)
                    VStack(spacing: 10) {
                        Text(
                            !hasProposal && !thinking && !input.voiceMode && !submitting ? "Из мысли. В дело." : status
                        )
                        .font(.system(size: hasProposal ? 23 : 32, weight: .semibold)).tracking(-1)
                        .multilineTextAlignment(.center)
                        if !hasProposal {
                            Text(
                                input.voiceMode
                                    ? (speech.isListening
                                        ? "Говорите свободно. Ваши слова появятся ниже."
                                        : "Запись включается только по нажатию микрофона.")
                                    : thinking
                                        ? status
                                        : "Расскажите, что нужно сделать.\nMono AI предложит задачу и подходящую папку."
                            )
                            .font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center).lineSpacing(5)
                        }
                    }
                    if !model.isInstalled {
                        VStack(spacing: 14) {
                            Text(
                                "Задачи и голосовой ввод уже доступны. Gemma можно скачать отдельно для дополнительных подсказок папки."
                            )
                            .font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                            if model.isDownloading { ProgressView(value: model.progress) }
                            Button("Настроить Mono AI") { settings = true }.buttonStyle(SharedPrimaryStyle())
                        }.padding(22).frame(maxWidth: .infinity)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                    if input.voiceMode || !input.message.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(input.voiceMode ? "ВАШ ГОЛОС" : "ВЫ").font(Theme.Typography.eyebrow).foregroundStyle(
                                Theme.Colors.textMuted)
                            Text(
                                input.voiceMode
                                    ? (input.pending.isEmpty
                                        ? "Здесь появятся ваши слова…" : input.pending) : input.message
                            )
                            .font(.system(size: 18)).textSelection(.enabled)
                            .foregroundStyle(
                                input.voiceMode && input.pending.isEmpty
                                    ? Theme.Colors.textMuted : Theme.Colors.textPrimary
                            )
                            .accessibilityIdentifier("mono-ai-transcript")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(Theme.Colors.fill.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
                    }
                    if hasProposal { proposalCard }
                    if thinking {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Gemma уточняет папку. Черновик уже можно проверить.").font(.caption)
                            Spacer()
                            Button("Остановить") { cancelEnrichment() }
                        }.foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let modelNotice {
                        Text(modelNotice).font(.caption).foregroundStyle(Theme.Colors.textMuted)
                    }
                    if let message = error ?? speech.error {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(Theme.Colors.priority)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("mono-ai-error")
                        if hasProposal && replyAttempted && speech.error != nil {
                            HStack {
                                Button("Повторить озвучку") {
                                    cancelEnrichment(); speakReply()
                                }
                                Button("Системным голосом") {
                                    UserDefaults.standard.set("system", forKey: MonoAIVoice.engineKey)
                                    cancelEnrichment()
                                    speakReply()
                                }
                            }.font(.caption)
                        }
                    }
                    if !input.message.isEmpty && !submitting && !hasProposal && !input.voiceMode {
                        Button("Повторить обработку") { prepareTask(retry: true) }
                    }
                    if !hasProposal && input.message.isEmpty && !input.voiceMode {
                        Button("Например: закончить макет приложения") { input.draft = "Закончить макет приложения" }
                            .font(.system(size: 12)).foregroundStyle(Theme.Colors.textMuted).buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 28)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.Colors.background.ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Theme.Colors.blueViolet.opacity(0.055)).frame(width: 380, height: 380)
                        .blur(radius: 70).offset(x: 140, y: -170).allowsHitTesting(false)
                }
        }
        .foregroundStyle(Theme.Colors.textPrimary).tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        .sheet(isPresented: $settings) {
            NavigationStack {
                ScrollView { MonoAISettingsView().padding(24).frame(maxWidth: 640) }
                    .background(Theme.Colors.background).navigationTitle("Mono AI")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { settings = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 620)
            #endif
        }
        .onAppear {
            model.refreshAvailability()
            guard !appeared else { return }
            appeared = true
            input.draft = initialText; selectedFolder = initialFolderID
        }
        .onChange(of: speech.transcript) { _, transcript in
            guard input.voiceMode else { return }
            input.receive(transcript)
        }
        .onChange(of: speech.isListening) { _, listening in if listening { recordingStarted = .now } }
        .onChange(of: AuthManager.shared.userID) { _, _ in resetConversation() }
        .onChange(of: tags.map { $0.id.uuidString + ":" + $0.name }) { _, _ in
            cancelEnrichment()
            guard let selectedFolder, !tags.contains(where: { $0.id == selectedFolder }), hasProposal, !saved else {
                return
            }
            self.selectedFolder = nil
            routingNeedsConfirmation = true
            routingExplanation = "Папка изменилась или удалена. Выберите, куда сохранить задачу."
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && speech.isListening) {
                if input.voiceMode {
                    error = "Запись остановлена. Полученный текст сохранён — можно продолжить или отправить его."
                }
                stopWork()
            }
        }
        .onDisappear { stopWork() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                stopWork(); onClose()
            } label: {
                Image(systemName: "xmark").frame(width: 42, height: 42)
                    .background(Theme.Colors.fill, in: Circle())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Закрыть Mono AI")
            VStack(alignment: .leading, spacing: 3) {
                Text("Mono AI").font(.system(size: 18, weight: .semibold)).tracking(-0.5)
                    .accessibilityIdentifier("mono-ai-screen")
                Label("НА УСТРОЙСТВЕ", systemImage: "lock.fill").font(.system(size: 8, weight: .medium)).tracking(1.2)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            Spacer()
            Button {
                stopRecording(showKeyboard: true, showSettings: true)
            } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 42, height: 42)
            }.buttonStyle(.plain).accessibilityLabel("Настройки Mono AI")
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var composer: some View {
        VStack(spacing: 11) {
            if input.voiceMode { recordingControls }
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    if speech.isListening || speech.isStarting { stopRecording() } else { startRecording() }
                } label: {
                    Image(systemName: speech.isListening || speech.isStarting ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20)).frame(width: 48, height: 48)
                        .foregroundStyle(speech.isListening ? Theme.Colors.onAccent : Theme.Colors.accent)
                        .background(speech.isListening ? Theme.Colors.accent : Theme.Colors.fill, in: Circle())
                }.buttonStyle(.plain).disabled(submitting || speech.isFinalizing)
                    .accessibilityLabel(
                        speech.isListening || speech.isStarting ? "Остановить запись" : "Сказать задачу"
                    )
                    .accessibilityIdentifier("mono-ai-microphone")
                if input.voiceMode {
                    Button {
                        stopRecording(showKeyboard: true)
                    } label: {
                        Label("Клавиатура", systemImage: "keyboard").font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.plain).disabled(submitting || speech.isFinalizing)
                        .accessibilityIdentifier("mono-ai-keyboard")
                } else {
                    TextField("Напишите или скажите задачу", text: $input.draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15)).lineLimit(1...4)
                        .padding(.vertical, 14).focused($inputFocused).disabled(submitting)
                        .accessibilityIdentifier("mono-ai-input")
                }
                Button {
                    prepareTask()
                } label: {
                    Image(systemName: submitting ? "ellipsis" : "arrow.up")
                        .font(.system(size: 19, weight: .semibold)).frame(width: 48, height: 48)
                        .foregroundStyle(Theme.Colors.onAccent).background(Theme.Colors.accent, in: Circle())
                }.buttonStyle(.plain)
                    .disabled(
                        submitting || speech.isStarting || speech.isFinalizing
                            || (input.pending.isEmpty && !speech.isListening)
                    )
                    .accessibilityLabel(
                        submitting
                            ? "Завершаю распознавание" : needsClarification ? "Уточнить задачу" : "Подготовить задачу"
                    )
                    .accessibilityIdentifier("mono-ai-send")
            }.padding(8).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 32))
                .overlay(
                    RoundedRectangle(cornerRadius: 32).strokeBorder(
                        Theme.Colors.ruleStrong.opacity(0.6), lineWidth: 0.7))
            Text(
                speech.isListening
                    ? "Речь остаётся на устройстве · нажмите ↑, когда закончите"
                    : "Локальный разбор · проверьте папку и срок перед добавлением"
            )
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
        }.padding(.horizontal, 20).padding(.bottom, 18).padding(.top, 10)
            .frame(maxWidth: 660).frame(maxWidth: .infinity)
    }

    private var recordingControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(speech.isListening ? Color.red : Theme.Colors.textMuted).frame(width: 8, height: 8)
                Text(
                    speech.isStarting
                        ? "Подключение…"
                        : speech.isListening
                            ? "Идёт запись голоса"
                            : speech.isFinalizing ? "Распознаю последние слова…" : "Микрофон выключен"
                )
                .font(.system(size: 13, weight: .medium))
                Spacer()
                if speech.isListening {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let seconds = max(0, Int(timeline.date.timeIntervalSince(recordingStarted)))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit().font(.caption)
                    }
                }
            }.accessibilityIdentifier("mono-ai-recording-status")
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { index in
                    Capsule().fill(speech.isListening ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.3))
                        .frame(
                            width: 4, height: speech.isListening ? 4 + speech.level * Double(8 + (index * 7 % 21)) : 4)
                }
            }.frame(height: 34).frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: speech.level)
                .accessibilityHidden(true)
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func startRecording() {
        guard !submitting, !speech.isFinalizing else { return }
        inputFocused = false
        cancelEnrichment()
        captureID = UUID()
        microphoneTask?.cancel()
        speech.stop()
        if input.voiceMode { input.useKeyboard() }
        input.beginVoice()
        replyAttempted = false
        if saved { understanding = nil; saved = false }
        error = nil
        let known = folders
        let preferred = selectedFolder ?? initialFolderID
        let ordered = known.filter { $0.id == preferred } + known.filter { $0.id != preferred }
        let hints = Array(ordered.flatMap { [$0.name] + $0.keywords }.prefix(50))
        microphoneTask = Task { await speech.start(contextualStrings: hints) }
    }

    private func stopRecording(showKeyboard: Bool = false, showSettings: Bool = false) {
        guard !submitting else { return }
        if speech.isStarting {
            microphoneTask?.cancel()
            speech.stop()
            if showKeyboard { input.useKeyboard(); inputFocused = !showSettings }
            if showSettings { settings = true }
            return
        }
        let identifier = captureID
        submitting = true
        inputTask = Task { @MainActor in
            let transcript = await speech.finishListening()
            guard !Task.isCancelled, identifier == captureID else { return }
            if input.voiceMode { input.receive(transcript) }
            submitting = false
            if showKeyboard { input.useKeyboard(); inputFocused = !showSettings }
            if showSettings { speech.stop(); settings = true }
        }
    }

    private var proposalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(
                    saved ? "Добавлено" : "ПРЕДЛОЖЕНИЕ MONO AI",
                    systemImage: saved ? "checkmark.circle.fill" : "sparkles"
                )
                .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.Colors.accent)
                Spacer()
                if !saved {
                    Button("Новая мысль") { resetConversation() }.font(.caption)
                }
            }
            if let clarification = understanding?.clarification {
                Label(clarification, systemImage: "bubble.left.and.text.bubble.right")
                    .font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                Text("Напишите или скажите уточнение ниже. Без подтверждения ничего не создаётся.")
                    .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                if !input.voiceMode {
                    Button("Изменить исходную фразу") {
                        cancelEnrichment()
                        speech.stop()
                        input.draft = understanding?.sourceText ?? input.message
                        inputFocused = true
                    }.font(.caption).disabled(submitting)
                }
            }
            TextField(
                "Название задачи",
                text: Binding(
                    get: { title },
                    set: {
                        title = $0; cancelEnrichment()
                    }), axis: .vertical
            )
            .font(.system(size: 21, weight: .medium))
            .textFieldStyle(.plain).disabled(saved).accessibilityIdentifier("mono-ai-proposal-title")
            Picker(
                "Папка",
                selection: Binding(
                    get: { selectedFolder },
                    set: {
                        cancelEnrichment()
                        selectedFolder = $0
                        routingNeedsConfirmation = false
                        routingExplanation = "Папка выбрана вами."
                    })
            ) {
                Text("Без папки").tag(nil as UUID?)
                ForEach(tags) { tag in Label(tag.name, systemImage: tag.folderIconName).tag(Optional(tag.id)) }
            }.disabled(saved).accessibilityIdentifier("mono-ai-folder")
            if !routingExplanation.isEmpty {
                Text(routingExplanation).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            if routingNeedsConfirmation && !saved {
                Button(selectedFolder == nil ? "Оставить без папки" : "Подтвердить эту папку") {
                    cancelEnrichment()
                    routingNeedsConfirmation = false
                }.buttonStyle(.bordered)
                if model.isInstalled {
                    Button("Подобрать папку с Gemma") { enrichFolder() }.font(.caption).disabled(thinking)
                }
            }
            deadlineControls
            Toggle(
                "Приоритет",
                isOn: Binding(
                    get: { priority },
                    set: {
                        priority = $0; cancelEnrichment()
                    })
            ).disabled(saved)
            if !saved && needsClarification {
                Text(
                    deadlineClarification
                        ?? (routingNeedsConfirmation
                            ? "Можно назвать папку следующим сообщением, например: «В учёбу»."
                            : "Уточните задачу следующим сообщением.")
                )
                .font(.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            Button {
                if speech.isPreparingVoice || speech.isSpeaking {
                    speech.stop()
                } else {
                    cancelEnrichment(); speakReply()
                }
            } label: {
                Label(
                    speech.isPreparingVoice || speech.isSpeaking ? "Остановить озвучку" : "Озвучить ответ",
                    systemImage: "speaker.wave.2")
            }.font(.caption).buttonStyle(.plain)
            if saved {
                Button("Ещё одна мысль", action: resetConversation)
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            } else {
                Button(action: saveTask) {
                    Label("Добавить задачу", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(SharedPrimaryStyle()).disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || needsClarification || submitting
                        || input.voiceMode || !input.pending.isEmpty
                )
                .accessibilityIdentifier("mono-ai-save")
                if input.voiceMode || !input.pending.isEmpty {
                    Text("Сначала отправьте новую фразу или вернитесь к клавиатуре и очистите её.")
                        .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }.padding(24).background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.Colors.accent.opacity(0.22), lineWidth: 1))
            .disabled(submitting || speech.isListening || speech.isStarting || speech.isFinalizing)
    }

    private var deadlineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let deadlineClarification {
                Label(deadlineClarification, systemImage: "calendar.badge.questionmark")
                    .font(.caption).foregroundStyle(Theme.Colors.priority)
                DatePicker(
                    "Срок сдачи",
                    selection: Binding(
                        get: { deadlineCandidate },
                        set: {
                            deadlineCandidate = $0
                            deadlineCandidateEdited = true
                            cancelEnrichment()
                        }), displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("mono-ai-deadline")
                Button("Подтвердить срок") {
                    cancelEnrichment()
                    if deadlineCandidate > .now { dueDate = deadlineCandidate; self.deadlineClarification = nil }
                }.buttonStyle(.bordered).disabled(deadlineCandidate <= .now)
                Button("Без срока") {
                    cancelEnrichment()
                    dueDate = nil; self.deadlineClarification = nil
                }
            } else if dueDate != nil {
                DatePicker(
                    "Срок сдачи",
                    selection: Binding(
                        get: { dueDate ?? deadlineCandidate },
                        set: {
                            dueDate = $0; cancelEnrichment()
                        }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .disabled(saved).accessibilityIdentifier("mono-ai-deadline")
                if !saved {
                    Button("Убрать срок") {
                        cancelEnrichment(); dueDate = nil
                    }
                }
            } else if !saved {
                Button {
                    cancelEnrichment()
                    deadlineCandidate = .now.addingTimeInterval(3600); deadlineClarification = "Выберите дату и время."
                } label: {
                    Label("Добавить срок", systemImage: "calendar.badge.plus")
                }
            }
        }
    }

    private func prepareTask(retry: Bool = false) {
        guard !submitting, !speech.isStarting else { return }
        cancelEnrichment()
        inputFocused = false
        let identifier = captureID
        submitting = true
        inputTask = Task { @MainActor in
            let wasVoice = input.voiceMode
            if wasVoice {
                let transcript = await speech.finishListening()
                guard !Task.isCancelled, identifier == captureID else { return }
                input.receive(transcript)
            }
            let message = retry ? input.message : (input.submit() ?? "")
            guard !Task.isCancelled, identifier == captureID else { return }
            submitting = false
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = speech.error ?? "Не услышал задачу. Попробуйте ещё раз или введите её текстом."
                return
            }
            let warning = wasVoice ? speech.error : nil
            microphoneTask?.cancel()
            speech.stop()
            speech.error = nil
            handleMessage(message)
            if let warning, understanding != nil { error = warning }
        }
    }

    private func handleMessage(_ message: String) {
        error = nil
        modelNotice = nil
        let previous = editableUnderstanding()
        let normalized = MonoAIRouting.words(message).joined(separator: " ")
        if previous != nil
            && ["да", "верно", "правильно", "подтверждаю", "yes", "ok", "нет", "неверно", "no"].contains(normalized)
        {
            error = "Уточните, что изменить: название, папку или срок. Для сохранения нажмите «Добавить задачу»."
            return
        }
        let result: MonoAIUnderstanding
        if let previous, !saved {
            result = MonoAITaskUnderstanding.refine(
                previous, with: message, folders: folders, preferredID: initialFolderID)
        } else {
            result = MonoAITaskUnderstanding.analyze(message, folders: folders, preferredID: initialFolderID)
        }
        apply(result)
        if result.clarification == nil && result.routing.needsConfirmation && model.isInstalled && !folders.isEmpty {
            enrichFolder()
        } else if voice {
            speakReply()
        }
    }

    private func editableUnderstanding() -> MonoAIUnderstanding? {
        guard var result = understanding else { return nil }
        result.title = title
        result.priority = priority
        result.routing = .init(
            folderIndex: folders.firstIndex(where: { $0.id == selectedFolder }), explanation: routingExplanation,
            needsConfirmation: routingNeedsConfirmation)
        let suggested = deadlineCandidateEdited ? deadlineCandidate : result.deadline.suggestedDate
        result.deadline = .init(
            date: dueDate, suggestedDate: dueDate ?? (deadlineClarification != nil ? suggested : nil),
            clarification: deadlineClarification)
        return result
    }

    private func apply(_ result: MonoAIUnderstanding) {
        understanding = result
        draftAccountID = AuthManager.shared.userID
        title = result.title
        priority = result.priority
        selectedFolder = result.routing.folderIndex.flatMap { folders.indices.contains($0) ? folders[$0].id : nil }
        routingExplanation = result.routing.explanation
        routingNeedsConfirmation = result.routing.needsConfirmation
        dueDate = result.deadline.date
        deadlineCandidate = result.deadline.suggestedDate ?? .now.addingTimeInterval(3600)
        deadlineCandidateEdited = false
        deadlineClarification = result.deadline.clarification
        saved = false
    }

    private func enrichFolder() {
        guard let current = editableUnderstanding(), current.clarification == nil,
            !current.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !saved
        else { return }
        cancelEnrichment()
        speech.stop()
        guard !MonoAIVoicePack.shared.isGenerating else {
            modelNotice = "Нейроголос ещё освобождает память. Черновик готов, папку можно выбрать вручную."
            return
        }
        guard let lease = model.beginGeneration() else {
            modelNotice =
                model.isInstalled
                ? "Gemma занята другой подсказкой. Этот черновик можно сохранить без ожидания."
                : "Gemma не установлена. Локальный разбор и ручной выбор папки доступны."
            return
        }
        let identifier = UUID()
        generationID = identifier
        let accountID = AuthManager.shared.userID
        let available = folders
        let preferred = selectedFolder ?? initialFolderID
        let candidates = available.filter { $0.id == preferred } + available.filter { $0.id != preferred }
        let modelFolders = Array(candidates.prefix(16)).map { folder in
            MonoAIFolder(
                id: folder.id, name: String(folder.name.prefix(60)), keywords: Array(folder.keywords.prefix(4)))
        }
        modelNotice = nil
        thinking = true
        generation = Task { @MainActor in
            defer {
                model.finishGeneration(lease)
                if generationID == identifier { thinking = false; generationID = nil }
            }
            do {
                try await model.prepareForInference()
                try Task.checkCancellation()
                let prompt = try MonoAIProposal.prompt(
                    text: current.title, folders: modelFolders, preferredID: preferred)
                let output = try await LocalInference.shared.generate(
                    modelURL: model.modelURL, prompt: prompt,
                    grammar: MonoAIProposal.grammar(folderCount: modelFolders.count), maximumDuration: 18)
                try Task.checkCancellation()
                guard generationID == identifier, accountID == AuthManager.shared.userID, !saved else { return }
                let result = try MonoAIProposal.parse(output, folderCount: modelFolders.count)
                let suggested = result.folder < 0 ? nil : modelFolders[result.folder].id
                let route = MonoAIRouting.decide(
                    text: current.sourceText, folders: folders,
                    suggestedIndex: folders.firstIndex { $0.id == suggested } ?? -1, preferredID: preferred)
                selectedFolder = route.folderIndex.flatMap { folders.indices.contains($0) ? folders[$0].id : nil }
                routingExplanation = route.explanation
                routingNeedsConfirmation = route.needsConfirmation
                modelNotice =
                    "Gemma предложила только папку. Название, срок и приоритет взяты из ваших слов; предположение папки нужно проверить."
                model.finishGeneration(lease)
                thinking = false
                if voice { speakReply() }
            } catch {
                guard generationID == identifier, !Task.isCancelled, accountID == AuthManager.shared.userID else {
                    return
                }
                modelNotice =
                    "Подсказка Gemma недоступна: \(error.localizedDescription) Черновик не потерян — выберите папку вручную."
                model.finishGeneration(lease)
                thinking = false
                if voice { speakReply() }
            }
        }
    }

    private func cancelEnrichment() {
        generationID = nil
        generation?.cancel()
        generation = nil
        thinking = false
    }

    private func speakReply() {
        guard understanding != nil else { return }
        replyAttempted = true
        var message: String
        if saved {
            message = "Готово! Задача добавлена."
        } else if let clarification = understanding?.clarification {
            message = clarification
        } else {
            message = "Подготовил: \(title). "
            if let deadlineClarification {
                message += deadlineClarification
            } else if routingNeedsConfirmation {
                message +=
                    selectedFolder.flatMap { id in tags.first { $0.id == id }?.name }.map {
                        "Предлагаю папку «\($0)». Подтвердите её или выберите другую."
                    } ?? "В какую папку добавить это дело? Можно сказать «без папки»."
            } else {
                message +=
                    selectedFolder.flatMap { id in tags.first { $0.id == id }?.name }.map { "Папка «\($0)». " }
                    ?? "Без папки. "
                if let dueDate {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "ru_RU")
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    message += "Срок: " + formatter.string(from: dueDate) + ". "
                }
                message += "Проверьте, всё ли верно."
            }
        }
        speech.speak(message)
    }

    private func saveTask() {
        guard !saved, !needsClarification, !submitting, hasProposal, !input.voiceMode, input.pending.isEmpty,
            !speech.isListening, !speech.isStarting, !speech.isFinalizing
        else { return }
        guard draftAccountID == AuthManager.shared.userID else {
            error = "Аккаунт изменился. Подготовьте задачу заново."
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle.count <= 300 else {
            error = "Название задачи должно содержать от 1 до 300 символов."
            return
        }
        if let dueDate, dueDate <= .now {
            deadlineCandidate = dueDate
            deadlineClarification = "Срок уже прошёл. Выберите будущую дату и время."
            return
        }
        let folder = tags.first { $0.id == selectedFolder }
        guard selectedFolder == nil || folder != nil else {
            error = "Эта папка удалена. Выберите другую или «Без папки»."
            return
        }
        cancelEnrichment()
        speech.stop()
        let task = TaskItem(
            title: trimmedTitle, bucket: .todo, priority: priority ? .high : .none, isHighPriorityToday: priority,
            dueDate: dueDate, reminderMinutesBefore: nil, tags: folder.map { [$0] } ?? [])
        context.insert(task)
        do {
            try context.save()
        } catch {
            context.delete(task)
            self.error = "Не удалось сохранить задачу. Черновик остался на экране: " + error.localizedDescription
            return
        }
        context.saveAndSync()
        #if os(macOS)
        if fromIsland { IslandController.shared.pin(task) }
        #endif
        saved = true
        error = nil
        Haptics.success()
        if voice { speakReply() }
    }

    private func stopWork() {
        captureID = UUID()
        cancelEnrichment()
        microphoneTask?.cancel()
        inputTask?.cancel()
        submitting = false
        speech.stop()
    }

    private func resetConversation() {
        stopWork()
        understanding = nil
        input = MonoAIInput()
        title = ""
        selectedFolder = initialFolderID
        priority = false
        dueDate = nil
        deadlineClarification = nil
        deadlineCandidateEdited = false
        routingNeedsConfirmation = false
        routingExplanation = ""
        saved = false
        error = nil
        speech.error = nil
        modelNotice = nil
        replyAttempted = false
    }
}
