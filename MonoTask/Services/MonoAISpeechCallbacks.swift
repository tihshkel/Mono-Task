import AVFoundation
import Foundation
import Speech

enum MonoAISpeechCallbacks {
    typealias AuthorizationRequest =
        @Sendable (
            @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
        ) -> Void

    struct RecognitionUpdate: Sendable {
        let text: String?
        let isFinal: Bool
        let error: String?
    }

    nonisolated static func authorization(
        using request: AuthorizationRequest = { SFSpeechRecognizer.requestAuthorization($0) }
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { @Sendable status in continuation.resume(returning: status) }
        }
    }

    nonisolated static func recognition(
        receive: @escaping @Sendable (RecognitionUpdate) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { @Sendable result, error in
            receive(
                RecognitionUpdate(
                    text: result?.bestTranscription.formattedString,
                    isFinal: result?.isFinal == true,
                    error: error?.localizedDescription))
        }
    }

    nonisolated static func tap(
        input: MonoAISpeechAudioInput, receiveLevel: @escaping @Sendable (Double) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, _ in
            input.append(buffer)
            var amplitude = 0.0
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                for index in 0..<Int(buffer.frameLength) {
                    let sample = samples[index].isFinite ? Double(samples[index]) : 0
                    amplitude += sample * sample
                }
                amplitude = min(1, sqrt(amplitude / Double(buffer.frameLength)) * 12)
            }
            receiveLevel(amplitude)
        }
    }
}

final class MonoAISpeechObservers: @unchecked Sendable {
    enum Event: Sendable {
        case configurationChanged, interrupted, routeUnavailable, servicesReset
    }

    private var tokens: [NSObjectProtocol] = []

    init(engineID: ObjectIdentifier, receive: @escaping @Sendable (Event) -> Void) {
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) {
                @Sendable notification in
                guard let object = notification.object,
                    ObjectIdentifier(object as AnyObject) == engineID
                else { return }
                receive(.configurationChanged)
            })
        #if os(iOS)
        tokens.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) {
                @Sendable notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
                    AVAudioSession.InterruptionType(rawValue: value.uintValue) == .began
                else { return }
                receive(.interrupted)
            })
        tokens.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) {
                @Sendable notification in
                guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: value.uintValue),
                    reason == .oldDeviceUnavailable || reason == .noSuitableRouteForCategory
                else { return }
                receive(.routeUnavailable)
            })
        tokens.append(
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) {
                @Sendable _ in receive(.servicesReset)
            })
        #endif
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

final class MonoAISpeechAudioInput: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var acceptingAudio = true

    init(contextualStrings: [String] = []) {
        request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        var seen = Set<String>()
        request.contextualStrings = contextualStrings.compactMap { phrase in
            let value = String(phrase.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }.prefix(50).map { $0 }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard acceptingAudio else { return }
            request.append(buffer)
        }
    }

    func finish() {
        lock.withLock {
            guard acceptingAudio else { return }
            acceptingAudio = false
            request.endAudio()
        }
    }
}
