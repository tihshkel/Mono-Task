import Foundation
#if os(iOS)
import os
#endif
#if arch(arm64) && !targetEnvironment(simulator)
import MLX
import MLXAudioCore
import MLXAudioTTS
import MLXLMCommon
#endif

public struct MonoVoiceAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
}

public enum MonoVoiceError: LocalizedError {
    case unsupported, empty, busy, memory, incomplete, invalidSpeaker, tooLong, timedOut

    public var errorDescription: String? {
        switch self {
        case .unsupported: "Нейроголоса доступны на Mac с Apple Silicon и физических iPhone."
        case .empty: "Не удалось подготовить голос. Попробуйте ещё раз."
        case .busy: "Голос ещё готовится. Подождите немного."
        case .memory:
            "Для нейроголоса нужно минимум 2,4 ГБ доступной памяти. Закройте другие приложения или выберите системный голос."
        case .incomplete: "Файлы нейроголоса отсутствуют или повреждены. Повторно скачайте голоса в настройках Mono AI."
        case .invalidSpeaker: "Выберите один из четырёх голосов в настройках Mono AI."
        case .tooLong: "Ответ слишком длинный для нейроголоса. Выберите системный голос для длинных ответов."
        case .timedOut:
            "Подготовка нейроголоса заняла слишком много времени. Повторите попытку или выберите системный голос."
        }
    }
}

public actor LocalVoice {
    public static let shared = LocalVoice()
    private var generating = false

    public func generate(text: String, speaker: String, directory: URL) async throws -> MonoVoiceAudio {
        guard !generating else { throw MonoVoiceError.busy }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw MonoVoiceError.empty }
        guard content.count <= 600 else { throw MonoVoiceError.tooLong }
        guard ["ryan", "aiden", "vivian", "serena"].contains(speaker) else {
            throw MonoVoiceError.invalidSpeaker
        }
        generating = true
        defer { generating = false }
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: MonoVoiceAudio.self) { tasks in
            tasks.addTask { try await Self.render(text: content, speaker: speaker, directory: directory) }
            tasks.addTask {
                try await Task.sleep(for: .seconds(120))
                throw MonoVoiceError.timedOut
            }
            defer { tasks.cancelAll() }
            guard let audio = try await tasks.next() else { throw MonoVoiceError.empty }
            return audio
        }
    }

    private nonisolated static func render(text: String, speaker: String, directory: URL) async throws -> MonoVoiceAudio
    {
        #if arch(arm64) && !targetEnvironment(simulator)
        let requiredFiles = [
            "config.json", "vocab.json", "merges.txt", "tokenizer_config.json", "model.safetensors",
            "speech_tokenizer/config.json", "speech_tokenizer/model.safetensors",
        ]
        guard
            requiredFiles.allSatisfy({
                let values = try? directory.appendingPathComponent($0).resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey,
                ])
                return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
            })
        else { throw MonoVoiceError.incomplete }
        #if os(iOS)
        guard os_proc_available_memory() >= 2_400_000_000 else { throw MonoVoiceError.memory }
        #endif
        let previousCacheLimit = Memory.cacheLimit
        Memory.cacheLimit = 32 * 1024 * 1024
        defer {
            Memory.clearCache()
            Memory.cacheLimit = previousCacheLimit
        }
        return try await synthesize(text: text, speaker: speaker, directory: directory)
        #else
        throw MonoVoiceError.unsupported
        #endif
    }

    #if arch(arm64) && !targetEnvironment(simulator)
    private nonisolated static func synthesize(text: String, speaker: String, directory: URL) async throws
        -> MonoVoiceAudio
    {
        let model = try await Qwen3TTSModel.fromModelDirectory(directory)
        try Task.checkCancellation()
        guard (8_000...96_000).contains(model.sampleRate) else { throw MonoVoiceError.incomplete }
        var samples: [Float] = []
        let maximumSamples = model.sampleRate * 70
        for part in chunks(text) {
            try Task.checkCancellation()
            let audio = try await model.generate(
                text: part, voice: speaker, refAudio: nil, refText: nil,
                language: "Russian",
                generationParameters: GenerateParameters(
                    maxTokens: 360, temperature: 0.6, topP: 0.9, repetitionPenalty: 1.05))
            try Task.checkCancellation()
            let chunk = audio.reshaped([-1]).asArray(Float.self)
            guard chunk.count >= model.sampleRate / 10, chunk.allSatisfy(\.isFinite) else {
                throw MonoVoiceError.empty
            }
            let pauseCount = samples.isEmpty ? 0 : model.sampleRate / 8
            guard samples.count + pauseCount + chunk.count <= maximumSamples else { throw MonoVoiceError.tooLong }
            if !samples.isEmpty {
                samples.append(contentsOf: repeatElement(Float.zero, count: pauseCount))
            }
            samples.append(contentsOf: chunk)
        }
        return MonoVoiceAudio(samples: samples, sampleRate: model.sampleRate)
    }
    #endif

    private nonisolated static func chunks(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !current.isEmpty && current.count + word.count + 1 > 180 {
                result.append(current)
                current = ""
            }
            if !current.isEmpty { current += " " }
            current += String(word)
            if current.count >= 60 && [".", "!", "?", ";"].contains(String(current.suffix(1))) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
