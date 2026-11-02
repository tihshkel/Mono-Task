import Foundation
import MonoVoice
import XCTest

@MainActor final class VoiceProbeTests: XCTestCase {
    func testFourRussianVoices() async throws {
        let directory = URL(fileURLWithPath: "/tmp/MonoAIResearch/qwen-voices")
        let output = URL(fileURLWithPath: "/Users/tihonshkel/Desktop/Mono/build/mono-ai/voice-samples")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for speaker in ["ryan", "aiden", "vivian", "serena"] {
            let start = Date()
            let audio = try await LocalVoice.shared.generate(
                text: "Привет! Я Mono AI. Помогу разложить ваши дела по местам.", speaker: speaker, directory: directory
            )
            XCTAssertGreaterThan(audio.samples.count, audio.sampleRate)
            XCTAssertTrue(audio.samples.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(audio.samples.map { abs($0) }.max() ?? 0, 0.01)
            try MonoAIWave.data(samples: audio.samples, sampleRate: audio.sampleRate).write(
                to: output.appendingPathComponent(speaker + ".wav"))
            print(
                "VOICE \(speaker): \(Double(audio.samples.count) / Double(audio.sampleRate)) seconds audio, \(Date().timeIntervalSince(start)) seconds synthesis"
            )
        }
    }
}
