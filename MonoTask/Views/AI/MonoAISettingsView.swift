import AVFoundation
import SwiftUI

struct MonoAISettingsView: View {
    @State private var model = MonoAIModelStore.shared
    @State private var confirmingDownload = false
    @State private var confirmingRemoval = false
    @State private var legalDocument: String?
    @AppStorage("monotask_ai_voice") private var voice = false
    @AppStorage(MonoAIVoice.identifierKey) private var voiceIdentifier = ""
    @AppStorage(MonoAIVoice.rateKey) private var voiceRate = MonoAIVoice.defaultRate
    @AppStorage(MonoAIVoice.pitchKey) private var voicePitch = MonoAIVoice.defaultPitch
    @AppStorage(MonoAIVoice.engineKey) private var voiceEngine = "system"
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewSpeech = MonoAISpeech()
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                MonoAIOrb(activity: .idle, level: 0).frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Mono AI").font(.system(size: 28, weight: .semibold)).tracking(-1)
                    Text("Ваши мысли. Ваше устройство.").foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            GroupCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Gemma 3 · 1B · Q4", systemImage: "cpu").font(.headline)
                    Text(model.status).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("mono-ai-model-status")
                    if model.isDownloading {
                        ProgressView(value: model.progress)
                        Text("Оставьте MonoTask открытым до конца загрузки.")
                            .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                        Button("Отменить загрузку", action: model.cancelDownload)
                    } else if model.isInstalled {
                        MonoAIEntryButton(title: "Попробовать Mono AI")
                        Button("Удалить модель · освободить 806 МБ", role: .destructive) { confirmingRemoval = true }
                            .disabled(model.isGenerating)
                    } else {
                        Button("Скачать модель · 806 МБ") { confirmingDownload = true }
                            .buttonStyle(SharedPrimaryStyle()).accessibilityIdentifier("mono-ai-download")
                    }
                    if let error = model.error {
                        Text(error).font(.subheadline).foregroundStyle(Theme.Colors.priority)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupCard {
                Toggle("Озвучивать ответы", isOn: $voice)
                    .font(.subheadline).foregroundStyle(Theme.Colors.textPrimary).padding(20)
            }
            GroupCard {
                DisclosureGroup("Голос Mono AI") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Голос", selection: $voiceIdentifier) {
                            Text("Автоматически · лучший установленный").tag("")
                            ForEach(voices, id: \.identifier) { item in
                                Text(item.name + (item.quality == .default ? "" : " · улучшенный")).tag(item.identifier)
                            }
                            if !voiceIdentifier.isEmpty && !voices.contains(where: { $0.identifier == voiceIdentifier })
                            {
                                Text("Недоступен · используется автоматический").tag(voiceIdentifier)
                            }
                        }.accessibilityIdentifier("mono-ai-voice-choice")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Темп речи").font(.caption)
                            Slider(value: $voiceRate, in: 0.35...0.6)
                                .accessibilityLabel("Темп речи Mono AI")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Высота голоса").font(.caption)
                            Slider(value: $voicePitch, in: 0.85...1.2)
                                .accessibilityLabel("Высота голоса Mono AI")
                        }
                        Button {
                            if previewSpeech.isSpeaking || previewSpeech.isPreparingVoice {
                                previewSpeech.stop()
                            } else {
                                voiceEngine = "system"
                                previewSpeech.speak(
                                    "Привет! Я Mono AI. Давайте разложим ваши дела по местам. Расскажите, что нужно сделать, а я помогу с папкой и сроком."
                                )
                            }
                        } label: {
                            Label(
                                previewSpeech.isSpeaking || previewSpeech.isPreparingVoice
                                    ? "Остановить пример" : "Послушать голос",
                                systemImage: previewSpeech.isSpeaking || previewSpeech.isPreparingVoice
                                    ? "stop.fill" : "speaker.wave.2")
                        }.buttonStyle(.bordered).accessibilityIdentifier("mono-ai-voice-preview")
                        Button("Сбросить настройки голоса") {
                            previewSpeech.stop()
                            voiceEngine = "system"
                            voiceIdentifier = ""; voiceRate = MonoAIVoice.defaultRate;
                            voicePitch = MonoAIVoice.defaultPitch
                        }.font(.caption)
                        Text(
                            "Здесь настраиваются системные голоса. Нейроголоса Qwen3 выбираются ниже. Темп и высота применяются только к системному голосу."
                        )
                        .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                    }.padding(.top, 16)
                }.padding(20)
            }
            MonoAINeuralVoicesView(speech: previewSpeech)
            DisclosureGroup("Об обработке данных") {
                Text(
                    "Текст обрабатывается на устройстве. Сохранённые задачи синхронизируются по настройкам аккаунта. Голос доступен при поддержке русского офлайн-распознавания. Проверяйте предложения Mono AI перед добавлением."
                )
                .font(.caption).foregroundStyle(Theme.Colors.textSecondary).padding(.top, 8)
            }.font(.caption).foregroundStyle(Theme.Colors.textMuted)
            VStack(alignment: .leading, spacing: 10) {
                Text("На базе Google Gemma 3. Движок llama.cpp.").font(.caption)
                Link("Условия использования Gemma", destination: URL(string: "https://ai.google.dev/gemma/terms")!)
                Link(
                    "Ограничения использования",
                    destination: URL(string: "https://ai.google.dev/gemma/prohibited_use_policy")!)
                Button("Копия условий и лицензий") {
                    legalDocument = ["GemmaTerms", "GemmaProhibitedUse", "MonoAINotice", "MonoVoiceNotice"].compactMap {
                        name in
                        Bundle.main.url(forResource: name, withExtension: "txt").flatMap {
                            try? String(contentsOf: $0, encoding: .utf8)
                        }
                    }.joined(separator: "\n\n────────────\n\n")
                }.buttonStyle(.plain)
                Text(
                    "Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms."
                )
                .font(.caption2)
            }.foregroundStyle(Theme.Colors.textMuted)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .onAppear { voices = MonoAIVoice.installed }
        .onDisappear { previewSpeech.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { previewSpeech.stop() } }
        .onChange(of: voiceIdentifier) { _, _ in previewSpeech.stop() }
        .onChange(of: voiceRate) { _, _ in previewSpeech.stop() }
        .onChange(of: voicePitch) { _, _ in previewSpeech.stop() }
        .onChange(of: voice) { _, enabled in if !enabled { previewSpeech.stop() } }
        .sheet(isPresented: Binding(get: { legalDocument != nil }, set: { if !$0 { legalDocument = nil } })) {
            VStack(spacing: 16) {
                HStack {
                    Text("Лицензии Mono AI").font(.headline); Spacer(); Button("Готово") { legalDocument = nil }
                }
                ScrollView { Text(legalDocument ?? "").font(.system(size: 12)).textSelection(.enabled) }
            }.padding(24).frame(minWidth: 320, minHeight: 400)
                .background(Theme.Colors.background)
        }
        .alert("Скачать Gemma для Mono AI?", isPresented: $confirmingDownload) {
            Button("Скачать и принять условия") { model.download() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(
                "Загрузка 806 МБ с Hugging Face (ggml-org), нужен минимум 1 ГБ свободного места. Использование модели регулируется условиями Gemma и ограничениями использования по ссылкам на этом экране. Модель не отправляет ваши запросы в облако."
            )
        }
        .confirmationDialog("Удалить локальную модель?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Удалить модель", role: .destructive, action: model.remove)
        } message: {
            Text("Задачи и хештеги останутся. Модель можно скачать снова.")
        }
    }
}
