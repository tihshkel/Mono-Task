import AVFoundation

@MainActor
enum MonoAIVoice {
    static let engineKey = "monotask_ai_voice_engine"
    static let presetKey = "monotask_ai_neural_voice"
    static let identifierKey = "monotask_ai_voice_identifier"
    static let rateKey = "monotask_ai_voice_rate"
    static let pitchKey = "monotask_ai_voice_pitch"
    static let defaultRate = 0.46
    static let defaultPitch = 1.04

    static var installed: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ru") }.sorted {
            if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func configure(_ utterance: AVSpeechUtterance, defaults: UserDefaults = .standard) {
        let identifier = defaults.string(forKey: identifierKey) ?? ""
        utterance.voice =
            installed.first { $0.identifier == identifier } ?? installed.first
            ?? AVSpeechSynthesisVoice(language: "ru-RU")
        let rate = defaults.object(forKey: rateKey) as? Double ?? defaultRate
        let pitch = defaults.object(forKey: pitchKey) as? Double ?? defaultPitch
        utterance.rate = Float(rate.isFinite ? min(max(rate, 0.35), 0.6) : defaultRate)
        utterance.pitchMultiplier = Float(pitch.isFinite ? min(max(pitch, 0.85), 1.2) : defaultPitch)
        utterance.postUtteranceDelay = 0.15
    }
}
