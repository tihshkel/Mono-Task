import AVFoundation
import Foundation
import Speech

@main
struct SpeechCallbacksTests {
    @MainActor
    static func main() async {
        for status in [
            SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted, .notDetermined,
        ] {
            let returned = await MonoAISpeechCallbacks.authorization { completion in
                DispatchQueue.global().async { completion(status) }
            }
            MainActor.preconditionIsolated()
            precondition(returned == status, "Authorization status lost across callback boundary")
        }
        let update = await withCheckedContinuation { continuation in
            let callback = MonoAISpeechCallbacks.recognition { continuation.resume(returning: $0) }
            DispatchQueue.global().async {
                callback(
                    nil,
                    NSError(
                        domain: "SpeechCallbackTest", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Synthetic recognition failure"]))
            }
        }
        MainActor.preconditionIsolated()
        precondition(update.text == nil && !update.isFinal && update.error == "Synthetic recognition failure")

        let input = MonoAISpeechAudioInput()
        let level = await withCheckedContinuation { continuation in
            let callback = MonoAISpeechCallbacks.tap(input: input) { continuation.resume(returning: $0) }
            DispatchQueue.global().async {
                let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
                buffer.frameLength = 160
                for index in 0..<160 { buffer.floatChannelData![0][index] = 0.05 }
                callback(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
            }
        }
        MainActor.preconditionIsolated()
        precondition(abs(level - 0.6) < 0.01, "Audio level calculation changed")
        await Task.detached {
            input.finish()
            input.finish()
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
            buffer.frameLength = 160
            buffer.floatChannelData![0].initialize(repeating: 0, count: 160)
            input.append(buffer)
        }.value
        print(
            "PASS: four background authorization callbacks, background recognition callback, audio tap, repeated stop")
    }
}
