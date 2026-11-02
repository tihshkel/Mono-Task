import AVFoundation
import Observation
import Speech
import MonoVoice

@MainActor
@Observable
final class MonoAISpeech: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, SFSpeechRecognizerDelegate {
    private(set) var isListening = false
    private(set) var isStarting = false
    private(set) var isFinalizing = false
    private(set) var isSpeaking = false
    private(set) var isPreparingVoice = false
    private(set) var level: Double = 0
    private(set) var transcript = ""
    var error: String?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionCompleted = true
    @ObservationIgnored private var audioInput: MonoAISpeechAudioInput?
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var utteranceID: ObjectIdentifier?
    @ObservationIgnored private var neuralTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playerID: ObjectIdentifier?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var observers: MonoAISpeechObservers?
    @ObservationIgnored private let audioOwnerID = UUID()
    private static var audioOwner: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
        observers = MonoAISpeechObservers(engineID: ObjectIdentifier(engine)) { @Sendable [weak self] event in
            Task { @MainActor in self?.audioChanged(event) }
        }
    }

    func start(contextualStrings: [String] = []) async {
        stop()
        let identifier = UUID()
        session = identifier
        transcript = ""
        isStarting = true
        defer { if session == identifier { isStarting = false } }
        error = nil
        let authorization = await MonoAISpeechCallbacks.authorization()
        guard session == identifier, !Task.isCancelled else { return }
        guard authorization == .authorized else {
            error =
                authorization == .restricted
                ? "Распознавание речи ограничено настройками устройства. Можно ввести задачу текстом."
                : "Разрешите MonoTask распознавание речи в системных настройках конфиденциальности. Можно ввести задачу текстом."
            return
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard session == identifier, !Task.isCancelled else { return }
        guard microphone else {
            error = "Для голосового ввода нужен доступ к микрофону. Текстовый ввод доступен всегда."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")),
            recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else {
            error =
                "На этом устройстве сейчас недоступно офлайн-распознавание русского языка. Используйте текстовый ввод."
            return
        }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            Self.audioOwner = audioOwnerID
            guard AVAudioSession.sharedInstance().isInputAvailable else {
                throw MonoAIError.message("Микрофон недоступен. Подключите его и попробуйте ещё раз.")
            }
            #endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
                throw MonoAIError.message("Микрофон недоступен. Подключите его и попробуйте ещё раз.")
            }
            let audio = MonoAISpeechAudioInput(contextualStrings: contextualStrings)
            audioInput = audio
            self.recognizer = recognizer
            recognizer.delegate = self
            recognitionCompleted = false
            transcript = ""
            let receive = MonoAISpeechCallbacks.recognition { @Sendable [weak self] update in
                Task { @MainActor in
                    guard let self, self.session == identifier, !self.recognitionCompleted else { return }
                    if let text = update.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.transcript = text
                    }
                    if update.isFinal || update.error != nil {
                        self.recognitionCompleted = true
                        self.endListening()
                        if update.error != nil {
                            self.error =
                                self.transcript.isEmpty
                                ? "Не удалось распознать речь. Проверьте микрофон и офлайн-распознавание русского языка или введите задачу текстом."
                                : "Запись остановлена. Распознанный текст сохранён — проверьте его перед отправкой."
                        } else if self.transcript.isEmpty {
                            self.error = "Не услышал задачу. Нажмите микрофон и попробуйте ещё раз или введите текст."
                        }
                        self.recognition = nil
                        self.recognizer?.delegate = nil
                        self.recognizer = nil
                        self.audioInput = nil
                    }
                }
            }
            recognition = recognizer.recognitionTask(with: audio.request, resultHandler: receive)
            let tap = MonoAISpeechCallbacks.tap(input: audio) { @Sendable [weak self] value in
                Task { @MainActor in
                    guard self?.session == identifier, self?.isListening == true else { return }
                    self?.level = value
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
            hasTap = true
            engine.prepare()
            try engine.start()
            try Task.checkCancellation()
            isListening = true
            recordingLimit = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(55)) } catch { return }
                guard let self, self.session == identifier, self.isListening else { return }
                _ = await self.finishListening()
                guard self.session == identifier else { return }
                self.error =
                    self.transcript.isEmpty
                    ? "Не услышал задачу. Запись остановлена — попробуйте ещё раз."
                    : "Запись завершена. Проверьте текст и отправьте задачу."
            }
        } catch {
            stop()
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    func endListening() {
        isListening = false
        isStarting = false
        level = 0
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        audioInput?.finish()
        deactivateAudio()
    }

    @discardableResult
    func finishListening() async -> String {
        let identifier = session
        guard isListening || isFinalizing else { return transcript }
        isFinalizing = true
        endListening()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while session == identifier, !recognitionCompleted, clock.now < deadline, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
        }
        guard session == identifier else { return "" }
        if !recognitionCompleted, !Task.isCancelled {
            error =
                transcript.isEmpty
                ? "Не удалось завершить распознавание. Попробуйте ещё раз или введите задачу текстом."
                : "Показан последний распознанный текст. Проверьте последние слова перед отправкой."
        }
        recognitionCompleted = true
        recognition?.cancel()
        recognition = nil
        recognizer?.delegate = nil
        recognizer = nil
        audioInput = nil
        isFinalizing = false
        return transcript
    }

    func stop() {
        session = UUID()
        recordingLimit?.cancel()
        recordingLimit = nil
        endListening()
        isFinalizing = false
        recognitionCompleted = true
        recognition?.cancel()
        recognition = nil
        recognizer?.delegate = nil
        recognizer = nil
        audioInput = nil
        synthesizer.stopSpeaking(at: .immediate)
        utteranceID = nil
        neuralTask?.cancel()
        neuralTask = nil
        player?.stop()
        player = nil
        playerID = nil
        isSpeaking = false
        isPreparingVoice = false
        deactivateAudio()
    }

    func speak(_ text: String) {
        stop()
        error = nil
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if UserDefaults.standard.string(forKey: MonoAIVoice.engineKey) == "qwen" {
            speakNeural(message)
            return
        }
        do {
            try activatePlayback()
            let utterance = AVSpeechUtterance(string: message)
            MonoAIVoice.configure(utterance)
            guard utterance.voice != nil else {
                throw MonoAIError.message(
                    "На устройстве нет русского системного голоса. Добавьте голос в системных настройках речи.")
            }
            utteranceID = ObjectIdentifier(utterance)
            isSpeaking = true
            synthesizer.speak(utterance)
        } catch {
            deactivateAudio()
            self.error = "Не удалось включить озвучку: " + error.localizedDescription
        }
    }

    private func speakNeural(_ text: String) {
        let pack = MonoAIVoicePack.shared
        guard MonoAIVoicePack.isSupported, pack.isInstalled else {
            error = "Скачайте нейроголоса в настройках Mono AI или выберите системный голос."
            return
        }
        let identifier = session
        let selected = UserDefaults.standard.string(forKey: MonoAIVoice.presetKey) ?? "serena"
        let speaker = MonoAIPresetVoice(rawValue: selected) ?? .serena
        isPreparingVoice = true
        neuralTask = Task {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while pack.isGenerating || MonoAIModelStore.shared.isGenerating, clock.now < deadline, !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard session == identifier, !Task.isCancelled else { return }
            guard !pack.isGenerating, !MonoAIModelStore.shared.isGenerating else {
                isPreparingVoice = false
                error = "Предыдущая модель ещё освобождает память. Повторите озвучку чуть позже."
                return
            }
            pack.isGenerating = true
            defer { pack.isGenerating = false }
            do {
                let audio = try await LocalVoice.shared.generate(
                    text: text, speaker: speaker.rawValue, directory: pack.directory)
                try Task.checkCancellation()
                guard session == identifier else { return }
                try activatePlayback()
                let output = try AVAudioPlayer(
                    data: MonoAIWave.validatedData(samples: audio.samples, sampleRate: audio.sampleRate))
                output.delegate = self
                player = output
                playerID = ObjectIdentifier(output)
                isPreparingVoice = false
                output.prepareToPlay()
                guard output.play() else { throw MonoAIError.message("Не удалось воспроизвести голос.") }
                isSpeaking = true
            } catch {
                guard session == identifier else { return }
                isPreparingVoice = false
                player?.stop()
                player = nil
                playerID = nil
                isSpeaking = false
                deactivateAudio()
                if !Task.isCancelled {
                    self.error =
                        "Нейроголос: " + error.localizedDescription
                        + " Текст ответа сохранён. Можно выбрать системный голос в настройках."
                }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor in self.finishedPlaying(identifier, message: flag ? nil : "Воспроизведение прервано.") }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identifier = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "Не удалось воспроизвести голос."
        Task { @MainActor in self.finishedPlaying(identifier, message: message) }
    }

    private func finishedPlaying(_ identifier: ObjectIdentifier, message: String?) {
        guard playerID == identifier else { return }
        player = nil
        playerID = nil
        isSpeaking = false
        if let message { error = message }
        deactivateAudio()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishedSpeaking(identifier) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishedSpeaking(identifier) }
    }

    private func finishedSpeaking(_ identifier: ObjectIdentifier) {
        guard utteranceID == identifier else { return }
        utteranceID = nil
        isSpeaking = false
        deactivateAudio()
    }

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        let identifier = ObjectIdentifier(speechRecognizer)
        Task { @MainActor in
            guard !available, let activeRecognizer = self.recognizer,
                ObjectIdentifier(activeRecognizer) == identifier,
                self.isListening || self.isFinalizing
            else { return }
            self.stop()
            self.error =
                "Офлайн-распознавание сейчас недоступно. Распознанный текст сохранён — можно продолжить с клавиатуры."
        }
    }

    private func audioChanged(_ event: MonoAISpeechObservers.Event) {
        switch event {
        case .configurationChanged:
            guard isListening, !engine.isRunning else { return }
        case .interrupted, .routeUnavailable, .servicesReset:
            guard isListening || isStarting || isFinalizing || isSpeaking || isPreparingVoice else { return }
        }
        let recording = isListening || isStarting || isFinalizing
        stop()
        error =
            recording
            ? "Микрофон был отключён или занят другим приложением. Ваш текст сохранён. Нажмите микрофон, чтобы продолжить."
            : "Озвучка прервана системой. Текст ответа сохранён."
    }

    private func activatePlayback() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        Self.audioOwner = audioOwnerID
        #endif
    }

    private func deactivateAudio() {
        #if os(iOS)
        guard Self.audioOwner == audioOwnerID else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Self.audioOwner = nil
        #endif
    }
}
