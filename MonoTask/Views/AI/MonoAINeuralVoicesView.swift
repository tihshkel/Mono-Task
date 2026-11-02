import SwiftUI

struct MonoAINeuralVoicesView: View {
    let speech: MonoAISpeech
    @State private var pack = MonoAIVoicePack.shared
    @State private var confirmingDownload = false
    @State private var confirmingRemoval = false
    @AppStorage(MonoAIVoice.engineKey) private var engine = "system"
    @AppStorage(MonoAIVoice.presetKey) private var selected = "serena"

    var body: some View {
        GroupCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Нейроголоса", systemImage: "waveform").font(.headline)
                    Spacer()
                    Text("QWEN3").font(.system(size: 9, weight: .semibold)).tracking(1)
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text(pack.status).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("mono-ai-voices-status")
                if MonoAIVoicePack.isSupported {
                    ForEach(MonoAIPresetVoice.allCases) { voice in
                        HStack(spacing: 12) {
                            Button {
                                speech.stop()
                                selected = voice.rawValue
                                if pack.isInstalled { engine = "qwen" }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: engine == "qwen" && selected == voice.rawValue
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                    .foregroundStyle(Theme.Colors.accent).font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(voice.name + " · " + voice.gender).font(.system(size: 14, weight: .medium))
                                        Text(voice.detail).font(.caption).foregroundStyle(Theme.Colors.textMuted)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(
                                    Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("mono-ai-preset-" + voice.rawValue)
                            Button {
                                let active =
                                    selected == voice.rawValue && (speech.isPreparingVoice || speech.isSpeaking)
                                speech.stop()
                                selected = voice.rawValue
                                engine = "qwen"
                                if !active {
                                    speech.speak("Привет! Я Mono AI. Расскажите о ваших планах, а я помогу с задачами.")
                                }
                            } label: {
                                Image(
                                    systemName: selected == voice.rawValue
                                        && (speech.isPreparingVoice || speech.isSpeaking) ? "stop.fill" : "play.fill"
                                )
                                .frame(width: 42, height: 42).background(Theme.Colors.fill, in: Circle())
                            }.buttonStyle(.plain).disabled(!pack.isInstalled)
                                .accessibilityLabel("Послушать " + voice.name)
                        }
                    }
                    if pack.isDownloading {
                        ProgressView(value: pack.progress)
                        Text("Оставьте приложение открытым до конца загрузки.").font(.caption).foregroundStyle(
                            Theme.Colors.textMuted)
                        Button("Отменить загрузку голосов", action: pack.cancelDownload)
                    } else if !pack.isInstalled {
                        Button(
                            pack.hasPartialDownload ? "Продолжить загрузку голосов" : "Скачать четыре голоса · 1,69 ГБ"
                        ) {
                            confirmingDownload = true
                        }
                        .buttonStyle(SharedPrimaryStyle()).accessibilityIdentifier("mono-ai-voices-download")
                        if pack.hasPartialDownload {
                            Text(
                                "Проверенные файлы сохраняются между попытками. Повторно загрузятся только недостающие."
                            )
                            .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                            Button("Удалить частичную загрузку", role: .destructive) { confirmingRemoval = true }
                                .font(.caption).disabled(pack.isGenerating)
                        }
                    } else {
                        Button("Удалить голоса · 1,69 ГБ", role: .destructive) { confirmingRemoval = true }
                            .font(.caption).disabled(pack.isGenerating || speech.isSpeaking)
                    }
                    if speech.isPreparingVoice {
                        HStack {
                            ProgressView().controlSize(.small); Text("Готовлю голос на устройстве…").font(.caption)
                        }
                    }
                    if let error = speech.error ?? pack.error {
                        Text(error).font(.caption).foregroundStyle(Theme.Colors.priority)
                    }
                    Text(
                        "Пресеты Qwen3‑TTS, используемые в Voicebox. Экспериментальный локальный синтез: произношение русского и скорость зависят от устройства. На iPhone для запуска нужно не менее 2,4 ГБ доступной оперативной памяти; при нехватке памяти выберите системный голос."
                    )
                    .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text(
                        "Нужен Mac с Apple Silicon или физический iPhone. В симуляторе и на Intel используйте системный голос."
                    )
                    .font(.caption).foregroundStyle(Theme.Colors.textMuted)
                }
                if engine == "qwen" {
                    Button("Использовать системный голос") {
                        speech.stop(); engine = "system"
                    }
                    .font(.caption)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: pack.isInstalled) { _, installed in if installed { engine = "qwen" } }
        .alert("Скачать нейроголоса?", isPresented: $confirmingDownload) {
            Button("Скачать 1,69 ГБ", action: pack.download)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(
                "Одна модель Qwen3‑TTS 0.6B Q4 с Hugging Face для Ryan, Aiden, Vivian и Serena. Нужно не менее 2,2 ГБ свободного места, а на iPhone — 2,4 ГБ доступной оперативной памяти. Загрузка сама по себе не гарантирует достаточную память для синтеза. Лицензия Apache 2.0 доступна в разделе лицензий Mono AI."
            )
        }
        .confirmationDialog("Удалить скачанные голоса?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Удалить нейроголоса", role: .destructive) {
                speech.stop(); pack.remove(); if !pack.isInstalled { engine = "system" }
            }
        } message: {
            Text(
                "Загруженные голоса и их частичная загрузка будут удалены. Модель задач Gemma и ваши задачи останутся.")
        }
    }
}
