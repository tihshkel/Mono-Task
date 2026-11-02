import AVFoundation
import Foundation

@main
struct VoicePreferencesTests {
    @MainActor
    static func main() {
        let suite = "MonoAIVoiceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let utterance = AVSpeechUtterance(string: "Тест без воспроизведения")
        MonoAIVoice.configure(utterance, defaults: defaults)
        precondition(abs(utterance.rate - Float(MonoAIVoice.defaultRate)) < 0.001)
        precondition(abs(utterance.pitchMultiplier - Float(MonoAIVoice.defaultPitch)) < 0.001)
        defaults.set(0.55, forKey: MonoAIVoice.rateKey)
        defaults.set(0.95, forKey: MonoAIVoice.pitchKey)
        defaults.set("missing-voice", forKey: MonoAIVoice.identifierKey)
        MonoAIVoice.configure(utterance, defaults: defaults)
        precondition(abs(utterance.rate - 0.55) < 0.001 && abs(utterance.pitchMultiplier - 0.95) < 0.001)
        precondition(utterance.voice?.language.hasPrefix("ru") != false, "Unavailable voice falls back to Russian")
        defaults.set(10.0, forKey: MonoAIVoice.rateKey)
        defaults.set(-10.0, forKey: MonoAIVoice.pitchKey)
        MonoAIVoice.configure(utterance, defaults: defaults)
        precondition(utterance.rate == 0.6 && utterance.pitchMultiplier == 0.85)
        print(
            "PASS: voice defaults, persisted tuning, unavailable voice fallback and bounds; no microphone or playback"
        )
    }
}
