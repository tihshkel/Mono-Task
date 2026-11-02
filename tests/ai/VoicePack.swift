import AVFoundation
import CryptoKit
import Foundation

@main
struct VoicePackTests {
    @MainActor
    static func main() async throws {
        precondition(MonoAIPresetVoice.allCases.count == 4)
        precondition(MonoAIPresetVoice.allCases.filter { $0.gender == "Мужской" }.count == 2)
        precondition(MonoAIPresetVoice.allCases.filter { $0.gender == "Женский" }.count == 2)
        precondition(MonoAIVoiceManifest.byteCount == 1_693_530_704)
        precondition(Set(MonoAIVoiceManifest.files.map(\.path)).count == MonoAIVoiceManifest.files.count)
        precondition(
            MonoAIVoiceManifest.files.allSatisfy {
                !$0.path.contains("..")
                    && MonoAIVoiceManifest.url(for: $0).absoluteString.contains(MonoAIVoiceManifest.revision)
            })
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MonoVoiceTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fixture = Data([1, 2, 3, 4])
        let url = temporary.appendingPathComponent("fixture")
        try fixture.write(to: url)
        let digest = SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined()
        let file = MonoAIVoiceFile(path: "fixture", bytes: 4, sha256: digest)
        try MonoAIVoicePack.verify(url, file: file)
        try Data([1, 2, 3, 5]).write(to: url)
        do { try MonoAIVoicePack.verify(url, file: file); preconditionFailure("Corruption accepted") } catch {}
        try Data([1]).write(to: url)
        do { try MonoAIVoicePack.verify(url, file: file); preconditionFailure("Truncated file accepted") } catch {}
        precondition(!MonoAIVoicePack.isComplete(temporary))
        let pack = MonoAIVoicePack(directory: temporary.appendingPathComponent("missing"))
        pack.cancelDownload(); pack.cancelDownload()
        precondition(!pack.isDownloading && !pack.isInstalled && pack.progress == 0)
        let wave = MonoAIWave.data(samples: [0, 1, -1, .nan, 2], sampleRate: 24000)
        precondition(wave.count == 54 && String(decoding: wave.prefix(4), as: UTF8.self) == "RIFF")
        let player = try AVAudioPlayer(data: wave)
        precondition(player.duration > 0)
        if CommandLine.arguments.count > 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1])
            for file in MonoAIVoiceManifest.files {
                try MonoAIVoicePack.verify(directory.appendingPathComponent(file.path), file: file)
            }
        }
        print(
            "PASS: four presets (2 male, 2 female), pinned manifest, integrity checks, truncation, idle cancellation and playable PCM container; no playback"
        )
    }
}
